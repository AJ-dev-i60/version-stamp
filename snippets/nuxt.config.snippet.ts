// Nuxt 3. nuxt.config runs during the BUILD stage, not the runtime stage, so it
// cannot read the VERSION file the runtime stage writes. Give the build stage
// the value directly instead — in that stage of the Dockerfile:
//
//   ARG APP_VERSION="dev unknown"
//   ENV APP_VERSION=$APP_VERSION
//
// The readFileSync fallback covers the optional in-build git stage, where a
// VERSION file does sit next to the working directory.

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
