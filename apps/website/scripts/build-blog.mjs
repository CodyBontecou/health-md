#!/usr/bin/env node
import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import matter from 'gray-matter';
import { marked } from 'marked';
import sanitizeHtml from 'sanitize-html';
import { parseDocument, DomUtils } from 'htmlparser2';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const SITE_URL = 'https://healthmd.app';
const CONTENT_DIR = path.join(ROOT, 'content', 'blog');
const BLOG_AUTHOR = {
  '@type': 'Person',
  name: 'Cody Bontecou',
  url: `${SITE_URL}/about/#team-behind-healthmd`,
};

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

// Input has already passed through sanitizeRenderedMarkdown. Parse headings so
// inline markup, entities and existing author-defined anchors stay intact.
export function addArticleContents(bodyHtml) {
  const document = parseDocument(bodyHtml);
  const elements = DomUtils.findAll(() => true, document.children);
  const usedIds = new Set(['article-contents-title', 'related-guides-title']);
  for (const element of elements) {
    const id = element.attribs.id;
    if (!id) continue;
    if (usedIds.has(id)) throw new Error(`Duplicate or reserved article ID: ${id}`);
    usedIds.add(id);
  }
  const sections = [];
  for (const heading of elements.filter(element => element.name === 'h2')) {
    const title = DomUtils.textContent(heading).replace(/\s+/g, ' ').trim();
    if (!title) continue;
    if (!heading.attribs.id) {
      const base = `section-${slugify(title) || 'overview'}`;
      let id = base;
      let suffix = 2;
      while (usedIds.has(id)) id = `${base}-${suffix++}`;
      heading.attribs.id = id;
      usedIds.add(id);
    }
    sections.push({ id: heading.attribs.id, title });
  }
  const navigation = sections.length >= 5
    ? `<nav class="article-contents" aria-labelledby="article-contents-title">
      <h2 id="article-contents-title">On this page</h2>
      <ul>${sections.map(({ id, title }) => `<li><a href="#${escapeHtml(encodeURIComponent(id))}">${escapeHtml(title)}</a></li>`).join('')}</ul>
    </nav>`
    : '';
  return { html: DomUtils.getInnerHTML(document, { encodeEntities: 'utf8' }), navigation };
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
    const platform = parsed.data.platform ?? 'apple';
    if (!['apple', 'android', 'both'].includes(platform)) {
      throw new Error(`${filename}: platform must be apple, android or both`);
    }

    posts.push({
      slug,
      title,
      description,
      lead: String(parsed.data.lead || description).trim(),
      category: String(parsed.data.category || 'Health.md').trim(),
      date,
      updated,
      image,
      platform,
      imageAlt: String(parsed.data.imageAlt || title).trim(),
      showCover: parsed.data.showCover !== false,
      tags: asStringArray(parsed.data.tags),
      related: parsed.data.related ?? [],
      body: parsed.content.trim(),
    });
  }

  return posts.sort((a, b) => b.date.getTime() - a.date.getTime());
}

// Resolve curated slugs against published content so drafts and typos cannot
// become recommendations. Titles and descriptions stay owned by each target.
export function resolveRelatedGuides(posts) {
  const bySlug = new Map(posts.map(post => [post.slug, post]));
  if (bySlug.size !== posts.length) throw new Error('Blog posts must have unique slugs');
  return new Map(posts.map(post => {
    const slugs = post.related ?? [];
    if (!Array.isArray(slugs) || slugs.length > 3) {
      throw new Error(`${post.slug}: related must be an array of at most three published slugs`);
    }
    if (new Set(slugs).size !== slugs.length) {
      throw new Error(`${post.slug}: related guides must not contain duplicates`);
    }
    return [post.slug, slugs.map(slug => {
      if (typeof slug !== 'string' || slug === post.slug || !bySlug.has(slug)) {
        throw new Error(`${post.slug}: invalid related guide ${String(slug)}`);
      }
      return bySlug.get(slug);
    })];
  }));
}

