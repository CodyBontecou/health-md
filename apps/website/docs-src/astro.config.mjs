import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';

const cloudflareAnalyticsGate = `
(function () {
  var productionHosts = {
    'instareply.isolated.tech': true,
    'voxboard.isolated.tech': true,
    'healthmd.isolated.tech': true,
    'isome.isolated.tech': true,
    'gitsyncmd.isolated.tech': true,
    'timemd.isolated.tech': true,
    'imghost.isolated.tech': true
  };

  if (!productionHosts[window.location.hostname]) {
    return;
  }

  function loadCloudflareBeacon() {
    if (document.querySelector('script[src="https://static.cloudflareinsights.com/beacon.min.js"]')) {
      return;
    }

    var script = document.createElement('script');
    script.defer = true;
    script.src = 'https://static.cloudflareinsights.com/beacon.min.js';
    script.setAttribute('data-cf-beacon', '{"token":"090f363070334cddad5c5cc1509b8807"}');
    document.head.appendChild(script);
  }

  fetch('https://img-host.costream.workers.dev/analytics-gate', {
    cache: 'no-store',
    mode: 'cors',
    credentials: 'omit'
  })
    .then(function (response) {
      return response.ok ? response.json() : { track: false };
    })
    .then(function (gate) {
      if (gate && gate.track) {
        loadCloudflareBeacon();
      }
    })
    .catch(function () {
      // Fail closed so excluded IPs are not accidentally tracked.
    });
})();
`;

export default defineConfig({
  site: 'https://healthmd.isolated.tech',
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
        { tag: 'script', content: cloudflareAnalyticsGate },
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
