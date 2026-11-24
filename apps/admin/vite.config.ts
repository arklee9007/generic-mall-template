import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'

export default defineConfig({
  plugins: [vue()],
  base: './',
  build: { outDir: process.env.GENERIC_ADMIN_OUT_DIR || 'dist' }
})
