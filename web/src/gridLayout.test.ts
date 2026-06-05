import { describe, expect, it } from 'vitest'
import { averageAspect, calColumns, columnsToRowHeight, getColumnLimits } from './gridLayout'

describe('getColumnLimits', () => {
  it('widens the allowed range with viewport width', () => {
    expect(getColumnLimits(400)).toEqual({ min: 1, max: 3 })
    expect(getColumnLimits(800)).toEqual({ min: 1, max: 5 })
    expect(getColumnLimits(1400)).toEqual({ min: 1, max: 7 })
  })

  it('uses boundary thresholds at 500 and 1100', () => {
    expect(getColumnLimits(499).max).toBe(3)
    expect(getColumnLimits(500).max).toBe(5)
    expect(getColumnLimits(1099).max).toBe(5)
    expect(getColumnLimits(1100).max).toBe(7)
  })
})

describe('calColumns', () => {
  it('picks a sensible default per width tier', () => {
    expect(calColumns(400)).toBe(1)
    expect(calColumns(800)).toBe(3)
    expect(calColumns(1400)).toBe(4)
  })
})

describe('averageAspect', () => {
  it('averages width/height across valid items', () => {
    expect(averageAspect([{ width: 800, height: 400 }, { width: 600, height: 600 }])).toBe(1.5)
  })

  it('ignores items with missing or zero dimensions', () => {
    expect(averageAspect([{ width: 800, height: 400 }, { width: 0, height: 0 }, {}])).toBe(2)
  })

  it('falls back to 1.5 when nothing is measurable', () => {
    expect(averageAspect([])).toBe(1.5)
    expect(averageAspect([{ width: 0, height: 100 }])).toBe(1.5)
  })
})

describe('columnsToRowHeight', () => {
  it('derives a row height that fits N items across the width', () => {
    // 1280 wide, 2 columns, 4:3 (aspect 1.333) -> ~480px rows
    expect(Math.round(columnsToRowHeight(1280, 2, 4 / 3))).toBe(480)
    // fewer columns => taller rows (bigger images)
    expect(columnsToRowHeight(1280, 1, 4 / 3)).toBeGreaterThan(columnsToRowHeight(1280, 2, 4 / 3))
  })

  it('returns a safe fallback for degenerate inputs', () => {
    expect(columnsToRowHeight(0, 3, 1.5)).toBe(300)
    expect(columnsToRowHeight(1280, 0, 1.5)).toBe(300)
    expect(columnsToRowHeight(1280, 3, 0)).toBe(300)
  })
})
