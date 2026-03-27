import { defineConfig } from '@playwright/test'

export default defineConfig({
  testDir: './tests',
  timeout: 30000,
  projects: [
    {
      name: 'chromium',
      use: { browserName: 'chromium' }
    },
    {
      name: 'webkit',
      // Enable touch so drag gestures behave Safari-like
      use: { browserName: 'webkit', hasTouch: true }
    }
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
