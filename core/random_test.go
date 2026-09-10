package core

import "testing"

func sampleImage(name string) ImageNode {
	return ImageNode{Node: Node{Name: name, Path: name}, Size: Size{Width: 100, Height: 200}}
}

func sampleVideo(name string, duration float64) VideoNode {
	return VideoNode{
		Node:        Node{Name: name, Path: name},
		Size:        Size{Width: 1920, Height: 1080},
		DurationSec: duration,
	}
}

func mixedNode() *TraverseNode {
	return &TraverseNode{
		Node:        Node{Name: "mixed", Path: "mixed"},
		Images:      []ImageNode{sampleImage("mixed/a.jpg"), sampleImage("mixed/b.jpg")},
		Videos:      []VideoNode{sampleVideo("mixed/c.mp4", 12.5), sampleVideo("mixed/d.mp4", 3)},
		Directories: make(map[string]*TraverseNode),
	}
}

// The sample is drawn at random, so each kind is exercised often enough that a
// leak from the other bucket would show up.
const sampleRuns = 200

func TestRandom_KindImageNeverReturnsVideo(t *testing.T) {
	dn := mixedNode()
	for i := 0; i < sampleRuns; i++ {
		got, err := dn.Random(true, MediaKindImage)
		if err != nil {
			t.Fatalf("run %d: %v", i, err)
		}
		if got.Type != "image" {
			t.Fatalf("run %d: got type %q for %s, want image", i, got.Type, got.Path)
		}
		if got.DurationSec != 0 {
			t.Fatalf("run %d: image %s carries duration %v", i, got.Path, got.DurationSec)
		}
	}
}

func TestRandom_KindVideoNeverReturnsImage(t *testing.T) {
	dn := mixedNode()
	for i := 0; i < sampleRuns; i++ {
		got, err := dn.Random(true, MediaKindVideo)
		if err != nil {
			t.Fatalf("run %d: %v", i, err)
		}
		if got.Type != "video" {
			t.Fatalf("run %d: got type %q for %s, want video", i, got.Type, got.Path)
		}
		if got.DurationSec == 0 {
			t.Fatalf("run %d: video %s lost its duration", i, got.Path)
		}
	}
}

func TestRandom_KindAllReturnsBoth(t *testing.T) {
	dn := mixedNode()
	seen := make(map[string]bool)
	for i := 0; i < sampleRuns; i++ {
		got, err := dn.Random(true, MediaKindAll)
		if err != nil {
			t.Fatalf("run %d: %v", i, err)
		}
		if got.Type != "image" && got.Type != "video" {
			t.Fatalf("run %d: unexpected type %q", i, got.Type)
		}
		seen[got.Type] = true
	}
	if !seen["image"] || !seen["video"] {
		t.Fatalf("kind all only ever produced %v", seen)
	}
}

// A directory holding only videos has nothing to give when images are asked
// for; the handler turns that error into an empty array rather than a 500.
func TestRandom_NoMatchingMediaErrors(t *testing.T) {
	empty := &TraverseNode{Node: Node{Path: "empty"}, Directories: make(map[string]*TraverseNode)}
	videoOnly := &TraverseNode{
		Node:        Node{Path: "clips"},
		Videos:      []VideoNode{sampleVideo("clips/a.mp4", 5)},
		Directories: make(map[string]*TraverseNode),
	}

	cases := []struct {
		name string
		dn   *TraverseNode
		kind MediaKind
	}{
		{"empty flatten", empty, MediaKindAll},
		{"empty non-flatten", empty, MediaKindAll},
		{"video-only asked for images", videoOnly, MediaKindImage},
	}
	for _, tc := range cases {
		for _, flatten := range []bool{true, false} {
			if _, err := tc.dn.Random(flatten, tc.kind); err == nil {
				t.Errorf("%s (flatten=%v): expected an error", tc.name, flatten)
			}
		}
	}
}

// The recursive branch must be able to reach media that lives only in
// subdirectories, and every subdirectory has to stay reachable.
//
// This is the regression guard for the missing `break` in the subdirectory
// pick: without it, restIndex hitting zero lets every later directory overwrite
// the choice, so the descent lands on whichever directory the map yields last
// instead of the one restIndex selected. Go randomises map iteration order, so
// the broken form still spreads across directories today — what this test
// pins down is that each subdirectory keeps being reachable, which is exactly
// what breaks the moment iteration order stops being random.
func TestRandom_FlattenReachesEverySubdirectory(t *testing.T) {
	root := &TraverseNode{
		Node:        Node{Path: ""},
		Images:      []ImageNode{sampleImage("root.jpg")},
		Directories: make(map[string]*TraverseNode),
	}
	for _, name := range []string{"alpha", "beta", "gamma"} {
		root.Directories[name] = &TraverseNode{
			Node:        Node{Name: name, Path: name},
			Images:      []ImageNode{sampleImage(name + "/pic.jpg")},
			Directories: make(map[string]*TraverseNode),
		}
	}

	seen := make(map[string]bool)
	for i := 0; i < 500; i++ {
		got, err := root.Random(true, MediaKindAll)
		if err != nil {
			t.Fatalf("run %d: %v", i, err)
		}
		seen[got.Path] = true
	}

	for _, want := range []string{"root.jpg", "alpha/pic.jpg", "beta/pic.jpg", "gamma/pic.jpg"} {
		if !seen[want] {
			t.Errorf("never sampled %s, only saw %v", want, seen)
		}
	}
}

// Non-flatten stays inside the directory it was asked about.
func TestRandom_NonFlattenIgnoresSubdirectories(t *testing.T) {
	root := &TraverseNode{
		Node:        Node{Path: ""},
		Images:      []ImageNode{sampleImage("root.jpg")},
		Directories: make(map[string]*TraverseNode),
	}
	root.Directories["alpha"] = &TraverseNode{
		Node:        Node{Name: "alpha", Path: "alpha"},
		Images:      []ImageNode{sampleImage("alpha/pic.jpg")},
		Directories: make(map[string]*TraverseNode),
	}

	for i := 0; i < sampleRuns; i++ {
		got, err := root.Random(false, MediaKindAll)
		if err != nil {
			t.Fatalf("run %d: %v", i, err)
		}
		if got.Path != "root.jpg" {
			t.Fatalf("run %d: descended into a subdirectory: %s", i, got.Path)
		}
	}
}

func TestParseMediaKind(t *testing.T) {
	cases := map[string]MediaKind{
		"image":    MediaKindImage,
		"video":    MediaKindVideo,
		"all":      MediaKindAll,
		"":         MediaKindImage,
		"IMAGE":    MediaKindImage,
		"nonsense": MediaKindImage,
	}
	for raw, want := range cases {
		if got := ParseMediaKind(raw); got != want {
			t.Errorf("ParseMediaKind(%q) = %v, want %v", raw, got, want)
		}
	}
}
