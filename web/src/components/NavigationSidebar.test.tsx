import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { describe, expect, it, vi } from 'vitest'
import NavigationSidebar from './NavigationSidebar'

vi.mock('../FileTree', () => ({
  default: () => <div data-testid="file-tree">Mock FileTree</div>,
}))

describe('NavigationSidebar', () => {
  it('invokes the shuffle settings callback from the sidebar button', async () => {
    const user = userEvent.setup()
    const onOpenShuffleSettings = vi.fn()

    render(<NavigationSidebar onOpenShuffleSettings={onOpenShuffleSettings} />)

    await user.click(screen.getByLabelText('Shuffle Settings'))

    expect(onOpenShuffleSettings).toHaveBeenCalledTimes(1)
    expect(screen.getByTestId('file-tree')).toBeInTheDocument()
  })
})
