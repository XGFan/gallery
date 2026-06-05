/**
 * @vitest-environment jsdom
 */
import { describe, expect, it, vi, afterEach } from 'vitest'
import { renderHook } from '@testing-library/react'
import { clamp, touchDistance, usePinchZoom } from './usePinchZoom'

/**
 * jsdom has no TouchEvent constructor, so fake one: a plain Event carrying a
 * `touches` array of `{ clientX, clientY }`, which is all the hook reads.
 */
function fakeTouchEvent(type: string, points: Array<[number, number]>): Event {
  const event = new Event(type, { bubbles: true, cancelable: true })
  const touches = points.map(([clientX, clientY]) => ({ clientX, clientY }))
  Object.defineProperty(event, 'touches', { value: touches })
  return event
}

function wheel(opts: WheelEventInit) {
  return new WheelEvent('wheel', { cancelable: true, ...opts })
}

describe('clamp', () => {
  it('passes through values inside the range and clamps outside', () => {
    expect(clamp(3, 1, 7)).toBe(3)
    expect(clamp(0, 1, 7)).toBe(1)
    expect(clamp(99, 1, 7)).toBe(7)
  })
})

describe('touchDistance', () => {
  it('computes the euclidean distance between two points', () => {
    expect(touchDistance({ clientX: 0, clientY: 0 } as Touch, { clientX: 3, clientY: 4 } as Touch)).toBe(5)
  })
})

