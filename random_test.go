package gallery

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/gin-gonic/gin"

	"gallery/core"
)

func randomTestGallery() *Gallery {
	root := &core.TraverseNode{Directories: make(map[string]*core.TraverseNode)}
	album := root.Locate("album")
	album.Images = []core.ImageNode{
		{Node: core.Node{Name: "a.jpg", Path: "album/a.jpg"}, Size: core.Size{Width: 100, Height: 200}},
	}
	album.Videos = []core.VideoNode{
		{Node: core.Node{Name: "b.mp4", Path: "album/b.mp4"}, Size: core.Size{Width: 1920, Height: 1080}, DurationSec: 42},
	}
	root.Locate("barren")
	return &Gallery{Root: root}
}

func randomRequest(t *testing.T, target string) []core.NodeWithParent {
	t.Helper()
	gin.SetMode(gin.TestMode)
	r := gin.New()
	r.GET("/api/random/*name", randomTestGallery().HandleRandom)

	resp := httptest.NewRecorder()
	r.ServeHTTP(resp, httptest.NewRequest(http.MethodGet, target, nil))
	if resp.Code != http.StatusOK {
		t.Fatalf("%s: got status %d, want 200", target, resp.Code)
	}

	var samples []core.NodeWithParent
	if err := json.Unmarshal(resp.Body.Bytes(), &samples); err != nil {
		t.Fatalf("%s: response is not a JSON array: %v (body %s)", target, err, resp.Body.String())
	}
	return samples
}

// The response shape is an array at every count, including one, so the client
// never has to branch on it.
func TestHandleRandom_AlwaysReturnsArray(t *testing.T) {
	samples := randomRequest(t, "/api/random/album")
	if len(samples) != 1 {
		t.Fatalf("got %d samples, want 1", len(samples))
	}
	if samples[0].Type != "image" {
		t.Errorf("default type should be image, got %q", samples[0].Type)
	}
}

func TestHandleRandom_CountBounds(t *testing.T) {
	cases := []struct {
		query string
		want  int
	}{
		{"?count=0", 1},
		{"?count=-3", 1},
		{"?count=abc", 1},
		{"?count=", 1},
		{"?count=3", 3},
		{"?count=200", maxRandomCount},
	}
	for _, tc := range cases {
		samples := randomRequest(t, "/api/random/album"+tc.query)
		if len(samples) != tc.want {
			t.Errorf("%s: got %d samples, want %d", tc.query, len(samples), tc.want)
		}
	}
}

func TestHandleRandom_TypeFilter(t *testing.T) {
	for _, sample := range randomRequest(t, "/api/random/album?count=20&type=video") {
		if sample.Type != "video" {
			t.Fatalf("type=video returned a %s: %s", sample.Type, sample.Path)
		}
		if sample.DurationSec != 42 {
			t.Fatalf("video %s lost its duration: %v", sample.Path, sample.DurationSec)
		}
	}
	for _, sample := range randomRequest(t, "/api/random/album?count=20&type=nonsense") {
		if sample.Type != "image" {
			t.Fatalf("an unknown type should fall back to image, got %s", sample.Type)
		}
	}
}

// An empty directory answers 200 with [], not a 500 and not null: the client
// keeps pulling from an unbounded stream and must not have to special-case it.
func TestHandleRandom_EmptyDirectoryReturnsEmptyArray(t *testing.T) {
	gin.SetMode(gin.TestMode)
	r := gin.New()
	r.GET("/api/random/*name", randomTestGallery().HandleRandom)

	resp := httptest.NewRecorder()
	r.ServeHTTP(resp, httptest.NewRequest(http.MethodGet, "/api/random/barren?count=5&type=all", nil))

	if resp.Code != http.StatusOK {
		t.Fatalf("got status %d, want 200", resp.Code)
	}
	if body := resp.Body.String(); body != "[]" {
		t.Fatalf("got body %q, want []", body)
	}
}
