//go:build vips && !nothumb

package thumbnail

import (
	"gallery/common/storage"
	"github.com/davidbyttow/govips/v2/vips"
	"log"
	"os"
	"path"
	"time"
)

type VipsWorker struct {
	OriginPrefix string
	ThumbPrefix  string
}

func NewImageWorker(originFs storage.Storage, thumbFs storage.Storage) Worker {
	log.Println("Using VipsWorker")
	vips.LoggingSettings(func(messageDomain string, messageLevel vips.LogLevel, message string) {

	}, vips.LogLevelInfo)
	vips.Startup(&vips.Config{})
	//TODO vips.Shutdown()
	return &VipsWorker{OriginPrefix: originFs.GetPath(), ThumbPrefix: thumbFs.GetPath()}
}

func (v *VipsWorker) Thumbnail(src string) {
	start := time.Now()
	file, err := vips.NewThumbnailWithSizeFromFile(path.Join(v.OriginPrefix, src),
		1920, 0, vips.InterestingNone, vips.SizeDown)
	if err != nil {
		log.Printf("Vips Thumbnail fail: %s, %s", path.Join(v.OriginPrefix, src), err)
		return
	}
	native, _, err := file.ExportNative()
	if err != nil {
		log.Printf("Vips Thumbnail fail: %s, %s", src, err)
		return
	}
	_ = storage.SafetyCreateDirectoryByFileName(path.Join(v.ThumbPrefix, src))
	err = os.WriteFile(path.Join(v.ThumbPrefix, src), native, 0644)
	if err != nil {
		log.Printf("Vips Thumbnail fail: %s, %s", src, err)
		return
	}
	log.Printf("Vips Thumbnail %s success in %d", src, time.Now().Sub(start).Milliseconds())
}
