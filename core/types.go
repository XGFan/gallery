package core

import (
	"errors"
	"math/rand"
	"sync"

	utils "github.com/XGFan/go-utils"
)

// Pipeline Data Structures
type SizeInfo struct {
	Path   string
	Width  int
	Height int
}

// ScanItemType Defines the type of items in the pipeline
type ScanItemType int

const (
	ItemDir  ScanItemType = iota
	ItemFile              // Non-image file
	ItemImage
	ItemVideo
)

// ScanItem carries data through the pipeline
type ScanItem struct {
	Type ScanItemType `json:"type"`
	Path string       `json:"path"`
	Name string       `json:"name"`

	// Payload (populated by stages)
	Width       int       `json:"width,omitempty"`
	Height      int       `json:"height,omitempty"`
	DurationSec float64   `json:"duration_sec,omitempty"`
	Tags        []TagInfo `json:"tags,omitempty"`
	Caption     string    `json:"caption,omitempty"`
}

// EmptySize represents an uninitialized size
var EmptySize = Size{}

// Node represents a basic file/directory node
type Node struct {
	Name       string `json:"name,omitempty"`
	Path       string `json:"path,omitempty"`
	LastScanID int64  `json:"-"`
}

// Size represents image dimensions
type Size struct {
	Width  int `json:"width,omitempty"`
	Height int `json:"height,omitempty"`
}

// TagInfo represents a tag with its confidence value
type TagInfo struct {
	Tag   string `json:"tag"`
	Value int    `json:"value"`
}

// TagStat represents tag statistics
type TagStat struct {
	Tag        string  `json:"tag"`
	Count      int     `json:"count"`
	TotalScore int     `json:"-"`
	AvgScore   float64 `json:"avgScore"`
	Weight     float64 `json:"weight"`
}

// ImageNode represents an image file
type ImageNode struct {
	Node
	Size
	Tags    []TagInfo `json:"tags,omitempty"`
	Caption string    `json:"caption,omitempty"`
}

// VideoNode represents a video file
type VideoNode struct {
	Node
	Size
	DurationSec float64   `json:"duration_sec,omitempty"`
	Tags        []TagInfo `json:"tags,omitempty"`
	Caption     string    `json:"caption,omitempty"`
}

// DirNode represents a directory for API response
type DirNode struct {
	Node
	Directories []Node    `json:"directories,omitempty"`
	Cover       ImageNode `json:"cover,omitempty"`
}

// NodeWithParent holds a node with its parent path
type NodeWithParent struct {
	ImageNode
	Parent string `json:"parent"`
}

// TraverseNode represents a directory with all its contents
type TraverseNode struct {
	Node
	Images      []ImageNode
	Videos      []VideoNode
	Others      []Node
	Directories map[string]*TraverseNode
	CoverIndex  int
	mu          sync.RWMutex // Protects concurrent access
}

// Locate finds or creates a node at the given path
func (dn *TraverseNode) Locate(path string) *TraverseNode {
	if path == "" || path == "/" {
		return dn
	}

	parts := splitPath(path)
	current := dn

	for _, part := range parts {
		current.mu.Lock()
		if current.Directories == nil {
			current.Directories = make(map[string]*TraverseNode)
		}
		if next, ok := current.Directories[part]; ok {
			current.mu.Unlock()
			current = next
		} else {
			newNode := &TraverseNode{
				Node: Node{
					Name: part,
					Path: joinPath(current.Path, part),
				},
				Directories: make(map[string]*TraverseNode),
			}
			current.Directories[part] = newNode
			current.mu.Unlock()
			current = newNode
		}
	}
	return current
}

// Load applies size cache to all images
func (dn *TraverseNode) Load(sizeCache map[string]Size) {
	for i := range dn.Images {
		if size, ok := sizeCache[dn.Images[i].Path]; ok {
			dn.Images[i].Size = size
		}
	}
	for i := range dn.Videos {
		if size, ok := sizeCache[dn.Videos[i].Path]; ok {
			dn.Videos[i].Size = size
		}
	}
	for _, sub := range dn.Directories {
		sub.Load(sizeCache)
	}
}

