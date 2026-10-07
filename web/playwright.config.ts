import { defineConfig } from '@playwright/test'

const desktop = { viewport: { width: 1440, height: 900 } }
const mobile = { viewport: { width: 430, height: 932 }, deviceScaleFactor: 3, isMobile: true, hasTouch: true }

export default defineConfig({
  testDir: './tests',
  timeout: 30000,
  projects: [
    { name: 'chromium-desktop', use: { browserName: 'chromium', ...desktop } },
    { name: 'chromium-mobile', use: { browserName: 'chromium', ...mobile } },
    { name: 'webkit-desktop', use: { browserName: 'webkit', ...desktop } },
    { name: 'webkit-mobile', use: { browserName: 'webkit', ...mobile } }
  ],
  use: {
    baseURL: 'http://localhost:5173'
  },
  webServer: {
    command: 'npm run dev -- --port 5173',
    url: 'http://localhost:5173',
    reuseExistingServer: false,
    timeout: 120000
  }
})
