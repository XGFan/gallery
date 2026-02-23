import { expect, test, type Locator, type Page } from '@playwright/test'

// Helper to check for video or fallback
async function expectVideoOrFallback(locator: Locator) {
  const video = locator.locator('video');
  const fallback = locator.getByTestId('video-fallback');
  await expect(video.or(fallback)).toBeVisible();
}

async function swipeUp(page: Page, slide: Locator) {
  const box = await slide.boundingBox();
  if (!box) throw new Error('Player not found');

  const startX = box.x + box.width / 2;
  const startY = box.y + box.height * 0.9;
  const endY = box.y + box.height * 0.1;

  await slide.dispatchEvent('pointerdown', {
    pointerType: 'touch',
    pointerId: 1,
    isPrimary: true,
    button: 0,
    buttons: 1,
    clientX: startX,
    clientY: startY
  });

  const steps = 18;
  for (let i = 1; i <= steps; i += 1) {
    const y = startY + ((endY - startY) * i) / steps;
    await slide.dispatchEvent('pointermove', {
      pointerType: 'touch',
      pointerId: 1,
      isPrimary: true,
      buttons: 1,
      clientX: startX,
      clientY: y
    });
  }

  await slide.dispatchEvent('pointerup', {
    pointerType: 'touch',
    pointerId: 1,
    isPrimary: true,
    button: 0,
    clientX: startX,
    clientY: endY
  });

  await page.mouse.move(startX, startY);
  await page.mouse.down();
  await page.mouse.move(startX, endY, { steps: 24 });
  await page.mouse.up();
}

const BACKEND_IMAGES = [
  {
    path: "image1.jpg",
    name: "Image 1",
    width: 1080,
    height: 1920
  }
];

const BACKEND_DIRECTORIES = [
  {
    path: "folder1",
    name: "Folder 1",
    cover: {
      path: "folder1/cover.jpg",
      name: "Cover",
      width: 1080,
      height: 1920
    }
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

    // Mock API response for mode=explore
    await page.route('**/api/explore/**', async route => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          directories: BACKEND_DIRECTORIES,
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

  test('opens lightbox from image mode when clicking image', async ({ page }) => {
    // Go to image mode
    await page.goto('/?mode=image');
    
    // Wait for gallery to load
    await expect(page.getByAltText('Image 1')).toBeVisible();

    // Click the image item
    await page.getByAltText('Image 1').click();

    // Lightbox should open
    await expect(page.locator('.yarl__container')).toBeVisible();
    await expect(page.getByTestId('vertical-player')).toHaveCount(0);
  });

  test('enters vertical player from image mode when clicking video', async ({ page }) => {
    // Go to image mode
    await page.goto('/?mode=image');
    
    // Wait for gallery to load
    await expect(page.getByAltText('Video 1')).toBeVisible();

    // Click the video item
    await page.getByAltText('Video 1').click();

    // Vertical Player should open
    const player = page.getByTestId('vertical-player');
    await expect(player).toBeVisible();

    // Verify video is shown (or fallback)
    await expectVideoOrFallback(player);
    
    // Close player
    await page.locator('button:has-text("Close"), button:has(.lucide-x)').click(); // Assuming X icon is inside a button
    await expect(player).not.toBeVisible();
  });

  test('enters vertical player from explore mode when clicking video', async ({ page }) => {
    await page.goto('/?mode=explore');

    await expect(page.getByAltText('Video 1')).toBeVisible();
    await page.getByAltText('Video 1').click();

    const player = page.getByTestId('vertical-player');
    await expect(player).toBeVisible();
    await expectVideoOrFallback(player);
  });

  test('swipes between items', async ({ page }) => {
    await page.goto('/?mode=image');
    // Click Video 1
    await page.getByAltText('Video 1').click();
    
    const player = page.getByTestId('vertical-player');
    await expect(player).toBeVisible();

    // Swipe Up (Next) -> Should go to Video 2
    await swipeUp(page, page.getByTestId('slide-1'));

    // Check if next item is visible
    await expect(page.getByTestId('slide-2')).toBeVisible();
    await expectVideoOrFallback(page.getByTestId('slide-2'));
  });

  test('scrolls/wheels between items', async ({ page }) => {
    await page.goto('/?mode=image');
    // Click Video 1
    await page.getByAltText('Video 1').click();
    
    const player = page.getByTestId('vertical-player');
    await expect(player).toBeVisible();

    // Wheel Scroll Down (deltaY > 0) -> Next Item -> Video 2
    await page.mouse.wheel(0, 100);

    // Wait for transition/debounce
    await expect(page.getByTestId('slide-2')).toBeVisible();
    await expectVideoOrFallback(page.getByTestId('slide-2'));

    // Wheel Scroll Up (deltaY < 0) -> Previous Item -> Video 1
    await page.mouse.wheel(0, -100);
    
    await expect(page.getByTestId('slide-1')).toBeVisible();
    await expectVideoOrFallback(page.getByTestId('slide-1'));
  });

  test('mixed mode behavior (default on)', async ({ page }) => {
      // Default is mixed mode ON. Sequence: Image1, Video1, Video2
      await page.goto('/?mode=image');
      await page.getByAltText('Video 1').click();
      
      // Initial: Video 1
      await expectVideoOrFallback(page.getByTestId('slide-1'));

      // Next: Video 2
      await swipeUp(page, page.getByTestId('slide-1'));
      
      await expectVideoOrFallback(page.getByTestId('slide-2'));
  });

  test('locks body scroll when open and restores when closed', async ({ page }) => {
    await page.goto('/?mode=image');
    // Ensure body is scrollable initially (or at least overflow is not hidden)
    await page.evaluate(() => document.body.style.overflow = 'auto');
    
    // Open player
    await page.getByAltText('Video 1').click();
    const player = page.getByTestId('vertical-player');
    await expect(player).toBeVisible();

    // Check overflow is hidden
    const overflow = await page.evaluate(() => document.body.style.overflow);
    expect(overflow).toBe('hidden');

    // Close player
    await page.locator('button:has-text("Close"), button:has(.lucide-x)').click();
    await expect(player).not.toBeVisible();

    // Check overflow is restored (empty string or whatever it was)
    const restoredOverflow = await page.evaluate(() => document.body.style.overflow);
    expect(restoredOverflow).not.toBe('hidden');
  });

  test('shows fallback when video fails to load', async ({ page }) => {
    // Override the video route for Video 1 to fail
    await page.route('**/video1.mp4', route => route.abort());

    await page.goto('/?mode=image');
    await page.getByAltText('Video 1').click();

    const player = page.getByTestId('vertical-player');
    await expect(player).toBeVisible();

    // Expect fallback to be visible
    const fallback = page.getByTestId('video-fallback');
    await expect(fallback).toBeVisible();
    await expect(fallback).toContainText('视频加载失败');
  });
});