// LoadTagsAndCaptions applies tag and caption caches
func (dn *TraverseNode) LoadTagsAndCaptions(tagCache map[string][]TagInfo, captionCache map[string]string, blacklist utils.Set[string]) {
	for i := range dn.Images {
		path := dn.Images[i].Path
		if tags, ok := tagCache[path]; ok {
			filtered := make([]TagInfo, 0, len(tags))
			for _, tag := range tags {
				if tag.Value >= TagMinValue && !blacklist.Contains(tag.Tag) {
					filtered = append(filtered, tag)
				}
			}
			dn.Images[i].Tags = filtered
		}
		if caption, ok := captionCache[path]; ok {
			dn.Images[i].Caption = caption
		}
	}
	for i := range dn.Videos {
		path := dn.Videos[i].Path
		if tags, ok := tagCache[path]; ok {
			filtered := make([]TagInfo, 0, len(tags))
			for _, tag := range tags {
				if tag.Value >= TagMinValue && !blacklist.Contains(tag.Tag) {
					filtered = append(filtered, tag)
				}
			}
			dn.Videos[i].Tags = filtered
		}
		if caption, ok := captionCache[path]; ok {
			dn.Videos[i].Caption = caption
		}
	}
	for _, sub := range dn.Directories {
		sub.LoadTagsAndCaptions(tagCache, captionCache, blacklist)
	}
}

// Dump exports all image sizes to a map
func (dn *TraverseNode) Dump() map[string]Size {
	result := make(map[string]Size)
	dn.dumpRecursive(result)
	return result
}

func (dn *TraverseNode) dumpRecursive(result map[string]Size) {
	for _, img := range dn.Images {
		if img.Size != EmptySize {
			result[img.Path] = img.Size
		}
	}
	for _, vid := range dn.Videos {
		if vid.Size != EmptySize {
			result[vid.Path] = vid.Size
		}
	}
	for _, sub := range dn.Directories {
		sub.dumpRecursive(result)
	}
}

// DumpMeta exports tags and captions
func (dn *TraverseNode) DumpMeta() (map[string][]TagInfo, map[string]string) {
	tags := make(map[string][]TagInfo)
	captions := make(map[string]string)
	dn.dumpMetaRecursive(tags, captions)
	return tags, captions
}

func (dn *TraverseNode) dumpMetaRecursive(tags map[string][]TagInfo, captions map[string]string) {
	for _, img := range dn.Images {
		if len(img.Tags) > 0 {
			tags[img.Path] = img.Tags
		}
		if img.Caption != "" {
			captions[img.Path] = img.Caption
		}
	}
	for _, vid := range dn.Videos {
		if len(vid.Tags) > 0 {
			tags[vid.Path] = vid.Tags
		}
		if vid.Caption != "" {
			captions[vid.Path] = vid.Caption
		}
	}
	for _, sub := range dn.Directories {
		sub.dumpMetaRecursive(tags, captions)
	}
}

// CleanupRecursively removes nodes that weren't updated in current scan and images with no size
func (dn *TraverseNode) CleanupRecursively(currentScanID int64) int {
	deletedCount := 0

	// Cleanup directories
	for name, sub := range dn.Directories {
		deletedCount += sub.CleanupRecursively(currentScanID)
		if sub.LastScanID != currentScanID {
			delete(dn.Directories, name)
			deletedCount++
		}
	}

	// Cleanup images (filter out those without size or not scanned)
	validImages := make([]ImageNode, 0, len(dn.Images))
	for _, img := range dn.Images {
		if img.LastScanID == currentScanID && img.Size != EmptySize {
			validImages = append(validImages, img)
		} else {
			deletedCount++
		}
	}
	dn.Images = validImages

	// Cleanup videos (filter out those not scanned)
	validVideos := make([]VideoNode, 0, len(dn.Videos))
	for _, vid := range dn.Videos {
		if vid.LastScanID == currentScanID {
			validVideos = append(validVideos, vid)
		} else {
			deletedCount++
		}
	}
	dn.Videos = validVideos

	return deletedCount
}

