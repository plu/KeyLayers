import { defineConfig } from 'vitepress'
import { downloadURL } from './links'

export const nav = [
  { text: 'Setup guide', link: '/guide/setup' },
  { text: 'Guide', link: '/guide/install' },
  { text: 'Contributing', link: '/contributing/' },
  { text: 'Download', link: downloadURL },
]

export const sidebar = [
  {
    text: 'Guide',
    items: [
      { text: 'Install', link: '/guide/install' },
      { text: 'Setup', link: '/guide/setup' },
      { text: 'Layers and keys', link: '/guide/layers' },
      { text: 'Macros', link: '/guide/macros' },
      { text: 'Pause and emergency stop', link: '/guide/pause' },
      { text: 'Updates', link: '/guide/updates' },
      { text: 'Troubleshooting', link: '/guide/troubleshooting' },
    ],
  },
  {
    text: 'Contributing',
    items: [
      { text: 'Building from source', link: '/contributing/' },
      { text: 'Architecture', link: '/ARCHITECTURE' },
      { text: 'Testing', link: '/TESTING' },
      { text: 'Releasing & manual checks', link: '/MANUAL-CHECKLIST' },
    ],
  },
]

// Served from https://johannes.plunien.com/KeyLayers/ (the plu.github.io user site's domain).
export default defineConfig({
  title: 'KeyLayers',
  description: 'Layers for every Mac keyboard',
  base: '/KeyLayers/',
  cleanUrls: true,
  lastUpdated: false,
  // Plans and specs for working on the repo, not for the site.
  srcExclude: ['superpowers/**'],
  head: [['link', { rel: 'icon', type: 'image/png', href: '/KeyLayers/favicon.png' }]],
  themeConfig: {
    nav,
    sidebar,
    search: { provider: 'local' },
    socialLinks: [{ icon: 'github', link: 'https://github.com/plu/KeyLayers' }],
    logo: '/icon.png',
    footer: { message: 'Released under the MIT License.', copyright: 'Copyright © 2026 Johannes Plunien' },
  },
})
