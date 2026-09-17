import path from 'node:path';
import { defineRouteMiddleware } from '@astrojs/starlight/route-data';
import type { SidebarEntry, SidebarLink } from '@astrojs/starlight/utils/routing/types';
import { docsPathForSlug, localeFromPathname } from '../../i18n/routes.mjs';
import { buildDocsMetadataMap } from '../lib/docs-metadata.mjs';
import { isCliDocsPath, isCliOverviewPath } from '../lib/docs-surface.mjs';

const docsRoot = process.cwd();
const docsMetadata = await buildDocsMetadataMap({
  contentRoot: path.join(docsRoot, 'src/content/docs'),
  repositoryRoot: path.resolve(docsRoot, '../../..'),
});

function sidebarLinks(entries: SidebarEntry[]): SidebarLink[] {
  return entries.flatMap((entry) => (
    entry.type === 'group' ? sidebarLinks(entry.entries) : [entry]
  ));
}

export const onRequest = defineRouteMiddleware((context) => {
  const route = context.locals.starlightRoute;
  const lastModified = docsMetadata.get(context.url.pathname)?.lastModified;
  if (lastModified) route.lastUpdated = lastModified;

  const cliGroup = route.sidebar.find((entry) => (
    entry.type === 'group' && sidebarLinks(entry.entries).some(({ href }) => isCliOverviewPath(href))
  ));
  if (!cliGroup || cliGroup.type !== 'group') return;

  if (!isCliDocsPath(context.url.pathname)) {
    const overview = sidebarLinks(cliGroup.entries).find(({ href }) => isCliOverviewPath(href));
    if (overview) cliGroup.entries = [overview];
    return;
  }

  cliGroup.collapsed = false;
  route.sidebar = [cliGroup];
  route.siteTitleHref = docsPathForSlug('cli', localeFromPathname(context.url.pathname));

  const links = sidebarLinks(route.sidebar);
  const currentIndex = links.findIndex(({ isCurrent }) => isCurrent);
  route.pagination = {
    prev: currentIndex > 0 ? links[currentIndex - 1] : undefined,
    next: currentIndex >= 0 && currentIndex < links.length - 1 ? links[currentIndex + 1] : undefined,
  };
});
