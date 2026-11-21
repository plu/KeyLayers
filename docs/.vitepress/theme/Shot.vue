<script setup lang="ts">
import { withBase } from 'vitepress'

// A screenshot in light and dark: docs/public/screenshots/<name>.light.png and .dark.png.
// The page shows the one that matches the site's appearance. (Raw <img> paths don't get the base
// path, so withBase adds /KeyLayers/.)
const props = defineProps<{ name: string; alt: string }>()
const src = (appearance: string) => withBase(`/screenshots/${props.name}.${appearance}.png`)
</script>

<template>
  <span class="shot">
    <img class="light-only" :src="src('light')" :alt="alt" loading="lazy" />
    <img class="dark-only" :src="src('dark')" :alt="alt" loading="lazy" />
  </span>
</template>
