package gallery

import (
	"errors"
	"github.com/XGFan/go-utils"
	"log"
	"math/rand"
	"path"
	"strings"
)

type TraverseNode struct {
	Node
	Images      []ImageNode
	Others      []Node
	Directories map[string]*TraverseNode
	CoverIndex  int
}

func MergeVirtualPath(name string, nodes []TraverseNode) TraverseNode {
	newNode := TraverseNode{
		Node: Node{
			Name: name,
			Path: name,
		},
		Images:      make([]ImageNode, 0),
		Others:      make([]Node, 0),
		Directories: make(map[string]*TraverseNode),
	}

	for _, node := range nodes {
		newNode.Images = append(newNode.Images, node.Images...)
		newNode.Others = append(newNode.Others, node.Others...)
		for dirName, dirNode := range node.Directories {
			if existingDir, exists := newNode.Directories[dirName]; exists {
				virtualPath := MergeVirtualPath(dirName, []TraverseNode{*existingDir, *dirNode})
				newNode.Directories[dirName] = &virtualPath
			} else {
				newNode.Directories[dirName] = dirNode
			}
		}
	}
	return newNode
}

func (dn *TraverseNode) explore() *SimpleDirectory {
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
		Others:      dn.Others,
	}
}

func (dn *TraverseNode) dump() map[string]Size {
	m := make(map[string]Size)
	for _, img := range dn.image() {
		m[img.Path] = img.Size
	}
	return m
}

func (dn *TraverseNode) load(cache map[string]Size) {
	for i := range dn.Images {
		if dn.Images[i].Size == EmptySize {
			dn.Images[i].Size = cache[dn.Images[i].Path]
		}
	}
	for i := range dn.Directories {
		dn.Directories[i].load(cache)
	}
}

func (dn *TraverseNode) image() []ImageNode {
	var images = make([]ImageNode, 0, 16)
	dn.ScanImages(&images)
	return images
}

func (dn *TraverseNode) album() []DirNode {
	var albums = make([]DirNode, 0, 16)
	dn.ScanAlbum(&albums)
	return albums
}

func (dn *TraverseNode) Random(flatten bool) (NodeWithParent, error) {
	if flatten {
		totalChoice := len(dn.Images) + len(dn.Directories)
		if totalChoice == 0 {
			log.Printf("%s is empty", dn.Path)
			return NodeWithParent{}, errors.New("can not found image")
		}
		index := rand.Intn(totalChoice)
		if index < len(dn.Images) {
			return NodeWithParent{
				ImageNode: dn.Images[index],
				Parent:    dn.Node,
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
			log.Printf("%s is empty", dn.Path)
			return NodeWithParent{}, errors.New("can not found image")
		}
		index := rand.Intn(len(dn.Images))
		return NodeWithParent{
			ImageNode: dn.Images[index],
			Parent:    dn.Node,
		}, nil
	}
}

func (dn *TraverseNode) toTree() map[string]interface{} {
	m := make(map[string]interface{})
	if dn.HasSudDirectories() {
		for _, node := range dn.Directories {
			if dn.Cover() != EmptyNode {
				m[node.Name] = node.toTree()
			}
		}
	}
	return m
}

func (dn *TraverseNode) ScanAlbum(result *[]DirNode) {
	for _, sub := range dn.Directories {
		if sub.HasImages() {
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

func (dn *TraverseNode) ScanImages(result *[]ImageNode) {
	*result = utils.AppendAll(*result, dn.Images)
	for _, sub := range dn.Directories {
		sub.ScanImages(result)
	}
}

func (dn *TraverseNode) HasImages() bool {
	return dn.Images != nil && len(dn.Images) > 0
}

func (dn *TraverseNode) Cover() ImageNode {
	if dn.HasImages() {
		return dn.Images[dn.CoverIndex]
	}
	if dn.HasSudDirectories() {
		for _, sub := range dn.Directories {
			subCover := sub.Cover()
			if subCover != EmptyNode {
				return subCover
			}
		}
	}
	return EmptyNode
}

func (dn *TraverseNode) HasSudDirectories() bool {
	return dn.Directories != nil && len(dn.Directories) > 0
}

func (dn *TraverseNode) Locate(path string) *TraverseNode {
	paths := strings.Split(path, "/")
	p := dn
	for _, s := range paths {
		p = p.OpenOrCreate(s)
	}
	return p
}

func (dn *TraverseNode) OpenOrCreate(name string) *TraverseNode {
	if name == "" {
		return dn
	}
	node, exist := dn.Directories[name]
	if exist {
		return node
	} else {
		newNode := TraverseNode{
			Node: Node{
				Name: name,
				Path: path.Join(dn.Path, name),
			},
			Images:      make([]ImageNode, 0),
			Others:      make([]Node, 0),
			Directories: make(map[string]*TraverseNode),
		}
		dn.Directories[name] = &newNode
		return &newNode
	}
}
