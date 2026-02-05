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
    baseURL: 'http://localhost:3000'
  },
  webServer: {
    command: 'npm run dev -- --host',
    url: 'http://localhost:3000',
    reuseExistingServer: true,
    timeout: 120000
  }
})
