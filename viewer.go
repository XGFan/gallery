package gallery

import (
	"bytes"
	"context"
	"embed"
	_ "embed"
	"encoding/json"
	"gallery/common/misc"
	"gallery/common/storage"
	"gallery/config"
	"gallery/fastimage"
	"gallery/thumbnail"
	"github.com/XGFan/go-utils"
	"github.com/gin-gonic/gin"
	"image"
	"io"
	"log"
	"net/http"
	"os"
	"path"
	"reflect"
	"strings"
	"sync"
	"time"
)

//go:embed web/dist
var webFs embed.FS

const ImgSizeCache = ".img-size.json"

type StaticImageResolver struct {
	OriginFs      storage.Storage
	CacheFs       storage.Storage
	Tasks         chan thumbnail.Task
	OriginAdapter http.FileSystem
	ThumbAdapter  http.FileSystem
}

func (sir *StaticImageResolver) Worker(ctx context.Context) {
	worker := thumbnail.NewWorker(sir.OriginFs, sir.CacheFs)
	worker.Run(ctx, sir.Tasks)
}

func (sir *StaticImageResolver) AddThumbTask(src string) {
	log.Printf("thumb cache missed: %s", src)
	sir.Tasks <- thumbnail.Task{
		Source: src,
	}
}

func NewStaticImageResolver(baseFs storage.Storage,
	cacheFs storage.Storage,
	forceThumb []string,
	ctx context.Context) *StaticImageResolver {
	sir := &StaticImageResolver{
		OriginFs: baseFs,
		CacheFs:  cacheFs,
		Tasks:    make(chan thumbnail.Task, 30),
	}
	pm := make(utils.PrefixMatcher)
	for _, p := range forceThumb {
		pm.Add(p)
	}

	go sir.Worker(ctx)
	sir.ThumbAdapter = FsFunc(func(name string) (http.File, error) {
		source := CleanUrlPath(name)
		if storage.IsValidPic(source) {
			f, err := cacheFs.Open(source)
			if os.IsNotExist(err) {
				sir.AddThumbTask(source)
				return sir.OriginFs.Open(name)
			} else {
				return f, err
			}
		} else {
			return nil, os.ErrNotExist
		}
	})

	sir.OriginAdapter = FsFunc(func(name string) (http.File, error) {
		source := CleanUrlPath(name)
		if !storage.IsValidPic(source) {
			return nil, os.ErrNotExist
		}
		if pm.Match(source) {
			return sir.ThumbAdapter.Open(name)
		}
		return sir.OriginFs.Open(source)
	})

	return sir
}

/**
there should be three modes
Explore mode: Simple mode, only show current directory
Album mode: Show current directory name and children directory names which contain images
Image mode: Show current directory and children images
*/

