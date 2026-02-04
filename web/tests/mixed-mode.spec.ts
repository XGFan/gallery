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

  // Check for Mixed Mode toggle
  const toggle = page.getByTestId('mixed-mode-toggle')
  
  // Verify default state (checked)
  await expect(toggle).toBeVisible()
  // Check using aria-checked
  await expect(toggle).toHaveAttribute('aria-checked', 'true')

  // Toggle it off
  await toggle.click()
  await expect(toggle).toHaveAttribute('aria-checked', 'false')

  // Reload to verify persistence
  await page.reload()
  
  // Re-open settings
  if (await openSidebarBtn.isVisible()) {
      await openSidebarBtn.click()
  }
  await expect(settingsBtn).toBeVisible()
  await settingsBtn.click()
  
  // Should still be unchecked
  await expect(toggle).toBeVisible()
  await expect(toggle).toHaveAttribute('aria-checked', 'false')
})
