package core

import (
	"image"
	"log"
	"path"
	"sync"
	"time"

	utils "github.com/XGFan/go-utils"

	"gallery/common/misc"
	"gallery/common/storage"
)

// Scanner handles filesystem scanning and pipeline
type Scanner struct {
	OriginFs     storage.Storage
	Exclude      utils.Set[string]
	Cache        *CacheManager // Dependency Injection
	VirtualPaths map[string][]string
}

// NewScanner creates a new Scanner
func NewScanner(originFs storage.Storage, exclude []string, cache *CacheManager, virtualPaths map[string][]string) *Scanner {
	return &Scanner{
		OriginFs:     originFs,
		Exclude:      utils.NewSetWithSlice(exclude),
		Cache:        cache,
		VirtualPaths: virtualPaths,
	}
}

// Scan orchestrates the full scanning process: FS Discovery -> Pipeline -> Virtual Paths -> Persist
func (s *Scanner) Scan(data *TraverseNode) {
	start := time.Now()
	log.Println("Scan started")

	source := s.StartDiscovery(8)
	s.RunPipeline(data, source)
	s.ApplyVirtualPaths(data)
	s.Persist(data)

	log.Printf("Scan finished: %s", time.Now().Sub(start).Truncate(time.Millisecond))
}

// Restore loads state from cache and reconstructs the tree via pipeline
// Returns number of items restored or error
func (s *Scanner) Restore(data *TraverseNode) (int, error) {
	items, err := s.Cache.LoadScanItems()
	if err != nil {
		return 0, err
	}
	if len(items) == 0 {
		return 0, nil
	}

	source := s.StartCacheStream(items)
	s.RunPipeline(data, source)
	s.ApplyVirtualPaths(data)

	return len(items), nil
}

// Persist saves the current tree state to cache
func (s *Scanner) Persist(data *TraverseNode) error {
	return s.Cache.Save(data)
}

// ApplyVirtualPaths merges virtual folders into the root
func (s *Scanner) ApplyVirtualPaths(root *TraverseNode) {
	if s.VirtualPaths == nil {
		return
	}
	for name, paths := range s.VirtualPaths {
		nodes := make([]*TraverseNode, 0, len(paths))
		for _, p := range paths {
			nodes = append(nodes, root.Locate(p))
		}
		virtualPath := s.mergeVirtualPath(name, nodes)
		root.Directories[name] = virtualPath
	}
}

func (s *Scanner) mergeVirtualPath(name string, nodes []*TraverseNode) *TraverseNode {
	result := &TraverseNode{
		Node:        Node{Name: name, Path: name, LastScanID: 1<<63 - 1}, // MaxInt64: never cleanup
		Directories: make(map[string]*TraverseNode),
	}

	for _, node := range nodes {
		for k, v := range node.Directories {
			result.Directories[k] = v // Shallow copy
		}
		result.Images = append(result.Images, node.Images...)
		result.Others = append(result.Others, node.Others...)
	}
	return result
}

// RunPipeline executes the full scan pipeline in a functional style
// It accepts a source channel which can come from Discovery (FS) or Cache (WarmUp)
func (s *Scanner) RunPipeline(data *TraverseNode, source <-chan ScanItem) {
	currentScanID := time.Now().UnixNano()

	// Pipeline Construction

	// 1. Source (Context-Injected)
	// source -> sizeProbe -> metaEnricher -> mutator

	// 2. Size Probe (Filter & Enrich)
	sizeOut := s.runSizeProbe(source, 4)

	// 3. Meta Enricher (Enrich)
	metaOut := s.runMetaEnricher(sizeOut, 4)

	// 4. Mutator (Sink & Cleanup)
	// Block until pipeline is completely finished
	<-s.runMutator(metaOut, 4, data, currentScanID)
}

// StartDiscovery scans the filesystem and emits initial items
func (s *Scanner) StartDiscovery(workerSize int) <-chan ScanItem {
	out := make(chan ScanItem, 2000)

	task := misc.NewUnboundedChan[Node](1)
	task.In <- Node{} // Start from root

	wg := &sync.WaitGroup{}
	wg.Add(1)

	// Monitor to close channels
	go func() {
		wg.Wait()
		close(task.In)
		close(out)
	}()

	// Discovery workers
	for i := 0; i < workerSize; i++ {
		go func() {
			for node := range task.Out {
				s.scanDir(node, out, wg, task)
			}
		}()
	}
	return out
}

// StartCacheStream emits items from a cached list
func (s *Scanner) StartCacheStream(items []ScanItem) <-chan ScanItem {
	out := make(chan ScanItem, 2000)
	go func() {
		for _, item := range items {
			out <- item
		}
		close(out)
	}()
	return out
}

func (s *Scanner) scanDir(node Node, out chan<- ScanItem, wg *sync.WaitGroup, task misc.UnboundedChan[Node]) {
	defer wg.Done()

	readDir, _ := s.OriginFs.ReadDir(node.Path)

	// Emit Dir Item
	out <- ScanItem{Type: ItemDir, Path: node.Path, Name: node.Name}

	for _, info := range readDir {
		targetPath := s.OriginFs.Join(node.Path, info.Name())
		if s.Exclude.Contains(targetPath) {
			continue
		}

		target := Node{Name: info.Name(), Path: targetPath}

		if info.IsDir() {
			wg.Add(1)
			task.In <- target
		} else if storage.IsNormalFile(info.Name()) {
			if storage.IsValidPic(info.Name()) {
				out <- ScanItem{Type: ItemImage, Path: targetPath, Name: info.Name()}
			} else {
				out <- ScanItem{Type: ItemFile, Path: targetPath, Name: info.Name()}
			}
		}
	}
}