describe('usePinchZoom', () => {
  afterEach(() => {
    vi.restoreAllMocks()
    document.documentElement.style.touchAction = ''
  })

  it('registers and tears down every gesture listener', () => {
    const docAdd = vi.spyOn(document, 'addEventListener')
    const docRemove = vi.spyOn(document, 'removeEventListener')
    const winAdd = vi.spyOn(window, 'addEventListener')
    const winRemove = vi.spyOn(window, 'removeEventListener')

    const { unmount } = renderHook(() => usePinchZoom({ onZoom: vi.fn() }))

    const docTypes = ['touchstart', 'touchmove', 'touchend', 'touchcancel', 'gesturestart', 'gesturechange']
    const added = new Set(docAdd.mock.calls.map(([t]) => t))
    for (const t of docTypes) expect(added).toContain(t)
    expect(winAdd.mock.calls.some(([t]) => t === 'wheel')).toBe(true)

    unmount()
    const removed = new Set(docRemove.mock.calls.map(([t]) => t))
    for (const t of docTypes) expect(removed).toContain(t)
    expect(winRemove.mock.calls.some(([t]) => t === 'wheel')).toBe(true)
  })

  it('disables native pinch-zoom while mounted and restores it on unmount', () => {
    const { unmount } = renderHook(() => usePinchZoom({ onZoom: vi.fn() }))
    expect(document.documentElement.style.touchAction).toBe('pan-x pan-y')
    unmount()
    expect(document.documentElement.style.touchAction).toBe('')
  })

  it('zooms in on ctrl + wheel up and out on wheel down', () => {
    vi.spyOn(Date, 'now').mockReturnValue(10_000)
    const onZoom = vi.fn()
    renderHook(() => usePinchZoom({ onZoom }))

    window.dispatchEvent(wheel({ deltaY: -120, ctrlKey: true }))
    expect(onZoom).toHaveBeenLastCalledWith(1)

    // advance past cooldown so the next step is allowed
    vi.spyOn(Date, 'now').mockReturnValue(10_400)
    window.dispatchEvent(wheel({ deltaY: 120, ctrlKey: true }))
    expect(onZoom).toHaveBeenLastCalledWith(-1)
  })

  it('ignores a plain wheel without ctrl/meta', () => {
    vi.spyOn(Date, 'now').mockReturnValue(10_000)
    const onZoom = vi.fn()
    renderHook(() => usePinchZoom({ onZoom }))
    window.dispatchEvent(wheel({ deltaY: -120 }))
    expect(onZoom).not.toHaveBeenCalled()
  })

  it('respects the wheel cooldown (no burst within one window)', () => {
    vi.spyOn(Date, 'now').mockReturnValue(10_000)
    const onZoom = vi.fn()
    renderHook(() => usePinchZoom({ onZoom, cooldownMs: 250 }))

    window.dispatchEvent(wheel({ deltaY: -120, ctrlKey: true }))
    window.dispatchEvent(wheel({ deltaY: -120, ctrlKey: true })) // same timestamp -> blocked
    expect(onZoom).toHaveBeenCalledTimes(1)
  })

  it('steps in on a two-finger spread and out on a pinch', () => {
    vi.spyOn(Date, 'now').mockReturnValue(10_000)
    const onZoom = vi.fn()
    renderHook(() => usePinchZoom({ onZoom, threshold: 30 }))

    // spread: 100px -> 140px (delta 40 > 30) => zoom in
    document.dispatchEvent(fakeTouchEvent('touchstart', [[0, 0], [100, 0]]))
    document.dispatchEvent(fakeTouchEvent('touchmove', [[0, 0], [140, 0]]))
    expect(onZoom).toHaveBeenLastCalledWith(1)

    // new gesture, advance past cooldown, pinch: 140 -> 90 (delta -50) => zoom out
    vi.spyOn(Date, 'now').mockReturnValue(10_400)
    document.dispatchEvent(fakeTouchEvent('touchstart', [[0, 0], [140, 0]]))
    document.dispatchEvent(fakeTouchEvent('touchmove', [[0, 0], [90, 0]]))
    expect(onZoom).toHaveBeenLastCalledWith(-1)
  })

  it('does not step for spreads below the threshold', () => {
    vi.spyOn(Date, 'now').mockReturnValue(10_000)
    const onZoom = vi.fn()
    renderHook(() => usePinchZoom({ onZoom, threshold: 30 }))
    document.dispatchEvent(fakeTouchEvent('touchstart', [[0, 0], [100, 0]]))
    document.dispatchEvent(fakeTouchEvent('touchmove', [[0, 0], [120, 0]])) // delta 20 < 30
    expect(onZoom).not.toHaveBeenCalled()
  })

  it('ignores single-finger moves (does not block scrolling)', () => {
    vi.spyOn(Date, 'now').mockReturnValue(10_000)
    const onZoom = vi.fn()
    renderHook(() => usePinchZoom({ onZoom }))
    document.dispatchEvent(fakeTouchEvent('touchstart', [[10, 10]]))
    document.dispatchEvent(fakeTouchEvent('touchmove', [[10, 90]]))
    expect(onZoom).not.toHaveBeenCalled()
  })

  it('re-arms the baseline so a sustained spread keeps stepping', () => {
    let t = 10_000
    vi.spyOn(Date, 'now').mockImplementation(() => t)
    const onZoom = vi.fn()
    renderHook(() => usePinchZoom({ onZoom, threshold: 30, cooldownMs: 250 }))

    document.dispatchEvent(fakeTouchEvent('touchstart', [[0, 0], [100, 0]]))
    document.dispatchEvent(fakeTouchEvent('touchmove', [[0, 0], [140, 0]])) // step 1
    t = 10_400
    document.dispatchEvent(fakeTouchEvent('touchmove', [[0, 0], [180, 0]])) // re-armed at 140, delta 40 => step 2
    expect(onZoom).toHaveBeenCalledTimes(2)
    expect(onZoom).toHaveBeenNthCalledWith(1, 1)
    expect(onZoom).toHaveBeenNthCalledWith(2, 1)
  })

  describe('when disabled', () => {
    it('attaches no listeners and leaves native pinch-zoom untouched', () => {
      const winAdd = vi.spyOn(window, 'addEventListener')
      const { unmount } = renderHook(() => usePinchZoom({ onZoom: vi.fn(), enabled: false }))
      expect(winAdd.mock.calls.some(([t]) => t === 'wheel')).toBe(false)
      expect(document.documentElement.style.touchAction).toBe('')
      unmount()
    })

    it('does not respond to ctrl + wheel or pinch', () => {
      vi.spyOn(Date, 'now').mockReturnValue(10_000)
      const onZoom = vi.fn()
      renderHook(() => usePinchZoom({ onZoom, enabled: false }))
      window.dispatchEvent(wheel({ deltaY: -120, ctrlKey: true }))
      document.dispatchEvent(fakeTouchEvent('touchstart', [[0, 0], [100, 0]]))
      document.dispatchEvent(fakeTouchEvent('touchmove', [[0, 0], [200, 0]]))
      expect(onZoom).not.toHaveBeenCalled()
    })
  })
})
