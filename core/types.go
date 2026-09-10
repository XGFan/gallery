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

// NodeWithParent holds a node with its parent path.
//
// A random sample may be either an image or a video, so Type is always emitted
// (never omitempty): the client decodes it as a required field to decide which
// renderer and which static route to use. DurationSec only carries a value for
// videos.
type NodeWithParent struct {
	ImageNode
	Parent      string  `json:"parent"`
	Type        string  `json:"type"`
	DurationSec float64 `json:"duration_sec,omitempty"`
}

// MediaKind selects which media types a random sample may draw from.
type MediaKind int

const (
	MediaKindImage MediaKind = iota
	MediaKindVideo
	MediaKindAll
)

// ParseMediaKind maps a ?type= query value onto a MediaKind. Anything the
// client did not spell exactly falls back to images, which is the semantic the
// endpoint had before the parameter existed.
func ParseMediaKind(raw string) MediaKind {
	switch raw {
	case "video":
		return MediaKindVideo
	case "all":
		return MediaKindAll
	default:
		return MediaKindImage
	}
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

// --- Concurrent access to a live tree ---
//
// The tree is mutated in place while it is being served: Locate inserts
// subdirectories under the write lock, and the scanner replaces Images/Videos
// under it too — all of that runs concurrently with HTTP handlers walking the
// same nodes, because the server starts listening before the first scan
// finishes. Every cold start is that window.
//
// Reading these fields directly is therefore a data race, and for the map it is
// not a subtle one: Go turns a concurrent map iteration and write into
// `fatal error: concurrent map iteration and map write`, which no recover can
// catch — the whole process dies. Reproduced under `go test -race`, and it
// fataled on 3 of 6 plain runs.
//
// So every read path goes through these. They are cheap: the map accessor
// copies pointers, and the slice accessors copy only the 3-word header. Reading
// elements from a snapshot header stays valid because the scanner only ever
// appends past the length a reader captured.

// subdirs is the child nodes, snapshotted under the read lock.
func (dn *TraverseNode) subdirs() []*TraverseNode {
	dn.mu.RLock()
	defer dn.mu.RUnlock()
	out := make([]*TraverseNode, 0, len(dn.Directories))
	for _, sub := range dn.Directories {
		out = append(out, sub)
	}
	return out
}

// NamedNode pairs a child with the key it is filed under, for the callers that
// need both.
type NamedNode struct {
	Name string
	Node *TraverseNode
}

func (dn *TraverseNode) namedSubdirs() []NamedNode {
	dn.mu.RLock()
	defer dn.mu.RUnlock()
	out := make([]NamedNode, 0, len(dn.Directories))
	for name, sub := range dn.Directories {
		out = append(out, NamedNode{Name: name, Node: sub})
	}
	return out
}

func (dn *TraverseNode) subdirCount() int {
	dn.mu.RLock()
	defer dn.mu.RUnlock()
	return len(dn.Directories)
}

func (dn *TraverseNode) imageSlice() []ImageNode {
	dn.mu.RLock()
	defer dn.mu.RUnlock()
	return dn.Images
}

func (dn *TraverseNode) videoSlice() []VideoNode {
	dn.mu.RLock()
	defer dn.mu.RUnlock()
	return dn.Videos
}

func (dn *TraverseNode) coverIndex() int {
	dn.mu.RLock()
	defer dn.mu.RUnlock()
	return dn.CoverIndex
}

func (dn *TraverseNode) otherSlice() []Node {
	dn.mu.RLock()
	defer dn.mu.RUnlock()
	return dn.Others
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
	// Under the write lock: this rewrites elements in place while HTTP handlers
	// may be reading the same slices. The recursion below stays outside it —
	// holding a parent's lock across a subtree walk would block the scanner
	// from inserting anywhere beneath it.
	dn.mu.Lock()
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
	dn.mu.Unlock()
	for _, sub := range dn.subdirs() {
		sub.Load(sizeCache)
	}
}

// LoadTagsAndCaptions applies tag and caption caches
func (dn *TraverseNode) LoadTagsAndCaptions(tagCache map[string][]TagInfo, captionCache map[string]string, blacklist utils.Set[string]) {
	dn.mu.Lock()
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
	dn.mu.Unlock()

	for _, sub := range dn.subdirs() {
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
	for _, img := range dn.imageSlice() {
		if img.Size != EmptySize {
			result[img.Path] = img.Size
		}
	}
	for _, vid := range dn.videoSlice() {
		if vid.Size != EmptySize {
			result[vid.Path] = vid.Size
		}
	}
	for _, sub := range dn.subdirs() {
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
	for _, img := range dn.imageSlice() {
		if len(img.Tags) > 0 {
			tags[img.Path] = img.Tags
		}
		if img.Caption != "" {
			captions[img.Path] = img.Caption
		}
	}
	for _, vid := range dn.videoSlice() {
		if len(vid.Tags) > 0 {
			tags[vid.Path] = vid.Tags
		}
		if vid.Caption != "" {
			captions[vid.Path] = vid.Caption
		}
	}
	for _, sub := range dn.subdirs() {
		sub.dumpMetaRecursive(tags, captions)
	}
}

// CleanupRecursively removes nodes that weren't updated in current scan and images with no size
func (dn *TraverseNode) CleanupRecursively(currentScanID int64) int {
	deletedCount := 0

	// Cleanup directories
	for _, entry := range dn.namedSubdirs() {
		name, sub := entry.Name, entry.Node
		deletedCount += sub.CleanupRecursively(currentScanID)
		if sub.LastScanID != currentScanID {
			// Deleting from the map is a write, so it needs the write lock even
			// though the walk above took a snapshot.
			dn.mu.Lock()
			delete(dn.Directories, name)
			dn.mu.Unlock()
			deletedCount++
		}
	}

	// Filtering republishes both slices, which readers may be holding. Under the
	// write lock so a reader sees either the old header or the new one, never a
	// half-written one.
	dn.mu.Lock()
	defer dn.mu.Unlock()

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
	sourceImages := dn.imageSlice()
	images := make([]ImageNode, len(sourceImages))
	for i, img := range sourceImages {
		images[i] = ImageNode{
			Node: Node{Name: img.Name, Path: img.Path},
			Size: EmptySize,
		}
	}

	sourceVideos := dn.videoSlice()
	videos := make([]VideoNode, len(sourceVideos))
	for i, vid := range sourceVideos {
		videos[i] = VideoNode{
			Node: Node{Name: vid.Name, Path: vid.Path},
			Size: EmptySize,
		}
	}

	dirs := make(map[string]*TraverseNode)
	for _, entry := range dn.namedSubdirs() {
		name, sub := entry.Name, entry.Node
		dirs[name] = sub.ToStructureOnly()
	}

	return &TraverseNode{
		Node:        Node{Name: dn.Name, Path: dn.Path},
		Images:      images,
		Videos:      videos,
		Others:      dn.otherSlice(),
		Directories: dirs,
		CoverIndex:  dn.coverIndex(),
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
	*result = append(*result, dn.imageSlice()...)
	for _, sub := range dn.subdirs() {
		sub.ScanImages(result)
	}
}

// ScanVideos collects all videos recursively
func (dn *TraverseNode) ScanVideos(result *[]VideoNode) {
	*result = append(*result, dn.videoSlice()...)
	for _, sub := range dn.subdirs() {
		sub.ScanVideos(result)
	}
}

// Explore returns the directory's immediate contents for API
func (dn *TraverseNode) Explore() *SimpleDirectory {
	var subDirectories = make([]DirNode, 0, dn.subdirCount())
	for _, directory := range dn.subdirs() {
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
		Images:      dn.imageSlice(),
		Videos:      dn.videoSlice(),
		Others:      dn.otherSlice(),
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
	for _, sub := range dn.subdirs() {
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

// HasMedia reports whether this subtree holds any image or video at all.
//
// Deliberately not expressed as "Cover() is non-empty". Cover falls back to a
// video only when that video has a probed size, so a directory full of clips
// whose ffprobe failed reports no cover while being full of media. Using cover
// as the media test made those directories vanish from the tree entirely.
func (dn *TraverseNode) HasMedia() bool {
	if dn.HasImages() || dn.HasVideos() {
		return true
	}
	for _, sub := range dn.subdirs() {
		if sub.HasMedia() {
			return true
		}
	}
	return false
}

// ToTree returns a tree representation for API
//
// A directory is in the tree exactly when its subtree holds media. That makes
// the tree and Album agree: a node has children here if and only if Album would
// list something under it — which is what the native client's view switcher
// uses to decide whether to offer the recursive views at all. See
// docs/adr/0007.
func (dn *TraverseNode) ToTree() map[string]interface{} {
	m := make(map[string]interface{})
	for _, node := range dn.subdirs() {
		if node.HasMedia() {
			m[node.Name] = node.ToTree()
		}
	}
	return m
}

// Random draws one media item of the requested kind from the tree.
//
// The probability is split evenly across this level's candidates, where a whole
// subdirectory counts as a single candidate no matter how much it holds. That
// makes the distribution uneven — a directory holding one image next to a
// 5000-item subtree gives that one image half the probability — and that is
// deliberate: see docs/adr/0008-random-is-an-unbounded-sample-stream.md. Do not
// "fix" it into a uniform draw.
func (dn *TraverseNode) Random(flatten bool, kind MediaKind) (NodeWithParent, error) {
	images, videos := dn.sampleCandidates(kind)
	localChoice := len(images) + len(videos)
	if !flatten {
		if localChoice == 0 {
			return NodeWithParent{}, errors.New("cannot find media")
		}
		return dn.sampleAt(images, videos, rand.Intn(localChoice)), nil
	}

	subs := dn.subdirs()
	totalChoice := localChoice + len(subs)
	if totalChoice == 0 {
		return NodeWithParent{}, errors.New("cannot find media")
	}
	index := rand.Intn(totalChoice)
	if index < localChoice {
		return dn.sampleAt(images, videos, index), nil
	}

	restIndex := index - localChoice
	nextDn := dn
	// subdirs() builds its slice by ranging the map, and Go randomizes map
	// iteration order, so the same restIndex reaches a different subdirectory on
	// every call. The sampler relies on that for its randomness at this level.
	// The snapshot is taken once above and used for both the count and the walk:
	// two snapshots could disagree if the scanner inserted between them.
	//
	// The break is load-bearing: without it, every directory after restIndex
	// hits zero would overwrite nextDn again, and the descent would always end
	// up in whichever subdirectory the map happened to yield last.
	for _, node := range subs {
		if restIndex != 0 {
			restIndex--
		} else {
			nextDn = node
			break
		}
	}
	if nextDn == dn {
		return NodeWithParent{}, errors.New("cannot find media")
	}
	return nextDn.Random(flatten, kind)
}

// sampleCandidates narrows this level's media down to what the requested kind
// allows.
func (dn *TraverseNode) sampleCandidates(kind MediaKind) ([]ImageNode, []VideoNode) {
	switch kind {
	case MediaKindVideo:
		return nil, dn.videoSlice()
	case MediaKindAll:
		return dn.imageSlice(), dn.videoSlice()
	default:
		return dn.imageSlice(), nil
	}
}

// sampleAt resolves an index over the concatenated images+videos candidates
// into the response node, tagging which of the two it came from.
func (dn *TraverseNode) sampleAt(images []ImageNode, videos []VideoNode, index int) NodeWithParent {
	if index < len(images) {
		return NodeWithParent{
			ImageNode: images[index],
			Parent:    dn.Path,
			Type:      "image",
		}
	}
	video := videos[index-len(images)]
	return NodeWithParent{
		ImageNode: ImageNode{
			Node:    video.Node,
			Size:    video.Size,
			Tags:    video.Tags,
			Caption: video.Caption,
		},
		Parent:      dn.Path,
		Type:        "video",
		DurationSec: video.DurationSec,
	}
}

// Cover returns the cover image for this directory
func (dn *TraverseNode) Cover() ImageNode {
	// One snapshot, then index into it. Re-reading the field between the length
	// check and the subscript is what turns a concurrent republish into an
	// out-of-range panic.
	if images := dn.imageSlice(); len(images) > 0 {
		index := dn.coverIndex()
		if index < 0 || index >= len(images) {
			index = 0
		}
		return images[index]
	}
	if videos := dn.videoSlice(); len(videos) > 0 {
		vid := videos[0]
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
	for _, sub := range dn.subdirs() {
		if subCover := sub.Cover(); !subCover.IsEmpty() {
			return subCover
		}
	}
	return EmptyNode
}

// HasImages checks if directory has images
func (dn *TraverseNode) HasImages() bool {
	return len(dn.imageSlice()) > 0
}

// HasVideos checks if directory has videos
func (dn *TraverseNode) HasVideos() bool {
	return len(dn.videoSlice()) > 0
}

// HasSubDirectories checks if directory has subdirectories
func (dn *TraverseNode) HasSubDirectories() bool {
	return dn.subdirCount() > 0
}