function headerHtml(depth = 1, platform = 'apple') {
  const prefix = depth === 2 ? '../../' : '../';
  const store = platform === 'android'
    ? { url: 'https://play.google.com/store/apps/details?id=com.healthmd.android', label: 'Google Play' }
    : { url: 'https://apps.apple.com/us/app/health-md/id6757763969', label: 'App Store' };
  const storeLinks = platform === 'both'
    ? '<a href="https://apps.apple.com/us/app/health-md/id6757763969" target="_blank" rel="noopener">App Store</a><a href="https://play.google.com/store/apps/details?id=com.healthmd.android" target="_blank" rel="noopener">Google Play</a>'
    : `<a href="${store.url}" target="_blank" rel="noopener">${store.label}</a>`;
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
          ${storeLinks}
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

function documentHead({ title, socialTitle = title, description, canonical, image, type = 'website', date, updated, depth = 1, breadcrumbs }) {
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
        author: BLOG_AUTHOR,
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
  const breadcrumbJsonLd = breadcrumbs && {
    '@context': 'https://schema.org',
    '@type': 'BreadcrumbList',
    itemListElement: breadcrumbs.map(({ name, url }, index) => ({
      '@type': 'ListItem', position: index + 1, name, item: url,
    })),
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
  ${type === 'article' ? `<meta property="article:modified_time" content="${isoDate(updated)}">` : ''}
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
  <link rel="stylesheet" href="${depth === 2 ? '../styles.css' : 'styles.css'}?v=20261030-header-wrap">
  <link rel="stylesheet" href="${prefix}assets/theme-icons.css">
  <script type="application/ld+json">${escapeJsonForHtml(jsonLd)}</script>${breadcrumbJsonLd ? `
  <script type="application/ld+json">${escapeJsonForHtml(breadcrumbJsonLd)}</script>` : ''}`;
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
  ${headerHtml(1, 'both')}
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
        <article><h3>CSV analysis</h3><p>Export selected dates, inspect a sample, and analyze CSV in a spreadsheet or a local Python script.</p><a href="/apple-health-to-csv/">Export Apple Health to CSV</a><a href="/apple-health-to-csv/#combine-csv-files">Combine daily CSV files</a><a href="/blog/apple-health-to-excel/">Analyze Apple Health in Excel</a><a href="/blog/apple-health-to-google-sheets/">Analyze Apple Health in Google Sheets</a><a href="/blog/apple-health-to-python/">Analyze Apple Health with Python</a><a href="/blog/export-apple-health-steps-data/">Export steps data</a><a href="/blog/export-apple-health-sleep-data/">Export sleep data</a><a href="/blog/export-apple-health-workouts/">Export workout data</a><a href="/blog/export-apple-health-heart-rate/">Export heart rate data</a><a href="/blog/export-apple-health-hrv/">Export HRV data</a></article>
        <article><h3>Obsidian</h3><p>Write health notes to your vault or add selected metrics to existing daily notes.</p><a href="/blog/export-apple-health-data-to-obsidian/">Apple Health to Obsidian</a><a href="/blog/export-health-connect-to-obsidian/">Health Connect to Obsidian</a><a href="/blog/health-md-for-macos/">Export Apple Health to a Mac vault</a></article>
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

async function renderPost(post, relatedGuides) {
  const canonical = `${SITE_URL}/blog/${post.slug}/`;
  const published = isoDate(post.date);
  const updated = isoDate(post.updated);
  const byline = `<p class="article-byline">
      <span>By <a href="${escapeHtml(BLOG_AUTHOR.url)}" rel="author">${escapeHtml(BLOG_AUTHOR.name)}</a></span>
      <span>Published <time datetime="${published}">${escapeHtml(formatDate(post.date))}</time></span>${updated !== published ? `
      <span>Updated <time datetime="${updated}">${escapeHtml(formatDate(post.updated))}</time></span>` : ''}
    </p>`;
  const breadcrumbs = [
    { name: 'Health.md', url: `${SITE_URL}/` },
    { name: 'Guides', url: `${SITE_URL}/blog/` },
    { name: post.title, url: canonical },
  ];
  const breadcrumbNav = `<nav class="article-breadcrumbs" aria-label="Breadcrumb">
      <ol>${breadcrumbs.map(({ name, url }, index) => `<li>${index ? '<span aria-hidden="true">/</span>' : ''}${index === breadcrumbs.length - 1
        ? `<span aria-current="page">${escapeHtml(name)}</span>`
        : `<a href="${escapeHtml(url)}">${escapeHtml(name)}</a>`}</li>`).join('')}</ol>
    </nav>`;
  const body = addArticleContents(sanitizeRenderedMarkdown(await marked.parse(post.body)));
  const cover = post.image && post.showCover
    ? `<figure class="article-cover"><img src="${escapeHtml(post.image)}" alt="${escapeHtml(post.imageAlt)}"></figure>`
    : '';
  const tags = post.tags.length
    ? `<div class="article-tags" aria-label="Tags">${post.tags.map((tag) => `<span>${escapeHtml(tag)}</span>`).join('')}</div>`
    : '';
  const relatedNav = relatedGuides.length
    ? `<nav class="article-related" aria-labelledby="related-guides-title">
      <h2 id="related-guides-title">Continue with a related guide</h2>
      <ul>${relatedGuides.map(guide => `<li><a href="/blog/${escapeHtml(guide.slug)}/">${escapeHtml(guide.title)}</a><p>${escapeHtml(guide.description)}</p></li>`).join('')}</ul>
    </nav>`
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
    breadcrumbs,
  })}
</head>
<body>
  ${headerHtml(2, post.platform)}
  <main class="article">
    ${breadcrumbNav}
    <span class="eyebrow">${escapeHtml(post.category)}</span>
    <h1>${escapeHtml(post.title)}</h1>
    ${byline}
    <p class="lead">${escapeHtml(post.lead)}</p>
    ${body.navigation}
    ${cover}
    <div class="article-body">${body.html}</div>
    ${tags}
    ${relatedNav}
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
  const relatedGuides = resolveRelatedGuides(posts);
  const blogOutput = path.join(outputRoot, 'blog');
  await fs.mkdir(blogOutput, { recursive: true });
  await fs.copyFile(path.join(ROOT, 'blog', 'styles.css'), path.join(blogOutput, 'styles.css'));
  await fs.writeFile(path.join(blogOutput, 'index.html'), renderIndex(posts));

  for (const post of posts) {
    const postOutput = path.join(blogOutput, post.slug);
    await fs.mkdir(postOutput, { recursive: true });
    await fs.writeFile(path.join(postOutput, 'index.html'), await renderPost(post, relatedGuides.get(post.slug)));
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