// runSizeProbe: Pass-through non-images, Validate/Size images.
func (s *Scanner) runSizeProbe(in <-chan ScanItem, workerSize int) (out chan ScanItem) {
	out = make(chan ScanItem, 100)
	var wg sync.WaitGroup

	for i := 0; i < workerSize; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for item := range in {
				if item.Type != ItemImage {
					out <- item
					continue
				}

				if item.Width > 0 && item.Height > 0 {
					out <- item
					continue
				}

				// Process Image
				width, height := 0, 0
				if size, ok := s.Cache.GetSize(item.Path); ok {
					width, height = size.Width, size.Height
				} else {
					if f, err := s.OriginFs.Open(item.Path); err == nil {
						if cfg, _, err := image.DecodeConfig(f); err == nil {
							width, height = cfg.Width, cfg.Height
						}
						f.Close()
					}
				}

				// Filter
				if width > 0 && height > 0 {
					item.Width = width
					item.Height = height
					out <- item
				}
				// Else: Drop
			}
		}()
	}

	go func() {
		wg.Wait()
		close(out)
	}()

	return out
}

// runMetaEnricher: Enrich images with tags/captions. Pass-through others.
func (s *Scanner) runMetaEnricher(in <-chan ScanItem, workerSize int) (out chan ScanItem) {
	out = make(chan ScanItem, 100)
	var wg sync.WaitGroup

	for i := 0; i < workerSize; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for item := range in {
				if item.Type == ItemImage {
					if len(item.Tags) == 0 {
						item.Tags = s.Cache.GetTags(item.Path)
					}
					if item.Caption == "" {
						item.Caption = s.Cache.GetCaption(item.Path)
					}
				}
				out <- item
			}
		}()
	}

	go func() {
		wg.Wait()
		close(out)
	}()

	return out
}

// runMutator: Sink. Apply changes to Root and perform cleanup.
func (s *Scanner) runMutator(in <-chan ScanItem, workerSize int, data *TraverseNode, currentScanID int64) <-chan struct{} {
	done := make(chan struct{})
	var wg sync.WaitGroup

	for i := 0; i < workerSize; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for item := range in {
				switch item.Type {
				case ItemDir:
					node := data.Locate(item.Path)
					node.mu.Lock()
					if node.LastScanID < currentScanID {
						node.Others = make([]Node, 0)
					}
					node.LastScanID = currentScanID
					node.mu.Unlock()

				case ItemFile:
					dirPath := path.Dir(item.Path)
					node := data.Locate(dirPath)
					node.mu.Lock()
					if node.LastScanID < currentScanID {
						node.LastScanID = currentScanID
						node.Others = make([]Node, 0)
					}
					node.Others = append(node.Others, Node{Name: item.Name, Path: item.Path})
					node.mu.Unlock()

				case ItemImage:
					dirPath := path.Dir(item.Path)
					node := data.Locate(dirPath)

					imgNode := ImageNode{
						Node:    Node{Name: item.Name, Path: item.Path, LastScanID: currentScanID},
						Size:    Size{Width: item.Width, Height: item.Height},
						Tags:    item.Tags,
						Caption: item.Caption,
					}

					node.mu.Lock()
					// O(1) append optimization:
					// If this node hasn't been touched in this scan yet, reset it.
					if node.LastScanID < currentScanID {
						node.LastScanID = currentScanID
						node.Images = make([]ImageNode, 0)
						// Others is already handled by ItemFile case, but strictly speaking
						// if a directory only has images, we should reset Others too if we want to be safe,
						// or rely on CleanupRecursively.
						// However, since we might visit ItemFile first or ItemImage first,
						// we need to be careful not to maximize LastScanID without clearing if we want to clear.
						// Actually, the safest bet is: Whichever comes first (Image or File or Dir) clears the node for the new scan.
						// But since we can't easily coordinate concurrent workers for the *same* node without a lock (which we have),
						// we just check the ID inside the lock.
						node.Others = make([]Node, 0)
					}

					// We only append. Duplicates within same scanID are impossible due to pipeline uniqueness (file path).
					// Duplicates across scans are handled by the reset above.
					node.Images = append(node.Images, imgNode)
					node.mu.Unlock()
				}
			}
		}()
	}

	go func() {
		wg.Wait()
		// Perform Cleanup after all mutations are done
		s.cleanupDeletedFiles(data, currentScanID)
		close(done)
	}()

	return done
}

func (s *Scanner) cleanupDeletedFiles(data *TraverseNode, currentScanID int64) {
	if data == nil {
		return
	}
	deletedCount := data.CleanupRecursively(currentScanID)
	if deletedCount > 0 {
		log.Printf("Cleaned up %d deleted files/images", deletedCount)
	}
}
