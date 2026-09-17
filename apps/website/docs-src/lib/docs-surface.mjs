import { stripLocalePrefix } from '../../i18n/routes.mjs';

const cliGuidePaths = new Set([
  '/docs/cli-direct/',
  '/docs/cli-extract/',
  '/docs/cli-jobs/',
]);

function pathnameFor(value) {
  const pathname = new URL(String(value ?? '/'), 'https://healthmd.app').pathname;
  return stripLocalePrefix(pathname);
}

export function isCliDocsPath(value) {
  const pathname = pathnameFor(value);
  return pathname.startsWith('/docs/cli/')
    || cliGuidePaths.has(pathname)
    || pathname.startsWith('/docs/cli-reference/');
}

export function isCliOverviewPath(value) {
  return pathnameFor(value) === '/docs/cli/';
}
