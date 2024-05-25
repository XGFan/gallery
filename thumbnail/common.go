package thumbnail

import (
	"context"
	"gallery/common/storage"
	"github.com/XGFan/go-utils"
	"github.com/disintegration/imaging"
	"image"
	"image/jpeg"
	"log"
	"time"
)

type ComposeWorker struct {
	Worker
}

func (cw *ComposeWorker) Run(ctx context.Context, tasks chan Task) {
	cache := utils.NewTTlCache[string, string](10 * time.Second)

	for {
		select {
		case <-ctx.Done():
			log.Println("Worker exit")
			return
		case task := <-tasks:
			if !cache.Filter(task.Source) {
				continue
			}
			cw.Thumbnail(task.Source)
		}
	}
}

func NewWorker(originFs storage.Storage, thumbFs storage.Storage) ComposeWorker {
	return ComposeWorker{
		NewImageWorker(originFs, thumbFs),
	}
}

type Worker interface {
	Thumbnail(src string)
}

type Task struct {
	Source string
}

type ImagingWorker struct {
	OriginFs storage.Storage
	ThumbFs  storage.Storage
}

func (img *ImagingWorker) Thumbnail(src string) {
	start := time.Now()
	imageContent, err := img.OriginFs.Open(src)
	defer imageContent.Close()
	if err != nil {
		log.Println(err)
		return
	}
	srcImage, _, err := image.Decode(imageContent)
	if err != nil {
		log.Println(err)
		return
	}
	dst := imaging.Resize(srcImage, 0, 1080, imaging.Lanczos)
	newCacheFile, createError := img.ThumbFs.Create(src)
	if createError != nil {
		log.Println(createError)
		return
	}
	defer newCacheFile.Close()
	err = jpeg.Encode(newCacheFile, dst, &jpeg.Options{Quality: jpeg.DefaultQuality})
	if err != nil {
		log.Printf("jpeg output fail: %s", err)
		return
	}
	log.Printf("Imaging Thumbnail %s success in %d", src, time.Now().Sub(start).Milliseconds())
}
