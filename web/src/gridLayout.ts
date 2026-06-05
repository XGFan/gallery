/**
 * Column-based layout math, mirroring the avp gallery's model.
 *
 * The image wall is driven by a discrete column count (like avp) instead of a
 * raw row height, so every zoom step produces a clean, visible change. The
 * justified grid (react-gallery-grid) still wants a target row height, which we
 * derive from the column count, the container width, and the average aspect
 * ratio of the items.
 */

/** Allowed column range for a given container width (mirrors avp). */
export function getColumnLimits(width: number): { min: number; max: number } {
  if (width < 500) return { min: 1, max: 3 };
  if (width < 1100) return { min: 1, max: 5 };
  return { min: 1, max: 7 };
}

/** Default column count for a fresh viewport (mirrors avp's calColumns). */
export function calColumns(width: number): number {
  if (width < 500) return 1;
  if (width < 1100) return 3;
  return 4;
}

/**
 * Average aspect ratio (width / height) across items, used to translate a
 * column count into a target row height. Items without positive dimensions are
 * ignored; falls back to 1.5 (avp's assumed ratio) when nothing is measurable.
 */
export function averageAspect(items: ReadonlyArray<{ width?: number; height?: number }>): number {
  let sum = 0;
  let count = 0;
  for (const it of items) {
    if (it.width && it.height && it.width > 0 && it.height > 0) {
      sum += it.width / it.height;
      count += 1;
    }
  }
  return count > 0 ? sum / count : 1.5;
}

/**
 * Target row height that yields roughly `columns` items per row in a justified
 * grid of the given container width: each item is ~`rowHeight * avgAspect` wide,
 * so `columns` of them fill the width.
 */
export function columnsToRowHeight(width: number, columns: number, avgAspect: number): number {
  if (width <= 0 || columns <= 0 || avgAspect <= 0) return 300;
  return width / (columns * avgAspect);
}