func EnableViewer(s *gin.Engine, conf config.GalleryConfig) {
	ctx, _ := context.WithCancel(context.Background())
	originFs := storage.NewFs(conf.Resource.Base)
	cacheFs := storage.NewFs(conf.Cache)
	collector := NewCollector(originFs, cacheFs, conf.Resource.Exclude, ctx)
	imageResolver := NewStaticImageResolver(originFs, cacheFs, conf.Resource.ForceThumbnail, ctx)
	//warmup
	go collector.warmUp()
	//image OriginFs
	s.StaticFS("/file/", imageResolver.OriginAdapter)
	s.StaticFS("/thumbnail/", imageResolver.ThumbAdapter)

	s.GET("/api/tree", func(c *gin.Context) {
		tree := collector.Data.toTree()
		withLeaf := misc.BoolVar(c.Query("leaf"), true)
		if !withLeaf {
			filterEmpty(tree)
		}
		c.JSON(200, tree)
	})

	s.GET("/api/explore/*name", func(c *gin.Context) {
		collector.Trigger()
		name := c.Param("name")[1:]
		node := collector.Data.Locate(name)
		c.JSON(200, node.explore())
	})

	s.GET("/api/image/*name", func(c *gin.Context) {
		collector.Trigger()
		name := c.Param("name")[1:]
		node := collector.Data.Locate(name)
		c.JSON(200, node.image())
	})

	s.GET("/api/album/*name", func(c *gin.Context) {
		collector.Trigger()
		name := c.Param("name")[1:]
		node := collector.Data.Locate(name)
		c.JSON(200, node.album())
	})

	s.GET("/api/random/*name", func(c *gin.Context) {
		name := c.Param("name")[1:]
		flatten := utils.DefaultToTrue(c.Query("flat"))
		random, _ := utils.Retry(5, func() (NodeWithParent, error) {
			return collector.Data.Locate(name).Random(flatten)
		})
		c.JSON(200, random)
	})
	s.NoRoute(func(c *gin.Context) {
		if c.Request.URL.Path == "/" || c.Request.URL.Path == "/index.html" {
			defer func() {
				c.Request.URL.Path = "/"
			}()
			c.FileFromFS("web/dist/", http.FS(webFs))
		} else {
			target := path.Join("web/dist", c.Request.URL.Path)
			f, err := webFs.Open(target)
			if err != nil {
				if os.IsNotExist(err) {
					c.FileFromFS("web/dist/", http.FS(webFs))
				}
			} else {
				f.Close()
				c.FileFromFS(target, http.FS(webFs))
			}
		}
	})
}

func filterEmpty(m map[string]interface{}) {
	for s, i := range m {
		if i == nil || len(i.(map[string]interface{})) == 0 {
			delete(m, s)
		} else {
			filterEmpty(i.(map[string]interface{}))
		}
	}
}

type Collector struct {
	OriginFs      storage.Storage
	CacheFs       storage.Storage
	Exclude       utils.Set[string]
	Data          *DirectoryNode
	lastScan      int64
	sizeCache     map[string]Size
	rescanTrigger chan struct{}
}

func NewCollector(originFs storage.Storage, cacheFs storage.Storage,
	exclude []string, ctx context.Context) *Collector {
	v := &Collector{
		OriginFs:      originFs,
		CacheFs:       cacheFs,
		Exclude:       utils.NewSetWithSlice(exclude),
		lastScan:      0,
		rescanTrigger: make(chan struct{}, 10),
	}
	go v.ScanWorker(ctx)
	return v
}

func (v *Collector) Trigger() {
	if (time.Now().Unix() - v.lastScan) > 300 {
		log.Println("viewer cache expired")
		go func() {
			v.rescanTrigger <- struct{}{}
		}()
	}
}

func (v *Collector) ScanWorker(ctx context.Context) {
	for {
		select {
		case <-ctx.Done():
			log.Println("Scan exit")
			return
		case <-v.rescanTrigger:
			start := time.Now()
			log.Println("Scan started")
			v.Scan()
			log.Printf("Scan Image finished: %s", time.Now().Sub(start).Truncate(time.Millisecond))
			v.ScanImgSize()
			log.Printf("Scan Size finished: %s", time.Now().Sub(start).Truncate(time.Millisecond))
		}
	}
}

func (v *Collector) warmUp() {
	start := time.Now()
	log.Println("Warmup Start")
	v.Scan()
	log.Printf("Warmup Image Finished: %s", time.Now().Sub(start).Truncate(time.Millisecond))
	v.ScanImgSize()
	log.Printf("Warmup Size Finished: %s", time.Now().Sub(start).Truncate(time.Millisecond))
}

func (v *Collector) Scan() {
	task := misc.NewUnboundedChan[Node](1)
	result := make(chan ScanInfo, 10)
	task.In <- Node{}
	wg := &sync.WaitGroup{}
	wg.Add(1)
	for i := 0; i < 16; i++ {
		go v.forkJoinScan(wg, task, result)
	}
	go func() {
		wg.Wait()
		close(task.In)
		close(result)
	}()
	node := &DirectoryNode{
		Node:        Node{},
		Images:      make([]ImageNode, 0),
		Others:      make([]Node, 0),
		Directories: make(map[string]*DirectoryNode),
	}
	for info := range result {
		located := node.Locate(info.Path)
		located.Images = info.Images
		located.Others = info.Others
		located.CoverIndex = info.CoverIndex
	}
	v.Data = node
	v.lastScan = time.Now().Unix()
}

