import { cleanup, render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import axios from 'axios'
import FileTree from './FileTree'
import { Album, generatePath } from './dto'
import type { AppCtx } from './types'

const mockUseLoaderData = vi.fn<() => AppCtx<Album>>()
const mockNavigate = vi.fn()

vi.mock('axios', () => ({
  default: {
    get: vi.fn(),
  },
}))

vi.mock('react-router-dom', async () => {
  const actual = await vi.importActual<typeof import('react-router-dom')>('react-router-dom')
  return {
    ...actual,
    useLoaderData: () => mockUseLoaderData(),
    useNavigate: () => mockNavigate,
  }
})

const mockedAxiosGet = vi.mocked(axios.get)

function renderFileTree(path: string, treeData: object) {
  mockUseLoaderData.mockReturnValue({
    module: 'test',
    data: new Album('album', generatePath(path), []),
  })
  mockedAxiosGet.mockResolvedValueOnce({ data: treeData })

  render(<FileTree />)
}

describe('FileTree', () => {
  beforeEach(() => {
    mockNavigate.mockReset()
    mockUseLoaderData.mockReset()
    mockedAxiosGet.mockReset()
    vi.spyOn(console, 'log').mockImplementation(() => {})
  })

  afterEach(() => {
    cleanup()
    vi.restoreAllMocks()
  })

  it('builds tree data, expands required ancestors, and lets selected folders collapse locally', async () => {
    const user = userEvent.setup()

    renderFileTree('photos 2024/trip shots/selected child', {
      'photos 2024': {
        'trip shots': {
          'selected child': {
            'frame 1.png': null,
          },
          'trip cover.jpg': null,
        },
        'city nights': {
          'neon sign.png': null,
        },
      },
    })

    await waitFor(() => {
      expect(screen.getByText('frame 1.png')).toBeInTheDocument()
    })

    expect(screen.getByText('photos 2024')).toBeInTheDocument()
    expect(screen.getByText('trip shots')).toBeInTheDocument()
    expect(screen.getByText('city nights')).toBeInTheDocument()

    await user.click(screen.getByText('selected child'))

    expect(mockNavigate).not.toHaveBeenCalled()
    expect(screen.queryByText('frame 1.png')).not.toBeInTheDocument()
    expect(screen.getByText('trip shots')).toBeInTheDocument()
    expect(screen.getByText('city nights')).toBeInTheDocument()

    await user.click(screen.getByText('selected child'))

    expect(screen.getByText('frame 1.png')).toBeInTheDocument()
  })

  it('navigates leaf nodes to image mode with encoded tree keys', async () => {
    const user = userEvent.setup()

    renderFileTree('photos 2024/trip shots', {
      'photos 2024': {
        'trip shots': {
          'beach day.jpg': null,
        },
      },
    })

    await waitFor(() => {
      expect(screen.getByText('beach day.jpg')).toBeInTheDocument()
    })

    await user.click(screen.getByText('beach day.jpg'))

    expect(mockNavigate).toHaveBeenCalledWith('/photos%202024/trip%20shots/beach%20day.jpg?mode=image')
  })

  it('navigates other non-leaf folders to album mode', async () => {
    const user = userEvent.setup()

    renderFileTree('photos 2024/trip shots', {
      'photos 2024': {
        'trip shots': {
          'beach day.jpg': null,
        },
        'city nights': {
          'neon sign.png': null,
        },
      },
    })

    await waitFor(() => {
      expect(screen.getByText('city nights')).toBeInTheDocument()
    })

    await user.click(screen.getByText('city nights'))

    expect(mockNavigate).toHaveBeenCalledWith('/photos%202024/city%20nights?mode=album')
  })
})
