import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';

export default defineConfig({
  site: 'https://healthmd.app',
  base: '/docs',
  trailingSlash: 'always',
  integrations: [
    starlight({
      title: 'health.md',
      description: 'Configure Health.md for agents, MCP, and CLI workflows, then explore versioned health-data contracts and private export tools.',
      favicon: '/favicon.png',
      logo: {
        src: './src/assets/icon_80x80.png',
        alt: 'health.md icon',
      },
      customCss: ['./src/styles/healthmd.css', './src/styles/agent-first.css'],
      components: {
        SocialIcons: './src/components/HeaderLinks.astro',
        Footer: './src/components/Footer.astro',
        ThemeProvider: './src/components/LightThemeProvider.astro',
        ThemeSelect: './src/components/EmptyThemeSelect.astro',
      },
      head: [
        { tag: 'link', attrs: { rel: 'icon', type: 'image/png', href: '/docs/favicon.png', sizes: '32x32' } },
        { tag: 'link', attrs: { rel: 'apple-touch-icon', sizes: '180x180', href: '/assets/app-icon/icon_180x180.png' } },
        { tag: 'script', attrs: { src: '/assets/analytics.js', defer: true } },
        { tag: 'script', attrs: { src: '/docs/vertical-tables.js', defer: true } },
        { tag: 'script', attrs: { src: '/assets/landing-three.js', type: 'module' } },
      ],
      sidebar: [
        {
          label: 'Agent Quickstart',
          items: [
            { label: 'Overview', slug: '' },
            { label: 'Configure your agent', slug: 'configuration' },
            { label: 'MCP server & tools', slug: 'mcp' },
            { label: 'CLI', slug: 'cli' },
            { label: 'Agent architecture', slug: 'agents' },
            { label: 'Query cookbook', slug: 'agent-queries' },
          ],
        },
        {
          label: 'Operate & Automate',
          items: [
            { label: 'Direct iPhone access', slug: 'cli-direct' },
            { label: 'Canonical extraction', slug: 'cli-extract' },
            { label: 'Durable jobs', slug: 'cli-jobs' },
            { label: 'Loopback API', slug: 'agent-api' },
          ],
        },
        {
          label: 'Data Contracts',
          items: [
            { label: 'Reference overview', slug: 'reference' },
            { label: 'API & CLI', slug: 'reference/api-and-cli' },
            { label: 'Queries & evidence', slug: 'reference/evidence-packets' },
            { slug: 'reference/query-manifests-and-diagnostics' },
            { slug: 'reference/daily-records' },
            { slug: 'reference/canonical-healthkit-records' },
            { slug: 'reference/export-formats' },
            { slug: 'reference/data-dictionary-and-rollups' },
            { slug: 'shared-metric-registry' },
            { label: 'Direct protocol', slug: 'reference/connected-mac-iphone-protocol' },
            { slug: 'reference/individual-entry-tracking' },
            { slug: 'reference/integration-recipes' },
            { label: 'Generated artifacts', slug: 'reference/generated' },
            { slug: 'reference/generation' },
          ],
        },
        {
          label: 'App & Export',
          items: [
            { slug: 'onboarding' },
            { slug: 'android' },
            { slug: 'macos' },
            { slug: 'folder-vault' },
            { slug: 'export' },
            { slug: 'metrics' },
            { slug: 'format' },
            { slug: 'scheduling' },
            { slug: 'sync' },
          ],
        },
        {
          label: 'Specialized Workflows',
          items: [
            { slug: 'individual-tracking' },
            { slug: 'daily-notes' },
            { slug: 'visualizations-roadmap' },
            { slug: 'shortcuts' },
            { slug: 'api-endpoint' },
            { slug: 'reference/other-export-surfaces' },
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
