<!-- Server-rendered pages (Nuxt shown; the idea ports anywhere). Put it in
     the layout, muted and small. -->

<script setup>
const { public: { version, commit } } = useRuntimeConfig()
</script>

<template>
  <span class="build-version">
    {{ version }}<template v-if="commit && commit !== 'unknown'"> · {{ commit }}</template>
  </span>
</template>

<style scoped>
.build-version {
  font-size: 0.75rem;
  opacity: 0.6;
  font-variant-numeric: tabular-nums;
}
</style>
