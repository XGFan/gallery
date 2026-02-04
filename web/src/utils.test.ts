/**
 * @vitest-environment jsdom
 */
import { describe, expect, it, vi, beforeEach } from 'vitest'
import { resp2Image, getMixedMode, setMixedMode, buildSwipeSequence } from './utils'
import type { ImgData } from './types'

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

describe('Mixed Mode storage', () => {
  beforeEach(() => {
    let store: Record<string, string> = {}
    vi.stubGlobal('localStorage', {
      getItem: vi.fn((key: string) => store[key] || null),
      setItem: vi.fn((key: string, value: string) => { store[key] = value }),
      clear: vi.fn(() => { store = {} }),
      removeItem: vi.fn((key: string) => { delete store[key] })
    })
  })

  it('defaults to true', () => {
    localStorage.clear()
    expect(getMixedMode()).toBe(true)
  })

  it('saves and retrieves mixed mode', () => {
    setMixedMode(false)
    expect(getMixedMode()).toBe(false)
    setMixedMode(true)
    expect(getMixedMode()).toBe(true)
  })
})

describe('buildSwipeSequence', () => {
  const mockData: ImgData[] = [
    { key: 'img1', src: '', imageType: 'image', name: 'img1', width: 100, height: 100 },
    { key: 'vid1', src: '', imageType: 'video', name: 'vid1', width: 100, height: 100 },
    { key: 'img2', src: '', imageType: 'image', name: 'img2', width: 100, height: 100 },
    { key: 'vid2', src: '', imageType: 'video', name: 'vid2', width: 100, height: 100 },
    { key: 'dir1', src: '', imageType: 'directory', name: 'dir1', width: 100, height: 100 },
  ]

  it('keeps all items when mixedMode is true', () => {
    const { sequence, initialIndex } = buildSwipeSequence(mockData, 'img2', true)
    expect(sequence).toEqual(mockData)
    expect(initialIndex).toBe(2)
  })

  it('filters by image type when mixedMode is false and entry is image', () => {
    const { sequence, initialIndex } = buildSwipeSequence(mockData, 'img2', false)
    expect(sequence).toHaveLength(2)
    expect(sequence[0].key).toBe('img1')
    expect(sequence[1].key).toBe('img2')
    expect(initialIndex).toBe(1)
  })

  it('filters by video type when mixedMode is false and entry is video', () => {
    const { sequence, initialIndex } = buildSwipeSequence(mockData, 'vid2', false)
    expect(sequence).toHaveLength(2)
    expect(sequence[0].key).toBe('vid1')
    expect(sequence[1].key).toBe('vid2')
    expect(initialIndex).toBe(1)
  })

  it('handles entry not found by returning all data and index 0', () => {
    const { sequence, initialIndex } = buildSwipeSequence(mockData, 'not-exists', true)
    expect(sequence).toEqual(mockData)
    expect(initialIndex).toBe(0)
  })

  it('handles entry not found with mixedMode false by returning all data and index 0', () => {
    const { sequence, initialIndex } = buildSwipeSequence(mockData, 'not-exists', false)
    expect(sequence).toEqual(mockData)
    expect(initialIndex).toBe(0)
  })

  it('handles directory type by returning all data if mixedMode is true', () => {
    const { sequence, initialIndex } = buildSwipeSequence(mockData, 'dir1', true)
    expect(sequence).toEqual(mockData)
    expect(initialIndex).toBe(4)
  })

  it('handles directory type by returning only directories if mixedMode is false', () => {
    const { sequence, initialIndex } = buildSwipeSequence(mockData, 'dir1', false)
    expect(sequence).toHaveLength(1)
    expect(sequence[0].key).toBe('dir1')
    expect(initialIndex).toBe(0)
  })
})
