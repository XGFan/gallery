/// <reference lib="es2015.promise" />
import { expect, test, type Page } from '@playwright/test'

// Real multi-touch + modifier-wheel input is only drivable via Chrome DevTools
// Protocol, so these gesture e2e tests are Chromium-only. The pure gesture/step
// logic is covered cross-engine by the unit tests in
// src/hooks/usePinchZoom.test.ts and src/gridLayout.test.ts.
test.skip(({ browserName }) => browserName !== 'chromium', 'CDP gesture input is Chromium-only')
test.use({ viewport: { width: 1280, height: 800 } })

const IMAGE_COUNT = 24

test.beforeEach(async ({ page }) => {
  await page.route('**/api/**', async route => {
    const url = route.request().url()
    if (url.includes('/api/media')) {
      const images = Array.from({ length: IMAGE_COUNT }, (_, i) => ({
        name: `img${i}`, path: `wall/img${i}.jpg`, width: 800, height: 600,
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

const firstItem = (page: Page) => page.locator('[aria-label^="View image"]').first()

async function gotoWall(page: Page) {
  await page.goto('/wall?mode=image')
  await expect(firstItem(page)).toBeVisible()
}

const columns = (page: Page) => page.evaluate(() => Number(localStorage.getItem('gallery-columns')))

// Number of items rendered in the first row (same top offset).
const renderedColumns = (page: Page) => page.evaluate(() => {
  const items = Array.from(document.querySelectorAll('[aria-label^="View image"]')) as HTMLElement[]
  if (!items.length) return 0
  const top0 = Math.round(items[0].getBoundingClientRect().top)
  return items.filter(e => Math.round(e.getBoundingClientRect().top) === top0).length
})

async function itemHeight(page: Page) {
  const box = await firstItem(page).boundingBox()
  return box?.height ?? 0
}

test('ctrl+wheel steps the column count (trackpad pinch)', async ({ page }) => {
  await gotoWall(page)
  const beforeCols = await columns(page)
  const beforeH = await itemHeight(page)

  const client = await page.context().newCDPSession(page)
  // modifiers bit 2 = Ctrl -> real wheel event with ctrlKey. Wheel up = zoom in.
  await client.send('Input.dispatchMouseEvent', { type: 'mouseWheel', x: 400, y: 400, deltaX: 0, deltaY: -250, modifiers: 2 })

  // zoom in => fewer columns => larger items
  await expect.poll(() => columns(page)).toBe(beforeCols - 1)
  await expect.poll(() => itemHeight(page)).toBeGreaterThan(beforeH)
  // the rendered layout matches the target exactly (maxColumns cap)
  expect(await renderedColumns(page)).toBe(beforeCols - 1)

  await page.waitForTimeout(300) // clear the step cooldown
  await client.send('Input.dispatchMouseEvent', { type: 'mouseWheel', x: 400, y: 400, deltaX: 0, deltaY: 250, modifiers: 2 })

  // zoom out => more columns again
  await expect.poll(() => columns(page)).toBe(beforeCols)
})

test('two-finger pinch-out enlarges the wall (fewer columns)', async ({ page }) => {
  await gotoWall(page)
  const beforeCols = await columns(page)
  const beforeH = await itemHeight(page)

  const client = await page.context().newCDPSession(page)
  await client.send('Emulation.setTouchEmulationEnabled', { enabled: true, maxTouchPoints: 2 })
  await client.send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [{ x: 350, y: 400 }, { x: 450, y: 400 }] })
  await client.send('Input.dispatchTouchEvent', { type: 'touchMove', touchPoints: [{ x: 250, y: 400 }, { x: 600, y: 400 }] })
  await client.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] })

  await expect.poll(() => columns(page)).toBeLessThan(beforeCols)
  await expect.poll(() => itemHeight(page)).toBeGreaterThan(beforeH)
})

test('gesture is disabled while the lightbox is open', async ({ page }) => {
  await gotoWall(page)
  await firstItem(page).click()
  await expect(page.locator('.yarl__root')).toBeVisible()

  const lockedCols = await columns(page)
  const client = await page.context().newCDPSession(page)
  await client.send('Input.dispatchMouseEvent', { type: 'mouseWheel', x: 400, y: 400, deltaX: 0, deltaY: -250, modifiers: 2 })

  await page.waitForTimeout(300)
  expect(await columns(page)).toBe(lockedCols)
})
