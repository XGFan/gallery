export interface ImgData {
  key: string
  src: string
  imageType: string
  name: string
  width: number
  height: number
  durationSec?: number
  videoSrc?: string
  playable?: boolean
}

export interface Node {
  name: string
  path: string
}

export interface ImageNode extends Node {
  width: number
  height: number
}

export interface VideoNode extends Node {
  width: number
  height: number
  duration_sec?: number
}

export interface DirNode extends Node {
  cover: ImageNode
}

export interface SimpleDirectory {
  images?: ImageNode[]
  videos?: VideoNode[]
  others?: Node[]
  directories?: DirNode[]
}

export interface NodeWithParent extends ImageNode {
  parent: string
}

export type Mode = 'album' | 'image' | 'explore' | 'random'

export interface AppCtx<T> {
  module: string
  data: T
}
