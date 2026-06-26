import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';

export default defineConfig({
  site: 'https://healthmd.app',
  base: '/docs',
  trailingSlash: 'always',
  integrations: [
    starlight({
      title: 'health.md Docs',
      description: 'A complete feature and data reference for health.md on iOS, iPadOS, and macOS.',
      logo: {
        src: './src/assets/icon_80x80.png',
        alt: 'health.md icon',
      },
      customCss: ['./src/styles/healthmd.css'],
      components: {
        SocialIcons: './src/components/HeaderLinks.astro',
        Footer: './src/components/Footer.astro',
      },
      head: [
        { tag: 'link', attrs: { rel: 'icon', href: '/favicon.ico', sizes: 'any' } },
        { tag: 'link', attrs: { rel: 'apple-touch-icon', sizes: '180x180', href: '/assets/app-icon/icon_180x180.png' } },
        { tag: 'script', attrs: { src: '/assets/analytics.js', defer: true } },
      ],
      sidebar: [
        {
          label: 'Getting Started',
          items: [
            { label: 'Overview', slug: '' },
            { slug: 'onboarding' },
            { slug: 'folder-vault' },
          ],
        },
        {
          label: 'Core Features',
          items: [
            { slug: 'export' },
            { slug: 'scheduling' },
            { slug: 'sync' },
          ],
        },
        {
          label: 'Customization',
          items: [
            { slug: 'metrics' },
            { slug: 'data-reference' },
            { slug: 'visualizations-roadmap' },
            { slug: 'format' },
            { slug: 'individual-tracking' },
            { slug: 'daily-notes' },
          ],
        },
        {
          label: 'Integrations',
          items: [
            { slug: 'shortcuts' },
            { slug: 'macos' },
          ],
        },
        {
          label: 'Account',
          items: [{ slug: 'paywall' }],
        },
      ],
    }),
  ],
});