// ToStructureOnly creates a copy with only structural info
func (dn *TraverseNode) ToStructureOnly() *TraverseNode {
	images := make([]ImageNode, len(dn.Images))
	for i, img := range dn.Images {
		images[i] = ImageNode{
			Node: Node{Name: img.Name, Path: img.Path},
			Size: EmptySize,
		}
	}

	videos := make([]VideoNode, len(dn.Videos))
	for i, vid := range dn.Videos {
		videos[i] = VideoNode{
			Node: Node{Name: vid.Name, Path: vid.Path},
			Size: EmptySize,
		}
	}

	dirs := make(map[string]*TraverseNode)
	for name, sub := range dn.Directories {
		dirs[name] = sub.ToStructureOnly()
	}

	return &TraverseNode{
		Node:        Node{Name: dn.Name, Path: dn.Path},
		Images:      images,
		Videos:      videos,
		Others:      dn.Others,
		Directories: dirs,
		CoverIndex:  dn.CoverIndex,
	}
}

// Flatten converts the tree into a flat list of ScanItems
func (n *TraverseNode) Flatten() []ScanItem {
	items := make([]ScanItem, 0)
	n.flattenRecursive(&items)
	return items
}

func (n *TraverseNode) flattenRecursive(items *[]ScanItem) {
	// Add self as Dir
	if n.Path != "" {
		*items = append(*items, ScanItem{Type: ItemDir, Path: n.Path, Name: n.Name})
	}

	// Add Files
	for _, o := range n.Others {
		*items = append(*items, ScanItem{Type: ItemFile, Path: o.Path, Name: o.Name})
	}

	// Add Images
	for _, img := range n.Images {
		*items = append(*items, ScanItem{Type: ItemImage, Path: img.Path, Name: img.Name, Width: img.Size.Width, Height: img.Size.Height, Tags: img.Tags, Caption: img.Caption})
	}

	// Add Videos
	for _, vid := range n.Videos {
		*items = append(*items, ScanItem{Type: ItemVideo, Path: vid.Path, Name: vid.Name, Width: vid.Size.Width, Height: vid.Size.Height, DurationSec: vid.DurationSec, Tags: vid.Tags, Caption: vid.Caption})
	}

	// Recurse
	for _, child := range n.Directories {
		child.flattenRecursive(items)
	}
}

// Helper functions
func splitPath(path string) []string {
	var parts []string
	for _, p := range splitBySlash(path) {
		if p != "" {
			parts = append(parts, p)
		}
	}
	return parts
}

func splitBySlash(s string) []string {
	result := make([]string, 0)
	start := 0
	for i := 0; i < len(s); i++ {
		if s[i] == '/' {
			if i > start {
				result = append(result, s[start:i])
			}
			start = i + 1
		}
	}
	if start < len(s) {
		result = append(result, s[start:])
	}
	return result
}

func joinPath(base, name string) string {
	if base == "" {
		return name
	}
	return base + "/" + name
}

// SimpleDirectory represents API response for explore endpoint
type SimpleDirectory struct {
	Directories []DirNode   `json:"directories,omitempty"`
	Images      []ImageNode `json:"images,omitempty"`
	Videos      []VideoNode `json:"videos,omitempty"`
	Others      []Node      `json:"others,omitempty"`
}

// MediaResponse represents API response for media endpoint
type MediaResponse struct {
	Images []ImageNode `json:"images"`
	Videos []VideoNode `json:"videos"`
}

// EmptyNode represents an empty image node
var EmptyNode = ImageNode{}

// IsEmpty checks if the image node is empty
func (n ImageNode) IsEmpty() bool {
	return n.Path == ""
}

// Image returns all images recursively
func (dn *TraverseNode) Image() []ImageNode {
	var images = make([]ImageNode, 0, 16)
	dn.ScanImages(&images)
	return images
}

// Video returns all videos recursively
func (dn *TraverseNode) Video() []VideoNode {
	var videos = make([]VideoNode, 0, 16)
	dn.ScanVideos(&videos)
	return videos
}

// ScanImages collects all images recursively
func (dn *TraverseNode) ScanImages(result *[]ImageNode) {
	*result = append(*result, dn.Images...)
	for _, sub := range dn.Directories {
		sub.ScanImages(result)
	}
}

