#!/usr/bin/env node
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import sanitizeHtml from 'sanitize-html';
import { defaultLocale, publishedLocales } from '../i18n/locales.mjs';
import { routePath } from '../i18n/routes.mjs';
import { loadCatalog } from './build-localized-pages.mjs';
import { renderLocalizedSitemap } from './build-localized-sitemap.mjs';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
export const publicPrivacyPages = [
  'about/index.html',
  'apple-health-export/index.html',
  'apple-health-to-csv/index.html',
  'health-data-for-ai/index.html',
];

// These global promises contradict the optional retained-export pilot. A
// statement scoped to the default/local path should say so explicitly.
const absoluteClaims = [
  /Health\.md\s+never\s+(?:stores?|retains?|keeps?)\s+(?:your\s+)?health\s+data/i,
  /Health\.md\s+does not\s+(?:store|retain|keep)\s+(?:your\s+)?health\s+data(?!\s+(?:by default|unless))/i,
  /Health\.md\s+does not keep\s+a\s+server-side\s+health\s+corpus/i,
  /\b(?:there is no|keeps no)\s+(?:Health\.md\s+)?health-data\s+cloud(?!\s+hop)/i,
  /\bHealth\.md\s+(?:does not|doesn't)\s+(?:operate|run|provide)\s+a\s+health-data\s+cloud/i,
  /Health\.md cloud copies\s*None\b/i,
  /there is no Health\.md cloud account for your health archive/i,
  /Health\.md (?:betreibt keine Cloud für Gesundheitsdaten|betreibt keinen Cloud-Dienst für Gesundheitsdaten)/i,
  /Health\.md (?:no opera una nube de datos de salud|no ofrece un servicio en la nube para datos de salud)/i,
  /Health\.md n[’']exploite (?:pas de (?:service )?cloud pour les données de santé|aucun cloud de données de santé)/i,
  /Health\.md non gestisce (?:alcun cloud di dati sanitari|un servizio cloud per i dati sanitari)/i,
  /Health\.md beheert geen cloud voor gezondheidsgegevens/i,
  /(?:O )?Health\.md não opera (?:uma nuvem de dados de saúde|um serviço de nuvem para dados de saúde)/i,
  /Health\.mdはヘルスデータ用クラウド(?:サービスを運営していません|を運用していません)/,
  /Health\.md는 건강 데이터 클라우드(?: 서비스를|를) 운영하지 않습니다/,
  /Health\.md 不(?:运营任何健康数据云端|运行健康数据云服务)/,
  /✓\s+(?:no Health\.md health-data cloud|keine Health\.md-Cloud für Gesundheitsdaten|sin nube de datos de salud de Health\.md|aucun cloud de données de santé Health\.md|nessun cloud di dati sanitari di Health\.md|geen Health\.md-cloud voor gezondheidsgegevens|sem nuvem de dados de saúde do Health\.md|Health\.mdのヘルスデータクラウドなし|Health\.md 건강 데이터 클라우드 없음|无 Health\.md 健康数据云端)/i,
];

// Meaning-level checks for the reviewed authored disclosures in every language:
// one owner, intentional uploads only, no public signup, no automatic device sync.
export const pilotBoundaryPatterns = {
  en: [/single-owner/i, /intentionally (?:uploaded|sent)/i, /no public signup/i, /no automatic device sync/i],
  de: [/nur für einen Eigentümer/i, /bewusst (?:hochgeladen|gesendet)/i, /keine öffentliche Registrierung/i, /keine automatische Gerätesynchronisierung/i],
  es: [/un único propietario/i, /(?:enviadas|cargadas) (?:de forma )?intencionalmente/i, /no (?:hay|ofrece) registro público/i, /(?:no hay|ni) sincronización automática de dispositivos/i],
  fr: [/un seul propriétaire/i, /(?:envoyés|téléversés) volontairement/i, /pas d’inscription publique/i, /(?:pas de|ni de) synchronisation automatique des appareils/i],
  it: [/un solo proprietario/i, /(?:inviate|caricate) intenzionalmente/i, /nessuna registrazione pubblica/i, /(?:nessuna|né) sincronizzazione automatica dei dispositivi/i],
  nl: [/één eigenaar/i, /bewust (?:geüploade|verstuurde)/i, /geen openbare registratie/i, /(?:geen|of) automatische apparaatsynchronisatie/i],
  'pt-br': [/um único proprietário/i, /(?:enviadas|carregadas) intencionalmente/i, /não há cadastro público/i, /(?:não há|nem) sincronização automática de dispositivos/i],
  ja: [/単一所有者/, /意図的に(?:アップロード|送信)した/, /一般公開の登録はありません/, /デバイスの自動同期(?:も|は)ありません/],
  ko: [/단일 소유자/, /의도적으로 업로드한/, /공개 가입은 없/, /기기 자동 동기화(?:도|는) 없/],
  'zh-hans': [/单一所有者/, /主动上传的/, /不开放公众注册/, /不自动同步设备/],
};

export function assertPilotBoundaries(copy, locale, label, { deviceSync = true } = {}) {
  const patterns = pilotBoundaryPatterns[locale];
  assert.ok(patterns, `Missing privacy review patterns for ${locale}`);
  for (const pattern of deviceSync ? patterns : patterns.slice(0, 3)) {
    assert.match(textContent(copy), pattern, `${label}: missing localized pilot boundary ${pattern}`);
  }
}

export function textContent(html) {
  return sanitizeHtml(html, { allowedTags: [], allowedAttributes: {} }).replace(/\s+/g, ' ').trim();
}

function stringsIn(value) {
  if (typeof value === 'string') return [value];
  if (value && typeof value === 'object') return Object.values(value).flatMap(stringsIn);
  return [];
}

export function assertPublicPrivacyCopy(html, label) {
  const schemas = [...html.matchAll(/<script\b[^>]*type="application\/ld\+json"[^>]*>([\s\S]*?)<\/script>/gi)]
    .map(([, json]) => JSON.parse(json));
  const body = html.replace(/<(script|style)\b[^>]*>[\s\S]*?<\/\1>/gi, '');
  const metadata = [...body.matchAll(/<meta\b[^>]*content="([^"]*)"[^>]*>/gi)].map(([, value]) => value);
  const copy = [textContent(body.replace(/<[^>]+>/g, ' ')), ...metadata, ...schemas.flatMap(stringsIn)].join('\n');
  for (const pattern of absoluteClaims) {
    assert.doesNotMatch(copy, pattern, `${label}: unqualified no-cloud promise`);
  }

  const visibleFaqs = new Map([...body.matchAll(/<h3\b[^>]*>([\s\S]*?)<\/h3>\s*<p\b[^>]*>([\s\S]*?)<\/p>/gi)]
    .map(([, question, answer]) => [textContent(question), textContent(answer)]));
  for (const schema of schemas) {
    for (const faq of (schema['@graph'] ?? [schema]).filter((entry) => entry['@type'] === 'FAQPage')) {
      for (const item of faq.mainEntity) {
        assert.equal(visibleFaqs.get(textContent(item.name)), textContent(item.acceptedAnswer.text),
          `${label}: visible and JSON-LD answers differ for ${item.name}`);
      }
    }
  }
}

async function publicFiles(directory, relative = '') {
  const files = [];
  for (const entry of await fs.readdir(directory, { withFileTypes: true })) {
    const child = path.join(relative, entry.name);
    if (entry.isDirectory()) files.push(...await publicFiles(path.join(directory, entry.name), child));
    else if (entry.isFile() && /\.(html|txt|md)$/.test(entry.name)) files.push(child);
  }
  return files.sort();
}

export async function checkBuiltPublicPrivacy(outputRoot) {
  const read = (file) => fs.readFile(path.join(outputRoot, file), 'utf8');
  const sitemap = await read('sitemap.xml');
  assert.equal(sitemap, renderLocalizedSitemap(sitemap), 'Built home/legal sitemap revision dates are stale');
  const dates = new Map([...sitemap.matchAll(/<url>([\s\S]*?)<\/url>/g)].map(([, entry]) => [
    entry.match(/<loc>([^<]+)<\/loc>/)[1], entry.match(/<lastmod>([^<]+)<\/lastmod>/)?.[1],
  ]));
  for (const route of ['privacy', 'terms']) {
    const file = routePath(route, defaultLocale).replace(/^\//, '');
    const visibleDate = (await read(file)).match(/Last updated: ([^<]+)</)[1];
    assert.equal(dates.get(`https://healthmd.app/${file}`), new Date(`${visibleDate} UTC`).toISOString().slice(0, 10),
      `${file}: built sitemap date does not match the visible legal revision`);
  }
  for (const slug of ['export-apple-health-data-to-obsidian', 'local-first-health-data-architecture']) {
    const source = await fs.readFile(path.join(ROOT, 'content/blog', `${slug}.md`), 'utf8');
    const updated = source.match(/^updated: "([^"]+)"$/m)[1].slice(0, 10);
    assert.equal(dates.get(`https://healthmd.app/blog/${slug}/`), updated, `${slug}: stale built blog revision date`);
    const file = path.join('blog', slug, 'index.html');
    assertPilotBoundaries(await read(file), defaultLocale, file);
  }
  for (const file of publicPrivacyPages) assertPilotBoundaries(await read(file), defaultLocale, file);
  for (const { code } of publishedLocales('landing')) {
    const route = routePath('home', code).replace(/^\//, '');
    const file = path.join(route, 'index.html');
    const [html, catalog] = await Promise.all([
      fs.readFile(path.join(outputRoot, file), 'utf8'), loadCatalog(code),
    ]);
    for (const key of ['trust', 'agentLede', 'meta.description']) {
      assert.ok(html.includes(catalog.landing.static[key]), `${file}: missing localized ${key} disclosure`);
    }
    assertPilotBoundaries(html, code, file, { deviceSync: false });
    for (const slug of ['android', 'guides/platform-features']) {
      const guide = path.join(route, 'docs', slug, 'index.html');
      const copy = await read(guide);
      assertPilotBoundaries(copy, code, guide);
      assert.ok(copy.includes('href="/privacy-policy.html"'), `${guide}: missing canonical privacy policy link`);
      const markdown = guide.replace(/index\.html$/, 'index.md');
      assertPilotBoundaries(await read(markdown), code, markdown);
    }
  }
  const cliIndex = await read('docs/cli/llms.txt');
  assertPilotBoundaries(cliIndex, defaultLocale, 'docs/cli/llms.txt');
  assert.equal(cliIndex, await fs.readFile(path.join(ROOT, 'docs-src/agent-docs/cli-llms.txt'), 'utf8'),
    'Built CLI agent index differs from its canonical authored source');
  const pages = await publicFiles(outputRoot);
  for (const file of pages) assertPublicPrivacyCopy(await read(file), file);
  assert.equal(publishedLocales('legal').map(({ code }) => code).join(','), defaultLocale,
    'Pilot-era legal translations require human review before publication');
  console.log(`Public privacy copy and FAQ parity audited on all ${pages.length} built HTML/text/Markdown pages; pilot boundaries verified in every landing/Android/platform locale.`);
}

const isDirectRun = process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (isDirectRun) await checkBuiltPublicPrivacy(path.join(ROOT, 'dist'));
