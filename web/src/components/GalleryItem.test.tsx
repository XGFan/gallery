/**
 * @vitest-environment jsdom
 */
import { cleanup, render, screen, fireEvent } from '@testing-library/react'
import { afterEach, describe, expect, it, vi } from 'vitest'
import { GalleryItem } from './GalleryItem'
import type { ImgData } from '../types'

describe('GalleryItem', () => {
  const defaultSize = { width: 200, height: 200 }

  afterEach(() => {
    cleanup()
  })

  it('renders image with correct aria-label', () => {
    const item: ImgData = {
      key: 'img1',
      src: '/file/img1.jpg',
      imageType: 'image',
      name: 'img1',
      width: 100,
      height: 100
    }
    const onClick = vi.fn()

    render(<GalleryItem item={item} size={defaultSize} onClick={onClick} />)

    const buttons = screen.getAllByRole('button', { name: 'View image img1' })
    expect(buttons[0]).toBeInTheDocument()
    expect(buttons[0]).toHaveAttribute('tabIndex', '0')
    expect(buttons[0]).not.toHaveAttribute('aria-disabled')
    expect(buttons[0]).not.toHaveClass('opacity-60')
  })

  it('renders playable video with Play icon and correct aria-label', () => {
    const item: ImgData = {
      key: 'vid1',
      src: '/poster/vid1.mp4',
      videoSrc: '/video/vid1.mp4',
      imageType: 'video',
      name: 'vid1',
      width: 100,
      height: 100,
      playable: true
    }
    const onClick = vi.fn()

    render(<GalleryItem item={item} size={defaultSize} onClick={onClick} />)

    const buttons = screen.getAllByRole('button', { name: 'Play video vid1' })
    expect(buttons[0]).toBeInTheDocument()
    expect(buttons[0]).toHaveAttribute('data-testid', 'gallery-video-item')
    expect(buttons[0]).not.toHaveAttribute('aria-disabled')
    expect(buttons[0]).not.toHaveClass('opacity-60')
  })

  it('renders non-playable video with View aria-label (fully actionable)', () => {
    const item: ImgData = {
      key: 'vid-bad',
      src: '/poster/vid-bad.mkv',
      videoSrc: '/video/vid-bad.mkv',
      imageType: 'video',
      name: 'vid-bad',
      width: 100,
      height: 100,
      playable: false
    }
    const onClick = vi.fn()

    render(<GalleryItem item={item} size={defaultSize} onClick={onClick} />)

    const buttons = screen.getAllByRole('button', { name: 'View vid-bad' })
    expect(buttons[0]).toBeInTheDocument()
    expect(buttons[0]).toHaveAttribute('data-testid', 'gallery-video-item')
    expect(buttons[0]).not.toHaveAttribute('aria-disabled')
    expect(buttons[0]).toHaveClass('opacity-60')
    expect(buttons[0]).toHaveClass('cursor-pointer')
    expect(buttons[0]).toHaveAttribute('tabIndex', '0')
  })

  it('renders directory with correct aria-label', () => {
    const item: ImgData = {
      key: 'folder1',
      src: '/thumbnail/folder1',
      imageType: 'directory',
      name: 'folder1',
      width: 100,
      height: 100
    }
    const onClick = vi.fn()

    render(<GalleryItem item={item} size={defaultSize} onClick={onClick} />)

    const buttons = screen.getAllByRole('button', { name: 'Open folder folder1' })
    expect(buttons[0]).toBeInTheDocument()
  })

  it('calls onClick when clicked', () => {
    const item: ImgData = {
      key: 'img1',
      src: '/file/img1.jpg',
      imageType: 'image',
      name: 'img1',
      width: 100,
      height: 100
    }
    const onClick = vi.fn()

    render(<GalleryItem item={item} size={defaultSize} onClick={onClick} />)

    const buttons = screen.getAllByRole('button', { name: 'View image img1' })
    fireEvent.click(buttons[0])
    expect(onClick).toHaveBeenCalledTimes(1)
  })

  it('calls onClick for non-playable video (explore mode navigation)', () => {
    const item: ImgData = {
      key: 'vid-bad',
      src: '/poster/vid-bad.mkv',
      videoSrc: '/video/vid-bad.mkv',
      imageType: 'video',
      name: 'vid-bad',
      width: 100,
      height: 100,
      playable: false
    }
    const onClick = vi.fn()

    render(<GalleryItem item={item} size={defaultSize} onClick={onClick} />)

    const buttons = screen.getAllByRole('button', { name: 'View vid-bad' })
    fireEvent.click(buttons[0])
    expect(onClick).toHaveBeenCalledTimes(1)
  })

  it('responds to keyboard Enter key', () => {
    const item: ImgData = {
      key: 'img1',
      src: '/file/img1.jpg',
      imageType: 'image',
      name: 'img1',
      width: 100,
      height: 100
    }
    const onClick = vi.fn()

    render(<GalleryItem item={item} size={defaultSize} onClick={onClick} />)

    const buttons = screen.getAllByRole('button', { name: 'View image img1' })
    fireEvent.keyDown(buttons[0], { key: 'Enter' })
    expect(onClick).toHaveBeenCalledTimes(1)
  })

  it('responds to keyboard Space key', () => {
    const item: ImgData = {
      key: 'img1',
      src: '/file/img1.jpg',
      imageType: 'image',
      name: 'img1',
      width: 100,
      height: 100
    }
    const onClick = vi.fn()

    render(<GalleryItem item={item} size={defaultSize} onClick={onClick} />)

    const buttons = screen.getAllByRole('button', { name: 'View image img1' })
    fireEvent.keyDown(buttons[0], { key: ' ' })
    expect(onClick).toHaveBeenCalledTimes(1)
  })
})
