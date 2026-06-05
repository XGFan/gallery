import { cleanup, render, screen, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import type { ImgData, Mode } from '../../types'
import { Album, generatePath } from '../../dto'
import MobileNav from './MobileNav'

const mockNavigate = vi.fn()
let loaderData: unknown

vi.mock('react-router-dom', async () => {
  const actual = await vi.importActual<typeof import('react-router-dom')>('react-router-dom')
  return {
    ...actual,
    useLoaderData: () => loaderData,
    useNavigate: () => mockNavigate
  }
})

// A deeper child keeps isLeaf=false so all four modes are offered.
const deepImages: ImgData[] = [
  {
    key: 'cats/sub/deep/child.jpg',
    src: '/file/cats/sub/deep/child.jpg',
    imageType: 'image',
    name: 'child',
    width: 100,
    height: 100
  }
]

function renderNav(mode: Mode = 'image', path = 'cats/sub', images = deepImages) {
  loaderData = { data: new Album(mode, generatePath(path), images) }
  return render(<MobileNav onSidebarToggle={() => {}} />)
}

describe('MobileNav', () => {
  afterEach(() => {
    cleanup()
    vi.restoreAllMocks()
    vi.unstubAllGlobals()
  })

  beforeEach(() => {
    let store: Record<string, string> = {}
    mockNavigate.mockReset()
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
  })

  it('switches mode with a single tap, keeping the current path', async () => {
    const user = userEvent.setup()
    renderNav('image')

    await user.click(screen.getByRole('button', { name: 'Albums' }))

    expect(mockNavigate).toHaveBeenCalledWith('/cats/sub?mode=album')
  })

  it('uses React Router navigation for shuffle in web mode', async () => {
    const user = userEvent.setup()
    localStorage.setItem('shuffle-open-mode', 'web')
    renderNav('image')

    await user.click(screen.getByRole('button', { name: 'Shuffle' }))

    expect(mockNavigate).toHaveBeenCalledWith('/cats/sub?mode=random')
  })

  it('hands shuffle off to tinyviewer when app mode is selected', async () => {
    const user = userEvent.setup()
    const location = { href: 'http://localhost/' } as Location
    localStorage.setItem('shuffle-open-mode', 'app')
    vi.spyOn(window, 'location', 'get').mockReturnValue(location)
    renderNav('image')

    await user.click(screen.getByRole('button', { name: 'Shuffle' }))

    expect(location.href).toBe('tinyviewer://cats/sub')
    expect(mockNavigate).not.toHaveBeenCalled()
  })

  it('opens the path sheet and jumps to an ancestor without horizontal scrolling', async () => {
    const user = userEvent.setup()
    renderNav('image')

    // No mode switcher hidden behind the title — the bar shows only nav.
    await user.click(screen.getByRole('button', { name: 'Show path' }))

    const sheet = screen.getByRole('dialog', { name: 'Path navigation' })
    // Full ancestry is a vertical list: Home / cats / sub.
    expect(within(sheet).getByRole('button', { name: 'Home' })).toBeInTheDocument()
    expect(within(sheet).getByRole('button', { name: 'sub' })).toHaveAttribute('aria-current', 'page')

    await user.click(within(sheet).getByRole('button', { name: 'cats' }))

    expect(mockNavigate).toHaveBeenCalledWith('/cats?mode=album')
  })

  it('collapses to Photos + Shuffle on a leaf folder', () => {
    // Flat children only => isLeaf=true => directory modes drop out.
    const flat: ImgData[] = [
      { key: 'cats/a.jpg', src: '/file/cats/a.jpg', imageType: 'image', name: 'a', width: 10, height: 10 }
    ]
    renderNav('image', 'cats', flat)

    expect(screen.getByRole('button', { name: 'Photos' })).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Shuffle' })).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Albums' })).not.toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Explore' })).not.toBeInTheDocument()
  })
})
