import { defaultLocale, localeFor } from './locales.mjs';

export const routes = Object.freeze({
  home: Object.freeze({ en: '/', es: '/es/' }),
  privacy: Object.freeze({ en: '/privacy-policy.html', es: '/es/privacy-policy.html' }),
  terms: Object.freeze({ en: '/terms-of-service.html', es: '/es/terms-of-service.html' }),
  docsHome: Object.freeze({ en: '/docs/', es: '/es/docs/' }),
  docsIphoneFirstExport: Object.freeze({
    en: '/docs/iphone-first-export/',
    es: '/es/docs/iphone-first-export/',
  }),
  docsAndroid: Object.freeze({ en: '/docs/android/', es: '/es/docs/android/' }),
  docsConfiguration: Object.freeze({
    en: '/docs/configuration/',
    es: '/es/docs/configuration/',
  }),
});

export const translatedDocSlugs = Object.freeze([
  'docs',
  'docs/iphone-first-export',
  'docs/android',
  'docs/configuration',
]);

const translatedDocSet = new Set(translatedDocSlugs);

export function routePath(routeId, locale = defaultLocale) {
  const route = routes[routeId];
  if (!route) throw new Error(`Unknown localized route: ${routeId}`);
  const path = route[locale];
  if (!path) throw new Error(`Route ${routeId} is not available for locale ${locale}`);
  return path;
}

export function docsEntryId(entry) {
  const normalized = entry.replace(/\\/g, '/').replace(/\.[^.]+$/, '');
  const isSpanish = normalized === 'es' || normalized.startsWith('es/');
  let slug = isSpanish ? normalized.replace(/^es\/?/, '') : normalized;
  slug = slug.replace(/(^|\/)index$/, '').replace(/^\/+|\/+$/g, '');
  return [isSpanish ? 'es' : '', 'docs', slug].filter(Boolean).join('/');
}

export function docsPathForSlug(slug, locale = defaultLocale) {
  localeFor(locale);
  const clean = slug.replace(/^\/+|\/+$/g, '');
  return `/${locale === defaultLocale ? '' : `${locale}/`}docs${clean ? `/${clean}` : ''}/`;
}

export function englishDocsPath(pathname) {
  return pathname.replace(/^\/es\/docs(?=\/|$)/, '/docs');
}

export function docSlugFromPath(pathname) {
  const withoutLocale = pathname.replace(/^\/es(?=\/)/, '');
  const match = withoutLocale.match(/^\/docs(?:\/(.*?))?\/?$/);
  return match ? ['docs', match[1] ?? ''].filter(Boolean).join('/') : null;
}

export function hasSpanishDocTranslation(pathname) {
  const slug = docSlugFromPath(pathname);
  return slug !== null && translatedDocSet.has(slug);
}
