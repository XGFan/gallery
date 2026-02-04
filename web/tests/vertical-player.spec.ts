import { expect, test } from '@playwright/test'
import { ImgData } from '../src/dto'

const BACKEND_IMAGES = [
  {
    path: "image1.jpg",
    name: "Image 1",
    width: 1080,
    height: 1920
  }
];

const BACKEND_VIDEOS = [
  {
    path: "video1.mp4",
    name: "Video 1",
    width: 1080,
    height: 1920,
    duration_sec: 10
  },
  {
    path: "video2.mp4",
    name: "Video 2",
    width: 1080,
    height: 1920,
    duration_sec: 15
  }
];

test.describe('VerticalPlayer Integration', () => {
  test.beforeEach(async ({ page }) => {
    // Mock API response for mode=image
    await page.route('**/api/media/**', async route => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          images: BACKEND_IMAGES,
          videos: BACKEND_VIDEOS
        })
      });
    });

    // Mock API tree response to prevent proxy errors
    await page.route('**/api/tree', async route => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: '{}'
      });
    });

    // Mock static files to avoid 404s
    await page.route('**/poster/**', async route => {
      await route.fulfill({ status: 200, contentType: 'image/jpeg', body: Buffer.from([0]) });
    });
    await page.route('**/file/**', async route => {
      await route.fulfill({ status: 200, contentType: 'image/jpeg', body: Buffer.from([0]) });
    });
    await page.route('**/video/**', async route => {
        // Return a minimal valid MP4 or just 200 OK empty
        await route.fulfill({ status: 200, contentType: 'video/mp4', body: Buffer.from([0]) });
    });

    // Mock video playback
    await page.addInitScript(() => {
      Object.defineProperty(HTMLMediaElement.prototype, 'play', {
        configurable: true,
        value: async function() { return Promise.resolve(); }
      });
      Object.defineProperty(HTMLMediaElement.prototype, 'pause', {
        configurable: true,
        value: function() { }
      });
      // Mock muted property
      let _muted = false;
      Object.defineProperty(HTMLMediaElement.prototype, 'muted', {
        get: () => _muted,
        set: (v) => { _muted = v; }
      });
    });
  });

  test('enters vertical player from image mode', async ({ page }) => {
    // Go to image mode
    await page.goto('/?mode=image');
    
    // Wait for gallery to load
    await expect(page.getByAltText('Image 1')).toBeVisible();

    // Click the first item (Image 1) - Index 0
    await page.getByAltText('Image 1').click();

    // Vertical Player should open
    const player = page.getByTestId('vertical-player');
    await expect(player).toBeVisible();

    // Verify first item is shown (Image 1 is index 0)
    await expect(page.getByTestId('slide-0').locator('img')).toBeVisible();
    
    // Close player
    await page.locator('button:has-text("Close"), button:has(.lucide-x)').click(); // Assuming X icon is inside a button
    await expect(player).not.toBeVisible();
  });

  test('swipes between items', async ({ page }) => {
    await page.goto('/?mode=image');
    // Click Image 1 (Index 0)
    await page.getByAltText('Image 1').click();
    
    const player = page.getByTestId('vertical-player');
    await expect(player).toBeVisible();

    const box = await player.boundingBox();
    if (!box) throw new Error('Player not found');

    const startX = box.x + box.width / 2;
    const startY = box.y + box.height * 0.8;
    const endY = box.y + box.height * 0.2;

    // Swipe Up (Next) -> Should go to Video 1 (Index 1)
    await page.mouse.move(startX, startY);
    await page.mouse.down();
    await page.mouse.move(startX, endY, { steps: 5 });
    await page.mouse.up();

    // Check if next item is visible (slide-1 which is Video 1)
    await expect(page.getByTestId('slide-1')).toBeVisible();
    await expect(page.getByTestId('slide-1').locator('video')).toBeVisible();
  });

  test('scrolls/wheels between items', async ({ page }) => {
    await page.goto('/?mode=image');
    // Click Image 1 (Index 0)
    await page.getByAltText('Image 1').click();
    
    const player = page.getByTestId('vertical-player');
    await expect(player).toBeVisible();

    // Wheel Scroll Down (deltaY > 0) -> Next Item -> Video 1 (Index 1)
    await page.mouse.wheel(0, 100);

    // Wait for transition/debounce
    await expect(page.getByTestId('slide-1')).toBeVisible();
    await expect(page.getByTestId('slide-1').locator('video')).toBeVisible();

    // Wheel Scroll Up (deltaY < 0) -> Previous Item -> Image 1 (Index 0)
    await page.mouse.wheel(0, -100);
    
    await expect(page.getByTestId('slide-0')).toBeVisible();
    await expect(page.getByTestId('slide-0').locator('img')).toBeVisible();
  });

  test('mixed mode behavior (default on)', async ({ page }) => {
      // Default is mixed mode ON. Sequence: Image1, Video1, Video2
      await page.goto('/?mode=image');
      await page.getByAltText('Image 1').click();
      
      const player = page.getByTestId('vertical-player');
      
      // Initial: Image 1
      await expect(page.getByTestId('slide-0').locator('img')).toBeVisible();

      // Next: Video 1
      const box = await player.boundingBox();
      if (!box) throw new Error('Player not found');
      const startX = box.x + box.width / 2;
      const startY = box.y + box.height * 0.8;
      const endY = box.y + box.height * 0.2;

      await page.mouse.move(startX, startY);
      await page.mouse.down();
      await page.mouse.move(startX, endY, { steps: 5 });
      await page.mouse.up();

      await expect(page.getByTestId('slide-1').locator('video')).toBeVisible();
  });
});
