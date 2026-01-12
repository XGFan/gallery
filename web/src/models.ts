import type { ImgData, Mode } from './types'

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

export function generatePath(url: string): Path {
  let result = RootNode
  url.split("/").forEach(path => {
    if (path !== '') {
      const name = decodeURIComponent(path)
      result = new Path(name, result)
    }
  })
  return result
}
