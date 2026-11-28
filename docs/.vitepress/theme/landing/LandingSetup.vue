<script setup lang="ts">
// "Before you start": KeyLayers isn't download-and-run. macOS needs three approvals, and the third
// (Input Monitoring for KeyLayersInputDaemon) has to be added by hand. This block sends people to the
// setup guide before they give up on a keyboard that doesn't remap yet.
import { withBase } from 'vitepress'

const steps = [
  {
    title: 'Login Items',
    text: 'Turn on KeyLayers under App Background Activity, so its helper and input service can run.',
  },
  {
    title: 'Accessibility',
    text: 'Allow KeyLayersHelper, so it can type your remapped keys.',
  },
  {
    title: 'Input Monitoring, by hand',
    text: 'macOS can’t ask for this one. Click +, press ⌘⇧G and add KeyLayersInputDaemon from inside the app.',
    manual: true,
  },
]
</script>

<template>
  <section id="setup" class="landing-setup">
    <div class="landing-setup-intro">
      <p class="landing-eyebrow">Before you start</p>
      <h2 class="landing-setup-title">Download, then set it up.</h2>
      <p class="landing-setup-lead">
        KeyLayers can’t remap anything until macOS approves it, in three steps. The app tells you which one
        is next, and the setup guide shows every click. It takes about five minutes.
      </p>
    </div>
    <ol class="landing-setup-steps">
      <li v-for="(step, index) in steps" :key="step.title" :class="{ 'landing-setup-manual': step.manual }">
        <span class="landing-setup-number">{{ index + 1 }}</span>
        <div>
          <h3>{{ step.title }}</h3>
          <p>{{ step.text }}</p>
        </div>
      </li>
    </ol>
    <div class="landing-setup-actions">
      <a class="landing-button landing-button-brand landing-button-large" :href="withBase('/guide/setup')">
        Follow the setup guide →
      </a>
    </div>
  </section>
</template>
