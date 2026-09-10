package core

import "testing"

// unsizedVideo is the case that broke ToTree: ffprobe never produced a size, so
// Cover() falls through and reports the directory as having nothing.
func unsizedVideo(name string) VideoNode {
	return VideoNode{Node: Node{Name: name, Path: name}}
}

func dir(name string, build func(*TraverseNode)) *TraverseNode {
	node := &TraverseNode{
		Node:        Node{Name: name, Path: name},
		Directories: make(map[string]*TraverseNode),
	}
	if build != nil {
		build(node)
	}
	return node
}

func TestToTree_KeepsVideoOnlyDirectoriesWithoutAProbedSize(t *testing.T) {
	clips := dir("clips", func(n *TraverseNode) {
		n.Videos = []VideoNode{unsizedVideo("clips/a.mp4")}
	})
	root := dir("", func(n *TraverseNode) {
		n.Directories["clips"] = clips
	})

	if !clips.Cover().IsEmpty() {
		t.Fatal("precondition: an unsized video should yield no cover")
	}
	tree := root.ToTree()
	if _, ok := tree["clips"]; !ok {
		t.Fatalf("a directory full of clips must stay reachable in the tree, got %v", tree)
	}
}

func TestToTree_DropsDirectoriesWithNoMediaAnywhere(t *testing.T) {
	empty := dir("junk", func(n *TraverseNode) {
		n.Others = []Node{{Name: "notes.txt", Path: "junk/notes.txt"}}
		n.Directories["deeper"] = dir("junk/deeper", nil)
	})
	root := dir("", func(n *TraverseNode) {
		n.Directories["junk"] = empty
	})

	if _, ok := root.ToTree()["junk"]; ok {
		t.Fatal("a subtree with no media at all is not part of the library")
	}
}

// The invariant the native client's view switcher rests on: a node has children
// in the tree exactly when Album would list something beneath it. If these two
// ever disagree, the switcher hides views that have content. See docs/adr/0007.
func TestToTreeAndAlbumAgreeOnWhatIsBeneathANode(t *testing.T) {
	root := dir("", func(n *TraverseNode) {
		n.Directories["photos"] = dir("photos", func(p *TraverseNode) {
			p.Images = []ImageNode{sampleImage("photos/a.jpg")}
		})
		n.Directories["clips"] = dir("clips", func(c *TraverseNode) {
			c.Videos = []VideoNode{unsizedVideo("clips/a.mp4")}
		})
		n.Directories["nested"] = dir("nested", func(v *TraverseNode) {
			v.Directories["inner"] = dir("nested/inner", func(i *TraverseNode) {
				i.Images = []ImageNode{sampleImage("nested/inner/a.jpg")}
			})
		})
		n.Directories["junk"] = dir("junk", nil)
	})

	tree := root.ToTree()
	for name, node := range root.Directories {
		subtree, inTree := tree[name]
		albums := node.Album()

		if !inTree {
			if len(albums) > 0 {
				t.Fatalf("%s is missing from the tree but Album lists %d entries", name, len(albums))
			}
			continue
		}
		hasChildren := len(subtree.(map[string]interface{})) > 0
		if hasChildren != (len(albums) > 0) {
			t.Fatalf(
				"%s: tree says hasChildren=%v but Album returned %d entries",
				name, hasChildren, len(albums),
			)
		}
	}
}
