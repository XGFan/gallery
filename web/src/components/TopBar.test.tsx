import { cleanup, render, screen, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import type { ImgData, Mode } from '../types'
import { Album, generatePath } from '../dto'
import TopBar from './TopBar'

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

const nestedImages: ImgData[] = [
  {
    key: 'cats/sub/child.jpg',
    src: '/file/cats/sub/child.jpg',
    imageType: 'image',
    name: 'child',
    width: 100,
    height: 100
  }
]

function renderTopBar(mode: Mode = 'image', path = 'cats') {
  loaderData = {
    data: new Album(mode, generatePath(path), nestedImages)
  }

  return render(<TopBar />)
}

async function expandSwitcher(user: ReturnType<typeof userEvent.setup>) {
  const header = screen.getByRole('banner')
  const buttons = within(header).getAllByRole('button')
  await user.click(buttons[buttons.length - 1])
}

describe('TopBar', () => {
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

    vi.stubGlobal('ResizeObserver', class {
      observe() {}
      disconnect() {}
    })

    Object.defineProperty(window, 'matchMedia', {
      writable: true,
      value: vi.fn().mockReturnValue({
        matches: false,
        addEventListener: vi.fn(),
        removeEventListener: vi.fn()
      })
    })
  })

  it('keeps the current mode last when the switcher expands', async () => {
    const user = userEvent.setup()

    renderTopBar('image')
    await expandSwitcher(user)

    const modeLabels = within(screen.getByRole('banner'))
      .getAllByRole('button')
      .map((button) => button.textContent?.trim() ?? '')
      .filter((label) => ['Albums', 'Explore', 'Shuffle', 'Photos'].includes(label))

    expect(modeLabels).toEqual(['Albums', 'Explore', 'Shuffle', 'Photos'])
  })

  it('uses React Router navigation for shuffle in web mode', async () => {
    const user = userEvent.setup()

    localStorage.setItem('shuffle-open-mode', 'web')
    renderTopBar('image')

    await expandSwitcher(user)
    await user.click(screen.getByRole('button', { name: 'Shuffle' }))

    expect(mockNavigate).toHaveBeenCalledWith('/cats?mode=random')
  })

  it('hands shuffle off to tinyviewer when app mode is selected', async () => {
    const user = userEvent.setup()
    const location = { href: 'http://localhost/' } as Location

    localStorage.setItem('shuffle-open-mode', 'app')
    vi.spyOn(window, 'location', 'get').mockReturnValue(location)
    renderTopBar('image')

    await expandSwitcher(user)
    await user.click(screen.getByRole('button', { name: 'Shuffle' }))

    expect(location.href).toBe('tinyviewer://cats')
    expect(mockNavigate).not.toHaveBeenCalled()
  })
})
