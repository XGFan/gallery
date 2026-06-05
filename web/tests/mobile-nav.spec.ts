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
        ...Array.from({ length: 6 }, (_, i) => ({
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
      await route.fulfill({ contentType: 'application/json', body: JSON.stringify({ images: [], videos: [], directories: [] }) })
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
