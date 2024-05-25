//go:build nothumb

package thumbnail

import (
	"gallery/common/storage"
)

func NewImageWorker(originFs storage.Storage, thumbFs storage.Storage) Worker {
	return &NoWorker{}
}

type NoWorker struct {
}

func (n NoWorker) Thumbnail(src string) {
}
