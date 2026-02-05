package gallery

import (
	"context"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/exec"
	"path"
	"strings"

	utils "github.com/XGFan/go-utils"
	"github.com/gin-gonic/gin"

	"gallery/common/storage"
	"gallery/core"
	"gallery/thumbnail"
)

// StaticImageResolver handles image file serving and thumbnail generation
type StaticImageResolver struct {
	OriginFs      storage.Storage
	CacheFs       storage.Storage
	Tasks         chan thumbnail.Task
	PosterQueue   core.PosterEnqueuer
	OriginAdapter http.FileSystem
	ThumbAdapter  http.FileSystem
	VideoAdapter  http.FileSystem
	PosterAdapter http.FileSystem
}

func (sir *StaticImageResolver) Worker(ctx context.Context) {
	worker := thumbnail.NewWorker(sir.OriginFs, sir.CacheFs)
	worker.Run(ctx, sir.Tasks)
}

func (sir *StaticImageResolver) AddThumbTask(src string) {
	log.Printf("thumb cache missed: %s", src)
	sir.Tasks <- thumbnail.Task{
		Source: src,
	}
}

func NewStaticImageResolver(baseFs storage.Storage,
	cacheFs storage.Storage,
	forceThumb []string,
	ctx context.Context) *StaticImageResolver {
	sir := &StaticImageResolver{
		OriginFs: baseFs,
		CacheFs:  cacheFs,
		Tasks:    make(chan thumbnail.Task, 30),
	}
	pm := make(utils.PrefixMatcher)
	for _, p := range forceThumb {
		pm.Add(p)
	}

	go sir.Worker(ctx)
	sir.ThumbAdapter = FsFunc(func(name string) (http.File, error) {
		source := CleanUrlPath(name)
		if storage.IsValidPic(source) {
			f, err := cacheFs.Open(source)
			if os.IsNotExist(err) {
				sir.AddThumbTask(source)
				return sir.OriginFs.Open(name)
			} else {
				return f, err
			}
		} else {
			return nil, os.ErrNotExist
		}
	})

	sir.OriginAdapter = FsFunc(func(name string) (http.File, error) {
		source := CleanUrlPath(name)
		if !storage.IsValidPic(source) {
			return nil, os.ErrNotExist
		}
		if pm.Match(source) {
			return sir.ThumbAdapter.Open(name)
		}
		return sir.OriginFs.Open(source)
	})

	sir.VideoAdapter = FsFunc(func(name string) (http.File, error) {
		source := CleanUrlPath(name)
		if !storage.IsValidVideo(source) {
			return nil, os.ErrNotExist
		}
		return sir.OriginFs.Open(source)
	})

	sir.PosterAdapter = FsFunc(func(name string) (http.File, error) {
		source := CleanUrlPath(name)
		if !storage.IsValidVideo(source) {
			return nil, os.ErrNotExist
		}
		return sir.openPosterFile(source)
	})

	return sir
}

type posterGenerator struct {
	originFs storage.Storage
	cacheFs  storage.Storage
}

func newPosterGenerator(originFs storage.Storage, cacheFs storage.Storage) *posterGenerator {
	return &posterGenerator{originFs: originFs, cacheFs: cacheFs}
}

func (pg *posterGenerator) Generate(ctx context.Context, source string) error {
	if pg == nil || pg.originFs == nil || pg.cacheFs == nil {
		return fmt.Errorf("poster generator not configured")
	}
	if source == "" || !storage.IsValidVideo(source) {
		return nil
	}

	cachePath := source + ".poster.jpg"
	if pg.cacheFs.Exist(cachePath) {
		return nil
	}

	inputPath := pg.originFs.Join(pg.originFs.GetPath(), source)
	outputPath := pg.cacheFs.Join(pg.cacheFs.GetPath(), cachePath)
	if err := storage.SafetyCreateDirectoryByFileName(outputPath); err != nil {
		return fmt.Errorf("poster cache mkdir failed: %s, err: %w", outputPath, err)
	}

	cmd := exec.CommandContext(ctx, "ffmpeg", "-ss", "00:00:05", "-i", inputPath, "-vf", "thumbnail=100,scale=1280:-1", "-vframes", "1", "-q:v", "2", "-y", outputPath)
	if output, err := cmd.CombinedOutput(); err != nil {
		return fmt.Errorf("poster generate failed: %s, err: %w, output: %s", source, err, strings.TrimSpace(string(output)))
	}

	return nil
}

var posterCoverCandidates = []string{"cover.jpg", "cover.jpeg", "cover.png", "cover.webp"}

func (sir *StaticImageResolver) openPosterFile(source string) (http.File, error) {
	parentDir := path.Dir(source)
	for _, candidate := range posterCoverCandidates {
		coverPath := path.Join(parentDir, candidate)
		if !storage.IsValidPic(coverPath) {
			continue
		}
		if f, err := sir.OriginFs.Open(coverPath); err == nil {
			return f, nil
		} else if !os.IsNotExist(err) {
			return nil, err
		}
	}

	cachePath := source + ".poster.jpg"
	if f, err := sir.CacheFs.Open(cachePath); err == nil {
		return f, nil
	} else if !os.IsNotExist(err) {
		return nil, err
	}

	return nil, os.ErrNotExist
}

const posterPlaceholderSVG = `<?xml version="1.0" encoding="UTF-8"?>
<svg width="640" height="360" viewBox="0 0 640 360" fill="none" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0%" stop-color="#1F2937"/>
      <stop offset="100%" stop-color="#111827"/>
    </linearGradient>
  </defs>
  <rect width="640" height="360" rx="16" fill="url(#bg)"/>
  <rect x="208" y="120" width="224" height="120" rx="12" fill="#0F172A" stroke="#374151"/>
  <polygon points="302,150 302,210 352,180" fill="#E5E7EB"/>
  <text x="320" y="270" fill="#D1D5DB" font-size="20" font-family="Helvetica, Arial, sans-serif" text-anchor="middle">Generating poster…</text>
</svg>
`

func (sir *StaticImageResolver) HandlePoster(c *gin.Context) {
	name := c.Param("name")
	source := CleanUrlPath(name)
	if !storage.IsValidVideo(source) {
		c.Status(http.StatusNotFound)
		return
	}

	if file, err := sir.openPosterFile(source); err == nil {
		defer file.Close()
		info, statErr := file.Stat()
		if statErr == nil {
			c.Header("X-Poster-Status", "ready")
			http.ServeContent(c.Writer, c.Request, info.Name(), info.ModTime(), file)
			return
		}
		log.Printf("poster stat failed: %s, err: %v", source, statErr)
	} else if !os.IsNotExist(err) {
		log.Printf("poster open failed: %s, err: %v", source, err)
	}

	if sir.PosterQueue != nil {
		sir.PosterQueue.Enqueue(source)
	}
	servePosterPlaceholder(c)
}

func servePosterPlaceholder(c *gin.Context) {
	c.Header("X-Poster-Status", "pending")
	c.Header("Cache-Control", "no-store")
	c.Data(http.StatusOK, "image/svg+xml; charset=utf-8", []byte(posterPlaceholderSVG))
}

// FsFunc is a function adapter for http.FileSystem
type FsFunc func(string) (http.File, error)

func (fsFunc FsFunc) Open(name string) (http.File, error) {
	return fsFunc(name)
}

// CleanUrlPath removes leading slash from URL path
func CleanUrlPath(name string) string {
	if strings.HasPrefix(name, "/") {
		return name[1:]
	}
	return name
}
