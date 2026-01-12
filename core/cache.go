package core

import (
	"bytes"
	"encoding/json"
	"io"
	"log"
	"reflect"

	utils "github.com/XGFan/go-utils"

	"gallery/common/storage"
)

// Cache file names
const ImgSizeCache = ".img-size.json"
const ImgTagCache = ".img-tag.json"
const ImgCaptionCache = ".img-caption.json"
const ImgStructureCache = ".img.json"
const TagMinValue = 60

// CacheManager handles persistence with smart diffing
type CacheManager struct {
	Fs           storage.Storage
	TagBlacklist utils.Set[string]

	// Internal state mirroring disk content
	currentSizes    map[string]Size
	currentTags     map[string][]TagInfo
	currentCaptions map[string]string
}

// NewCacheManager creates a new CacheManager
func NewCacheManager(cacheFs storage.Storage, tagBlacklist []string) *CacheManager {
	return &CacheManager{
		Fs:              cacheFs,
		TagBlacklist:    utils.NewSetWithSlice(tagBlacklist),
		currentSizes:    make(map[string]Size),
		currentTags:     make(map[string][]TagInfo),
		currentCaptions: make(map[string]string),
	}
}

// LoadScanItems loads the structure snapshot (Event Stream) and auxiliary caches
func (c *CacheManager) LoadScanItems() ([]ScanItem, error) {
	// 1. Load Auxiliary Caches (Knowledge Base)
	// We load these first so Scanner can use them even if Structure Cache is partial or missing.
	c.loadJSON(ImgSizeCache, &c.currentSizes)
	c.loadJSON(ImgTagCache, &c.currentTags)
	c.loadJSON(ImgCaptionCache, &c.currentCaptions)

	log.Printf("Knowledge Base loaded: %d sizes, %d tags", len(c.currentSizes), len(c.currentTags))

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

	return nil
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
