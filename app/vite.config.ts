import { defineConfig } from 'vitest/config'
import { loadEnv } from 'vite'
import react from '@vitejs/plugin-react'

export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, process.cwd(), '')
  const apiTarget = mode === 'e2e'
    ? 'http://127.0.0.1:44317'
    : process.env.VITE_API_TARGET || env.VITE_API_TARGET || 'http://127.0.0.1:3000'
  return {
    plugins: [react()],
    server: {
      host: '127.0.0.1',
      proxy: { '/api': apiTarget, '/examples': apiTarget },
    },
    test: {
      environment: 'jsdom',
      setupFiles: './src/test/setup.ts',
      css: true,
      include: ['src/**/*.test.{ts,tsx}'],
    },
  }
})
