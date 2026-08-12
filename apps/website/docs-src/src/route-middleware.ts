import path from 'node:path';
import { defineRouteMiddleware } from '@astrojs/starlight/route-data';
import { buildDocsMetadataMap } from '../lib/docs-metadata.mjs';

const docsRoot = process.cwd();
const docsMetadata = await buildDocsMetadataMap({
  contentRoot: path.join(docsRoot, 'src/content/docs'),
  repositoryRoot: path.resolve(docsRoot, '../../..'),
});

export const onRequest = defineRouteMiddleware((context) => {
  const lastModified = docsMetadata.get(context.url.pathname)?.lastModified;
  if (!lastModified) return;
  context.locals.starlightRoute.lastUpdated = lastModified;
});
