import { defineConfig } from 'astro/config';
import sitemap from '@astrojs/sitemap';
import starlight from '@astrojs/starlight';

export default defineConfig({
  site: 'https://healthmd.app',
  base: '/docs',
  trailingSlash: 'always',
  integrations: [
    sitemap({
      filter: (page) => new URL(page).pathname !== '/docs/data-reference/',
    }),
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
        Head: './src/components/Head.astro',
        SocialIcons: './src/components/HeaderLinks.astro',
        Footer: './src/components/Footer.astro',
        ThemeProvider: './src/components/LightThemeProvider.astro',
        ThemeSelect: './src/components/EmptyThemeSelect.astro',
      },
      head: [
        { tag: 'link', attrs: { rel: 'icon', type: 'image/png', href: '/docs/favicon.png', sizes: '32x32' } },
        { tag: 'link', attrs: { rel: 'apple-touch-icon', sizes: '180x180', href: '/assets/app-icon/icon_180x180.png' } },
        { tag: 'meta', attrs: { property: 'og:image', content: 'https://healthmd.app/docs/social/docs-og.png' } },
        { tag: 'meta', attrs: { property: 'og:image:width', content: '1200' } },
        { tag: 'meta', attrs: { property: 'og:image:height', content: '630' } },
        { tag: 'meta', attrs: { property: 'og:image:alt', content: 'Health.md documentation — export, query, automate, and build' } },
        { tag: 'meta', attrs: { name: 'twitter:image', content: 'https://healthmd.app/docs/social/docs-og.png' } },
        { tag: 'meta', attrs: { name: 'twitter:image:alt', content: 'Health.md documentation — export, query, automate, and build' } },
        { tag: 'script', attrs: { src: '/assets/analytics.js', defer: true } },
        { tag: 'script', attrs: { src: '/docs/vertical-tables.js', defer: true } },
        {
          tag: 'script',
          attrs: { type: 'module' },
          content: `
            const strand = document.querySelector('[data-three-strand]');
            const reducedMotion = window.matchMedia?.('(prefers-reduced-motion: reduce)').matches ?? false;
            const saveData = navigator.connection?.saveData ?? false;
            if (strand && !reducedMotion && !saveData) {
              let scheduled = false;
              const load = () => import('/assets/landing-three.bundle.js');
              const schedule = () => {
                if (scheduled) return;
                scheduled = true;
                const afterLoad = () => window.setTimeout(() => {
                  if ('requestIdleCallback' in window) requestIdleCallback(load, { timeout: 2000 });
                  else load();
                }, 3000);
                if (document.readyState === 'complete') afterLoad();
                else window.addEventListener('load', afterLoad, { once: true });
              };
              if ('IntersectionObserver' in window) {
                const observer = new IntersectionObserver((entries) => {
                  if (entries.some((entry) => entry.isIntersecting)) {
                    observer.disconnect();
                    schedule();
                  }
                }, { rootMargin: '160px' });
                observer.observe(strand);
              } else schedule();
            }
          `,
        },
      ],
      sidebar: [
        {
          label: 'Get Started',
          items: [
            { label: 'Choose a goal', slug: '' },
            { label: 'First iPhone export', slug: 'iphone-first-export' },
            { label: 'First Android export', slug: 'android' },
            { label: 'Connect a local agent', slug: 'configuration' },
            { label: 'Mac companion', slug: 'macos' },
          ],
        },
        {
          label: 'Use an Agent',
          collapsed: true,
          items: [
            { label: 'MCP server & tools', slug: 'mcp' },
            { label: 'Bundled & portable CLI', slug: 'cli' },
            { label: 'Query cookbook', slug: 'agent-queries' },
            { label: 'Agent architecture', slug: 'agents' },
            { label: 'Direct iPhone CLI · Preview', slug: 'cli-direct' },
            { label: 'Canonical extraction', slug: 'cli-extract' },
            { label: 'Durable jobs', slug: 'cli-jobs' },
          ],
        },
        {
          label: 'Export & Automate',
          collapsed: true,
          items: [
            { label: 'Apple onboarding', slug: 'onboarding' },
            { label: 'Folders & vaults', slug: 'folder-vault' },
            { label: 'Export from iPhone', slug: 'export' },
            { label: 'Apple Health metrics', slug: 'metrics' },
            { label: 'Export formatting', slug: 'format' },
            { label: 'iPhone scheduling', slug: 'scheduling' },
            { label: 'Mac sync', slug: 'sync' },
            { label: 'Shortcuts & App Intents', slug: 'shortcuts' },
            { label: 'Individual entries', slug: 'individual-tracking' },
            { label: 'Daily notes', slug: 'daily-notes' },
          ],
        },
        {
          label: 'Build an Integration',
          collapsed: true,
          items: [
            { label: 'Contract overview', slug: 'reference' },
            { label: 'API & CLI envelopes', slug: 'reference/api-and-cli' },
            { label: 'Queries & evidence', slug: 'reference/evidence-packets' },
            { label: 'Loopback API', slug: 'agent-api' },
            { label: 'URL endpoint', slug: 'api-endpoint' },
            { label: 'Direct protocol', slug: 'reference/connected-mac-iphone-protocol' },
            { label: 'Integration recipes', slug: 'reference/integration-recipes' },
            { label: 'Generated artifacts', slug: 'reference/generated' },
          ],
        },
        {
          label: 'Data Reference',
          collapsed: true,
          items: [
            { label: 'Daily records', slug: 'reference/daily-records' },
            { label: 'Canonical HealthKit records', slug: 'reference/canonical-healthkit-records' },
            { label: 'Export formats', slug: 'reference/export-formats' },
            { label: 'Dictionary & roll-ups', slug: 'reference/data-dictionary-and-rollups' },
            { label: 'Shared metric registry', slug: 'shared-metric-registry' },
            { label: 'Reference generation', slug: 'reference/generation' },
          ],
        },
        {
          label: 'More',
          collapsed: true,
          items: [
            { label: 'Visualization catalog', slug: 'visualizations-roadmap' },
            { label: 'Unlock & plans', slug: 'paywall' },
          ],
        },
      ],
    }),
  ],
});
