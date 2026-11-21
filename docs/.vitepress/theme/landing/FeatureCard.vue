<script setup lang="ts">
import { withBase } from 'vitepress'

// A feature: a crop of a screenshot on a tinted background, a title and a short text (the slot).
// zoom is the screenshot's width relative to the card (CSS background-size, e.g. "190%"), focus the
// part that shows (CSS background-position, e.g. "72% 42%" or "center top").
const props = defineProps<{ title: string; shot: string; alt: string; zoom?: string; focus?: string }>()
const style = (appearance: string) => ({
  backgroundImage: `url(${withBase(`/screenshots/${props.shot}.${appearance}.png`)})`,
  backgroundSize: `${props.zoom ?? '100%'} auto`,
  backgroundPosition: props.focus ?? 'left top',
})
</script>

<template>
  <article class="feature-card">
    <div class="feature-card-media">
      <div class="feature-card-shot light-only" role="img" :aria-label="alt" :style="style('light')" />
      <div class="feature-card-shot dark-only" role="img" :aria-label="alt" :style="style('dark')" />
    </div>
    <div class="feature-card-body">
      <h3>{{ title }}</h3>
      <p><slot /></p>
    </div>
  </article>
</template>
