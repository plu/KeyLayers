<script setup lang="ts">
// "And the small things": short facts, two columns. Each icon is an inline SVG path (24x24, stroked).
const things = [
  {
    title: 'Emergency stop.',
    text: 'Left Control + Left Option + Left Command + Escape pauses remapping from anywhere.',
    icon: 'M6 6h12v12H6z',
  },
  {
    title: 'Lock a layer.',
    text: 'Double-tap a layer key to stay on it. The menu bar and a short overlay show where you are.',
    icon: 'M7 11V8a5 5 0 0 1 10 0v3M5 11h14v10H5z',
  },
  {
    title: 'Every Apple layout.',
    text: 'The MacBook keyboard and the Magic Keyboard, in ANSI, ISO and JIS.',
    icon: 'M3 7h18v10H3zM7 11h.01M11 11h.01M15 11h.01M8 14h8',
  },
  {
    title: 'Several keymaps.',
    text: 'One for coding, one for writing. Switch with a key.',
    icon: 'M4 6h16M4 12h16M4 18h10',
  },
  {
    title: 'Import and export.',
    text: 'Your keymaps are one file. Take them to your next Mac.',
    icon: 'M12 3v12m0 0-4-4m4 4 4-4M5 21h14',
  },
  {
    title: 'Updates itself.',
    text: 'Signed, notarized updates. Your setup and permissions stay.',
    icon: 'M20 12a8 8 0 1 1-2.3-5.7M20 4v4h-4',
  },
]
</script>

<template>
  <ul class="small-things">
    <li v-for="thing in things" :key="thing.title">
      <svg viewBox="0 0 24 24" aria-hidden="true"><path :d="thing.icon" /></svg>
      <p><strong>{{ thing.title }}</strong> {{ thing.text }}</p>
    </li>
  </ul>
</template>
