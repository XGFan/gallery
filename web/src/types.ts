export interface ImgData {
  key: string
  src: string
  imageType: string
  name: string
  width: number
  height: number
}

export interface Node {
  name: string
  path: string
}

export interface ImageNode extends Node {
  width: number
  height: number
}

export interface DirNode extends Node {
  cover: ImageNode
}

export interface SimpleDirectory {
  images?: ImageNode[]
  videos?: ImageNode[]
  others?: Node[]
  directories?: DirNode[]
}

export interface NodeWithParent extends ImageNode {
  parent: Node
}

export type Mode = 'album' | 'image' | 'explore' | 'random'

export interface AppCtx<T> {
  module: string
  data: T
}
