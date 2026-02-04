import {defineConfig} from 'vite'
import react from '@vitejs/plugin-react'
import fs from 'node:fs'
import path from 'node:path'

const getProxyConfig = () => {
  const target = process.env.PROXY_TARGET || 'local'
  const configPath = path.resolve(process.cwd(), 'config', `proxy.${target}.json`)

  console.log(`Loading proxy config: ${target}`)

  try {
    if (fs.existsSync(configPath)) {
      const content = fs.readFileSync(configPath, 'utf-8')
      return JSON.parse(content)
    } else {
      console.warn(`Proxy config file not found: ${configPath}. Falling back to local.`)
    }
  } catch (error) {
    console.warn(`Failed to load or parse proxy config at ${configPath}: ${error}. Falling back to local.`)
  }

  if (target !== 'local') {
    const localConfigPath = path.resolve(process.cwd(), 'config', 'proxy.local.json')
    try {
      if (fs.existsSync(localConfigPath)) {
        return JSON.parse(fs.readFileSync(localConfigPath, 'utf-8'))
      }
    } catch (e) {
      console.warn(`Failed to load fallback local proxy config: ${e}`)
    }
  }

  return {
    "/api": "http://127.0.0.1:8000/",
    "/file": "http://127.0.0.1:8000/",
    "/thumbnail": "http://127.0.0.1:8000/",
    "/video": "http://127.0.0.1:8000/",
    "/poster": "http://127.0.0.1:8000/",
  }
}

// https://vitejs.dev/config/
export default defineConfig({
  plugins: [react()],
  server: {
    port: 3000,
    host: true,
    proxy: getProxyConfig()
  },
  build: {}

})
