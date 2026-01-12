package gallery

import (
	"context"
	"embed"
	"log"
	"net/http"
	"os"
	"path"
	"sort"
	"time"

	utils "github.com/XGFan/go-utils"
	"github.com/gin-gonic/gin"
	swaggerFiles "github.com/swaggo/files"
	ginSwagger "github.com/swaggo/gin-swagger"

	"gallery/common/misc"
	"gallery/common/storage"
	"gallery/config"
	"gallery/core"
	_ "gallery/swagger"
)

// @title Gallery API
// @version 1.0
// @description Image gallery service with folder browsing, album management and tagging support.
// @BasePath /

//go:embed web/dist
var webFs embed.FS

type Gallery struct {
	Root     *core.TraverseNode
	lastScan int64

	scanner       *core.Scanner
	originFs      storage.Storage
	rescanTrigger chan struct{}
}

// NewGallery creates a new Gallery
func NewGallery(originFs storage.Storage, cacheFs storage.Storage,
	exclude []string, virtualPath map[string][]string, tagBlacklist []string, ctx context.Context) *Gallery {
	cache := core.NewCacheManager(cacheFs, tagBlacklist)
	g := &Gallery{
		Root:          &core.TraverseNode{Directories: make(map[string]*core.TraverseNode)},
		scanner:       core.NewScanner(originFs, exclude, cache, virtualPath),
		rescanTrigger: make(chan struct{}),
	}
	go g.scanWorker(ctx)
	return g
}

// Trigger triggers a rescan if cache expired
func (g *Gallery) Trigger() {
	if (time.Now().Unix() - g.lastScan) > 300 {
		go func() {
			select {
			case g.rescanTrigger <- struct{}{}:
				log.Println("viewer cache expired")
			default:
			}
		}()
	}
}

func (g *Gallery) scanWorker(ctx context.Context) {
	for {
		select {
		case <-ctx.Done():
			log.Println("Scan exit")
			return
		case <-g.rescanTrigger:
			g.scanner.Scan(g.Root)
			g.lastScan = time.Now().Unix()
		}
	}
}

func (g *Gallery) warmUp() {
	if count, err := g.scanner.Restore(g.Root); err == nil && count > 0 {
		log.Printf("Warm up complete, service ready (restored %d items)", count)
	} else {
		log.Printf("Cache incomplete, waiting for scan")
	}
	g.rescanTrigger <- struct{}{}
}

// GetAllTags returns all tags with statistics
func (g *Gallery) GetAllTags() []core.TagStat {
	tagStats := make(map[string]*core.TagStat)

	allImages := g.Root.Image()
	for _, img := range allImages {
		for _, tag := range img.Tags {
			if tag.Value < core.TagMinValue {
				continue
			}
			if g.scanner.Cache.TagBlacklist.Contains(tag.Tag) {
				continue
			}
			if stat, exists := tagStats[tag.Tag]; exists {
				stat.Count++
				stat.TotalScore += tag.Value
			} else {
				tagStats[tag.Tag] = &core.TagStat{
					Tag:        tag.Tag,
					Count:      1,
					TotalScore: tag.Value,
				}
			}
		}
	}

	result := make([]core.TagStat, 0, len(tagStats))
	for _, stat := range tagStats {
		stat.AvgScore = float64(stat.TotalScore) / float64(stat.Count)
		stat.Weight = float64(stat.Count) * stat.AvgScore
		result = append(result, *stat)
	}

	sort.Slice(result, func(i, j int) bool {
		return result[i].Weight > result[j].Weight
	})

	return result
}

// HandleTree godoc
// @Summary Get folder tree
// @Description Returns the directory tree structure
// @Tags browse
// @Produce json
// @Param leaf query bool false "Include leaf nodes (default: true)"
// @Success 200 {object} map[string]interface{}
// @Router /api/tree [get]
func (g *Gallery) HandleTree(c *gin.Context) {
	tree := g.Root.ToTree()
	withLeaf := misc.BoolVar(c.Query("leaf"), true)
	if !withLeaf {
		filterEmpty(tree)
	}
	c.JSON(200, tree)
}

