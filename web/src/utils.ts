import type { ImgData, DirNode, ImageNode, SimpleDirectory, NodeWithParent } from './types'

export const DEFAULT_PAGE_SIZE = 30
export type ShuffleOpenMode = "web" | "app"
const SHUFFLE_OPEN_MODE_KEY = "shuffle-open-mode"

export function getShuffleOpenMode(): ShuffleOpenMode {
  const value = localStorage.getItem(SHUFFLE_OPEN_MODE_KEY)
  return value === "app" ? "app" : "web"
}

export function setShuffleOpenMode(mode: ShuffleOpenMode): void {
  localStorage.setItem(SHUFFLE_OPEN_MODE_KEY, mode)
}

export function customEncodeURI(s: string): string {
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
      key: customEncodeURI(it.path),
      src: customEncodeURI('/thumbnail/' + it.cover.path),
      imageType: "directory",
      name: it.name,
      width: it.cover.width,
      height: it.cover.height
    } as ImgData))
  }
  if (mode === "image") {
    return (resp as ImageNode[]).map(it => ({
      key: customEncodeURI(it.path),
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
        key: customEncodeURI(it.path),
        src: customEncodeURI('/thumbnail/' + it.cover.path),
        imageType: "directory",
        name: it.name,
        width: it.cover.width,
        height: it.cover.height
      } as ImgData)) ?? [];
    const images = ((resp as SimpleDirectory).images ?? []).map(it => ({
      key: customEncodeURI(it.path),
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
      key: customEncodeURI(data.path),
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

export function shuffle<T>(array: T[]): T[] {
  for (let i = array.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [array[i], array[j]] = [array[j], array[i]];
  }
  return array;
}
