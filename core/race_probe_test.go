package core

import (
	"sync"
	"testing"
)

// The shape production actually has: HTTP handlers walking the tree while a
// scan is mutating it. The server starts listening before the first scan
// finishes (see the startup log ordering), so every cold start is this.
//
// Run with -race. A plain run is also meaningful: a concurrent map iteration
// and write is a *fatal* error in Go, which no recover can catch.
func TestRaceProbe_ReadersVsScanner(t *testing.T) {
	root := &TraverseNode{Directories: make(map[string]*TraverseNode)}
	for _, name := range []string{"a", "b", "c"} {
		n := root.Locate(name)
		n.Images = []ImageNode{{Node: Node{Name: "x.jpg", Path: name + "/x.jpg"}, Size: Size{Width: 2, Height: 3}}}
		n.Videos = []VideoNode{{Node: Node{Name: "v.mp4", Path: name + "/v.mp4"}, Size: Size{Width: 4, Height: 3}}}
	}

	const rounds = 300
	var wg sync.WaitGroup

	// Scanner: creates directories and republishes the media slices, exactly
	// what the Mutator stage does.
	wg.Add(1)
	go func() {
		defer wg.Done()
		for i := 0; i < rounds; i++ {
			node := root.Locate(string(rune('a'+i%26)) + "/" + string(rune('a'+i%5)))
			node.mu.Lock()
			node.Images = make([]ImageNode, 0)
			node.Images = append(node.Images, ImageNode{
				Node: Node{Name: "n.jpg", Path: node.Path + "/n.jpg"},
				Size: Size{Width: 1, Height: 1},
			})
			node.Videos = make([]VideoNode, 0)
			node.mu.Unlock()
		}
	}()

	// Every read path an HTTP handler can reach.
	readers := []func(){
		func() { _, _ = root.Random(true, MediaKindAll) },
		func() { _ = root.ToTree() },
		func() { _ = root.Album() },
		func() { _ = root.Explore() },
		func() { _ = root.Image() },
		func() { _ = root.Cover() },
	}
	for _, read := range readers {
		wg.Add(1)
		go func(fn func()) {
			defer wg.Done()
			for i := 0; i < rounds; i++ {
				fn()
			}
		}(read)
	}

	wg.Wait()
}