// HandleExplore godoc
// @Summary Explore a directory
// @Description Returns immediate contents of a directory (subdirectories, images, others)
// @Tags browse
// @Produce json
// @Param name path string true "Directory path"
// @Success 200 {object} core.SimpleDirectory
// @Router /api/explore/{name} [get]
func (g *Gallery) HandleExplore(c *gin.Context) {
	g.Trigger()
	name := c.Param("name")[1:]
	node := g.Root.Locate(name)
	c.JSON(200, node.Explore())
}

// HandleImage godoc
// @Summary List all images under a directory
// @Description Returns all images recursively under the specified directory
// @Tags images
// @Produce json
// @Param name path string true "Directory path"
// @Success 200 {array} core.ImageNode
// @Router /api/image/{name} [get]
func (g *Gallery) HandleImage(c *gin.Context) {
	g.Trigger()
	name := c.Param("name")[1:]
	node := g.Root.Locate(name)
	c.JSON(200, node.Image())
}

// HandleAlbum godoc
// @Summary List all albums under a directory
// @Description Returns all album directories (directories containing images) recursively
// @Tags albums
// @Produce json
// @Param name path string true "Directory path"
// @Success 200 {array} core.DirNode
// @Router /api/album/{name} [get]
func (g *Gallery) HandleAlbum(c *gin.Context) {
	g.Trigger()
	name := c.Param("name")[1:]
	node := g.Root.Locate(name)
	c.JSON(200, node.Album())
}

// HandleRandom godoc
// @Summary Get a random image
// @Description Returns a random image from the specified directory
// @Tags images
// @Produce json
// @Param name path string true "Directory path"
// @Param flat query bool false "Flatten search into subdirectories (default: true)"
// @Success 200 {object} core.NodeWithParent
// @Router /api/random/{name} [get]
func (g *Gallery) HandleRandom(c *gin.Context) {
	name := c.Param("name")[1:]
	flatten := utils.DefaultToTrue(c.Query("flat"))
	random, _ := utils.Retry(5, func() (core.NodeWithParent, error) {
		return g.Root.Locate(name).Random(flatten)
	})
	c.JSON(200, random)
}

// HandleTag godoc
// @Summary Get all tags
// @Description Returns tag statistics across all images
// @Tags tags
// @Produce json
// @Success 200 {array} core.TagStat
// @Router /api/tag [get]
func (g *Gallery) HandleTag(c *gin.Context) {
	c.JSON(200, g.GetAllTags())
}

// Init initializes the gallery routes
func Init(s *gin.Engine, conf config.GalleryConfig) {
	ctx, _ := context.WithCancel(context.Background())
	originFs := storage.NewFs(conf.Resource.Base)
	cacheFs := storage.NewFs(conf.Cache)
	gallery := NewGallery(originFs, cacheFs, conf.Resource.Exclude, conf.Resource.VirtualPath, conf.Resource.TagBlacklist, ctx)
	imageResolver := NewStaticImageResolver(originFs, cacheFs, conf.Resource.ForceThumbnail, ctx)

	// warmup
	go gallery.warmUp()

	// image OriginFs
	s.StaticFS("/file/", imageResolver.OriginAdapter)
	s.StaticFS("/thumbnail/", imageResolver.ThumbAdapter)

	// Swagger UI
	s.GET("/swagger/*any", ginSwagger.WrapHandler(swaggerFiles.Handler))

	// API routes
	s.GET("/api/tree", gallery.HandleTree)
	s.GET("/api/explore/*name", gallery.HandleExplore)
	s.GET("/api/image/*name", gallery.HandleImage)
	s.GET("/api/album/*name", gallery.HandleAlbum)
	s.GET("/api/random/*name", gallery.HandleRandom)
	s.GET("/api/tag", gallery.HandleTag)

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

// filterEmpty removes empty directories from tree
func filterEmpty(m map[string]interface{}) {
	for k, v := range m {
		if mm, ok := v.(map[string]interface{}); ok {
			if len(mm) == 0 {
				delete(m, k)
			} else {
				filterEmpty(mm)
				if mm != nil && len(mm) == 0 {
					delete(m, k)
				}
			}
		}
	}
}
