<script setup lang="ts">
import { withBase } from 'vitepress'
import { downloadURL } from '../../links'
import { data as release } from './release.data'
import Shot from '../Shot.vue'
</script>

<template>
  <section class="landing-hero">
    <div class="landing-hero-text">
      <p class="landing-eyebrow">Keyboard layers for macOS</p>
      <h1 class="landing-title">
        Hold a key.<br />
        <span class="landing-accent">Get a whole new keyboard.</span>
      </h1>
      <p class="landing-lead">
        Arrows on H J K L, Home and End under your fingers, media keys where you want them. On the
        built-in MacBook keyboard and on every other one.
      </p>
      <div class="landing-actions">
        <a class="landing-button landing-button-brand" :href="downloadURL">
          Download KeyLayers<span v-if="release.version" class="landing-version">v{{ release.version }}</span>
        </a>
        <a class="landing-button landing-button-setup" :href="withBase('/guide/setup')">Setup guide</a>
        <a class="landing-button landing-button-alt" href="https://github.com/plu/KeyLayers">View on GitHub</a>
      </div>
      <p class="landing-note landing-note-setup">
        <strong>Not just download and run:</strong> macOS needs three approvals before KeyLayers can remap,
        one of them added by hand. <a :href="withBase('/guide/setup')">The setup guide</a> walks you through it.
      </p>
      <p class="landing-note">Free and open source (MIT) · macOS 26 (Tahoe) or later</p>
    </div>
    <img class="landing-icon" :src="withBase('/icon.png')" alt="" width="256" height="256" />
  </section>

  <section class="landing-showcase">
    <Shot name="app/keyboard-mod" alt="KeyLayers showing the Mod layer: arrows on H J K L, Home, End and page keys, media keys on the top row" />
    <div class="landing-showcase-caption">
      <strong>Hold fn for the Mod layer.</strong>
      The starter keymap puts the arrows on H J K L, Home, Page Down, Page Up and End on Y U I O, and the
      Mac's media keys on F1 to F12. Change any key in the app.
    </div>
  </section>
</template>
