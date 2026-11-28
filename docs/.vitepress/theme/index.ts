import DefaultTheme from 'vitepress/theme'
import type { Theme } from 'vitepress'
import Shot from './Shot.vue'
import LandingHero from './landing/LandingHero.vue'
import LandingSection from './landing/LandingSection.vue'
import FeatureCard from './landing/FeatureCard.vue'
import SmallThings from './landing/SmallThings.vue'
import LandingSetup from './landing/LandingSetup.vue'
import './custom.css'
import './landing.css'

export default {
  extends: DefaultTheme,
  enhanceApp({ app }) {
    app.component('Shot', Shot)
    app.component('LandingHero', LandingHero)
    app.component('LandingSection', LandingSection)
    app.component('FeatureCard', FeatureCard)
    app.component('SmallThings', SmallThings)
    app.component('LandingSetup', LandingSetup)
  },
} satisfies Theme
