import { defineConfig } from 'astro/config';
import sitemap from '@astrojs/sitemap';
import starlight from '@astrojs/starlight';
import { docsPathForSlug, hasSpanishDocTranslation } from '../i18n/routes.mjs';

const site = 'https://healthmd.app';
const doc = (slug = '') => ['docs', slug].filter(Boolean).join('/');
const translatedLabel = (label, es) => ({ label, translations: { es } });
const item = (label, es, slug = '') => ({ ...translatedLabel(label, es), slug: doc(slug) });

function localizedSitemapLinks(pathname) {
  if (!hasSpanishDocTranslation(pathname)) return undefined;
  const slug = pathname
    .replace(/^\/es(?=\/)/, '')
    .replace(/^\/docs\/?/, '')
    .replace(/\/$/, '');
  const english = new URL(docsPathForSlug(slug, 'en'), site).href;
  const spanish = new URL(docsPathForSlug(slug, 'es'), site).href;
  return [
    { lang: 'en', url: english },
    { lang: 'es', url: spanish },
    { lang: 'x-default', url: english },
  ];
}

export default defineConfig({
  site,
  trailingSlash: 'always',
  integrations: [
    sitemap({
      filter: (page) => {
        const pathname = new URL(page).pathname;
        if (pathname === '/docs/data-reference/' || pathname === '/es/docs/data-reference/') return false;
        if (pathname.startsWith('/es/docs/') || pathname === '/es/docs/') {
          return hasSpanishDocTranslation(pathname);
        }
        return pathname.startsWith('/docs/');
      },
      namespaces: { xhtml: true },
      serialize: (entry) => ({
        ...entry,
        links: localizedSitemapLinks(new URL(entry.url).pathname),
      }),
    }),
    starlight({
      title: { en: 'health.md', es: 'health.md' },
      description: 'Configure Health.md for agents, MCP, and CLI workflows, then explore versioned health-data contracts and private export tools.',
      favicon: '/docs/favicon.png',
      defaultLocale: 'root',
      locales: {
        root: { label: 'English', lang: 'en' },
        es: { label: 'Español', lang: 'es' },
      },
      logo: {
        src: './src/assets/icon_80x80.png',
        alt: 'health.md',
      },
      customCss: ['./src/styles/healthmd.css', './src/styles/agent-first.css'],
      expressiveCode: {
        getBlockLocale: ({ file }) => {
          const sourcePath = (file.path ?? '').replaceAll('\\', '/');
          const pathname = file.url?.pathname ?? '';
          return sourcePath.includes('/src/content/docs/es/') || pathname.startsWith('/es/') ? 'es' : 'en';
        },
      },
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
          ...translatedLabel('Get Started', 'Primeros pasos'),
          items: [
            item('Choose a goal', 'Elige un objetivo'),
            item('First iPhone export', 'Primera exportación desde iPhone', 'iphone-first-export'),
            item('First Android export', 'Primera exportación desde Android', 'android'),
            item('Connect a local agent', 'Conecta un agente local', 'configuration'),
            item('Mac companion', 'Aplicación complementaria para Mac', 'macos'),
          ],
        },
        {
          ...translatedLabel('Use an Agent', 'Usar un agente'),
          collapsed: true,
          items: [
            item('MCP server & tools', 'Servidor MCP y herramientas', 'mcp'),
            item('Bundled & portable CLI', 'CLI incluida y portátil', 'cli'),
            item('Query cookbook', 'Recetas de consultas', 'agent-queries'),
            item('Agent architecture', 'Arquitectura de agentes', 'agents'),
            item('Direct iPhone CLI · Preview', 'CLI directa para iPhone · Vista previa', 'cli-direct'),
            item('Canonical extraction', 'Extracción canónica', 'cli-extract'),
            item('Durable jobs', 'Trabajos duraderos', 'cli-jobs'),
          ],
        },
        {
          ...translatedLabel('Export & Automate', 'Exportar y automatizar'),
          collapsed: true,
          items: [
            item('Apple onboarding', 'Configuración inicial en Apple', 'onboarding'),
            item('Folders & vaults', 'Carpetas y bóvedas', 'folder-vault'),
            item('Export from iPhone', 'Exportar desde iPhone', 'export'),
            item('Apple Health metrics', 'Métricas de Apple Health', 'metrics'),
            item('Export formatting', 'Formato de exportación', 'format'),
            item('iPhone scheduling', 'Programación en iPhone', 'scheduling'),
            item('Mac sync', 'Sincronización con Mac', 'sync'),
            item('Shortcuts & App Intents', 'Atajos y App Intents', 'shortcuts'),
            item('Individual entries', 'Entradas individuales', 'individual-tracking'),
            item('Daily notes', 'Notas diarias', 'daily-notes'),
          ],
        },
        {
          ...translatedLabel('Build an Integration', 'Crear una integración'),
          collapsed: true,
          items: [
            item('Contract overview', 'Resumen de contratos', 'reference'),
            item('API & CLI envelopes', 'Envoltorios de API y CLI', 'reference/api-and-cli'),
            item('Queries & evidence', 'Consultas y evidencia', 'reference/evidence-packets'),
            item('Loopback API', 'API de loopback', 'agent-api'),
            item('URL endpoint', 'Endpoint URL', 'api-endpoint'),
            item('Direct protocol', 'Protocolo directo', 'reference/connected-mac-iphone-protocol'),
            item('Integration recipes', 'Recetas de integración', 'reference/integration-recipes'),
            item('Generated artifacts', 'Artefactos generados', 'reference/generated'),
          ],
        },
        {
          ...translatedLabel('Data Reference', 'Referencia de datos'),
          collapsed: true,
          items: [
            item('Daily records', 'Registros diarios', 'reference/daily-records'),
            item('Canonical HealthKit records', 'Registros canónicos de HealthKit', 'reference/canonical-healthkit-records'),
            item('Export formats', 'Formatos de exportación', 'reference/export-formats'),
            item('Dictionary & roll-ups', 'Diccionario y agregaciones', 'reference/data-dictionary-and-rollups'),
            item('Shared metric registry', 'Registro compartido de métricas', 'shared-metric-registry'),
            item('Reference generation', 'Generación de la referencia', 'reference/generation'),
          ],
        },
        {
          ...translatedLabel('More', 'Más'),
          collapsed: true,
          items: [
            item('Visualization catalog', 'Catálogo de visualizaciones', 'visualizations-roadmap'),
            item('Unlock & plans', 'Desbloqueo y planes', 'paywall'),
          ],
        },
      ],
    }),
  ],
});
