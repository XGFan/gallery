import { describe, expect, it, vi } from 'vitest'
import { resp2Image } from './utils'

describe('resp2Image', () => {
  it('maps media videos to poster/video sources with playable flag', () => {
    const canPlaySpy = vi.spyOn(HTMLMediaElement.prototype, 'canPlayType').mockReturnValue('probably')
    const response = {
      images: [],
      videos: [
        {
          name: 'clip',
          path: 'videos/clip.mp4',
          width: 640,
          height: 360,
          duration_sec: 65.4
        }
      ]
    }

    const result = resp2Image(response, 'media')
    const videoItem = result.find(item => item.imageType === 'video')

    expect(videoItem).toBeDefined()
    expect(videoItem?.src).toBe('/poster/videos/clip.mp4')
    expect(videoItem?.videoSrc).toBe('/video/videos/clip.mp4')
    expect(videoItem?.playable).toBe(true)
    expect(videoItem?.durationSec).toBe(65.4)

    canPlaySpy.mockRestore()
  })
})
