package core

import (
	"bytes"
	"encoding/binary"
	"image"
	"image/jpeg"
	"os"
	"path/filepath"
	"testing"

	"gallery/common/storage"
)

// exifJPEG encodes a w×h JPEG carrying an Exif APP1 segment with the given orientation.
func exifJPEG(t *testing.T, w, h int, orientation uint16) []byte {
	t.Helper()
	var buf bytes.Buffer
	if err := jpeg.Encode(&buf, image.NewGray(image.Rect(0, 0, w, h)), nil); err != nil {
		t.Fatal(err)
	}
	// big-endian TIFF header, IFD0 with a single Orientation entry
	tiff := []byte("MM\x00\x2a\x00\x00\x00\x08\x00\x01\x01\x12\x00\x03\x00\x00\x00\x01\x00\x00\x00\x00\x00\x00\x00\x00")
	binary.BigEndian.PutUint16(tiff[18:], orientation)
	payload := append([]byte("Exif\x00\x00"), tiff...)
	seg := []byte{0xff, 0xe1, 0, 0}
	binary.BigEndian.PutUint16(seg[2:], uint16(len(payload)+2))
	data := buf.Bytes()
	return bytes.Join([][]byte{data[:2], seg, payload, data[2:]}, nil)
}

func TestSizeProbe_AppliesExifOrientation(t *testing.T) {
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, "rotated.jpg"), exifJPEG(t, 40, 30, 6), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "plain.jpg"), exifJPEG(t, 40, 30, 1), 0o644); err != nil {
		t.Fatal(err)
	}

	cache := NewCacheManager(newFakeStorage(nil), nil)
	scanner := NewScanner(storage.NewLocalFs(dir), nil, cache, nil, &mockPosterQueue{})
	root := &TraverseNode{Directories: make(map[string]*TraverseNode)}

	source := make(chan ScanItem, 2)
	source <- ScanItem{Type: ItemImage, Path: "rotated.jpg", Name: "rotated.jpg"}
	source <- ScanItem{Type: ItemImage, Path: "plain.jpg", Name: "plain.jpg"}
	close(source)
	scanner.RunPipeline(root, source)

	want := map[string]Size{
		"rotated.jpg": {Width: 30, Height: 40},
		"plain.jpg":   {Width: 40, Height: 30},
	}
	if len(root.Images) != len(want) {
		t.Fatalf("got %d images, want %d", len(root.Images), len(want))
	}
	for _, img := range root.Images {
		if img.Size != want[img.Name] {
			t.Errorf("%s: size %+v, want %+v", img.Name, img.Size, want[img.Name])
		}
	}
}
