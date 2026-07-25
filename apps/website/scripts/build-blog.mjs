#!/usr/bin/env node
import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import matter from 'gray-matter';
import { marked } from 'marked';
import sanitizeHtml from 'sanitize-html';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const SITE_URL = 'https://healthmd.app';
const CONTENT_DIR = path.join(ROOT, 'content', 'blog');

marked.setOptions({
  gfm: true,
  breaks: false,
});

function escapeHtml(value) {
  return String(value ?? '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
}

function escapeJsonForHtml(value) {
  return JSON.stringify(value).replaceAll('<', '\\u003c');
}

function sanitizeRenderedMarkdown(html) {
  return sanitizeHtml(html, {
    allowedTags: [
      ...sanitizeHtml.defaults.allowedTags,
      'audio',
      'figcaption',
      'figure',
      'img',
      'source',
      'video',
    ],
    allowedAttributes: {
      '*': ['class', 'id', 'role', 'title'],
      a: ['href', 'rel', 'target'],
      audio: ['controls', 'preload', 'src'],
      img: ['alt', 'decoding', 'height', 'loading', 'sizes', 'src', 'srcset', 'width'],
      source: ['src', 'srcset', 'type'],
      video: ['controls', 'height', 'poster', 'preload', 'src', 'width'],
    },
    allowedSchemes: ['http', 'https', 'mailto'],
    allowedSchemesByTag: {
      img: ['http', 'https', 'data'],
    },
    allowProtocolRelative: false,
    enforceHtmlBoundary: true,
    transformTags: {
      a: (_tagName, attributes) => ({
        tagName: 'a',
        attribs: {
          ...attributes,
          ...(attributes.target === '_blank' ? { rel: 'noopener noreferrer' } : {}),
        },
      }),
    },
  });
}

function slugify(value) {
  return String(value ?? '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .replace(/-{2,}/g, '-')
    .slice(0, 80);
}

function asDate(value, field, filename) {
  const date = value instanceof Date ? value : new Date(String(value ?? ''));
  if (Number.isNaN(date.getTime())) {
    throw new Error(`${filename}: ${field} must be a valid date`);
  }
  return date;
}

function asStringArray(value) {
  if (!Array.isArray(value)) return [];
  return value.map(String).map((item) => item.trim()).filter(Boolean);
}

function normalizeImage(value) {
  const image = String(value ?? '').trim();
  if (!image) return '';
  if (image.startsWith('/')) return `${SITE_URL}${image}`;
  try {
    return new URL(image).toString();
  } catch {
    throw new Error(`Invalid blog image URL: ${image}`);
  }
}

function formatDate(date) {
  return new Intl.DateTimeFormat('en-US', {
    timeZone: 'UTC',
    year: 'numeric',
    month: 'long',
    day: 'numeric',
  }).format(date);
}

function isoDate(date) {
  return date.toISOString().slice(0, 10);
}

async function loadPosts() {
  await fs.mkdir(CONTENT_DIR, { recursive: true });
  const entries = await fs.readdir(CONTENT_DIR, { withFileTypes: true });
  const posts = [];

  for (const entry of entries) {
    if (!entry.isFile() || !entry.name.endsWith('.md')) continue;

    const filename = entry.name;
    const raw = await fs.readFile(path.join(CONTENT_DIR, filename), 'utf8');
    const parsed = matter(raw);
    const slug = slugify(parsed.data.slug || filename.slice(0, -3));
    const title = String(parsed.data.title ?? '').trim();
    const description = String(parsed.data.description ?? '').trim();

    if (!slug || !title || !description) {
      throw new Error(`${filename}: slug, title, and description are required`);
    }

    const draft = parsed.data.draft === true;
    if (draft) continue;

    const date = asDate(parsed.data.date, 'date', filename);
    const updated = parsed.data.updated
      ? asDate(parsed.data.updated, 'updated', filename)
      : date;
    const image = normalizeImage(parsed.data.image);

    posts.push({
      slug,
      title,
      description,
      lead: String(parsed.data.lead || description).trim(),
      category: String(parsed.data.category || 'Health.md').trim(),
      date,
      updated,
      image,
      imageAlt: String(parsed.data.imageAlt || title).trim(),
      showCover: parsed.data.showCover !== false,
      tags: asStringArray(parsed.data.tags),
      body: parsed.content.trim(),
    });
  }

  return posts.sort((a, b) => b.date.getTime() - a.date.getTime());
}

function headerHtml(depth = 1) {
  const prefix = depth === 2 ? '../../' : '../';
  return `<header class="site-header">
    <div class="container header-inner">
      <a class="brand" href="${prefix}index.html">
        <img src="${prefix}assets/app-icon/icon_80x80.png" alt="">
        <span>health.md</span>
      </a>
      <div class="header-actions">
        <nav class="nav" aria-label="Primary navigation">
          <a href="${prefix}visualizations/">Visualizations</a>
          <a href="${prefix}docs/">Docs</a>
          <a href="${depth === 2 ? '../' : './'}">Blog</a>
          <a href="https://apps.apple.com/us/app/health-md/id6757763969" target="_blank" rel="noopener">App Store</a>
        </nav>
        <div class="theme-toggle" role="group" aria-label="Color theme">
          <button type="button" data-theme-option="system" aria-pressed="true">Auto</button>
          <button type="button" data-theme-option="light" aria-pressed="false">Light</button>
          <button type="button" data-theme-option="dark" aria-pressed="false">Dark</button>
        </div>
      </div>
    </div>
  </header>`;
}

function footerHtml(depth = 1) {
  const prefix = depth === 2 ? '../../' : '../';
  return `<footer>
    <div class="container footer-inner">
      <p>© ${new Date().getUTCFullYear()} health.md</p>
      <p><a href="${prefix}privacy-policy.html">Privacy</a> · <a href="${prefix}terms-of-service.html">Terms</a></p>
    </div>
  </footer>
  <script src="${prefix}assets/analytics.js" defer></script>`;
}

function documentHead({ title, socialTitle = title, description, canonical, image, type = 'website', date, updated, depth = 1 }) {
  const prefix = depth === 2 ? '../../' : '../';
  const socialImage = image || `${SITE_URL}/assets/app-icon/icon_1024x1024.png`;
  const jsonLd = type === 'article'
    ? {
        '@context': 'https://schema.org',
        '@type': 'BlogPosting',
        headline: socialTitle,
        description,
        datePublished: isoDate(date),
        dateModified: isoDate(updated),
        author: { '@type': 'Person', name: 'Cody Bontecou' },
        publisher: { '@type': 'Organization', name: 'Health.md', url: SITE_URL },
        image: socialImage,
        mainEntityOfPage: canonical,
      }
    : {
        '@context': 'https://schema.org',
        '@type': 'Blog',
        name: title,
        description,
        url: canonical,
      };

  return `<meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>${escapeHtml(title)}</title>
  <meta name="description" content="${escapeHtml(description)}">
  <link rel="canonical" href="${escapeHtml(canonical)}">
  <meta name="robots" content="index,follow">
  <meta name="theme-color" content="#6d4aff">
  <meta property="og:type" content="${type}">
  <meta property="og:site_name" content="Health.md">
  <meta property="og:title" content="${escapeHtml(socialTitle)}">
  <meta property="og:description" content="${escapeHtml(description)}">
  <meta property="og:url" content="${escapeHtml(canonical)}">
  <meta property="og:image" content="${escapeHtml(socialImage)}">
  ${type === 'article' ? `<meta property="article:published_time" content="${isoDate(date)}">` : ''}
  <meta name="twitter:card" content="${image ? 'summary_large_image' : 'summary'}">
  <meta name="twitter:title" content="${escapeHtml(socialTitle)}">
  <meta name="twitter:description" content="${escapeHtml(description)}">
  <meta name="twitter:image" content="${escapeHtml(socialImage)}">
  <link rel="icon" href="${prefix}favicon.ico" sizes="any">
  <link rel="apple-touch-icon" sizes="180x180" href="${prefix}assets/app-icon/icon_180x180.png">
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=IBM+Plex+Mono:wght@400;500;600;700&family=IBM+Plex+Sans:wght@400;500;600;700&family=IBM+Plex+Serif:wght@500;600;700&display=swap" rel="stylesheet">
  <script src="${prefix}assets/theme.js"></script>
  <link rel="stylesheet" href="${depth === 2 ? '../styles.css' : 'styles.css'}">
  <link rel="stylesheet" href="${prefix}assets/theme-icons.css">
  <script type="application/ld+json">${escapeJsonForHtml(jsonLd)}</script>`;
}

function renderIndex(posts) {
  const cards = posts.map((post) => {
    const image = post.image
      ? `<img src="${escapeHtml(post.image)}" loading="lazy" decoding="async" alt="${escapeHtml(post.imageAlt)}">`
      : '';
    return `<a class="post-card${post.image ? '' : ' post-card--text'}" href="${escapeHtml(post.slug)}/">
          <div>
            <span class="post-meta">${escapeHtml(formatDate(post.date))} · ${escapeHtml(post.category)}</span>
            <h2>${escapeHtml(post.title)}</h2>
            <p>${escapeHtml(post.description)}</p>
          </div>
          ${image}
        </a>`;
  }).join('\n        ');

  const title = 'Health.md Blog — Product Updates and Workflows';
  const description = 'Product updates, release notes, and workflow articles for Health.md Apple Health exports, Obsidian workflows, and local-first data archives.';

  return `<!DOCTYPE html>
<html lang="en">
<head>
  ${documentHead({ title, description, canonical: `${SITE_URL}/blog/` })}
</head>
<body>
  ${headerHtml()}
  <main>
    <section class="hero">
      <div class="container hero-grid">
        <div>
          <span class="eyebrow">Product updates</span>
          <h1>Release notes and workflow ideas for Health.md.</h1>
          <p>New app features, workflow changes, and practical examples for Apple Health, Obsidian, and local data export systems.</p>
        </div>
        <figure class="hero-shot">
          <img src="../assets/screenshots/optimized/macos-track-every-export-1200.webp" width="1200" height="750" loading="eager" decoding="async" alt="Health.md export history on Mac">
        </figure>
      </div>
    </section>
    <section class="posts">
      <div class="container post-list">
        ${cards || '<p>No posts have been published yet.</p>'}
      </div>
    </section>
  </main>
  ${footerHtml()}
</body>
</html>
`;
}

async function renderPost(post) {
  const canonical = `${SITE_URL}/blog/${post.slug}/`;
  const bodyHtml = sanitizeRenderedMarkdown(await marked.parse(post.body));
  const cover = post.image && post.showCover
    ? `<figure class="article-cover"><img src="${escapeHtml(post.image)}" alt="${escapeHtml(post.imageAlt)}"></figure>`
    : '';
  const tags = post.tags.length
    ? `<div class="article-tags" aria-label="Tags">${post.tags.map((tag) => `<span>${escapeHtml(tag)}</span>`).join('')}</div>`
    : '';

  return `<!DOCTYPE html>
<html lang="en">
<head>
  ${documentHead({
    title: `${post.title} | Health.md Blog`,
    socialTitle: post.title,
    description: post.description,
    canonical,
    image: post.image,
    type: 'article',
    date: post.date,
    updated: post.updated,
    depth: 2,
  })}
</head>
<body>
  ${headerHtml(2)}
  <main class="article">
    <span class="eyebrow">${escapeHtml(formatDate(post.date))} · ${escapeHtml(post.category)}</span>
    <h1>${escapeHtml(post.title)}</h1>
    <p class="lead">${escapeHtml(post.lead)}</p>
    ${cover}
    <div class="article-body">${bodyHtml}</div>
    ${tags}
  </main>
  ${footerHtml(2)}
</body>
</html>
`;
}

function updateSitemap(source, posts) {
  const withoutOldBlogUrls = source.replace(
    /\s*<url>\s*<loc>https:\/\/healthmd\.app\/blog(?:\/[^<]*)?<\/loc>[\s\S]*?<\/url>/g,
    '',
  );
  const anchor = '  <!-- BEGIN GENERATED VISUALIZATION URLS -->';
  if (!withoutOldBlogUrls.includes(anchor)) {
    throw new Error('sitemap.xml is missing the generated visualization marker');
  }

  const latest = posts[0] ? isoDate(posts[0].updated) : isoDate(new Date());
  const urls = [
    `  <!-- BEGIN GENERATED BLOG URLS -->`,
    `  <url>\n    <loc>${SITE_URL}/blog/</loc>\n    <lastmod>${latest}</lastmod>\n    <changefreq>weekly</changefreq>\n    <priority>0.7</priority>\n  </url>`,
    ...posts.map((post) => `  <url>\n    <loc>${SITE_URL}/blog/${post.slug}/</loc>\n    <lastmod>${isoDate(post.updated)}</lastmod>\n    <changefreq>monthly</changefreq>\n    <priority>0.6</priority>\n  </url>`),
    `  <!-- END GENERATED BLOG URLS -->`,
    '',
  ].join('\n');

  return withoutOldBlogUrls.replace(anchor, `${urls}${anchor}`);
}

export async function buildBlog({ outputRoot = ROOT } = {}) {
  const posts = await loadPosts();
  const blogOutput = path.join(outputRoot, 'blog');
  await fs.mkdir(blogOutput, { recursive: true });
  await fs.copyFile(path.join(ROOT, 'blog', 'styles.css'), path.join(blogOutput, 'styles.css'));
  await fs.writeFile(path.join(blogOutput, 'index.html'), renderIndex(posts));

  for (const post of posts) {
    const postOutput = path.join(blogOutput, post.slug);
    await fs.mkdir(postOutput, { recursive: true });
    await fs.writeFile(path.join(postOutput, 'index.html'), await renderPost(post));
  }

  const sitemapSource = await fs.readFile(path.join(ROOT, 'sitemap.xml'), 'utf8');
  await fs.writeFile(path.join(outputRoot, 'sitemap.xml'), updateSitemap(sitemapSource, posts));
  return posts;
}

const isDirectRun = process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (isDirectRun) {
  const outputFlag = process.argv.indexOf('--output');
  const outputRoot = outputFlag >= 0 && process.argv[outputFlag + 1]
    ? path.resolve(process.argv[outputFlag + 1])
    : ROOT;
  const posts = await buildBlog({ outputRoot });
  console.log(`Built ${posts.length} Health.md blog post${posts.length === 1 ? '' : 's'} in ${outputRoot}`);
}
