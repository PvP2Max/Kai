import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

export default defineConfig({
  plugins: [react()],
  server: {
    port: 5173,
    host: true,
    allowedHosts: ['kai.pvp2max.com', 'localhost'],
    proxy: {
      '/api': {
        target: 'http://kai-backend:8000',
        changeOrigin: true,
      },
    },
  },
})
