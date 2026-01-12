package main

import (
	"fmt"
	"gallery"
	"gallery/config"
	"log"
	_ "net/http/pprof"
	"os"
	"os/exec"
	"runtime"

	"github.com/XGFan/go-utils"
	"github.com/gin-gonic/gin"
	"gopkg.in/yaml.v3"
)

func main() {
	conf := new(config.GalleryConfig)
	bytes, err := utils.LocateAndRead("gallery.yaml")
	if err != nil {
		if !os.IsNotExist(err) {
			log.Println("Read gallery.yaml fail, fallback")
		}
	} else {
		log.Println("Load config from gallery.yaml")
		err = yaml.Unmarshal(bytes, conf)
		if err != nil {
			log.Println("Parse gallery.yaml fail, fallback")
		}
		log.Printf("Load Config: %+v", conf)
	}
	conf.Setup()
	gin.SetMode(gin.ReleaseMode)
	engine := gin.Default()
	engine.Use(func(context *gin.Context) {
		context.Writer.Header().Set("Server", "SAIO")
		context.Writer.Header().Set("Access-Control-Allow-Origin", "*")
		context.Writer.Header().Set("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
		context.Writer.Header().Set("Access-Control-Allow-Headers", "Origin, Content-Type")
		if context.Request.Method == "OPTIONS" {
			context.AbortWithStatus(204)
			return
		}
	})
	gallery.Init(engine, *conf)
	openBrowser(fmt.Sprintf("http://localhost:%d/", conf.Port))
	_ = engine.Run(fmt.Sprintf(":%d", conf.Port))
}

func openBrowser(url string) {
	log.Printf("Open %s", url)
	switch runtime.GOOS {
	case "linux":
		_ = exec.Command("xdg-open", url).Start()
	case "windows":
		_ = exec.Command("rundll32", "url.dll,FileProtocolHandler", url).Start()
	case "darwin":
		_ = exec.Command("open", url).Start()
	}
}
