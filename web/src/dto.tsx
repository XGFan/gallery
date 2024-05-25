export interface ImgData {
  key: string
  src: string
  imageType: string
  name: string
  width: number
  height: number
}

export class Path {
  readonly name: string
  readonly path: string
  readonly parent?: Path

  constructor(name: string, parent?: Path) {
    this.name = name;
    if (parent != undefined) {
      if (parent.path != '') {
        this.path = parent.path + '/' + name;
      } else {
        this.path = name
      }
    } else {
      this.path = name
    }
    this.parent = parent;
  }

  parents(): Path[] {
    let result = new Array<Path>()
    let p = this.parent
    while (p) {
      result = result.concat(p)
      p = p.parent
    }
    return result
  }
}

export const RootNode = new Path('')

export type Mode = 'album' | 'image' | 'explore' | 'random'

export class Album {
  readonly mode: Mode
  readonly path: Path
  readonly images: ImgData[]

  constructor(mode: Mode, path: Path, images: ImgData[]) {
    this.mode = mode;
    this.path = path
    this.images = images;
  }

  subAlbum(pageSize: number): Album {
    return new Album(this.mode, this.path, this.images.slice(0, pageSize))
  }
}

interface Node {
  name: string
  path: string
}

interface ImageNode extends Node {
  width: number
  height: number
}

interface DirNode extends Node {
  cover: ImageNode
}

interface SimpleDirectory {
  images?: ImageNode[]
  videos?: ImageNode[]
  others?: Node[]
  directories?: DirNode[]
}

interface NodeWithParent extends ImageNode {
  parent: Node
}

export const DEFAULT_PAGE_SIZE = 30

export interface RefView {
  url: string
  name: string
  updateAt: Date
}

export interface VideoView {
  url: string
  name: string
  preview: string
  flag: number
}

export interface ViewPage {
  total: number
  data: VideoView[]
}

export interface AppCtx<T> {
  module: string
  data: T
}

export interface Search {
  tag: string[],
  girl: string[],
  keyword?: string,
  filterOut?: boolean,
  random?: boolean
}

export interface Refs {
  girls: RefView[],
  tags: RefView[],
}

export interface JableApp {
  views: ViewPage,
  refs: Refs
  search: Search
}

export class VideoImage implements ImgData {
  flag: number

  imageType: string;
  key: string;
  name: string;
  src: string;
  width: number = 800;
  height: number = 538;


  constructor(video: VideoView) {
    this.src = video.preview
    this.name = video.name
    this.key = video.url
    this.imageType = 'image'
    this.flag = video.flag
  }

}

export class JableAlbum {
  readonly total: number
  images: VideoImage[]

  constructor(viewPage: ViewPage) {
    this.total = viewPage.total
    this.images = viewPage.data.map(it => new VideoImage(it))
  }

  size(): number {
    return this.images.length
  }

  concat(viewPage: ViewPage): JableAlbum {
    const newAlbum = new JableAlbum(viewPage);
    newAlbum.images = this.images.concat(newAlbum.images)
    return newAlbum
  }

  setFlat(key: string, flag: number) {
    const index = this.images.findIndex(it => it.key === key);
    if (index > -1) {
      this.images[index].flag = flag;
      const newAlbum = new JableAlbum({total: this.total, data: []});
      newAlbum.images = this.images.slice()
      return newAlbum
    }
    return this
  }
}

export interface Task {
  id: number
  url: string
  title: string
  total: number
  success: number
  fail: number
  status: 'WAITING' | 'RUNNING' | 'FINISHED' | 'ERROR'
}

export interface TaskPage {
  total: number,
  data: Task[]
}

function customEncodeURI(s: string): string {
  return s.split("/").map(it => encodeURIComponent(it)).join("/")
}

export function resp2Image(resp: unknown, mode: string): ImgData[] {
  if (mode === "album") {
    return (resp as DirNode[]).filter(it => {
      if (it.cover.height == undefined || it.cover.width == undefined) {
        console.log("error: ", it)
        return false
      }
      return true
    }).map(it => ({
      key: it.path,
      src: customEncodeURI('/thumbnail/' + it.cover.path),
      imageType: "directory",
      name: it.name,
      width: it.cover.width,
      height: it.cover.height
    } as ImgData))
  }
  if (mode === "image") {
    return (resp as ImageNode[]).map(it => ({
      key: it.path,
      src: customEncodeURI('/file/' + it.path),
      imageType: "image",
      name: it.name,
      width: it.width,
      height: it.height
    } as ImgData))
  } else if (mode === "explore") {
    const directories = ((resp as SimpleDirectory).directories ?? [])
      .filter(it => {
        if (it.cover.height == undefined || it.cover.width == undefined) {
          console.log("error: ", it)
          return false
        }
        return true
      })
      .map(it => ({
        key: it.path,
        src: customEncodeURI('/thumbnail/' + it.cover.path),
        imageType: "directory",
        name: it.name,
        width: it.cover.width,
        height: it.cover.height
      } as ImgData)) ?? [];
    const images = ((resp as SimpleDirectory).images ?? []).map(it => ({
      key: it.path,
      src: customEncodeURI('/file/' + it.path),
      imageType: "image",
      name: it.name,
      width: it.width,
      height: it.height
    }) as ImgData) ?? [];
    return directories.concat(images)
  } else if (mode === 'random') {
    const data = resp as NodeWithParent
    return [{
      key: data.path,
      src: customEncodeURI('/file/' + data.path),
      imageType: "image",
      name: data.name,
      width: data.width,
      height: data.height
    }]
  }
  console.log("unknown mode", mode)
  return []
}

export function updateRef(search: Search, type: 'tag' | 'girl', key: string): Search {
  if (type === 'tag') {
    const index = search.tag.indexOf(key);
    if (index > -1) {
      return {
        ...search,
        tag: search.tag.slice(0, index).concat(search.tag.slice(index + 1))
      }
    } else {
      return {
        ...search,
        tag: search.tag.concat(key)
      }
    }
  } else if (type === 'girl') {
    const index = search.girl.indexOf(key);
    if (index > -1) {
      return {
        ...search,
        girl: search.girl.slice(0, index).concat(search.girl.slice(index + 1))
      }
    } else {
      return {
        ...search,
        girl: search.girl.concat(key)
      }
    }
  }
  return search
}

export function buildQueryStr(s: Search): string {
  const params = new URLSearchParams();
  if (s.keyword != undefined) {
    params.append("keyword", s.keyword)
  }
  if (s.filterOut != undefined) {
    params.append("filterOut", String(s.filterOut))
  }
  if (s.random != undefined) {
    params.append("random", String(s.random))
  }
  s.tag.forEach(value => params.append("tag", value))
  s.girl.forEach(value => params.append("girl", value))
  return params.toString()
}

export function calColumns(containerWidth: number) {
  if (containerWidth < 420) {
    return 2
  }
  if (containerWidth < 1200) {
    return 3
  }
  return 4
}

export function generatePath(url: string): Path {
  let result = RootNode
  url.split("/").forEach(path => {
    if (path !== '') {
      result = new Path(path, result)
    }
  })
  return result
}