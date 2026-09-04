package gallery

import (
	"sort"
	"strconv"

	"github.com/gin-gonic/gin"

	"gallery/core"
)

// MediaItem is the unified representation of an image or a video in the paged
// response. The web frontend consumes the separate images/videos arrays, but a
// native client renders both into a single masonry wall, so it needs one merged
// sequence carrying a type tag.
type MediaItem struct {
	Type        string  `json:"type"` // "image" or "video"
	Name        string  `json:"name"`
	Path        string  `json:"path"`
	Width       int     `json:"width"`
	Height      int     `json:"height"`
	DurationSec float64 `json:"duration_sec,omitempty"`
}

// MediaPage is the paged response returned when the client asks for a page.
type MediaPage struct {
	Items  []MediaItem `json:"items"`
	Total  int         `json:"total"`
	Offset int         `json:"offset"`
	Limit  int         `json:"limit"`
}

// parsePageParams reports whether the client requested pagination, along with
// the requested window. When it returns false the caller must fall back to the
// legacy images/videos response so the web frontend stays untouched.
func parsePageParams(c *gin.Context) (offset int, limit int, requested bool) {
	raw := c.Query("limit")
	if raw == "" {
		return 0, 0, false
	}
	limit, err := strconv.Atoi(raw)
	if err != nil || limit <= 0 {
		return 0, 0, false
	}
	offset, err = strconv.Atoi(c.Query("offset"))
	if err != nil || offset < 0 {
		offset = 0
	}
	return offset, limit, true
}

// mergeMedia flattens images and videos into a single ordered sequence.
//
// The ordering matters: the scanner is a concurrent pipeline, so the node order
// inside the in-memory tree is not stable across scans. Paging over an unstable
// order would silently duplicate and drop items across page boundaries, so the
// merged sequence is explicitly sorted by path.
func mergeMedia(images []core.ImageNode, videos []core.VideoNode) []MediaItem {
	items := make([]MediaItem, 0, len(images)+len(videos))
	for _, it := range images {
		items = append(items, MediaItem{
			Type:   "image",
			Name:   it.Name,
			Path:   it.Path,
			Width:  it.Width,
			Height: it.Height,
		})
	}
	for _, it := range videos {
		items = append(items, MediaItem{
			Type:        "video",
			Name:        it.Name,
			Path:        it.Path,
			Width:       it.Width,
			Height:      it.Height,
			DurationSec: it.DurationSec,
		})
	}
	sort.Slice(items, func(i, j int) bool { return items[i].Path < items[j].Path })
	return items
}

// paginate slices out one page. An out-of-range offset yields an empty page
// rather than an error, so a client that keeps scrolling past the end simply
// stops receiving items.
func paginate(items []MediaItem, offset int, limit int) MediaPage {
	total := len(items)
	if offset > total {
		offset = total
	}
	end := offset + limit
	if end > total {
		end = total
	}
	return MediaPage{
		Items:  items[offset:end],
		Total:  total,
		Offset: offset,
		Limit:  limit,
	}
}
