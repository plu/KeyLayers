<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
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
// The screenshots are 2x: shown wider than half their pixel width, the browser stretches them and
// they blur. Each image caps itself at its natural size in points once it has loaded.
const maxWidth = ref<string>()
const cap = (image: HTMLImageElement) => {
  if (image.naturalWidth > 0) maxWidth.value = `${image.naturalWidth / 2}px`
}
const loaded = (event: Event) => cap(event.target as HTMLImageElement)
// An image that loaded before the page became interactive fired its load event too early.
const root = ref<HTMLElement>()
onMounted(() => root.value?.querySelectorAll('img').forEach((image) => image.complete && cap(image)))
const frame = computed(() =>
  props.name.startsWith('app/status') ? 'panel' : props.name.startsWith('app/') ? 'window' : 'none',
)
</script>

<template>
  <span ref="root" class="shot" :class="`shot-${frame}`" :style="{ maxWidth: maxWidth ? `min(100%, ${maxWidth})` : undefined }">
    <span v-if="frame === 'window'" class="shot-titlebar" aria-hidden="true">
      <span class="shot-light shot-close" />
      <span class="shot-light shot-minimize" />
      <span class="shot-light shot-zoom" />
    </span>
    <img class="light-only" :src="src('light')" :alt="alt" loading="lazy" @load="loaded" />
    <img class="dark-only" :src="src('dark')" :alt="alt" loading="lazy" @load="loaded" />
  </span>
</template>
