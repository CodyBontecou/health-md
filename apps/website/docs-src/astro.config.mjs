import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';

export default defineConfig({
  site: 'https://healthmd.app',
  base: '/docs',
  trailingSlash: 'always',
  integrations: [
    starlight({
      title: 'health.md Docs',
      description: 'A complete feature and data reference for health.md on iOS, iPadOS, macOS, and Android.',
      favicon: '/favicon.png',
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
        { tag: 'link', attrs: { rel: 'icon', type: 'image/png', href: '/docs/favicon.png', sizes: '32x32' } },
        { tag: 'link', attrs: { rel: 'apple-touch-icon', sizes: '180x180', href: '/assets/app-icon/icon_180x180.png' } },
        { tag: 'script', attrs: { src: '/assets/analytics.js', defer: true } },
        { tag: 'script', attrs: { src: '/docs/vertical-tables.js', defer: true } },
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
          label: 'Platform Guides',
          items: [
            { slug: 'android' },
            { slug: 'macos' },
          ],
        },
        {
          label: 'Customization',
          items: [
            { slug: 'metrics' },
            { slug: 'visualizations-roadmap' },
            { slug: 'format' },
            { slug: 'individual-tracking' },
            { slug: 'daily-notes' },
          ],
        },
        {
          label: 'Export Reference',
          items: [
            { label: 'Reference overview', slug: 'reference' },
            { slug: 'reference/daily-records' },
            { slug: 'reference/canonical-healthkit-records' },
            { slug: 'reference/query-manifests-and-diagnostics' },
            { slug: 'reference/export-formats' },
            { slug: 'reference/individual-entry-tracking' },
            { slug: 'reference/data-dictionary-and-rollups' },
            { slug: 'reference/api-and-cli' },
            { slug: 'reference/connected-mac-iphone-protocol' },
            { slug: 'reference/other-export-surfaces' },
            { slug: 'reference/integration-recipes' },
            { slug: 'reference/generation' },
          ],
        },
        {
          label: 'Integrations',
          items: [
            { slug: 'shortcuts' },
            { slug: 'api-endpoint' },
            { slug: 'cli' },
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
