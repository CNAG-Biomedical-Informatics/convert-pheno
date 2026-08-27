import { defineConfig } from '@playwright/test'

export default defineConfig({
  testDir: './e2e',
  timeout: 60_000,
  use: {
    baseURL: 'http://127.0.0.1:45317',
    launchOptions: process.env.PLAYWRIGHT_CHROMIUM_PATH
      ? { executablePath: process.env.PLAYWRIGHT_CHROMIUM_PATH }
      : {},
  },
  webServer: [
    {
      command: 'morbo -l http://127.0.0.1:44317 ../api/perl/main.pl',
      port: 44317,
      reuseExistingServer: false,
      timeout: 30_000,
    },
    {
      command: 'npm run dev -- --mode e2e --port 45317',
      port: 45317,
      reuseExistingServer: false,
      timeout: 30_000,
    },
  ],
})