// ScanVideos collects all videos recursively
func (dn *TraverseNode) ScanVideos(result *[]VideoNode) {
	*result = append(*result, dn.Videos...)
	for _, sub := range dn.Directories {
		sub.ScanVideos(result)
	}
}

// Explore returns the directory's immediate contents for API
func (dn *TraverseNode) Explore() *SimpleDirectory {
	var subDirectories = make([]DirNode, 0, len(dn.Directories))
	for _, directory := range dn.Directories {
		subDirectories = append(subDirectories, DirNode{
			Node: Node{
				Name: directory.Name,
				Path: directory.Path,
			},
			Cover: directory.Cover(),
		})
	}
	return &SimpleDirectory{
		Directories: subDirectories,
		Images:      dn.Images,
		Videos:      dn.Videos,
		Others:      dn.Others,
	}
}

// Album returns all album directories recursively
func (dn *TraverseNode) Album() []DirNode {
	var albums = make([]DirNode, 0, 16)
	dn.ScanAlbum(&albums)
	return albums
}

// ScanAlbum collects all album directories recursively
func (dn *TraverseNode) ScanAlbum(result *[]DirNode) {
	for _, sub := range dn.Directories {
		if sub.HasImages() || sub.HasVideos() {
			*result = append(*result, DirNode{
				Node: Node{
					Name: sub.Name,
					Path: sub.Path,
				},
				Cover: sub.Cover(),
			})
		}
		sub.ScanAlbum(result)
	}
}

// ToTree returns a tree representation for API
func (dn *TraverseNode) ToTree() map[string]interface{} {
	m := make(map[string]interface{})
	if dn.HasSubDirectories() {
		for _, node := range dn.Directories {
			if !node.Cover().IsEmpty() {
				m[node.Name] = node.ToTree()
			}
		}
	}
	return m
}

// Random returns a random image from the tree
func (dn *TraverseNode) Random(flatten bool) (NodeWithParent, error) {
	if flatten {
		totalChoice := len(dn.Images) + len(dn.Directories)
		if totalChoice == 0 {
			return NodeWithParent{}, errors.New("cannot find image")
		}
		index := rand.Intn(totalChoice)
		if index < len(dn.Images) {
			return NodeWithParent{
				ImageNode: dn.Images[index],
				Parent:    dn.Path,
			}, nil
		} else {
			restIndex := index - len(dn.Images)
			nextDn := dn
			for _, node := range dn.Directories {
				if restIndex != 0 {
					restIndex--
				} else {
					nextDn = node
				}
			}
			return nextDn.Random(flatten)
		}
	} else {
		if len(dn.Images) == 0 {
			return NodeWithParent{}, errors.New("cannot find image")
		}
		index := rand.Intn(len(dn.Images))
		return NodeWithParent{
			ImageNode: dn.Images[index],
			Parent:    dn.Path,
		}, nil
	}
}

// Cover returns the cover image for this directory
func (dn *TraverseNode) Cover() ImageNode {
	if dn.HasImages() {
		return dn.Images[dn.CoverIndex]
	}
	if dn.HasVideos() {
		vid := dn.Videos[0]
		if vid.Size.Width > 0 && vid.Size.Height > 0 {
			return ImageNode{
				Node: Node{
					Name: vid.Name,
					Path: vid.Path,
				},
				Size: vid.Size,
			}
		}
	}
	if dn.HasSubDirectories() {
		for _, sub := range dn.Directories {
			subCover := sub.Cover()
			if !subCover.IsEmpty() {
				return subCover
			}
		}
	}
	return EmptyNode
}

// HasImages checks if directory has images
func (dn *TraverseNode) HasImages() bool {
	return dn.Images != nil && len(dn.Images) > 0
}

// HasVideos checks if directory has videos
func (dn *TraverseNode) HasVideos() bool {
	return dn.Videos != nil && len(dn.Videos) > 0
}

// HasSubDirectories checks if directory has subdirectories
func (dn *TraverseNode) HasSubDirectories() bool {
	return dn.Directories != nil && len(dn.Directories) > 0
}
