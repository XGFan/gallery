package main

import (
	"fmt"
	"gallery"
	"gallery/config"
	"github.com/XGFan/go-utils"
	"github.com/gin-gonic/gin"
	"gopkg.in/yaml.v3"
	"log"
	_ "net/http/pprof"
	"os/exec"
	"runtime"
)

func main() {
	conf := new(config.GalleryConfig)
	bytes, err := utils.LocateAndRead("gallery.yaml")
	if err != nil {
		log.Println("Read gallery.yaml fail, fallback")
	} else {
		log.Println("Load config from gallery.yaml")
		err = yaml.Unmarshal(bytes, conf)
		if err != nil {
			log.Println("Parse gallery.yaml fail, fallback")
		}
	}
	conf.Setup()
	log.Printf("Load Config: %+v", conf)
	gin.SetMode(gin.ReleaseMode)
	engine := gin.Default()
	engine.Use(func(context *gin.Context) {
		context.Writer.Header().Set("Server", "SAIO")
	})
	gallery.EnableViewer(engine, *conf)
	openBrowser(fmt.Sprintf("http://localhost:%d/", conf.Port))
	engine.Run(fmt.Sprintf(":%d", conf.Port))
}

func openBrowser(url string) {
	var err error
	switch runtime.GOOS {
	case "linux":
		err = exec.Command("xdg-open", url).Start()
	case "windows":
		err = exec.Command("rundll32", "url.dll,FileProtocolHandler", url).Start()
	case "darwin":
		err = exec.Command("open", url).Start()
	default:
		err = fmt.Errorf("unsupported platform")
	}
	if err != nil {
		log.Fatal(err)
	}
}
