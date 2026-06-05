/// <reference lib="es2015.promise" />
import { expect, test, type Page } from '@playwright/test'

// Real multi-touch + modifier-wheel input is only drivable via Chrome DevTools
// Protocol, so these gesture e2e tests are Chromium-only. The pure gesture math
// is covered cross-engine by the unit tests in src/hooks/usePinchZoom.test.ts.
test.skip(({ browserName }) => browserName !== 'chromium', 'CDP gesture input is Chromium-only')

const IMAGE_COUNT = 16

test.beforeEach(async ({ page }) => {
  // Serve a populated image wall without needing the Go backend.
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
  // Thumbnails/originals 404 harmlessly; layout sizing comes from width/height.
  await page.route(/\/(thumbnail|file|poster|video)\//, route => route.abort())
})

const firstItem = (page: Page) => page.locator('[aria-label^="View image"]').first()

async function gotoWall(page: Page) {
  await page.goto('/wall?mode=image')
  await expect(firstItem(page)).toBeVisible()
}

function rowHeight(page: Page) {
  return page.evaluate(() => Number(localStorage.getItem('row-height')))
}

async function itemHeight(page: Page) {
  const box = await firstItem(page).boundingBox()
  return box?.height ?? 0
}

test('ctrl+wheel resizes the image wall (trackpad pinch)', async ({ page }) => {
  await gotoWall(page)

  const beforeRH = await rowHeight(page)
  const beforeH = await itemHeight(page)

  const client = await page.context().newCDPSession(page)
  // modifiers bit 2 = Ctrl -> dispatches a real wheel event with ctrlKey=true.
  // deltaY < 0 (wheel up) => zoom in => larger.
  await client.send('Input.dispatchMouseEvent', {
    type: 'mouseWheel', x: 400, y: 400, deltaX: 0, deltaY: -250, modifiers: 2,
  })

  await expect.poll(() => rowHeight(page)).toBeGreaterThan(beforeRH)
  await expect.poll(() => itemHeight(page)).toBeGreaterThan(beforeH)

  const afterInRH = await rowHeight(page)

  // Now zoom back out (wheel down) => smaller.
  await client.send('Input.dispatchMouseEvent', {
    type: 'mouseWheel', x: 400, y: 400, deltaX: 0, deltaY: 250, modifiers: 2,
  })

  await expect.poll(() => rowHeight(page)).toBeLessThan(afterInRH)
})

test('two-finger pinch-out enlarges the image wall', async ({ page }) => {
  await gotoWall(page)
  const beforeRH = await rowHeight(page)
  const beforeH = await itemHeight(page)

  const client = await page.context().newCDPSession(page)
  await client.send('Emulation.setTouchEmulationEnabled', { enabled: true, maxTouchPoints: 2 })

  // Baseline: two fingers 100px apart, then spread to 300px apart.
  await client.send('Input.dispatchTouchEvent', {
    type: 'touchStart', touchPoints: [{ x: 350, y: 400 }, { x: 450, y: 400 }],
  })
  await client.send('Input.dispatchTouchEvent', {
    type: 'touchMove', touchPoints: [{ x: 250, y: 400 }, { x: 550, y: 400 }],
  })
  await client.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] })

  await expect.poll(() => rowHeight(page)).toBeGreaterThan(beforeRH)
  await expect.poll(() => itemHeight(page)).toBeGreaterThan(beforeH)
})

test('gesture is disabled while the lightbox is open', async ({ page }) => {
  await gotoWall(page)

  // Open the lightbox by clicking an image (mode=image -> lightbox for images).
  await firstItem(page).click()
  await expect(page.locator('.yarl__root')).toBeVisible()

  const lockedRH = await rowHeight(page)

  const client = await page.context().newCDPSession(page)
  // ctrl+wheel while the lightbox owns zoom must NOT resize the wall behind it.
  await client.send('Input.dispatchMouseEvent', {
    type: 'mouseWheel', x: 400, y: 400, deltaX: 0, deltaY: -250, modifiers: 2,
  })

  // Give any (incorrectly attached) handler a chance to fire, then assert no change.
  await page.waitForTimeout(300)
  expect(await rowHeight(page)).toBe(lockedRH)
})
