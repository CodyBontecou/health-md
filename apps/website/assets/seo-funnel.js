import { FUNNEL_ENDPOINT, funnelPage, validFunnelEvent } from './funnel-contract.js';

const SEARCH_DOMAINS = ['google.com', 'google.co.uk', 'google.de', 'google.fr', 'google.es', 'google.it', 'google.co.jp', 'google.co.in', 'google.com.au', 'bing.com', 'duckduckgo.com', 'search.yahoo.com', 'search.brave.com', 'ecosia.org', 'baidu.com', 'yandex.com', 'yandex.ru'];
const CSV_FILES = Object.freeze({
  '/docs/reference/generated/core/summary-day.csv': 'summary_csv',
  '/assets/samples/health-data-sample.csv': 'homepage_csv',
  '/assets/samples/apple-health-sleep-excerpt.csv': 'sleep_csv',
  '/assets/samples/health-connect-summary-excerpt.csv': 'android_csv',
});
const started = new WeakSet();

export function funnelSource(href, referrer) {
  if (new URL(href).searchParams.has('utm_campaign')) return 'campaign';
  if (!referrer) return 'direct';
  try {
    const host = new URL(referrer).hostname;
    if (host === 'healthmd.app' || host === 'www.healthmd.app') return 'internal';
    if (SEARCH_DOMAINS.some(domain => host === domain || host.endsWith('.' + domain))) return 'search_referral';
  } catch { return 'other_referral'; }
  return 'other_referral';
}

export function funnelLink(href, origin) {
  let url;
  try { url = new URL(href, origin); } catch { return null; }
  if (url.protocol !== 'https:') return null;
  if (url.origin === origin) {
    if (Object.hasOwn(CSV_FILES, url.pathname)) return { action: 'csv_sample_download', target: CSV_FILES[url.pathname] };
    if (url.pathname === '/assets/downloads/healthmd-obsidian-starter.zip') return { action: 'starter_vault_download', target: 'starter_vault' };
  }
  if (url.hostname === 'apps.apple.com' && /\/id6757763969\/?$/.test(url.pathname)) return { action: 'store_click', target: 'app_store' };
  if (url.hostname === 'play.google.com' && url.pathname === '/store/apps/details' && url.searchParams.get('id') === 'com.healthmd.android') return { action: 'store_click', target: 'google_play' };
  if (url.hostname === 'f-droid.org' && url.pathname === '/packages/com.healthmd.android/') return { action: 'store_click', target: 'f_droid' };
  return null;
}

function placement(anchor) {
  if (anchor.closest('header')) return 'header';
  if (anchor.closest('footer')) return 'footer';
  if (anchor.closest('.csv-final-action, .download-cta')) return 'final';
  if (anchor.closest('.about-hero, .hero')) return 'hero';
  return 'body';
}

export function startFunnel(win) {
  const doc = win.document, nav = win.navigator;
  if (!['healthmd.app', 'www.healthmd.app'].includes(win.location.hostname) || win.location.protocol !== 'https:' ||
      nav.globalPrivacyControl === true || nav.doNotTrack === '1' || win.doNotTrack === '1' || started.has(doc)) return;
  const page = funnelPage(win.location.pathname);
  if (!page) return;
  started.add(doc);
  const source = funnelSource(win.location.href, doc.referrer);
  let sent = 0;
  function send(action, target, position) {
    const payload = { v: 1, ...page, source, action, target, placement: position };
    if (!validFunnelEvent(payload) || sent >= 100) return;
    sent++;
    // Keep navigation native; no retry, cookies, referrer URL, storage or visitor ID.
    try {
      win.fetch(FUNNEL_ENDPOINT, {
        // CORS mode preserves Origin under no-referrer in Fetch-compliant browsers.
        // The URL remains same-origin; the collector rejects cross-origin requests.
        method: 'POST', mode: 'cors', credentials: 'omit', keepalive: true,
        referrerPolicy: 'no-referrer', headers: { 'content-type': 'application/json' },
        body: JSON.stringify(payload),
      }).catch(function () {});
    } catch { /* Analytics must never interrupt the requested action. */ }
  }
  function clicked(event) {
    if (!event.isTrusted ||
        (event.type === 'click' ? event.button !== 0 : event.button !== 1)) return;
    const anchor = event.target?.closest?.('a[href]');
    if (!anchor) return;
    // The homepage's primary click handler prevents navigation when exporting
    // several formats, then activates separate links programmatically. Count the
    // selected CSV once from the original activation, never those synthetic clicks.
    if (page.page === 'home' && anchor.matches('[data-sample-download]') && event.type === 'click') {
      if (doc.querySelector('[data-export-format="csv"][aria-pressed="true"]')) send('csv_sample_download', 'homepage_csv', 'body');
      return;
    }
    if (event.defaultPrevented) return;
    const link = funnelLink(anchor.href, win.location.origin);
    if (link) send(link.action, link.target, placement(anchor));
  }
  doc.addEventListener('click', clicked);
  doc.addEventListener('auxclick', clicked);
  send('page_view', 'none', 'page');
}

if (typeof window !== 'undefined') startFunnel(window);
