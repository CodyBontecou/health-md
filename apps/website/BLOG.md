# Health.md blog content

Blog source lives in `content/blog/*.md`. Run `npm run build` to render the complete static site into `dist/`.

Required frontmatter:

```yaml
---
title: A post title
description: Search and social description
date: 2026-07-15T12:00:00.000Z
updated: 2026-07-15T12:00:00.000Z
category: Product update
draft: false
tags:
  - healthmd
---
```

Optional fields are `lead`, `image`, `imageAlt`, and `showCover`. Root-relative and absolute image URLs are supported. Drafts are excluded from the index, generated pages, and sitemap.

The build preserves the rest of the existing static site, sanitizes rendered Markdown, renders each post at `/blog/<slug>/`, rebuilds `/blog/`, and generates the blog entries in `/sitemap.xml`. Vercel runs this build and deploys `dist/`.

Posts published from codybontecou.com are written into this directory through the GitHub Contents API. Treat those Markdown files—not generated HTML—as the source of truth.
