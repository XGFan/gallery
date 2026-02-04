/// <reference lib="es2015.promise" />
import { expect, test } from '@playwright/test'

const posterPixel = Uint8Array.from(
  atob('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO5j3QAAAABJRU5ErkJggg=='),
  c => c.charCodeAt(0)
)

test('renders video card from media response', async ({ page }) => {
  await page.route(/\/api\/media\/?$/, async route => {
    await route.fulfill({
      contentType: 'application/json',
      body: JSON.stringify({
        images: [],
        videos: [
          {
            name: 'clip',
            path: 'videos/clip.mp4',
            width: 640,
            height: 360,
            duration_sec: 65.4
          }
        ]
      })
    })
  })

  await page.route(/\/poster\/.+/, async route => {
    await route.fulfill({
      status: 200,
      headers: {
        'Content-Type': 'image/png'
      },
      body: posterPixel
    })
  })

  await page.goto('/?mode=image')

  const videoCard = page.getByTestId('gallery-video-item')
  await expect(videoCard).toHaveCount(1)
  await expect(videoCard).toBeVisible()
  await expect(videoCard.getByText('1:05')).toBeVisible()
})

test('renders disabled video card', async ({ page }) => {
  await page.route(/\/api\/media\/?$/, async route => {
    await route.fulfill({
      contentType: 'application/json',
      body: JSON.stringify({
        images: [],
        videos: [
          {
            name: 'bad_clip',
            path: 'videos/bad.mp4',
            width: 640,
            height: 360,
            duration_sec: 0
          }
        ]
      })
    })
  })

  // Mock document.createElement to return false for canPlayType
  await page.addInitScript(() => {
    const original = document.createElement.bind(document);
    document.createElement = ((...args: Parameters<typeof document.createElement>) => {
      const element = original(...args);
      if (args[0] === 'video' && element instanceof HTMLVideoElement) {
        element.canPlayType = () => '';
      }
      return element;
    }) as typeof document.createElement;
  });

  await page.goto('/?mode=image')

  const videoCard = page.getByTestId('gallery-video-item')
  await expect(videoCard).toHaveCount(1)
  await expect(videoCard).toHaveClass(/cursor-not-allowed/)
  await expect(videoCard).toHaveClass(/opacity-60/)
})
