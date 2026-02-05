/// <reference lib="es2015.promise" />
import { expect, test } from '@playwright/test'

test.beforeEach(async ({ page }) => {
  // Mock all API requests to debug and ensure coverage
  await page.route('**/api/**', async route => {
    const url = route.request().url();
    // /api/album returns an array of directories
    if (url.includes('/api/album')) {
        await route.fulfill({
            contentType: 'application/json',
            body: JSON.stringify([])
        });
    } else {
        // /api/media and /api/explore return a directory object
        await route.fulfill({
            contentType: 'application/json',
            body: JSON.stringify({ images: [], videos: [], directories: [] })
        });
    }
  })
})

test.use({ viewport: { width: 375, height: 667 } })

test('toggles mixed mode in shuffle settings', async ({ page }) => {
  await page.goto('/')

  // Wait for the app to load
  await expect(page.locator('header')).toBeVisible()

  // Open sidebar if not open
  const openSidebarBtn = page.getByLabel('Open Sidebar')
  if (await openSidebarBtn.isVisible()) {
      await openSidebarBtn.click()
  }

  // Open Shuffle Settings from Sidebar
  // Sidebar animation might take time
  const settingsBtn = page.getByLabel('Shuffle Settings')
  await expect(settingsBtn).toBeVisible()
  await settingsBtn.click()

  // Check Modal Title
  await expect(page.getByText('Shuffle Mode')).toBeVisible()

  // Check for Mixed Mode buttons
  const mixedBtn = page.getByTestId('mixed-mode-mixed')
  const isolatedBtn = page.getByTestId('mixed-mode-isolated')
  
  // Verify default state (Mixed is active)
  await expect(mixedBtn).toBeVisible()
  await expect(mixedBtn).toHaveAttribute('aria-pressed', 'true')
  await expect(isolatedBtn).toHaveAttribute('aria-pressed', 'false')

  // Switch to Isolated
  await isolatedBtn.click()
  await expect(mixedBtn).toHaveAttribute('aria-pressed', 'false')
  await expect(isolatedBtn).toHaveAttribute('aria-pressed', 'true')

  // Reload to verify persistence
  await page.reload()
  
  // Re-open settings
  if (await openSidebarBtn.isVisible()) {
      await openSidebarBtn.click()
  }
  await expect(settingsBtn).toBeVisible()
  await settingsBtn.click()
  
  // Should still be Isolated
  await expect(isolatedBtn).toBeVisible()
  await expect(isolatedBtn).toHaveAttribute('aria-pressed', 'true')
})
