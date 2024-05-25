package storage

import (
	"io"
	"log"
	"net/http"
	"os"
	"path"
	"strings"
)

type LocalFs struct {
	*os.File
}

func (fs *LocalFs) OpenOrMkdir(name string) Storage {
	return &LocalFs{SafetyOpenDirectory(fs.Name(), name)}
}

func (fs *LocalFs) Save(name string, reader io.ReadCloser) error {
	defer reader.Close()
	fileName := path.Join(fs.Name(), name)
	fileWriter, e := os.OpenFile(fileName, os.O_CREATE|os.O_RDWR|os.O_TRUNC, 0666)
	if e != nil {
		return e
	}
	_, e = io.Copy(fileWriter, reader)
	if e != nil {
		return e
	}
	e = fileWriter.Close()
	return e
}

func (fs *LocalFs) Exist(name string) bool {
	fileName := path.Join(fs.Name(), name)
	if _, err := os.Stat(fileName); os.IsNotExist(err) {
		return false
	}
	return true
}

func (fs *LocalFs) Open(name string) (http.File, error) {
	fileName := path.Join(fs.Name(), name)
	return os.Open(fileName)
}

func (fs *LocalFs) Rename(oldName, newName string) error {
	oldFileName := path.Join(fs.Name(), oldName)
	newFileName := path.Join(fs.Name(), newName)
	return os.Rename(oldFileName, newFileName)
}

func (fs *LocalFs) Create(name string) (FileInf, error) {
	target := path.Join(fs.Name(), name)
	_ = SafetyCreateDirectoryByFileName(target)
	return os.OpenFile(target, os.O_RDWR|os.O_CREATE|os.O_TRUNC, 0666)
}

func (fs *LocalFs) ReadDir(name string) ([]os.FileInfo, error) {
	fileName := path.Join(fs.Name(), name)
	open, _ := os.Open(fileName)
	return open.Readdir(0)
}

func (fs *LocalFs) Read(name string) ([]byte, error) {
	fileName := path.Join(fs.Name(), name)
	return os.ReadFile(fileName)
}

func (fs *LocalFs) Join(s ...string) string {
	return path.Join(s...)
}

func (fs *LocalFs) GetPath() string {
	return fs.File.Name()
}

func SafetyOpenDirectory(paths ...string) *os.File {
	fp := path.Join(paths...)
	if _, err := os.Stat(fp); os.IsNotExist(err) {
		err = os.MkdirAll(fp, 0755)
	}
	f, err := os.Open(fp)
	if err != nil {
		log.Panicln(err)
	}
	return f
}

func SafetyCreateDirectoryByFileName(fileName string) error {
	if strings.ContainsRune(fileName, os.PathSeparator) {
		index := strings.LastIndexByte(fileName, os.PathSeparator)
		return os.MkdirAll(fileName[:index], 0755)
	}
	return nil
}

func NewLocalFs(paths ...string) Storage {
	directory := SafetyOpenDirectory(paths...)
	return &LocalFs{directory}
}
