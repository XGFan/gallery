package core

import (
	"bytes"
	"encoding/json"
	"io"
	"log"
	"reflect"
	"sync"
	"time"

	utils "github.com/XGFan/go-utils"

	"gallery/common/storage"
)

// Cache file names
const ImgSizeCache = ".img-size.json"
const ImgTagCache = ".img-tag.json"
const ImgCaptionCache = ".img-caption.json"
const ImgStructureCache = ".img.json"
const VideoMetaCache = ".video-meta.json"
const TagMinValue = 60

// VideoMeta represents metadata for video files
type VideoMeta struct {
	Path            string  `json:"path,omitempty"`
	DurationSec     float64 `json:"duration_sec"`
	Width           int     `json:"width"`
	Height          int     `json:"height"`
	SizeBytes       int64   `json:"size_bytes"`
	ModTimeUnixNano int64   `json:"mod_time_unix_nano"`
}

// CacheManager handles persistence with smart diffing
type CacheManager struct {
	Fs           storage.Storage
	TagBlacklist utils.Set[string]

	// Internal state mirroring disk content
	currentSizes     map[string]Size
	currentTags      map[string][]TagInfo
	currentCaptions  map[string]string
	currentVideoMeta map[string]VideoMeta
	workingVideoMeta map[string]VideoMeta
	videoMetaMu      sync.RWMutex
}

// NewCacheManager creates a new CacheManager
func NewCacheManager(cacheFs storage.Storage, tagBlacklist []string) *CacheManager {
	return &CacheManager{
		Fs:               cacheFs,
		TagBlacklist:     utils.NewSetWithSlice(tagBlacklist),
		currentSizes:     make(map[string]Size),
		currentTags:      make(map[string][]TagInfo),
		currentCaptions:  make(map[string]string),
		currentVideoMeta: make(map[string]VideoMeta),
		workingVideoMeta: make(map[string]VideoMeta),
	}
}

// LoadScanItems loads the structure snapshot (Event Stream) and auxiliary caches
func (c *CacheManager) LoadScanItems() ([]ScanItem, error) {
	// 1. Load Auxiliary Caches (Knowledge Base)
	// We load these first so Scanner can use them even if Structure Cache is partial or missing.
	c.loadJSON(ImgSizeCache, &c.currentSizes)
	c.loadJSON(ImgTagCache, &c.currentTags)
	c.loadJSON(ImgCaptionCache, &c.currentCaptions)
	c.loadJSON(VideoMetaCache, &c.currentVideoMeta)

	c.videoMetaMu.Lock()
	for k, v := range c.currentVideoMeta {
		c.workingVideoMeta[k] = v
	}
	c.videoMetaMu.Unlock()

	log.Printf("Knowledge Base loaded: %d sizes, %d tags, %d video metas", len(c.currentSizes), len(c.currentTags), len(c.currentVideoMeta))

	// 2. Load Structure Snapshot (Event Stream)
	var items []ScanItem
	if f, err := c.Fs.Open(ImgStructureCache); err == nil {
		defer f.Close()
		if err := json.NewDecoder(f).Decode(&items); err != nil {
			log.Printf("Failed to decode structure cache: %v", err)
			return nil, err
		}
	} else {
		return nil, nil // No cache exists
	}

	log.Printf("Structure Snapshot loaded: %d events", len(items))
	return items, nil
}

