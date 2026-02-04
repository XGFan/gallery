package storage

import (
	"bytes"
	"fmt"
	"github.com/XGFan/go-utils"
	"io"
	"net/http"
	"os"
	"strings"
)

type Storage interface {
	OpenOrMkdir(name string) Storage
	Save(name string, reader io.ReadCloser) error
	Rename(oldName, newName string) error
	Exist(name string) bool
	ReadDir(name string) ([]os.FileInfo, error)
	Open(name string) (http.File, error)
	Read(name string) ([]byte, error)
	Join(s ...string) string
	Create(fileName string) (FileInf, error)
	GetPath() string
}
type FileInf interface {
	io.Reader
	io.Writer
	io.Seeker
	io.Closer
}

var picExts = utils.NewSetWithSlice[string]([]string{"png", "jpg", "jpeg", "bmp", "gif"})
var videoExts = utils.NewSetWithSlice[string]([]string{"mp4", "avi", "mkv", "webm", "flv", "wmv", "ts", "mov", "m4v", "ogv", "ogg"})

func NewFs(str string) Storage {
	return NewLocalFs(str)
}

func IsValidVideo(name string) bool {
	ext := GetExt(name)
	if !(videoExts.Contains(ext)) {
		return false
	}
	return true
}

func IsValidPic(name string) bool {
	ext := GetExt(name)
	if !(picExts.Contains(ext)) {
		return false
	}
	if strings.Contains(name, "thumb") {
		return false
	}
	return true
}

func GetExt(s string) string {
	split := strings.Split(s, ".")
	return strings.ToLower(split[len(split)-1])
}

func IsNormalFile(name string) bool {
	if name == "" {
		return false
	}
	switch name[0] {
	case '@':
		fallthrough
	case '.':
		fallthrough
	case '~':
		return false
	default:
		return true
	}
}

func NormPath(path string) string {
	path = strings.Replace(path, `/`, `\`, -1)
	for strings.HasPrefix(path, `.\`) {
		path = path[2:]
	}
	if path == "." {
		return ""
	}
	return path
}

func GetOrCreateFile(baseFs Storage, dbFile string) (string, error) {
	if !baseFs.Exist(dbFile) {
		_, err := baseFs.Create(dbFile)
		if err != nil {
			return "", fmt.Errorf("create %s file fail: %w", dbFile, err)
		}
	}
	return baseFs.Join(baseFs.GetPath(), dbFile), nil
}

type ProxyFs struct {
	Storage
	Transform func(origin []byte) ([]byte, error)
}

func (pfs ProxyFs) Save(name string, reader io.ReadCloser) error {
	defer utils.CloseSilent(reader)
	all, err := io.ReadAll(reader)
	if err != nil {
		return err
	}
	modified, err := pfs.Transform(all)
	if err != nil {
		return err
	}
	return pfs.Storage.Save(name, io.NopCloser(bytes.NewReader(modified)))
}
