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
      div: ['aria-label', 'tabindex'],
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

function formatDate(date, { shortMonth = false } = {}) {
  return new Intl.DateTimeFormat('en-US', {
    timeZone: 'UTC',
    year: 'numeric',
    month: shortMonth ? 'short' : 'long',
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
      <a class="brand" href="${prefix}">
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
  const items = posts.map((post) => {
    const tags = post.tags.length
      ? `\n            <div class="post-item__tags">${post.tags.map((tag) => `#${escapeHtml(tag)}`).join(' ')}</div>`
      : '';
    return `<li class="post-item">
          <div class="post-item__main">
            <a class="post-item__title" href="${escapeHtml(post.slug)}/">${escapeHtml(post.title)}</a>${tags}
          </div>
          <time class="post-item__date" datetime="${isoDate(post.date)}">${escapeHtml(formatDate(post.date, { shortMonth: true }))}</time>
        </li>`;
  }).join('\n        ');

  const title = 'Health.md Guides — Export, Obsidian and Automation';
  const description = 'Practical guides to exporting Apple Health and Health Connect data, opening CSV files, updating Obsidian notes, and automating your own health-data workflows.';

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
          <span class="eyebrow">Health data guides</span>
          <h1>Put your health data where you can use it.</h1>
          <p>Start with one useful export, then connect your spreadsheet, Obsidian vault, or agent. Choose a workflow below, or browse the latest articles.</p>
        </div>
      </div>
    </section>
    <section class="workflow-directory container" aria-labelledby="workflow-heading">
      <h2 id="workflow-heading">Choose your first workflow</h2>
      <div class="workflow-grid">
        <article><h3>Spreadsheets</h3><p>Export selected dates, inspect a sample, and import CSV into Excel, Sheets, or Numbers.</p><a href="/apple-health-to-csv/">Export Apple Health to CSV</a><a href="/blog/apple-health-to-excel/">Analyze Apple Health in Excel</a><a href="/blog/apple-health-to-google-sheets/">Analyze Apple Health in Google Sheets</a><a href="/blog/export-apple-health-steps-data/">Export steps data</a><a href="/blog/export-apple-health-sleep-data/">Export sleep data</a><a href="/blog/export-apple-health-workouts/">Export workout data</a><a href="/blog/export-apple-health-heart-rate/">Export heart rate data</a><a href="/blog/export-apple-health-hrv/">Export HRV data</a></article>
        <article><h3>Obsidian</h3><p>Write health notes to your vault or add selected metrics to existing daily notes.</p><a href="/blog/export-apple-health-data-to-obsidian/">Apple Health to Obsidian</a><a href="/blog/export-health-connect-to-obsidian/">Health Connect to Obsidian</a></article>
        <article><h3>Android</h3><p>Authorize Health Connect, choose a folder, and verify your first exported file.</p><a href="/health-connect-export/">Start an Android export</a></article>
        <article><h3>Reports, automation and agents</h3><p>Create a PDF report, set up scheduled files, or choose an agent workflow with its device requirements.</p><a href="/docs/scheduling/">Set up scheduled exports</a><a href="/blog/export-health-data-without-the-cloud/">Export without cloud storage</a><a href="/blog/export-apple-health-data-pdf/">Create a health summary PDF</a><a href="/health-data-for-ai/">Use health data with AI</a><a href="/blog/analyze-apple-health-with-claude/">Analyze Apple Health with Claude</a><a href="/blog/apple-health-to-chatgpt/">Analyze Apple Health with ChatGPT</a></article>
      </div>
      <p><a href="/apple-health-export/">Compare Apple Health export workflows</a>, <a href="/blog/apple-health-xml-export/">open an Apple Health XML archive</a>, <a href="/blog/health-md-vs-health-auto-export/">compare Health.md and Health Auto Export</a>, or <a href="/docs/troubleshooting/">troubleshoot an export</a>.</p>
    </section>
    <section class="posts" aria-labelledby="latest-articles">
      <h2 class="container" id="latest-articles">Latest articles and product updates</h2>
      <ul class="container post-list">
        ${items || '<li class="post-item">No posts have been published yet.</li>'}
      </ul>
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