// Save persists changes to disk if needed
func (c *CacheManager) Save(root *TraverseNode) error {
	// 1. Save Structure (Flatten Tree to Event Stream)
	// We always save structure to ensure it matches current runtime state.
	items := root.Flatten()
	c.saveJSON(ImgStructureCache, items)

	// 2. Diff and Save Sizes
	newSizes := root.Dump()
	if !reflect.DeepEqual(c.currentSizes, newSizes) {
		if c.saveJSON(ImgSizeCache, newSizes) == nil {
			c.currentSizes = newSizes
			log.Printf("Updated size cache: %d entries", len(newSizes))
		}
	}

	// 3. Diff and Save Meta
	newTags, newCaptions := root.DumpMeta()

	if !reflect.DeepEqual(c.currentTags, newTags) {
		if c.saveJSON(ImgTagCache, newTags) == nil {
			c.currentTags = newTags
			log.Printf("Updated tag cache: %d entries", len(newTags))
		}
	}

	if !reflect.DeepEqual(c.currentCaptions, newCaptions) {
		if c.saveJSON(ImgCaptionCache, newCaptions) == nil {
			c.currentCaptions = newCaptions
			log.Printf("Updated caption cache: %d entries", len(newCaptions))
		}
	}

	// 4. Diff and Save Video Meta
	visibleVideos := collectVideoPaths(root)
	c.videoMetaMu.Lock()
	pruneVideoMeta(c.workingVideoMeta, visibleVideos)
	if !reflect.DeepEqual(c.currentVideoMeta, c.workingVideoMeta) {
		if c.saveJSON(VideoMetaCache, c.workingVideoMeta) == nil {
			c.currentVideoMeta = make(map[string]VideoMeta)
			for k, v := range c.workingVideoMeta {
				c.currentVideoMeta[k] = v
			}
			log.Printf("Updated video meta cache: %d entries", len(c.currentVideoMeta))
		}
	}
	c.videoMetaMu.Unlock()

	return nil
}

func collectVideoPaths(root *TraverseNode) map[string]struct{} {
	visible := make(map[string]struct{})
	if root == nil {
		return visible
	}
	for _, video := range root.Video() {
		if video.Path == "" {
			continue
		}
		visible[video.Path] = struct{}{}
	}
	return visible
}

func pruneVideoMeta(meta map[string]VideoMeta, visible map[string]struct{}) {
	if len(meta) == 0 {
		return
	}
	for path := range meta {
		if _, ok := visible[path]; !ok {
			delete(meta, path)
		}
	}
}

// GetSize provides size lookup for Scanner (optimization)
func (c *CacheManager) GetSize(path string) (Size, bool) {
	s, ok := c.currentSizes[path]
	return s, ok
}

// GetTags provides tag lookup (optimization)
func (c *CacheManager) GetTags(path string) []TagInfo {
	return c.currentTags[path]
}

// GetCaption provides caption lookup (optimization)
func (c *CacheManager) GetCaption(path string) string {
	return c.currentCaptions[path]
}

// GetVideoMeta provides video metadata lookup
func (c *CacheManager) GetVideoMeta(path string) (VideoMeta, bool) {
	c.videoMetaMu.RLock()
	defer c.videoMetaMu.RUnlock()
	v, ok := c.workingVideoMeta[path]
	return v, ok
}

// UpsertVideoMeta updates video metadata
func (c *CacheManager) UpsertVideoMeta(path string, meta VideoMeta) {
	c.videoMetaMu.Lock()
	defer c.videoMetaMu.Unlock()
	c.workingVideoMeta[path] = meta
}

// NeedsVideoMetaRefresh checks if video metadata needs update based on modTime and size
func (c *CacheManager) NeedsVideoMetaRefresh(path string, modTime time.Time, size int64) bool {
	c.videoMetaMu.RLock()
	defer c.videoMetaMu.RUnlock()
	meta, ok := c.workingVideoMeta[path]
	if !ok {
		return true
	}
	return meta.ModTimeUnixNano != modTime.UnixNano() || meta.SizeBytes != size
}

// Helpers

func (c *CacheManager) loadJSON(name string, v interface{}) {
	f, err := c.Fs.Open(name)
	if err != nil {
		return
	}
	defer f.Close()
	json.NewDecoder(f).Decode(v)
}

func (c *CacheManager) saveJSON(name string, v interface{}) error {
	data, err := json.Marshal(v)
	if err != nil {
		return err
	}
	return c.Fs.Save(name, io.NopCloser(bytes.NewReader(data)))
}
