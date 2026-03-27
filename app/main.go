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

var locateAndRead = utils.LocateAndRead
var unmarshalYAML = yaml.Unmarshal

func main() {
	conf := new(config.GalleryConfig)
	loadConfig(conf)
	conf.Setup()
	gin.SetMode(gin.ReleaseMode)
	engine := gin.Default()
	engine.Use(corsMiddleware())
	gallery.Init(engine, *conf)
	openBrowser(fmt.Sprintf("http://localhost:%d/", conf.Port))
	_ = engine.Run(fmt.Sprintf(":%d", conf.Port))
}

func loadConfig(conf *config.GalleryConfig) {
	bytes, err := locateAndRead("gallery.yaml")
	if err != nil {
		if !os.IsNotExist(err) {
			log.Println("Read gallery.yaml fail, fallback")
		}
		return
	}

	log.Println("Load config from gallery.yaml")
	err = unmarshalYAML(bytes, conf)
	if err != nil {
		log.Println("Parse gallery.yaml fail, fallback")
	}
	log.Printf("Load Config: %+v", conf)
}

func corsMiddleware() gin.HandlerFunc {
	return func(context *gin.Context) {
		context.Writer.Header().Set("Server", "SAIO")
		context.Writer.Header().Set("Access-Control-Allow-Origin", "*")
		context.Writer.Header().Set("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
		context.Writer.Header().Set("Access-Control-Allow-Headers", "Origin, Content-Type")
		if context.Request.Method == "OPTIONS" {
			context.AbortWithStatus(204)
			return
		}
	}
}

func browserCommand(goos string, url string) (string, []string, bool) {
	switch goos {
	case "linux":
		return "xdg-open", []string{url}, true
	case "windows":
		return "rundll32", []string{"url.dll,FileProtocolHandler", url}, true
	case "darwin":
		return "open", []string{url}, true
	default:
		return "", nil, false
	}
}

func openBrowser(url string) {
	log.Printf("Open %s", url)
	command, args, ok := browserCommand(runtime.GOOS, url)
	if !ok {
		return
	}
	_ = exec.Command(command, args...).Start()
}
