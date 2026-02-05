import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const __dirname = path.dirname(fileURLToPath(import.meta.url))

// https://vitejs.dev/config/
export default defineConfig(({ mode }) => {
  const proxyPath = path.resolve(
    __dirname,
    `config/proxy.${mode === 'remote' ? 'remote' : 'local'}.json`
  )
  const proxy = JSON.parse(fs.readFileSync(proxyPath, 'utf-8'))

  return {
    plugins: [react()],
    server: {
      port: 3000,
      host: true,
      proxy
    },
    build: {}
  }
})
