package gallery

import (
	"context"
	"log"
	"net/http"
	"os"
	"strings"

	utils "github.com/XGFan/go-utils"

	"gallery/common/storage"
	"gallery/thumbnail"
)

// StaticImageResolver handles image file serving and thumbnail generation
type StaticImageResolver struct {
	OriginFs      storage.Storage
	CacheFs       storage.Storage
	Tasks         chan thumbnail.Task
	OriginAdapter http.FileSystem
	ThumbAdapter  http.FileSystem
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

	return sir
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
