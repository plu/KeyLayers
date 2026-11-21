<script setup lang="ts">
import { computed } from 'vue'
import { withBase } from 'vitepress'

// A screenshot in light and dark: docs/public/screenshots/<name>.light.png and .dark.png.
// The page shows the one that matches the site's appearance. (Raw <img> paths don't get the base
// path, so withBase adds /KeyLayers/.)
//
// The app screenshots come from the snapshot tests, which render a window's contents without its
// frame, so they get one here: app/status-* (a part of the window) a rounded border, every other
// app/* shot a window with a title bar. System Settings shots already show their window.
const props = defineProps<{ name: string; alt: string }>()
const src = (appearance: string) => withBase(`/screenshots/${props.name}.${appearance}.png`)
const frame = computed(() =>
  props.name.startsWith('app/status') ? 'panel' : props.name.startsWith('app/') ? 'window' : 'none',
)
</script>

<template>
  <span class="shot" :class="`shot-${frame}`">
    <span v-if="frame === 'window'" class="shot-titlebar" aria-hidden="true">
      <span class="shot-light shot-close" />
      <span class="shot-light shot-minimize" />
      <span class="shot-light shot-zoom" />
    </span>
    <img class="light-only" :src="src('light')" :alt="alt" loading="lazy" />
    <img class="dark-only" :src="src('dark')" :alt="alt" loading="lazy" />
  </span>
</template>