func (v *Collector) ScanImgSize() {
	if v.sizeCache == nil {
		open, err := v.CacheFs.Open(ImgSizeCache)
		if err == nil {
			defer open.Close()
			_ = json.NewDecoder(open).Decode(&v.sizeCache)
			log.Printf("Load img size cache from disk, size: %d", len(v.sizeCache))
		}
	}
	if v.sizeCache != nil {
		v.Data.load(v.sizeCache)
	}
	collectImgSize(v.OriginFs, v.Data)
	newCache := v.Data.dump()
	if !reflect.DeepEqual(v.sizeCache, newCache) {
		marshal, _ := json.Marshal(newCache)
		_ = v.CacheFs.Save(ImgSizeCache, io.NopCloser(bytes.NewReader(marshal)))
		v.sizeCache = newCache
		log.Printf("Save new img size cache to disk, size: %d", len(newCache))
	}

}

func collectImgSize(fs storage.Storage, dn *DirectoryNode) {
	for i := range dn.Images {
		if dn.Images[i].Size != EmptySize {
			continue
		}
		file, err := fs.Open(dn.Images[i].Path)
		if err == nil {
			imageInfo := fastimage.GetInfoReader(file)
			if imageInfo.Width != 0 && imageInfo.Height != 0 {
				dn.Images[i].Size = Size{
					Width:  int(imageInfo.Width),
					Height: int(imageInfo.Height),
				}
			} else {
				file.Seek(0, 0)
				img, _, err := image.Decode(file)
				if err != nil {
					log.Printf("detect image failed: %s, %s", dn.Images[i].Path, err)
				} else {
					log.Printf("detect image by fallback: %s", dn.Images[i].Path)
					dn.Images[i].Size = Size{
						Width:  img.Bounds().Dx(),
						Height: img.Bounds().Dy(),
					}
				}
			}
		}
	}
	for i := range dn.Directories {
		collectImgSize(fs, dn.Directories[i])
	}
}

func (v *Collector) forkJoinScan(wg *sync.WaitGroup, task misc.UnboundedChan[Node], result chan ScanInfo) {
	for node := range task.Out {
		readDir, _ := v.OriginFs.ReadDir(node.Path)
		images := make([]ImageNode, 0, 16)
		others := make([]Node, 0, 16)
		var coverIndex = 0
		for _, info := range readDir {
			targetPath := v.OriginFs.Join(node.Path, info.Name())
			if v.Exclude.Contains(targetPath) {
				continue
			}
			if !storage.IsNormalFile(info.Name()) {
				continue
			}
			target := Node{
				Name: info.Name(),
				Path: targetPath,
			}
			if info.IsDir() { //目录下的子文件夹
				//has more task
				wg.Add(1)
				task.In <- target
			} else if storage.IsValidPic(info.Name()) {
				imageNode := ImageNode{
					Node: target,
					Size: EmptySize,
				}
				images = append(images, imageNode)
				if strings.HasPrefix(strings.ToLower(info.Name()), "cover") {
					coverIndex = len(images) - 1
				}
			} else {
				others = append(others, target)
			}
		}
		result <- ScanInfo{
			Node:       node,
			Images:     images,
			Others:     others,
			CoverIndex: coverIndex,
		}
		wg.Done()
	}
}

type ScanInfo struct {
	Node
	Images     []ImageNode
	Others     []Node
	CoverIndex int
}

type FsFunc func(string) (http.File, error)

func (fsFunc FsFunc) Open(name string) (http.File, error) {
	return fsFunc(name)
}

func CleanUrlPath(name string) string {
	if strings.HasPrefix(name, "/") {
		return name[1:]
	}
	return name
}
