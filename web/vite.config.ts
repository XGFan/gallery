import {defineConfig} from 'vite'
import react from '@vitejs/plugin-react'

// https://vitejs.dev/config/
export default defineConfig({
  plugins: [react()],
  server: {
    port: 3000,
    host: true,
    proxy: {
      "/api": "http://127.0.0.1:8000/",
      "/file": "http://127.0.0.1:8000/",
      "/thumbnail": "http://127.0.0.1:8000/",
    }
  },
  build: {}

})
