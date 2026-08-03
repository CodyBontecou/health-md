import { defineConfig } from 'astro/config';
import sitemap from '@astrojs/sitemap';
import starlight from '@astrojs/starlight';
import {
  defaultLocale,
  localeFor,
  publishedLocales,
} from '../i18n/locales.mjs';
import { starlightSidebar } from '../i18n/docs-ui.mjs';
import {
  docSlugFromPath,
  docsPathForSlug,
  hasDocTranslation,
  localeFromPathname,
  stripLocalePrefix,
  translatedLocalesForDoc,
} from '../i18n/routes.mjs';

const site = 'https://healthmd.app';
const docsLocales = publishedLocales('docs');

function localizedSitemapLinks(pathname) {
  const slug = docSlugFromPath(pathname);
  if (!slug) return undefined;
  const links = translatedLocalesForDoc(pathname).map((code) => {
    const locale = localeFor(code);
    return {
      lang: locale.lang,
      url: new URL(docsPathForSlug(slug, code), site).href,
    };
  });
  links.push({
    lang: 'x-default',
    url: new URL(docsPathForSlug(slug, defaultLocale), site).href,
  });
  return links;
}

const starlightLocales = Object.fromEntries(docsLocales.map((locale) => [
  locale.code === defaultLocale ? 'root' : locale.path,
  { label: locale.label, lang: locale.lang },
]));
const localizedTitles = Object.fromEntries(docsLocales.map((locale) => [locale.lang, 'health.md']));

export default defineConfig({
  site,
  trailingSlash: 'always',
  integrations: [
    sitemap({
      filter: (page) => {
        const pathname = new URL(page).pathname;
        const englishPath = stripLocalePrefix(pathname);
        if (englishPath === '/docs/data-reference/') return false;
        if (!englishPath.startsWith('/docs/')) return false;
        const locale = localeFromPathname(pathname);
        return locale === defaultLocale || hasDocTranslation(pathname, locale);
      },
      namespaces: { xhtml: true },
      serialize: (entry) => ({
        ...entry,
        links: localizedSitemapLinks(new URL(entry.url).pathname),
      }),
    }),
    starlight({
      title: localizedTitles,
      description: 'Configure Health.md for agents, MCP, and CLI workflows, then explore versioned health-data contracts and private export tools.',
      favicon: '/docs/favicon.png',
      defaultLocale: 'root',
      locales: starlightLocales,
      logo: {
        src: './src/assets/icon_80x80.png',
        alt: 'health.md',
      },
      customCss: ['./src/styles/healthmd.css', './src/styles/agent-first.css'],
      expressiveCode: {
        getBlockLocale: ({ file }) => {
          const sourcePath = (file.path ?? '').replaceAll('\\', '/');
          const sourceLocale = docsLocales.find((locale) =>
            locale.path && sourcePath.includes(`/src/content/docs/${locale.path}/`),
          );
          if (sourceLocale) return sourceLocale.lang;
          const pathname = file.url?.pathname ?? '';
          return localeFor(localeFromPathname(pathname)).lang;
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
      sidebar: starlightSidebar(),
    }),
  ],
});
