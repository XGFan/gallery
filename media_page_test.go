package gallery

import (
	"math"
	"net/http/httptest"
	"testing"

	"github.com/gin-gonic/gin"

	"gallery/core"
)

func paramsFor(t *testing.T, query string) (int, int, bool) {
	t.Helper()
	gin.SetMode(gin.TestMode)
	c, _ := gin.CreateTestContext(httptest.NewRecorder())
	c.Request = httptest.NewRequest("GET", "/api/media/x"+query, nil)
	return parsePageParams(c)
}

// The web frontend never sends ?limit=, and it must keep receiving the legacy
// images/videos response. This is the switch that guarantees it.
func TestParsePageParams_NoLimitMeansNoPaging(t *testing.T) {
	for _, query := range []string{"", "?flat=true", "?limit=", "?limit=abc", "?limit=0", "?limit=-5", "?offset=10"} {
		if _, _, requested := paramsFor(t, query); requested {
			t.Errorf("query %q should not request paging", query)
		}
	}
}

func TestParsePageParams_Window(t *testing.T) {
	offset, limit, requested := paramsFor(t, "?flat=true&offset=60&limit=30")
	if !requested {
		t.Fatal("expected paging to be requested")
	}
	if offset != 60 || limit != 30 {
		t.Errorf("got offset=%d limit=%d, want 60/30", offset, limit)
	}
}

func TestParsePageParams_BadOffsetFallsBackToZero(t *testing.T) {
	for _, query := range []string{"?limit=10&offset=-1", "?limit=10&offset=xyz"} {
		offset, _, requested := paramsFor(t, query)
		if !requested {
			t.Fatalf("query %q should still request paging", query)
		}
		if offset != 0 {
			t.Errorf("query %q: got offset=%d, want 0", query, offset)
		}
	}
}

func img(path string) core.ImageNode {
	return core.ImageNode{Node: core.Node{Name: path, Path: path}, Size: core.Size{Width: 100, Height: 200}}
}

func vid(path string, duration float64) core.VideoNode {
	return core.VideoNode{
		Node:        core.Node{Name: path, Path: path},
		Size:        core.Size{Width: 1920, Height: 1080},
		DurationSec: duration,
	}
}

// The scanner is concurrent, so tree order is not stable across scans. Paging
// over an unstable order would duplicate and drop items at page boundaries.
func TestMergeMedia_SortsByPathAndInterleavesTypes(t *testing.T) {
	items := mergeMedia(
		[]core.ImageNode{img("a/c.jpg"), img("a/a.jpg")},
		[]core.VideoNode{vid("a/d.mp4", 12.5), vid("a/b.mp4", 3)},
	)

	gotPaths := make([]string, len(items))
	for i, it := range items {
		gotPaths[i] = it.Path
	}
	wantPaths := []string{"a/a.jpg", "a/b.mp4", "a/c.jpg", "a/d.mp4"}
	if len(gotPaths) != len(wantPaths) {
		t.Fatalf("got %d items %v, want %d %v", len(gotPaths), gotPaths, len(wantPaths), wantPaths)
	}
	for i := range wantPaths {
		if gotPaths[i] != wantPaths[i] {
			t.Fatalf("got order %v, want %v", gotPaths, wantPaths)
		}
	}

	if items[0].Type != "image" || items[1].Type != "video" {
		t.Errorf("types not tagged correctly: %q, %q", items[0].Type, items[1].Type)
	}
	if items[1].DurationSec != 3 {
		t.Errorf("video duration lost: got %v", items[1].DurationSec)
	}
}

func TestPaginate_Window(t *testing.T) {
	items := mergeMedia([]core.ImageNode{img("1"), img("2"), img("3"), img("4"), img("5")}, nil)

	page := paginate(items, 1, 2)
	if page.Total != 5 || page.Offset != 1 || page.Limit != 2 {
		t.Errorf("got total=%d offset=%d limit=%d, want 5/1/2", page.Total, page.Offset, page.Limit)
	}
	if len(page.Items) != 2 || page.Items[0].Path != "2" || page.Items[1].Path != "3" {
		t.Errorf("unexpected window: %+v", page.Items)
	}
}

// A client that keeps scrolling past the end should just stop receiving items.
func TestPaginate_BeyondEndIsEmptyNotPanic(t *testing.T) {
	items := mergeMedia([]core.ImageNode{img("1"), img("2")}, nil)

	for _, tc := range []struct{ offset, limit int }{{2, 10}, {99, 10}} {
		page := paginate(items, tc.offset, tc.limit)
		if len(page.Items) != 0 {
			t.Errorf("offset=%d: got %d items, want 0", tc.offset, len(page.Items))
		}
		if page.Total != 2 {
			t.Errorf("offset=%d: got total=%d, want 2", tc.offset, page.Total)
		}
	}

	// Partial last page.
	page := paginate(items, 1, 10)
	if len(page.Items) != 1 || page.Items[0].Path != "2" {
		t.Errorf("unexpected last page: %+v", page.Items)
	}
}

// A large limit used to overflow offset+limit into a negative number, which
// slipped past the "> total" clamp and panicked the slice expression. Reachable
// from any client that sends ?limit=<huge>.
func TestPaginate_HugeLimitDoesNotPanic(t *testing.T) {
	items := mergeMedia([]core.ImageNode{img("1"), img("2"), img("3")}, nil)

	for _, tc := range []struct {
		name   string
		offset int
		limit  int
	}{
		{"max int", 1, math.MaxInt},
		{"max int at zero offset", 0, math.MaxInt},
		{"huge but not max", 2, 1 << 60},
	} {
		t.Run(tc.name, func(t *testing.T) {
			page := paginate(items, tc.offset, tc.limit)
			want := len(items) - tc.offset
			if len(page.Items) != want {
				t.Errorf("got %d items, want %d", len(page.Items), want)
			}
			if page.Total != 3 {
				t.Errorf("got total=%d, want 3", page.Total)
			}
		})
	}
}

func TestParsePageParams_ClampsHugeLimit(t *testing.T) {
	_, limit, requested := paramsFor(t, "?limit=9223372036854775807")
	if !requested {
		t.Fatal("a huge limit is still a paging request")
	}
	if limit != maxPageSize {
		t.Errorf("got limit=%d, want it clamped to %d", limit, maxPageSize)
	}
}
