import {
  authoredDocSlugs,
  defaultLocale,
  enabledLocales,
  localeFor,
  localizedPathname,
  publishedLocales,
} from './locales.mjs';

const routeDefinitions = Object.freeze({
  home: '/',
  privacy: '/privacy-policy.html',
  terms: '/terms-of-service.html',
  docsHome: '/docs/',
  docsIphoneFirstExport: '/docs/iphone-first-export/',
  docsAndroid: '/docs/android/',
  docsConfiguration: '/docs/configuration/',
});

export const routes = Object.freeze(Object.fromEntries(
  Object.entries(routeDefinitions).map(([routeId, pathname]) => [
    routeId,
    Object.freeze(Object.fromEntries(
      enabledLocales.map((locale) => [locale, localizedPathname(pathname, locale)]),
    )),
  ]),
));

export const translatedDocSlugs = authoredDocSlugs;

export const translatedDocSlugsByLocale = Object.freeze(Object.fromEntries(
  enabledLocales.map((code) => [code, localeFor(code).translatedDocSlugs]),
));

const translatedDocSets = new Map(
  enabledLocales.map((code) => [code, new Set(translatedDocSlugsByLocale[code])]),
);

export function routePath(routeId, locale = defaultLocale) {
  const route = routes[routeId];
  if (!route) throw new Error(`Unknown localized route: ${routeId}`);
  const pathname = route[locale];
  if (!pathname) throw new Error(`Route ${routeId} is not available for locale ${locale}`);
  return pathname;
}

export function localeFromPathname(pathname) {
  const firstSegment = String(pathname ?? '').split(/[?#]/, 1)[0].split('/').filter(Boolean)[0];
  if (!firstSegment) return defaultLocale;
  return enabledLocales.find((code) => {
    const locale = localeFor(code);
    return locale.path && locale.path.toLowerCase() === firstSegment.toLowerCase();
  }) ?? defaultLocale;
}

export function stripLocalePrefix(pathname) {
  const value = String(pathname ?? '/');
  const locale = localeFromPathname(value);
  if (locale === defaultLocale) return value;
  const prefix = `/${localeFor(locale).path}`;
  const stripped = value.slice(prefix.length);
  return stripped.startsWith('/') ? stripped : `/${stripped}`;
}

export function localizedEquivalentPath(pathname, locale = defaultLocale) {
  const base = stripLocalePrefix(pathname);
  return localizedPathname(base, locale);
}

export function docsEntryId(entry) {
  const normalized = entry.replace(/\\/g, '/').replace(/\.[^.]+$/, '').replace(/^\/+|\/+$/g, '');
  const firstSegment = normalized.split('/')[0];
  const locale = enabledLocales.find((code) => localeFor(code).path === firstSegment) ?? defaultLocale;
  const withoutLocale = locale === defaultLocale
    ? normalized
    : normalized.replace(new RegExp(`^${localeFor(locale).path}/?`), '');
  const slug = withoutLocale.replace(/(^|\/)index$/, '').replace(/^\/+|\/+$/g, '');
  return [locale === defaultLocale ? '' : localeFor(locale).path, 'docs', slug]
    .filter(Boolean)
    .join('/');
}

export function docsPathForSlug(slug, locale = defaultLocale) {
  localeFor(locale);
  const clean = String(slug ?? '').replace(/^\/+|\/+$/g, '').replace(/^docs\/?/, '');
  return localizedPathname(`/docs${clean ? `/${clean}` : ''}/`, locale);
}

export function englishDocsPath(pathname) {
  const withoutLocale = stripLocalePrefix(pathname);
  return withoutLocale.replace(/^(\/docs(?:\/|$))/, '$1');
}

export function docSlugFromPath(pathname) {
  const withoutLocale = stripLocalePrefix(String(pathname ?? '').split(/[?#]/, 1)[0]);
  const match = withoutLocale.match(/^\/docs(?:\/(.*?))?\/?$/);
  return match ? ['docs', match[1] ?? ''].filter(Boolean).join('/') : null;
}

export function hasDocTranslation(pathname, locale = localeFromPathname(pathname)) {
  const slug = docSlugFromPath(pathname);
  if (slug === null) return false;
  if (locale === defaultLocale) return true;
  return translatedDocSets.get(locale)?.has(slug) ?? false;
}

export function translatedLocalesForDoc(pathname) {
  const slug = docSlugFromPath(pathname);
  if (slug === null) return [];
  return publishedLocales('docs')
    .map(({ code }) => code)
    .filter((locale) => locale === defaultLocale || translatedDocSets.get(locale)?.has(slug));
}
