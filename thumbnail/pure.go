//go:build !vips && !nothumb

package thumbnail

import (
	"gallery/common/storage"
	"log"
)

func NewImageWorker(originFs storage.Storage, thumbFs storage.Storage) Worker {
	log.Println("Using ImagingWorker")
	return &ImagingWorker{originFs, thumbFs}
}
