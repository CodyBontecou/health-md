import assert from 'node:assert/strict';
import test from 'node:test';
import { mkdtemp, readFile, rm } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { parseDocument, DomUtils } from 'htmlparser2';
import { addArticleContents, buildBlog } from '../scripts/build-blog.mjs';

const elements = html => DomUtils.findAll(() => true, parseDocument(html).children);
const headings = html => elements(html).filter(element => element.name === 'h2');
const links = html => elements(html).filter(element => element.name === 'a');

test('contents preserves authored IDs, reserves existing targets, and disambiguates repeated headings', () => {
  const source = '<div id="section-export"></div><h2>Export</h2><h2>Export</h2><h2 id="custom &amp; scope">Dates &amp; units</h2><h2>Files</h2><h2>Notes</h2>';
  const result = addArticleContents(source);
  assert.deepEqual(headings(result.html).map(heading => heading.attribs.id), [
    'section-export-2', 'section-export-3', 'custom & scope', 'section-files', 'section-notes',
  ]);
  assert.deepEqual(links(result.navigation).map(link => decodeURIComponent(link.attribs.href.slice(1))), headings(result.html).map(heading => heading.attribs.id));
  assert.deepEqual(addArticleContents(result.html), result, 'reprocessing keeps the same fragment URLs');
});

test('contents labels retain readable inline text without nested links or executable markup', () => {
  const source = '<h2>Use <a href="/docs/">docs</a> &amp; <code>CSV</code></h2><h2>&lt;img src=x onerror=alert(1)&gt;</h2><h2>Three</h2><h2>Four</h2><h2>Five</h2><h3>Subsection</h3><pre><code>&lt;h2&gt;Not a heading&lt;/h2&gt;</code></pre>';
  const result = addArticleContents(source);
  assert.equal(links(result.navigation).length, 5, 'only main sections are listed');
  assert.equal(DomUtils.textContent(links(result.navigation)[0]), 'Use docs & CSV');
  assert.equal(DomUtils.textContent(links(result.navigation)[1]), '<img src=x onerror=alert(1)>');
  assert.ok(elements(result.navigation).every(element => !['img', 'script', 'code'].includes(element.name)));
  for (const link of links(result.navigation)) assert.equal(links(DomUtils.getInnerHTML(link)).length, 0);
  assert.ok(result.html.includes('&lt;h2&gt;Not a heading&lt;/h2&gt;'));
});

test('short articles get stable anchors without a redundant contents list', () => {
  const result = addArticleContents('<h2>Overview</h2><p>Short guide.</p><h2>Next step</h2>');
  assert.equal(result.navigation, '');
  assert.equal(headings(result.html).length, 2);
  assert.ok(headings(result.html).every(heading => heading.attribs.id));
});

test('ambiguous authored or template IDs fail instead of generating broken navigation', () => {
  for (const source of ['<div id="same"></div><h2 id="same">Two</h2>', '<h2 id="article-contents-title">Reserved</h2>', '<div id="related-guides-title"></div>']) {
    assert.throws(() => addArticleContents(source), /Duplicate or reserved article ID/);
  }
});

test('published long guides have one matching link per main section and retain existing Obsidian targets', async t => {
  const outputRoot = await mkdtemp(path.join(os.tmpdir(), 'healthmd-contents-'));
  t.after(() => rm(outputRoot, { recursive: true, force: true }));
  const posts = await buildBlog({ outputRoot });
  let longGuides = 0;
  let shortGuides = 0;
  for (const post of posts) {
    const html = await readFile(path.join(outputRoot, 'blog', post.slug, 'index.html'), 'utf8');
    const nodes = elements(html);
    const body = nodes.find(node => node.attribs.class === 'article-body');
    const sections = headings(DomUtils.getInnerHTML(body));
    const nav = nodes.find(node => node.attribs.class === 'article-contents');
    const ids = nodes.map(node => node.attribs.id).filter(Boolean);
    assert.equal(new Set(ids).size, ids.length, post.slug);
    assert.ok(sections.every(section => section.attribs.id));
    if (sections.length >= 5) {
      longGuides++;
      assert.ok(nav, post.slug);
      const navLinks = links(DomUtils.getInnerHTML(nav));
      assert.deepEqual(navLinks.map(link => decodeURIComponent(link.attribs.href.slice(1))), sections.map(section => section.attribs.id));
      assert.deepEqual(navLinks.map(link => DomUtils.textContent(link)), sections.map(section => DomUtils.textContent(section).replace(/\s+/g, ' ').trim()));
    } else {
      shortGuides++;
      assert.ok(!nav, post.slug);
    }
    if (post.slug === 'export-apple-health-data-to-obsidian') {
      assert.ok(ids.includes('starter-vault'));
      assert.ok(ids.includes('your-first-note'));
    }
  }
  assert.ok(longGuides > 0 && shortGuides > 0);
});
