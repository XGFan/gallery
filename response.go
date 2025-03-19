package gallery

type Node struct {
	//名称
	Name string `json:"name,omitempty"`
	//路径
	Path string `json:"path,omitempty"`
}

type Size struct {
	//宽
	Width int `json:"width,omitempty"`
	//长
	Height int `json:"height,omitempty"`
}

type DirNode struct {
	Node
	//封面
	Cover ImageNode `json:"cover,omitempty"`
}

type ImageNode struct {
	Node
	Size
}

type SimpleDirectory struct {
	Images      []ImageNode `json:"images,omitempty"`
	Others      []Node      `json:"others,omitempty"`
	Directories []DirNode   `json:"directories,omitempty"`
}

type NodeWithParent struct {
	ImageNode
	Parent Node `json:"parent,omitempty"`
}

var EmptyNode = ImageNode{}
var EmptySize = Size{}
