package config

import (
	"github.com/XGFan/go-utils"
	"log"
	"path"
	"path/filepath"
)

type Setup interface {
	Setup()
}

type GalleryConfig struct {
	Port               int            `yaml:"port"`
	Resource           ResourceConfig `yaml:"resource"`
	ThumbnailProcessor string         `yaml:"thumbnail_processor"`
	Cache              string         `yaml:"cache"`
}

type ResourceConfig struct {
	Base           string   `yaml:"base"`
	Exclude        []string `yaml:"exclude"`
	ForceThumbnail []string `yaml:"force_thumbnail"`
}

func (g *GalleryConfig) Setup() {
	var err error
	if g.Port == 0 {
		g.Port = 8000
	}
	if g.Resource.Base == "" {
		g.Resource.Base = "."
	}
	if !path.IsAbs(g.Resource.Base) {
		g.Resource.Base, err = filepath.Abs(g.Resource.Base)
		utils.PanicIfErr(err)
	}
	if g.Resource.Exclude != nil {
		for _, s := range g.Resource.Exclude {
			if path.IsAbs(s) {
				log.Fatal("resource.exclude only support relative path")
			}
		}
	}
	if g.Resource.ForceThumbnail != nil {
		for _, s := range g.Resource.ForceThumbnail {
			if path.IsAbs(s) {
				log.Fatal("resource.force_thumbnail only support relative path")
			}
		}
	}
	if g.Cache == "" {
		g.Cache = ".cache"
	}
	if !path.IsAbs(g.Cache) {
		g.Cache, err = filepath.Abs(g.Cache)
		utils.PanicIfErr(err)
	}
	if g.ThumbnailProcessor == "" {
		g.ThumbnailProcessor = "AUTO"
	}
}
