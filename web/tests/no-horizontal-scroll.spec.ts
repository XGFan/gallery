/// <reference lib="es2015.promise" />
import { expect, test } from '@playwright/test'

// Regression guard: the gallery must fill the width with no horizontal scrollbar,
// even when its (tall) content shows a vertical scrollbar. The vertical scrollbar
// is a classic 6px one (::-webkit-scrollbar in index.css), so any `100vw`-based
// width overflows by the scrollbar width.

const IMAGE_COUNT = 24

test.beforeEach(async ({ page }) => {
  await page.route('**/api/**', async route => {
    const url = route.request().url()
    if (url.includes('/api/media')) {
      const images = Array.from({ length: IMAGE_COUNT }, (_, i) => ({
        name: `img${i}`,
        path: `wall/img${i}.jpg`,
        width: 800,
        height: 600,
      }))
      await route.fulfill({ contentType: 'application/json', body: JSON.stringify({ images, videos: [] }) })
    } else if (url.includes('/api/album')) {
      await route.fulfill({ contentType: 'application/json', body: JSON.stringify([]) })
    } else {
      await route.fulfill({ contentType: 'application/json', body: JSON.stringify({ images: [], videos: [], directories: [] }) })
    }
  })
  await page.route(/\/(thumbnail|file|poster|video)\//, route => route.abort())
})

test('the page has no horizontal scrollbar when content is tall', async ({ page }) => {
  await page.goto('/wall?mode=image')
  await expect(page.locator('[aria-label^="View image"]').first()).toBeVisible()

  const metrics = await page.evaluate(() => {
    const doc = document.documentElement
    return {
      scrollWidth: doc.scrollWidth,
      clientWidth: doc.clientWidth,
      // Confirm the scenario: content is tall enough to need a vertical scrollbar.
      verticalScroll: doc.scrollHeight > doc.clientHeight,
    }
  })

  expect(metrics.verticalScroll).toBe(true)
  expect(metrics.scrollWidth).toBeLessThanOrEqual(metrics.clientWidth)
})
