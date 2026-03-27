import { cleanup, render, screen, waitFor } from '@testing-library/react'
import type { ReactNode } from 'react'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

const { axiosGetMock, resp2ImageMock, shuffleMock } = vi.hoisted(() => ({
  axiosGetMock: vi.fn(),
  resp2ImageMock: vi.fn(),
  shuffleMock: vi.fn((images: Array<{ key: string }>) => images.reverse())
}))

vi.mock('axios', () => ({
  default: {
    get: axiosGetMock
  }
}))

vi.mock('react-router-dom', async () => {
  const React = await vi.importActual<typeof import('react')>('react')
  const LocationContext = React.createContext({ pathname: '', search: '' })
  const LoaderDataContext = React.createContext<unknown>(undefined)

  return {
    createBrowserRouter: (routes: Array<{ element: ReactNode; loader: (args: { request: { url: string }; params: Record<string, string> }) => Promise<unknown> }>) => ({ routes }),
    RouterProvider: ({ router }: { router: { routes: Array<{ element: ReactNode; loader: (args: { request: { url: string }; params: Record<string, string> }) => Promise<unknown> }> } }) => {
      const route = router.routes[0]
      const location = React.useMemo(() => ({
        pathname: window.location.pathname,
        search: window.location.search
      }), [])
      const [loaderData, setLoaderData] = React.useState<unknown>(undefined)

      React.useEffect(() => {
        let cancelled = false

        Promise.resolve(route.loader({
          request: { url: window.location.href },
          params: { '*': location.pathname.replace(/^\//, '') }
        })).then(data => {
          if (!cancelled) {
            setLoaderData(data)
          }
        })

        return () => {
          cancelled = true
        }
      }, [location.pathname, location.search, route])

      return (
        <LocationContext.Provider value={location}>
          <LoaderDataContext.Provider value={loaderData}>
            {loaderData ? route.element : null}
          </LoaderDataContext.Provider>
        </LocationContext.Provider>
      )
    },
    useLocation: () => React.useContext(LocationContext),
    useLoaderData: () => React.useContext(LoaderDataContext)
  }
})

vi.mock('./dto', async () => {
  const actual = await vi.importActual<typeof import('./dto')>('./dto')
  return {
    ...actual,
    resp2Image: resp2ImageMock,
    shuffle: shuffleMock
  }
})

vi.mock('./Viewer', async () => {
  const { useLoaderData, useLocation } = await import('react-router-dom')

  return {
    default: function MockViewer() {
      const loaderData = useLoaderData() as {
        module: string
        data: {
          mode: string
          path: { path: string }
          images: Array<{ key: string }>
        }
      }
      const location = useLocation()

      return (
        <div>
          <div data-testid="module">{loaderData.module}</div>
          <div data-testid="mode">{loaderData.data.mode}</div>
          <div data-testid="path">{loaderData.data.path.path}</div>
          <div data-testid="image-keys">{loaderData.data.images.map(item => item.key).join(',')}</div>
          <div data-testid="location">{location.pathname + location.search}</div>
        </div>
      )
    }
  }
})

vi.mock('./layouts/RootLayout.tsx', () => ({
  default: ({ children }: { children: ReactNode }) => <div data-testid="root-layout">{children}</div>
}))

async function renderAt(url: string) {
  vi.resetModules()
  window.history.replaceState({}, '', url)
  const { default: App } = await import('./App')
  render(<App />)

  await waitFor(() => {
    expect(screen.getByTestId('module')).toHaveTextContent('viewer')
  })
}

describe('App route loader', () => {
  beforeEach(() => {
    axiosGetMock.mockReset()
    resp2ImageMock.mockReset()
    shuffleMock.mockClear()
    axiosGetMock.mockResolvedValue({ data: { ok: true } })
    vi.stubGlobal('Request', window.Request)
    vi.stubGlobal('AbortController', window.AbortController)
    vi.stubGlobal('AbortSignal', window.AbortSignal)
  })

  afterEach(() => {
    vi.unstubAllGlobals()
    cleanup()
  })

  it('loads album mode from the album endpoint', async () => {
    resp2ImageMock.mockReturnValue([
      { key: 'album-1' },
      { key: 'album-2' }
    ])

    await renderAt('/summer/trip?mode=album')

    expect(axiosGetMock).toHaveBeenCalledWith('/api/album/summer/trip', {})
    expect(resp2ImageMock).toHaveBeenCalledWith({ ok: true }, 'album')
    expect(screen.getByTestId('mode')).toHaveTextContent('album')
    expect(screen.getByTestId('path')).toHaveTextContent('summer/trip')
    expect(screen.getByTestId('image-keys')).toHaveTextContent('album-1,album-2')
  })

  it('maps image mode to the media endpoint instead of the image endpoint', async () => {
    resp2ImageMock.mockReturnValue([
      { key: 'media-1' }
    ])

    await renderAt('/summer/trip?mode=image')

    expect(axiosGetMock).toHaveBeenCalledWith('/api/media/summer/trip', {})
    expect(axiosGetMock).not.toHaveBeenCalledWith('/api/image/summer/trip', {})
    expect(resp2ImageMock).toHaveBeenCalledWith({ ok: true }, 'media')
    expect(screen.getByTestId('mode')).toHaveTextContent('image')
    expect(screen.getByTestId('image-keys')).toHaveTextContent('media-1')
  })

  it('loads explore mode from the explore endpoint', async () => {
    resp2ImageMock.mockReturnValue([
      { key: 'explore-1' }
    ])

    await renderAt('/folders?mode=explore')

    expect(axiosGetMock).toHaveBeenCalledWith('/api/explore/folders', {})
    expect(resp2ImageMock).toHaveBeenCalledWith({ ok: true }, 'explore')
    expect(screen.getByTestId('mode')).toHaveTextContent('explore')
    expect(screen.getByTestId('image-keys')).toHaveTextContent('explore-1')
  })

  it('keeps random mode while requesting image data and shuffling mapped results', async () => {
    resp2ImageMock.mockReturnValue([
      { key: 'first' },
      { key: 'second' },
      { key: 'third' }
    ])

    await renderAt('/shuffle/me?mode=random')

    expect(axiosGetMock).toHaveBeenCalledWith('/api/image/shuffle/me', {})
    expect(resp2ImageMock).toHaveBeenCalledWith({ ok: true }, 'image')
    expect(shuffleMock).toHaveBeenCalledTimes(1)
    expect(screen.getByTestId('mode')).toHaveTextContent('random')
    expect(screen.getByTestId('location')).toHaveTextContent('/shuffle/me?mode=random')
    expect(screen.getByTestId('image-keys')).toHaveTextContent('third,second,first')
  })
})
