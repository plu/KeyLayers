import { defineConfig } from 'vitepress'

// The latest release's zip: what "Download" links to everywhere.
export const downloadURL = 'https://github.com/plu/KeyLayers/releases/latest/download/KeyLayers.zip'

export const nav = [
  { text: 'Guide', link: '/guide/install' },
  { text: 'Contributing', link: '/ARCHITECTURE' },
  { text: 'Download', link: downloadURL },
]

export const sidebar = [
  {
    text: 'Contributing',
    items: [
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
  themeConfig: {
    nav,
    sidebar,
    search: { provider: 'local' },
    socialLinks: [{ icon: 'github', link: 'https://github.com/plu/KeyLayers' }],
  },
})
