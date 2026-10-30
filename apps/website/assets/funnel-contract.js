// Shared browser/collector vocabulary. No free-text or visitor identifiers.
export const FUNNEL_ENDPOINT = '/v1/web-events';
export const FUNNEL_PAGES = Object.freeze({
  home: '/', csv: '/apple-health-to-csv/',
  obsidian: '/blog/export-apple-health-data-to-obsidian/',
  export: '/apple-health-export/', guides: '/blog/', ai: '/health-data-for-ai/',
  android_export: '/health-connect-export/',
  android_obsidian: '/blog/export-health-connect-to-obsidian/',
  excel: '/blog/apple-health-to-excel/', sheets: '/blog/apple-health-to-google-sheets/',
  sleep: '/blog/export-apple-health-sleep-data/', steps: '/blog/export-apple-health-steps-data/',
  heart_rate: '/blog/export-apple-health-heart-rate/', hrv: '/blog/export-apple-health-hrv/',
  workouts: '/blog/export-apple-health-workouts/', pdf: '/blog/export-apple-health-data-pdf/',
  claude: '/blog/analyze-apple-health-with-claude/', chatgpt: '/blog/apple-health-to-chatgpt/',
  local_export: '/blog/export-health-data-without-the-cloud/',
  auto_export_comparison: '/blog/health-md-vs-health-auto-export/',
  xml_export: '/blog/apple-health-xml-export/',
  mac_export: '/blog/health-md-for-macos/',
  python: '/blog/apple-health-to-python/',
  blood_pressure: '/blog/export-apple-health-blood-pressure/',
  weight: '/blog/export-apple-health-weight-data/',
  samsung_export: '/blog/export-samsung-health-data/',
  garmin_export: '/blog/export-garmin-connect-data/',
  fitbit_export: '/blog/export-fitbit-data/',
  oura_export: '/blog/export-oura-data/',
  whoop_export: '/blog/export-whoop-data/',
  withings_export: '/blog/export-withings-data/',
  strava_export: '/blog/export-strava-data/',
  cronometer_export: '/blog/export-cronometer-data/',
  myfitnesspal_export: '/blog/export-myfitnesspal-data/',
  google_fit_export: '/blog/export-google-fit-data/',
  polar_export: '/blog/export-polar-flow-data/',
  zepp_export: '/blog/export-zepp-amazfit-data/',
  home_assistant: '/blog/apple-health-home-assistant/',
});
export const FUNNEL_LOCALES = Object.freeze(['en', 'es', 'de', 'fr', 'pt-br', 'it', 'nl', 'ja', 'ko', 'zh-hans']);
export const FUNNEL_ACTIONS = Object.freeze({
  page_view: ['none'],
  csv_sample_download: ['summary_csv', 'homepage_csv', 'sleep_csv', 'android_csv'],
  starter_vault_download: ['starter_vault'],
  store_click: ['app_store', 'google_play', 'f_droid'],
});
export const FUNNEL_SOURCES = Object.freeze(['search_referral', 'internal', 'other_referral', 'direct', 'campaign']);
export const FUNNEL_PLACEMENTS = Object.freeze(['page', 'hero', 'body', 'header', 'footer', 'final']);
const FIELDS = ['v', 'page', 'locale', 'action', 'target', 'placement', 'source'];

export function validFunnelEvent(event) {
  if (!event || typeof event !== 'object' || Array.isArray(event)) return false;
  const keys = Object.keys(event);
  return keys.length === FIELDS.length && keys.every(key => FIELDS.includes(key)) &&
    event.v === 1 && FIELDS.slice(1).every(key => typeof event[key] === 'string') &&
    Object.hasOwn(FUNNEL_PAGES, event.page) &&
    FUNNEL_LOCALES.includes(event.locale) && (event.locale === 'en' || event.page === 'home') &&
    Object.hasOwn(FUNNEL_ACTIONS, event.action) &&
    FUNNEL_ACTIONS[event.action].includes(event.target) &&
    FUNNEL_PLACEMENTS.includes(event.placement) && FUNNEL_SOURCES.includes(event.source) &&
    ((event.action === 'page_view') === (event.placement === 'page'));
}

export function funnelPage(pathname) {
  let locale = 'en';
  const first = pathname.split('/')[1];
  if (first !== 'en' && FUNNEL_LOCALES.includes(first)) {
    locale = first;
    pathname = pathname.slice(first.length + 1) || '/';
  }
  // Only the homepage is translated today; do not invent translated guide routes.
  if (locale !== 'en' && pathname !== '/') return null;
  const page = Object.keys(FUNNEL_PAGES).find(id => FUNNEL_PAGES[id] === pathname);
  return page ? { page, locale } : null;
}
