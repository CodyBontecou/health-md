import { defineCollection } from 'astro:content';
import { docsLoader } from '@astrojs/starlight/loaders';
import { docsSchema } from '@astrojs/starlight/schema';
import { docsEntryId } from '../../i18n/routes.mjs';

export const collections = {
  docs: defineCollection({
    loader: docsLoader({ generateId: ({ entry }) => docsEntryId(entry) }),
    schema: docsSchema(),
  }),
};
