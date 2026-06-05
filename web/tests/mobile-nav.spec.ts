import { expect, test } from '@playwright/test'

// Mobile navigation redesign: on a phone-width viewport the top bar carries only
// navigation (drawer + path title), mode switching moves to a bottom tab bar,
// and the breadcrumb becomes a vertical Path Sheet — so there is never any
// horizontal scrolling and the two jobs no longer fight for the top axis.

test.use({ viewport: { width: 390, height: 844 } })

const DEEP = 'holiday/2024/summer'

test.beforeEach(async ({ page }) => {
  await page.route('**/api/**', async route => {
    const url = route.request().url()
    if (url.includes('/api/media')) {
      const images = [
        // Enough images that the wall is taller than the viewport (scrollable).
        ...Array.from({ length: 30 }, (_, i) => ({
          name: `img${i}`,
          path: `${DEEP}/img${i}.jpg`,
          width: 800,
          height: 600,
        })),
        // A grandchild keeps isLeaf=false so all four modes are offered.
        { name: 'deep', path: `${DEEP}/extra/deep.jpg`, width: 800, height: 600 },
      ]
      await route.fulfill({ contentType: 'application/json', body: JSON.stringify({ images, videos: [] }) })
    } else if (url.includes('/api/album')) {
      // A real ancestor has subfolders, so album mode stays album (not a leaf).
      await route.fulfill({
        contentType: 'application/json',
        body: JSON.stringify([
          { name: '2024', path: 'holiday/2024', cover: { name: 'c', path: 'holiday/2024/c.jpg', width: 100, height: 100 } },
        ]),
      })
    } else if (url.includes('/api/explore')) {
      // A subdirectory keeps explore non-leaf, so selecting Explore stays in
      // explore mode rather than auto-redirecting to photos on an empty folder.
      await route.fulfill({
        contentType: 'application/json',
        body: JSON.stringify({
          images: [],
          videos: [],
          directories: [{ name: 'sub', path: `${DEEP}/sub`, cover: { name: 'c', path: `${DEEP}/sub/c.jpg`, width: 100, height: 100 } }],
        }),
      })
    } else {
      await route.fulfill({ contentType: 'application/json', body: JSON.stringify({}) })
    }
  })
  await page.route(/\/(thumbnail|file|poster|video)\//, route => route.abort())
})

test('mode switching lives in a bottom tab bar, not the top bar', async ({ page }) => {
  await page.goto(`/${DEEP}?mode=image`)

  const title = page.getByRole('button', { name: 'Show path' })
  await expect(title).toBeVisible()
  await expect(title).toContainText('summer')

  // The top bar holds no mode switcher any more...
  await expect(page.getByRole('banner').getByRole('button', { name: 'Explore' })).toHaveCount(0)

  // ...mode switching is a single-tap bottom tab bar.
  const tabbar = page.getByRole('navigation', { name: 'View mode' })
  await expect(tabbar).toBeVisible()
  await tabbar.getByRole('button', { name: 'Explore' }).click()

  await expect(page).toHaveURL(/mode=explore/)
})

test('tapping the title opens a vertical Path Sheet that jumps to an ancestor', async ({ page }) => {
  await page.goto(`/${DEEP}?mode=image`)

  await page.getByRole('button', { name: 'Show path' }).click()

  const sheet = page.getByRole('dialog', { name: 'Path navigation' })
  await expect(sheet).toBeVisible()
  await expect(sheet.getByRole('button', { name: 'Home' })).toBeVisible()
  await expect(sheet.getByRole('button', { name: 'summer' })).toHaveAttribute('aria-current', 'page')

  await sheet.getByRole('button', { name: 'holiday' }).click()

  await expect(page).toHaveURL(/\/holiday\?mode=album/)
})

test('no horizontal scrollbar on a phone viewport', async ({ page }) => {
  await page.goto(`/${DEEP}?mode=image`)
  await expect(page.getByRole('button', { name: 'Show path' })).toBeVisible()

  const metrics = await page.evaluate(() => {
    const doc = document.documentElement
    return { scrollWidth: doc.scrollWidth, clientWidth: doc.clientWidth }
  })

  expect(metrics.scrollWidth).toBeLessThanOrEqual(metrics.clientWidth)
})

test('the counter and the bottom tab bar are mutually exclusive across scroll', async ({ page }) => {
  await page.goto(`/${DEEP}?mode=image`)
  const tabbar = page.getByRole('navigation', { name: 'View mode' })
  const counter = page.getByRole('button', { name: 'Open settings' })
  const counterOpacity = () => counter.evaluate(el => getComputedStyle(el).opacity)
  await expect(tabbar).toBeVisible()

  // At the top: nav reachable, counter hidden.
  await expect(tabbar).toBeInViewport()
  expect(await counterOpacity()).toBe('0')

  // Scroll down → counter (loading progress) appears, nav slides away.
  await page.mouse.move(195, 420)
  await page.mouse.wheel(0, 500)
  await expect(tabbar).not.toBeInViewport()
  await expect.poll(counterOpacity).toBe('1')

  // Idle in the content → both hidden (clean wall).
  await page.waitForTimeout(1800)
  await expect(tabbar).not.toBeInViewport()
  await expect.poll(counterOpacity).toBe('0')

  // Scroll up → nav returns, counter stays hidden.
  await page.mouse.wheel(0, -300)
  await expect(tabbar).toBeInViewport()
  expect(await counterOpacity()).toBe('0')
})
