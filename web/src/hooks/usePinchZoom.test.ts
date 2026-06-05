/**
 * @vitest-environment jsdom
 */
import { describe, expect, it, vi, afterEach } from 'vitest'
import { renderHook } from '@testing-library/react'
import { clamp, computePinchValue, touchDistance, usePinchZoom } from './usePinchZoom'

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

describe('clamp', () => {
  it('passes through values inside the range', () => {
    expect(clamp(500, 250, 1000)).toBe(500)
  })

  it('clamps to the lower and upper bounds', () => {
    expect(clamp(100, 250, 1000)).toBe(250)
    expect(clamp(5000, 250, 1000)).toBe(1000)
  })
})

describe('touchDistance', () => {
  it('computes the euclidean distance between two points', () => {
    const a = { clientX: 0, clientY: 0 } as Touch
    const b = { clientX: 3, clientY: 4 } as Touch
    expect(touchDistance(a, b)).toBe(5)
  })
})

describe('computePinchValue', () => {
  it('scales up when fingers spread apart', () => {
    // distance doubled -> value doubled
    expect(computePinchValue(300, 100, 200, 250, 1000)).toBe(600)
  })

  it('scales down when fingers pinch together', () => {
    // distance halved -> value halved
    expect(computePinchValue(600, 200, 100, 250, 1000)).toBe(300)
  })

  it('rounds the scaled value to an integer', () => {
    expect(computePinchValue(500, 100, 101, 250, 1000)).toBe(505)
  })

  it('clamps to max when spreading far', () => {
    expect(computePinchValue(800, 100, 300, 250, 1000)).toBe(1000)
  })

  it('clamps to min when pinching close', () => {
    expect(computePinchValue(400, 200, 10, 250, 1000)).toBe(250)
  })

  it('returns a clamped start value when the gesture has no baseline distance', () => {
    expect(computePinchValue(500, 0, 200, 250, 1000)).toBe(500)
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

    const { unmount } = renderHook(() =>
      usePinchZoom({ value: 500, setValue: vi.fn(), min: 250, max: 1000 }),
    )

    const docTypes = ['touchstart', 'touchmove', 'touchend', 'touchcancel', 'gesturestart', 'gesturechange']
    const added = new Set(docAdd.mock.calls.map(([type]) => type))
    for (const type of docTypes) expect(added).toContain(type)
    expect(winAdd.mock.calls.some(([type]) => type === 'wheel')).toBe(true)

    unmount()

    const removed = new Set(docRemove.mock.calls.map(([type]) => type))
    for (const type of docTypes) expect(removed).toContain(type)
    expect(winRemove.mock.calls.some(([type]) => type === 'wheel')).toBe(true)
  })

  it('disables native pinch-zoom while mounted and restores it on unmount', () => {
    const { unmount } = renderHook(() =>
      usePinchZoom({ value: 500, setValue: vi.fn(), min: 250, max: 1000 }),
    )
    expect(document.documentElement.style.touchAction).toBe('pan-x pan-y')
    unmount()
    expect(document.documentElement.style.touchAction).toBe('')
  })

  it('zooms in on ctrl + wheel up (negative deltaY)', () => {
    const setValue = vi.fn()
    renderHook(() => usePinchZoom({ value: 500, setValue, min: 250, max: 1000 }))

    window.dispatchEvent(new WheelEvent('wheel', { deltaY: -100, ctrlKey: true, cancelable: true }))

    expect(setValue).toHaveBeenCalledWith(600)
  })

  it('zooms out on ctrl + wheel down (positive deltaY)', () => {
    const setValue = vi.fn()
    renderHook(() => usePinchZoom({ value: 500, setValue, min: 250, max: 1000 }))

    window.dispatchEvent(new WheelEvent('wheel', { deltaY: 100, ctrlKey: true, cancelable: true }))

    expect(setValue).toHaveBeenCalledWith(400)
  })

  it('ignores a plain wheel without ctrl/meta', () => {
    const setValue = vi.fn()
    renderHook(() => usePinchZoom({ value: 500, setValue, min: 250, max: 1000 }))

    window.dispatchEvent(new WheelEvent('wheel', { deltaY: -100, cancelable: true }))

    expect(setValue).not.toHaveBeenCalled()
  })

  it('does not fire setValue when the clamped value is unchanged', () => {
    const setValue = vi.fn()
    // Already at max; wheel-up would push beyond it -> clamped to the same value.
    renderHook(() => usePinchZoom({ value: 1000, setValue, min: 250, max: 1000 }))

    window.dispatchEvent(new WheelEvent('wheel', { deltaY: -100, ctrlKey: true, cancelable: true }))

    expect(setValue).not.toHaveBeenCalled()
  })

  it('scales the value on a two-finger pinch-out', () => {
    const setValue = vi.fn()
    renderHook(() => usePinchZoom({ value: 300, setValue, min: 250, max: 1000 }))

    // Baseline: two fingers 100px apart.
    document.dispatchEvent(fakeTouchEvent('touchstart', [[0, 0], [100, 0]]))
    // Spread to 200px apart -> value scales x2 -> 600.
    document.dispatchEvent(fakeTouchEvent('touchmove', [[0, 0], [200, 0]]))

    expect(setValue).toHaveBeenCalledWith(600)
  })

  it('ignores single-finger touch moves (does not block scrolling)', () => {
    const setValue = vi.fn()
    renderHook(() => usePinchZoom({ value: 500, setValue, min: 250, max: 1000 }))

    document.dispatchEvent(fakeTouchEvent('touchstart', [[10, 10]]))
    document.dispatchEvent(fakeTouchEvent('touchmove', [[10, 80]]))

    expect(setValue).not.toHaveBeenCalled()
  })

  it('re-baselines after a 2->3->2 finger transition instead of jumping', () => {
    const setValue = vi.fn()
    renderHook(() => usePinchZoom({ value: 400, setValue, min: 250, max: 1000 }))

    // Clean two-finger pinch to 200px (from 100px) -> 800.
    document.dispatchEvent(fakeTouchEvent('touchstart', [[0, 0], [100, 0]]))
    document.dispatchEvent(fakeTouchEvent('touchmove', [[0, 0], [200, 0]]))
    expect(setValue).toHaveBeenLastCalledWith(800)
    setValue.mockClear()

    // A third finger lands: gesture invalidated, no resize from the stale pair.
    document.dispatchEvent(fakeTouchEvent('touchmove', [[0, 0], [200, 0], [300, 0]]))
    expect(setValue).not.toHaveBeenCalled()

    // Back to two fingers: first move re-baselines (no jump), it does not resize.
    document.dispatchEvent(fakeTouchEvent('touchmove', [[0, 0], [50, 0]]))
    expect(setValue).not.toHaveBeenCalled()

    // Subsequent move scales relative to the NEW 50px baseline -> 100px = x2 = 800.
    document.dispatchEvent(fakeTouchEvent('touchmove', [[0, 0], [100, 0]]))
    expect(setValue).toHaveBeenLastCalledWith(800)
  })

  describe('when disabled', () => {
    it('attaches no listeners and leaves native pinch-zoom untouched', () => {
      const winAdd = vi.spyOn(window, 'addEventListener')
      const { unmount } = renderHook(() =>
        usePinchZoom({ value: 500, setValue: vi.fn(), min: 250, max: 1000, enabled: false }),
      )

      expect(winAdd.mock.calls.some(([type]) => type === 'wheel')).toBe(false)
      expect(document.documentElement.style.touchAction).toBe('')
      unmount()
    })

    it('does not respond to ctrl + wheel', () => {
      const setValue = vi.fn()
      renderHook(() => usePinchZoom({ value: 500, setValue, min: 250, max: 1000, enabled: false }))

      window.dispatchEvent(new WheelEvent('wheel', { deltaY: -100, ctrlKey: true, cancelable: true }))

      expect(setValue).not.toHaveBeenCalled()
    })

    it('does not respond to a two-finger pinch', () => {
      const setValue = vi.fn()
      renderHook(() => usePinchZoom({ value: 300, setValue, min: 250, max: 1000, enabled: false }))

      document.dispatchEvent(fakeTouchEvent('touchstart', [[0, 0], [100, 0]]))
      document.dispatchEvent(fakeTouchEvent('touchmove', [[0, 0], [200, 0]]))

      expect(setValue).not.toHaveBeenCalled()
    })
  })
})
