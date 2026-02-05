package gallery

import (
	"context"
	"errors"
	"strings"
	"testing"

	"gallery/common/storage"
	"gallery/core"
)

func TestCalcPosterOffsetSec(t *testing.T) {
	tests := []struct {
		name       string
		duration   float64
		expectOK   bool
		expectSecs float64
	}{
		{name: "invalid", duration: 0, expectOK: false},
		{name: "short-under-2", duration: 2, expectOK: true, expectSecs: 1},
		{name: "short-cap", duration: 10, expectOK: true, expectSecs: 2},
		{name: "edge-30", duration: 30, expectOK: true, expectSecs: 2},
		{name: "mid-31", duration: 31, expectOK: true, expectSecs: 30},
		{name: "edge-300", duration: 300, expectOK: true, expectSecs: 30},
		{name: "long-301", duration: 301, expectOK: true, expectSecs: 45},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			offset, ok := calcPosterOffsetSec(tt.duration)
			if ok != tt.expectOK {
				t.Fatalf("expect ok=%v, got %v", tt.expectOK, ok)
			}
			if !ok {
				return
			}
			if offset != tt.expectSecs {
				t.Fatalf("expect offset=%.3f, got %.3f", tt.expectSecs, offset)
			}
		})
	}
}

func TestPosterAttemptArgs(t *testing.T) {
	args := buildPosterAttemptArgs("/input/video.mp4", "/output/poster.jpg")
	if hasArg(args, "-ss") {
		t.Fatalf("attempt1 should not include -ss")
	}
	assertArgPair(t, args, "-pix_fmt", "yuvj420p")
	assertArgPair(t, args, "-vf", posterFilter)

	offset := 2.0
	argsWithOffset := buildPosterAttemptWithOffsetArgs("/input/video.mp4", "/output/poster.jpg", offset)
	assertArgPair(t, argsWithOffset, "-ss", formatPosterOffsetSec(offset))
	assertArgPair(t, argsWithOffset, "-pix_fmt", "yuvj420p")
	assertArgPair(t, argsWithOffset, "-vf", posterFilter)
}

func TestPosterAttemptArgsWithOffsetMatrix(t *testing.T) {
	tests := []struct {
		name       string
		duration   float64
		expectSecs float64
	}{
		{name: "short", duration: 10, expectSecs: 2},
		{name: "mid", duration: 120, expectSecs: 30},
		{name: "long", duration: 600, expectSecs: 45},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			offset, ok := calcPosterOffsetSec(tt.duration)
			if !ok {
				t.Fatalf("expect offset ok")
			}
			if offset != tt.expectSecs {
				t.Fatalf("expect offset=%.3f, got %.3f", tt.expectSecs, offset)
			}
			args := buildPosterAttemptWithOffsetArgs("/input/video.mp4", "/output/poster.jpg", offset)
			assertArgPair(t, args, "-ss", formatPosterOffsetSec(tt.expectSecs))
			assertArgPair(t, args, "-pix_fmt", "yuvj420p")
			assertArgPair(t, args, "-vf", posterFilter)
		})
	}
}

func TestPosterGenerateDurationMissing(t *testing.T) {
	cacheDir := t.TempDir()
	originDir := t.TempDir()
	originFs := storage.NewFs(originDir)
	cacheFs := storage.NewFs(cacheDir)

	pg := newPosterGenerator(originFs, cacheFs, func(path string) (core.VideoMeta, bool) {
		return core.VideoMeta{}, false
	})
	pg.probeVideoMeta = func(absPath string) (int, int, float64, error) {
		return 0, 0, 0, errors.New("probe failed")
	}
	pg.runPosterAttempt = func(ctx context.Context, source string, args []string, label string) error {
		return errors.New("ffmpeg failed")
	}

	err := pg.Generate(context.Background(), "video.mp4")
	if err == nil {
		t.Fatalf("expect error")
	}
	if !strings.Contains(err.Error(), "poster duration probe failed") {
		t.Fatalf("unexpected error: %v", err)
	}
}

func hasArg(args []string, target string) bool {
	for _, arg := range args {
		if arg == target {
			return true
		}
	}
	return false
}

func assertArgPair(t *testing.T, args []string, flag string, value string) {
	t.Helper()
	for i := 0; i < len(args)-1; i++ {
		if args[i] == flag && args[i+1] == value {
			return
		}
	}
	t.Fatalf("missing arg pair %s %s", flag, value)
}
