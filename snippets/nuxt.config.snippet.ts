// Nuxt 3. Also add `COPY --from=version /VERSION ./VERSION` to the BUILDER
// stage as well as the runtime stage — nuxt.config runs at build time and
// needs to read the file.

import { readFileSync } from 'node:fs'

const raw = process.env.APP_VERSION ?? (() => {
  try { return readFileSync('VERSION', 'utf-8') } catch { return 'dev unknown' }
})()
const [version, commit] = raw.trim().split(/\s+/)

export default defineNuxtConfig({
  runtimeConfig: {
    public: { version, commit },
  },
})
