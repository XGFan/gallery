import { cleanup, render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import RootLayout from './RootLayout'

vi.mock('../components/NavigationSidebar', () => ({
  default: ({ onOpenShuffleSettings }: { onOpenShuffleSettings?: () => void }) => (
    <aside data-testid="navigation-sidebar">
      <button type="button" aria-label="Shuffle Settings" onClick={onOpenShuffleSettings}>
        Shuffle Settings
      </button>
    </aside>
  )
}))

vi.mock('../components/TopBar', () => ({
  default: ({ onSidebarToggle, isSidebarOpen }: { onSidebarToggle?: () => void; isSidebarOpen?: boolean }) => (
    <button
      type="button"
      aria-label={isSidebarOpen ? 'Close Sidebar' : 'Open Sidebar'}
      onClick={onSidebarToggle}
    >
      {isSidebarOpen ? 'Close Sidebar' : 'Open Sidebar'}
    </button>
  )
}))

describe('RootLayout', () => {
  afterEach(() => {
    cleanup()
    vi.unstubAllGlobals()
  })

  beforeEach(() => {
    let store: Record<string, string> = {}
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

  it('toggles the sidebar and opens/closes shuffle settings', async () => {
    const user = userEvent.setup()

    render(
      <RootLayout>
        <div>content</div>
      </RootLayout>
    )

    await user.click(screen.getByRole('button', { name: 'Open Sidebar' }))
    expect(screen.getByRole('button', { name: 'Close Sidebar' })).toBeInTheDocument()

    await user.click(screen.getByRole('button', { name: 'Shuffle Settings' }))

    expect(screen.getByRole('dialog')).toBeInTheDocument()
    expect(screen.getByText('Shuffle Mode')).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Open Sidebar' })).toBeInTheDocument()

    await user.click(screen.getByRole('button', { name: 'Close' }))
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument()
  })

  it('persists mixed mode choices across renders', async () => {
    const user = userEvent.setup()

    const { unmount } = render(
      <RootLayout>
        <div>content</div>
      </RootLayout>
    )

    await user.click(screen.getByRole('button', { name: 'Open Sidebar' }))
    await user.click(screen.getByRole('button', { name: 'Shuffle Settings' }))

    const mixedButton = screen.getByTestId('mixed-mode-mixed')
    const isolatedButton = screen.getByTestId('mixed-mode-isolated')

    expect(mixedButton).toHaveAttribute('aria-pressed', 'true')
    expect(isolatedButton).toHaveAttribute('aria-pressed', 'false')

    await user.click(isolatedButton)

    expect(localStorage.getItem('mixed-mode')).toBe('false')
    expect(mixedButton).toHaveAttribute('aria-pressed', 'false')
    expect(isolatedButton).toHaveAttribute('aria-pressed', 'true')

    unmount()

    render(
      <RootLayout>
        <div>content</div>
      </RootLayout>
    )

    await user.click(screen.getByRole('button', { name: 'Open Sidebar' }))
    await user.click(screen.getByRole('button', { name: 'Shuffle Settings' }))

    expect(screen.getByTestId('mixed-mode-mixed')).toHaveAttribute('aria-pressed', 'false')
    expect(screen.getByTestId('mixed-mode-isolated')).toHaveAttribute('aria-pressed', 'true')
  })

  it('stores the selected shuffle open mode and closes the modal', async () => {
    const user = userEvent.setup()

    render(
      <RootLayout>
        <div>content</div>
      </RootLayout>
    )

    await user.click(screen.getByRole('button', { name: 'Open Sidebar' }))
    await user.click(screen.getByRole('button', { name: 'Shuffle Settings' }))
    await user.click(screen.getByRole('button', { name: 'App' }))

    expect(localStorage.getItem('shuffle-open-mode')).toBe('app')
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument()
  })
})
