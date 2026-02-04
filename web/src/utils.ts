import type { ImgData, DirNode, ImageNode, SimpleDirectory, NodeWithParent, VideoNode } from './types'

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

// Singleton video element for capability testing
let testVideoElement: HTMLVideoElement | null = null;
const VIDEO_EXTENSIONS = new Set(['mp4', 'm4v', 'mov', 'webm', 'ogv', 'ogg', 'avi', 'mkv', 'flv', 'wmv', 'ts']);

function getTestVideoElement(): HTMLVideoElement | null {
  if (typeof document === 'undefined') return null;
  if (!testVideoElement) {
    testVideoElement = document.createElement('video');
  }
  return testVideoElement;
}

function isVideoPlayable(path: string): boolean {
  if (typeof document === 'undefined') return true
  const video = getTestVideoElement();
  if (!video) return true;

  const ext = path.split('.').pop()?.toLowerCase() || '';
  if (['mp4', 'm4v'].includes(ext)) return video.canPlayType('video/mp4') !== '';
  if (ext === 'mov') return video.canPlayType('video/quicktime') !== '';
  if (ext === 'webm') return video.canPlayType('video/webm') !== '';
  
  // Other formats assumed playable or let the browser decide later (default true as fallback)
  return true
}

function isVideoPath(path: string): boolean {
  const ext = path.split('.').pop()?.toLowerCase()
  return !!ext && VIDEO_EXTENSIONS.has(ext)
}

export function getMimeType(path: string): string | undefined {
  const ext = path.split('.').pop()?.toLowerCase()
  switch(ext) {
    case 'mp4':
    case 'm4v': return 'video/mp4';
    case 'mov': return 'video/quicktime';
    case 'webm': return 'video/webm';
    default: return undefined;
  }
}

const mapImageNode = (it: ImageNode): ImgData => ({
  key: customEncodeURI(it.path),
  src: customEncodeURI('/file/' + it.path),
  imageType: "image",
  name: it.name,
  width: it.width,
  height: it.height
});

const mapVideoNode = (it: VideoNode): ImgData => ({
  key: customEncodeURI(it.path),
  src: customEncodeURI('/poster/' + it.path),
  videoSrc: customEncodeURI('/video/' + it.path),
  imageType: "video",
  name: it.name,
  width: it.width,
  height: it.height,
  durationSec: it.duration_sec,
  playable: isVideoPlayable(it.path)
});

const mapDirNode = (it: DirNode): ImgData | null => {
  if (it.cover.height == undefined || it.cover.width == undefined) {
    console.log("error: ", it)
    return null
  }
  return {
    key: customEncodeURI(it.path),
    src: customEncodeURI((isVideoPath(it.cover.path) ? '/poster/' : '/thumbnail/') + it.cover.path),
    imageType: "directory",
    name: it.name,
    width: it.cover.width,
    height: it.cover.height
  }
};

export function resp2Image(resp: unknown, mode: string): ImgData[] {
  if (mode === "album") {
    return (resp as DirNode[])
      .map(mapDirNode)
      .filter((it): it is ImgData => it !== null);
  }

  if (mode === "image" || mode === "media" || mode === "explore") {
    // "image" mode is theoretically handled as "media" in App.tsx loader for the API call,
    // but the actual response structure for "image" (if not redirected) is ImageNode[].
    // However, App.tsx logic suggests: const requestMode = mode === 'image' ? 'media' ...
    // So resp2Image receives 'media' for image mode.
    
    if (mode === "image") {
       // Fallback if strictly "image" mode response (ImageNode[]) passed
       return (resp as ImageNode[]).map(mapImageNode);
    }

    // media (images + videos) OR explore (dirs + images + videos)
    const data = resp as SimpleDirectory;
    let result: ImgData[] = [];

    if (mode === "explore" && data.directories) {
      result = result.concat(
        data.directories
          .map(mapDirNode)
          .filter((it): it is ImgData => it !== null)
      );
    }

    if (data.images) {
      result = result.concat(data.images.map(mapImageNode));
    }

    if (data.videos) {
      result = result.concat(data.videos.map(mapVideoNode));
    }

    return result;
  }
  
  if (mode === 'random') {
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
