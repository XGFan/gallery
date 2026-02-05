package core

import (
	"bytes"
	"io"
	"net/http"
	"os"
	"path"
	"sync"
	"testing"
	"time"

	"gallery/common/storage"
)

type fakeFileInfo struct {
	name    string
	size    int64
	modTime time.Time
}

func (fi fakeFileInfo) Name() string       { return fi.name }
func (fi fakeFileInfo) Size() int64        { return fi.size }
func (fi fakeFileInfo) Mode() os.FileMode  { return 0644 }
func (fi fakeFileInfo) ModTime() time.Time { return fi.modTime }
func (fi fakeFileInfo) IsDir() bool        { return false }
func (fi fakeFileInfo) Sys() interface{}   { return nil }

type fakeFile struct {
	*bytes.Reader
	info os.FileInfo
}

func (f *fakeFile) Close() error               { return nil }
func (f *fakeFile) Stat() (os.FileInfo, error) { return f.info, nil }
func (f *fakeFile) Readdir(count int) ([]os.FileInfo, error) {
	return nil, nil
}

type fakeStorage struct {
	files map[string]*fakeFileInfo
}

func newFakeStorage(files map[string]*fakeFileInfo) *fakeStorage {
	if files == nil {
		files = make(map[string]*fakeFileInfo)
	}
	return &fakeStorage{files: files}
}

func (fs *fakeStorage) OpenOrMkdir(name string) storage.Storage { return fs }
func (fs *fakeStorage) Save(name string, reader io.ReadCloser) error {
	if reader != nil {
		_ = reader.Close()
	}
	return nil
}
func (fs *fakeStorage) Rename(oldName, newName string) error { return nil }
func (fs *fakeStorage) Exist(name string) bool {
	_, ok := fs.files[name]
	return ok
}
func (fs *fakeStorage) ReadDir(name string) ([]os.FileInfo, error) {
	return []os.FileInfo{}, nil
}
func (fs *fakeStorage) Open(name string) (http.File, error) {
	info, ok := fs.files[name]
	if !ok {
		return nil, os.ErrNotExist
	}
	return &fakeFile{Reader: bytes.NewReader(nil), info: info}, nil
}
func (fs *fakeStorage) Read(name string) ([]byte, error) { return nil, os.ErrNotExist }
func (fs *fakeStorage) Join(s ...string) string          { return path.Join(s...) }
func (fs *fakeStorage) Create(fileName string) (storage.FileInf, error) {
	return nil, os.ErrNotExist
}
func (fs *fakeStorage) GetPath() string { return "/fake" }

type mockPosterQueue struct {
	mu      sync.Mutex
	sources []string
}

func (mq *mockPosterQueue) Enqueue(source string) {
	mq.mu.Lock()
	mq.sources = append(mq.sources, source)
	mq.mu.Unlock()
}

func (mq *mockPosterQueue) Count() int {
	mq.mu.Lock()
	defer mq.mu.Unlock()
	return len(mq.sources)
}

func TestScanEnqueuePoster_MissingPoster(t *testing.T) {
	modTime := time.Now()
	originFs := newFakeStorage(map[string]*fakeFileInfo{
		"video.mp4": {name: "video.mp4", size: 1024, modTime: modTime},
	})
	cacheFs := newFakeStorage(nil)
	cache := NewCacheManager(cacheFs, nil)
	cache.UpsertVideoMeta("video.mp4", VideoMeta{
		Path:            "video.mp4",
		DurationSec:     12,
		Width:           1920,
		Height:          1080,
		SizeBytes:       1024,
		ModTimeUnixNano: modTime.UnixNano(),
	})

	queue := &mockPosterQueue{}
	scanner := NewScanner(originFs, nil, cache, nil, queue)
	root := &TraverseNode{Directories: make(map[string]*TraverseNode)}

	source := make(chan ScanItem, 1)
	source <- ScanItem{Type: ItemVideo, Path: "video.mp4", Name: "video.mp4"}
	close(source)

	scanner.RunPipeline(root, source)

	if queue.Count() != 1 {
		t.Fatalf("expected enqueue for missing poster, got %d", queue.Count())
	}
}

func TestScanEnqueuePoster_NoChange_NoEnqueue(t *testing.T) {
	modTime := time.Now()
	originFs := newFakeStorage(map[string]*fakeFileInfo{
		"video.mp4": {name: "video.mp4", size: 2048, modTime: modTime},
	})
	cacheFs := newFakeStorage(map[string]*fakeFileInfo{
		"video.mp4.poster.jpg": {name: "video.mp4.poster.jpg", size: 100, modTime: modTime},
	})
	cache := NewCacheManager(cacheFs, nil)
	cache.UpsertVideoMeta("video.mp4", VideoMeta{
		Path:            "video.mp4",
		DurationSec:     8,
		Width:           1280,
		Height:          720,
		SizeBytes:       2048,
		ModTimeUnixNano: modTime.UnixNano(),
	})

	queue := &mockPosterQueue{}
	scanner := NewScanner(originFs, nil, cache, nil, queue)
	root := &TraverseNode{Directories: make(map[string]*TraverseNode)}

	source := make(chan ScanItem, 1)
	source <- ScanItem{Type: ItemVideo, Path: "video.mp4", Name: "video.mp4"}
	close(source)

	scanner.RunPipeline(root, source)

	if queue.Count() != 0 {
		t.Fatalf("expected no enqueue when poster exists and unchanged, got %d", queue.Count())
	}
}
