package gallery

import (
	"bytes"
	"context"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"

	"github.com/gin-gonic/gin"

	"gallery/common/storage"
)

type mockPosterQueue struct {
	items []string
}

func (mq *mockPosterQueue) Enqueue(source string) {
	mq.items = append(mq.items, source)
}

func (mq *mockPosterQueue) Count() int {
	return len(mq.items)
}

func TestPosterHandler_Pending_ReturnsPlaceholderAndHeader(t *testing.T) {
	gin.SetMode(gin.TestMode)
	originDir := t.TempDir()
	cacheDir := t.TempDir()
	resolver := NewStaticImageResolver(storage.NewFs(originDir), storage.NewFs(cacheDir), nil, context.Background())
	queue := &mockPosterQueue{}
	resolver.PosterQueue = queue

	r := gin.New()
	r.GET("/poster/*name", resolver.HandlePoster)

	req, err := http.NewRequest(http.MethodGet, "/poster/videos/clip.mp4", nil)
	if err != nil {
		t.Fatalf("new request: %v", err)
	}
	resp := httptest.NewRecorder()
	r.ServeHTTP(resp, req)

	if resp.Code != http.StatusOK {
		t.Fatalf("expected status 200, got %d", resp.Code)
	}
	if got := resp.Header().Get("X-Poster-Status"); got != "pending" {
		t.Fatalf("expected pending status header, got %q", got)
	}
	if got := resp.Header().Get("Cache-Control"); got != "no-store" {
		t.Fatalf("expected no-store cache header, got %q", got)
	}
	if !bytes.Contains(resp.Body.Bytes(), []byte("Generating")) {
		t.Fatalf("expected placeholder body, got %q", resp.Body.String())
	}
	if queue.Count() != 1 {
		t.Fatalf("expected enqueue once, got %d", queue.Count())
	}
	if queue.items[0] != "videos/clip.mp4" {
		t.Fatalf("expected enqueue source videos/clip.mp4, got %q", queue.items[0])
	}
}

func TestPosterHandler_Ready_ReturnsRealPosterAndHeader(t *testing.T) {
	gin.SetMode(gin.TestMode)
	originDir := t.TempDir()
	cacheDir := t.TempDir()

	coverPath := filepath.Join(originDir, "videos", "cover.jpg")
	if err := os.MkdirAll(filepath.Dir(coverPath), 0o755); err != nil {
		t.Fatalf("mkdir cover dir: %v", err)
	}
	if err := os.WriteFile(coverPath, []byte("ready"), 0o644); err != nil {
		t.Fatalf("write cover: %v", err)
	}

	resolver := NewStaticImageResolver(storage.NewFs(originDir), storage.NewFs(cacheDir), nil, context.Background())
	queue := &mockPosterQueue{}
	resolver.PosterQueue = queue

	r := gin.New()
	r.GET("/poster/*name", resolver.HandlePoster)

	req, err := http.NewRequest(http.MethodGet, "/poster/videos/clip.mp4", nil)
	if err != nil {
		t.Fatalf("new request: %v", err)
	}
	resp := httptest.NewRecorder()
	r.ServeHTTP(resp, req)

	if resp.Code != http.StatusOK {
		t.Fatalf("expected status 200, got %d", resp.Code)
	}
	if got := resp.Header().Get("X-Poster-Status"); got != "ready" {
		t.Fatalf("expected ready status header, got %q", got)
	}
	if got := resp.Body.String(); got != "ready" {
		t.Fatalf("expected poster body, got %q", got)
	}
	if queue.Count() != 0 {
		t.Fatalf("expected no enqueue for ready poster, got %d", queue.Count())
	}
}
