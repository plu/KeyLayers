<script setup lang="ts">
// A landing page section: small label, heading, and whatever goes in the slot. "narrow" keeps prose to
// a readable line length; "tinted" puts the section on a soft panel.
defineProps<{ eyebrow: string; title: string; narrow?: boolean; tinted?: boolean }>()
</script>

<template>
  <section class="landing-section" :class="{ 'landing-section-tinted': tinted }">
    <p class="landing-eyebrow landing-center">{{ eyebrow }}</p>
    <h2 class="landing-heading landing-center">{{ title }}</h2>
    <div :class="{ 'landing-narrow': narrow }">
      <slot />
    </div>
  </section>
</template>
