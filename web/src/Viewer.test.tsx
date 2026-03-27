/**
 * @vitest-environment jsdom
 */
import { cleanup, fireEvent, render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import type { ImgData, Mode } from './types'
import { Album, generatePath } from './dto'

const mockNavigate = vi.fn()
let loaderData: { data: Album }
let store: Record<string, string> = {}

vi.mock('react-router-dom', async () => {
  const React = await vi.importActual<typeof import('react')>('react')
  return {
    useLoaderData: () => loaderData,
    useNavigate: () => mockNavigate,
    useLocation: () => React.useMemo(() => ({ pathname: window.location.pathname, search: window.location.search }), [])
  }
})

vi.mock('react-gallery-grid', () => ({
  Gallery: ({ items, itemRenderer }: { items: ImgData[]; itemRenderer: (props: { item: ImgData; size: { width: number; height: number }; index: number }) => React.ReactNode }) => (
    <div data-testid="gallery">
      {items.map((item, index) => (
        <React.Fragment key={item.key}>
          {itemRenderer({ item, size: { width: 200, height: 200 }, index })}
        </React.Fragment>
      ))}
    </div>
  )
}))

vi.mock('react-infinite-scroll-component', () => ({
  default: ({ children, dataLength, hasMore, next }: { children: React.ReactNode; dataLength: number; hasMore: boolean; next: () => void }) => (
    <div data-testid="infinite-scroll" data-length={dataLength} data-has-more={hasMore}>
      {children}
      {hasMore && <button type="button" onClick={next}>Load More</button>}
    </div>
  )
}))

vi.mock('yet-another-react-lightbox', () => ({
  default: ({ slides, index, open, close, on }: {
    slides: unknown[];
    index: number;
    open: boolean;
    close: () => void;
    on?: { exiting?: () => void };
  }) => (
    <div data-testid="lightbox" data-open={open} data-index={index}>
      <button type="button" onClick={close} aria-label="Close lightbox">Close</button>
      <div data-testid="current-slide">{slides[index] ? JSON.stringify(slides[index]) : ''}</div>
      <button type="button" onClick={on?.exiting} aria-label="Exit fullscreen">Exit Fullscreen</button>
    </div>
  ),
  createIcon: (_name: string, _path: React.ReactNode) => () => null,
  IconButton: ({ label, onClick }: { label: string; onClick: () => void }) => (
    <button type="button" onClick={onClick} aria-label={label}>{label}</button>
  ),
  useLightboxState: () => ({ currentSlide: null }),
  Fullscreen: vi.fn(),
  Slideshow: vi.fn(),
  Zoom: vi.fn(),
  Video: vi.fn()
}))

vi.mock('./components/VerticalPlayer', () => ({
  default: ({ items, initialIndex, onClose }: { items: ImgData[]; initialIndex: number; onClose: () => void }) => (
    <div data-testid="vertical-player" data-initial-index={initialIndex}>
      {items.map((item, i) => (
        <div key={item.key} data-testid={`slide-${i + 1}`}>{item.name}</div>
      ))}
      <button type="button" onClick={onClose} aria-label="Close player">Close</button>
    </div>
  )
}))

vi.mock('./components/ui/Modal', () => ({
  Modal: ({ isOpen, onClose, title, children }: { isOpen: boolean; onClose: () => void; title: string; children: React.ReactNode }) => (
    isOpen ? (
      <div role="dialog" aria-label={title}>
        <button type="button" onClick={onClose} aria-label="Close modal">Close</button>
        {children}
      </div>
    ) : null
  )
}))

vi.mock('./components/ui/Slider', () => ({
  Slider: ({ min, max, value, onChange }: { min: number; max: number; value: number; onChange: (v: number) => void }) => (
    <input
      type="range"
      min={min}
      max={max}
      value={value}
      onChange={(e) => onChange(Number(e.target.value))}
      data-testid="row-height-slider"
    />
  )
}))

vi.mock('./components/GalleryItem', () => ({
  GalleryItem: ({ item, onClick }: { item: ImgData; size: { width: number; height: number }; onClick: () => void }) => {
    const isVideo = item.imageType === 'video'
    const isPlayable = isVideo && item.playable !== false
    const ariaLabel = item.imageType === 'directory'
      ? `Open folder ${item.name}`
      : isVideo
        ? (isPlayable ? `Play video ${item.name}` : `View ${item.name}`)
        : `View image ${item.name}`
    return (
      <button
        type="button"
        data-testid={`gallery-item-${item.key}`}
        onClick={onClick}
        aria-label={ariaLabel}
      >
        {item.name}
      </button>
    )
  }
}))

vi.mock('./utils', async () => {
  const actual = await vi.importActual<typeof import('./utils')>('./utils')
  return {
    ...actual,
    getMixedMode: () => true
  }
})

import React from 'react'
import Viewer from './Viewer'

const defaultImages: ImgData[] = [
  { key: 'img1', src: '/file/img1.jpg', imageType: 'image', name: 'img1', width: 100, height: 100 },
  { key: 'img2', src: '/file/img2.jpg', imageType: 'image', name: 'img2', width: 100, height: 100 },
  { key: 'vid1', src: '/poster/vid1.mp4', videoSrc: '/video/vid1.mp4', imageType: 'video', name: 'vid1', width: 100, height: 100, playable: true },
  { key: 'vid2', src: '/poster/vid2.mp4', videoSrc: '/video/vid2.mp4', imageType: 'video', name: 'vid2', width: 100, height: 100, playable: true },
  { key: 'dir1', src: '/thumbnail/dir1', imageType: 'directory', name: 'dir1', width: 100, height: 100 }
]

const nonPlayableVideo: ImgData = { key: 'vid-bad', src: '/poster/vid-bad.mkv', videoSrc: '/video/vid-bad.mkv', imageType: 'video', name: 'vid-bad', width: 100, height: 100, playable: false }

const videosOnly: ImgData[] = [
  { key: 'vid1', src: '/poster/vid1.mp4', videoSrc: '/video/vid1.mp4', imageType: 'video', name: 'vid1', width: 100, height: 100, playable: true },
  { key: 'vid2', src: '/poster/vid2.mp4', videoSrc: '/video/vid2.mp4', imageType: 'video', name: 'vid2', width: 100, height: 100, playable: true },
]

function renderViewer(mode: Mode = 'image', images: ImgData[] = defaultImages, path = 'test') {
  loaderData = {
    data: new Album(mode, generatePath(path), images)
  }
  return render(<Viewer />)
}

describe('Viewer', () => {
  beforeEach(() => {
    store = {}
    vi.stubGlobal('localStorage', {
      getItem: vi.fn((key: string) => store[key] ?? null),
      setItem: vi.fn((key: string, value: string) => {
        store[key] = value
      }),
      clear: vi.fn(() => {
        store = {}
      }),
      removeItem: vi.fn((key: string) => {
        delete store[key]
      })
    })
    mockNavigate.mockReset()
    vi.spyOn(window, 'scrollTo').mockImplementation(() => {})
  })

  afterEach(() => {
    cleanup()
    vi.restoreAllMocks()
    vi.unstubAllGlobals()
  })

  describe('row-height localStorage fallback and persistence', () => {
    it('uses DEFAULT_ROW_HEIGHT when localStorage is empty', async () => {
      renderViewer()
      expect(localStorage.getItem('row-height')).toBe('500')
    })

    it('uses DEFAULT_ROW_HEIGHT for invalid values below 200', async () => {
      store['row-height'] = '50'
      renderViewer()
      expect(localStorage.getItem('row-height')).toBe('500')
    })

    it('uses DEFAULT_ROW_HEIGHT for invalid values above 1000', async () => {
      store['row-height'] = '2000'
      renderViewer()
      expect(localStorage.getItem('row-height')).toBe('500')
    })

    it('uses DEFAULT_ROW_HEIGHT for non-numeric values', async () => {
      store['row-height'] = 'invalid'
      renderViewer()
      expect(localStorage.getItem('row-height')).toBe('500')
    })

    it('persists row-height changes to localStorage when value changes', async () => {
      store['row-height'] = '300'
      renderViewer()

      expect(localStorage.getItem('row-height')).toBe('300')
    })

    it('uses valid row-height from localStorage', async () => {
      store['row-height'] = '600'
      renderViewer()
      expect(localStorage.getItem('row-height')).toBe('600')
    })
  })

  describe('random-mode initialization', () => {
    it('initializes with index 0 and opens lightbox in random mode', async () => {
      renderViewer('random')

      const lightbox = screen.getByTestId('lightbox')
      expect(lightbox).toHaveAttribute('data-open', 'true')
      expect(lightbox).toHaveAttribute('data-index', '0')
    })

    it('does not open lightbox immediately in non-random modes', async () => {
      renderViewer('image')

      const lightbox = screen.getByTestId('lightbox')
      expect(lightbox).toHaveAttribute('data-open', 'false')
    })
  })

  describe('image-mode click branching', () => {
    it('opens lightbox when clicking image in image mode', async () => {
      const user = userEvent.setup()
      renderViewer('image')

      const imageItem = screen.getByTestId('gallery-item-img1')
      await user.click(imageItem)

      const lightbox = screen.getByTestId('lightbox')
      expect(lightbox).toHaveAttribute('data-open', 'true')
      expect(screen.queryByTestId('vertical-player')).not.toBeInTheDocument()
    })

    it('opens vertical player when clicking playable video in image mode', async () => {
      const user = userEvent.setup()
      renderViewer('image', videosOnly)

      const videoItem = screen.getByTestId('gallery-item-vid1')
      await user.click(videoItem)

      expect(screen.getByTestId('vertical-player')).toBeInTheDocument()
      expect(screen.getByTestId('vertical-player')).toHaveAttribute('data-initial-index', '0')

      const lightbox = screen.getByTestId('lightbox')
      expect(lightbox).toHaveAttribute('data-open', 'false')
    })

    it('opens vertical player for non-playable video in image mode (player shows fallback)', async () => {
      const user = userEvent.setup()
      renderViewer('image', [nonPlayableVideo])

      const videoItem = screen.getByTestId('gallery-item-vid-bad')
      await user.click(videoItem)

      expect(screen.getByTestId('vertical-player')).toBeInTheDocument()
      const lightbox = screen.getByTestId('lightbox')
      expect(lightbox).toHaveAttribute('data-open', 'false')
    })
  })

  describe('explore-mode click branching', () => {
    it('opens lightbox when clicking image in explore mode', async () => {
      const user = userEvent.setup()
      renderViewer('explore')

      const imageItem = screen.getByTestId('gallery-item-img1')
      await user.click(imageItem)

      const lightbox = screen.getByTestId('lightbox')
      expect(lightbox).toHaveAttribute('data-open', 'true')
      expect(screen.queryByTestId('vertical-player')).not.toBeInTheDocument()
    })

    it('opens vertical player when clicking playable video in explore mode', async () => {
      const user = userEvent.setup()
      renderViewer('explore', videosOnly)

      const videoItem = screen.getByTestId('gallery-item-vid1')
      await user.click(videoItem)

      expect(screen.getByTestId('vertical-player')).toBeInTheDocument()
      const lightbox = screen.getByTestId('lightbox')
      expect(lightbox).toHaveAttribute('data-open', 'false')
    })

    it('navigates to explore path when clicking directory in explore mode', async () => {
      const user = userEvent.setup()
      renderViewer('explore')

      const dirItem = screen.getByTestId('gallery-item-dir1')
      await user.click(dirItem)

      expect(mockNavigate).toHaveBeenCalledWith('/dir1?mode=explore')
      expect(screen.queryByTestId('vertical-player')).not.toBeInTheDocument()
      const lightbox = screen.getByTestId('lightbox')
      expect(lightbox).toHaveAttribute('data-open', 'false')
    })

    it('navigates to explore path when clicking non-playable video in explore mode', async () => {
      const user = userEvent.setup()
      renderViewer('explore', [nonPlayableVideo, ...defaultImages.slice(0, 2)])

      const videoItem = screen.getByTestId('gallery-item-vid-bad')
      await user.click(videoItem)

      expect(mockNavigate).toHaveBeenCalledWith('/vid-bad?mode=explore')
      expect(screen.queryByTestId('vertical-player')).not.toBeInTheDocument()
    })
  })

  describe('album-mode click behavior', () => {
    it('navigates to image mode when clicking item in album mode', async () => {
      const user = userEvent.setup()
      renderViewer('album')

      const imageItem = screen.getByTestId('gallery-item-img1')
      await user.click(imageItem)

      expect(mockNavigate).toHaveBeenCalledWith('/img1?mode=image')
    })
  })

  describe('close side effects', () => {
    it('resets index, activePlayer, and entryKey when closing lightbox', async () => {
      const user = userEvent.setup()
      renderViewer('image')

      const imageItem = screen.getByTestId('gallery-item-img1')
      await user.click(imageItem)

      const lightbox = screen.getByTestId('lightbox')
      expect(lightbox).toHaveAttribute('data-open', 'true')
      expect(lightbox).toHaveAttribute('data-index', '0')

      await user.click(screen.getByRole('button', { name: 'Close lightbox' }))

      expect(lightbox).toHaveAttribute('data-open', 'false')
      const secondImage = screen.getByTestId('gallery-item-img2')
      await user.click(secondImage)
      expect(lightbox).toHaveAttribute('data-open', 'true')
    })

    it('resets index, activePlayer, and entryKey when closing vertical player', async () => {
      const user = userEvent.setup()
      renderViewer('image', videosOnly)

      const videoItem = screen.getByTestId('gallery-item-vid1')
      await user.click(videoItem)

      expect(screen.getByTestId('vertical-player')).toBeInTheDocument()

      await user.click(screen.getByRole('button', { name: 'Close player' }))

      expect(screen.queryByTestId('vertical-player')).not.toBeInTheDocument()

      const secondVideo = screen.getByTestId('gallery-item-vid2')
      await user.click(secondVideo)
      expect(screen.getByTestId('vertical-player')).toBeInTheDocument()
      expect(screen.getByTestId('vertical-player')).toHaveAttribute('data-initial-index', '1')
    })
  })

  describe('counter behavior', () => {
    it('shows counter with correct counts', async () => {
      renderViewer('image')

      expect(screen.getByRole('button', { name: 'Open settings' })).toHaveTextContent('5 / 5')
    })

    it('counter is initially visible with opacity-100 class', async () => {
      renderViewer('image')

      const counterButton = screen.getByRole('button', { name: 'Open settings' })
      expect(counterButton).toHaveClass('opacity-100')
    })

    it('opens config modal when clicking counter', async () => {
      const user = userEvent.setup()
      renderViewer('image')

      await user.click(screen.getByRole('button', { name: 'Open settings' }))

      expect(screen.getByRole('dialog', { name: 'Settings' })).toBeInTheDocument()
    })
  })

  describe('config modal row-height persistence', () => {
    it('persists row-height changes to localStorage via slider', async () => {
      const user = userEvent.setup()
      store['row-height'] = '300'
      renderViewer()

      await user.click(screen.getByRole('button', { name: 'Open settings' }))

      const slider = screen.getByTestId('row-height-slider')
      expect(slider).toHaveValue('300')

      fireEvent.change(slider, { target: { value: '600' } })

      expect(localStorage.getItem('row-height')).toBe('600')
    })

    it('slider shows current row-height value', async () => {
      const user = userEvent.setup()
      store['row-height'] = '750'
      renderViewer()

      await user.click(screen.getByRole('button', { name: 'Open settings' }))

      const slider = screen.getByTestId('row-height-slider')
      expect(slider).toHaveValue('750')
    })
  })

  describe('random mode exiting behavior', () => {
    it('renders with lightbox open in random mode', async () => {
      renderViewer('random')

      const lightbox = screen.getByTestId('lightbox')
      expect(lightbox).toHaveAttribute('data-open', 'true')
      expect(lightbox).toHaveAttribute('data-index', '0')
    })
  })

  describe('infinite scroll', () => {
    it('renders with correct data length and hasMore', async () => {
      const manyImages: ImgData[] = Array.from({ length: 50 }, (_, i) => ({
        key: `img-${i}`,
        src: `/file/img-${i}.jpg`,
        imageType: 'image',
        name: `img-${i}`,
        width: 100,
        height: 100
      }))

      renderViewer('image', manyImages)

      const scrollContainer = screen.getByTestId('infinite-scroll')
      expect(scrollContainer).toHaveAttribute('data-length', '30')
      expect(scrollContainer).toHaveAttribute('data-has-more', 'true')
    })

    it('shows load more button when hasMore is true', async () => {
      const manyImages: ImgData[] = Array.from({ length: 50 }, (_, i) => ({
        key: `img-${i}`,
        src: `/file/img-${i}.jpg`,
        imageType: 'image',
        name: `img-${i}`,
        width: 100,
        height: 100
      }))

      renderViewer('image', manyImages)

      expect(screen.getByText('Load More')).toBeInTheDocument()
    })

    it('does not show load more button when all items loaded', async () => {
      renderViewer('image', defaultImages.slice(0, 2))

      expect(screen.queryByText('Load More')).not.toBeInTheDocument()
    })
  })
})
