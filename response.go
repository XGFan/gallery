package gallery

type SimpleDirectory struct {
	Images      []ImageNode `json:"images,omitempty"`
	Others      []Node      `json:"others,omitempty"`
	Directories []DirNode   `json:"directories,omitempty"`
}

type DirNode struct {
	Name  string    `json:"name,omitempty"`
	Path  string    `json:"path,omitempty"`
	Cover ImageNode `json:"cover,omitempty"`
}

type Node struct {
	Name string `json:"name,omitempty"`
	Path string `json:"path,omitempty"`
}

type ImageNode struct {
	Node
	Size
}

type Size struct {
	Width  int `json:"width,omitempty"`
	Height int `json:"height,omitempty"`
}

type NodeWithParent struct {
	ImageNode
	Parent Node `json:"parent,omitempty"`
}

var EmptyNode = ImageNode{}
var EmptySize = Size{}
