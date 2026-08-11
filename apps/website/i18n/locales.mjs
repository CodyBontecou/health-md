export const defaultLocale = 'en';

// Authored user guides are translated. Generated contract/reference pages remain
// canonical English artifacts and use the protected fallback route behavior.
export const authoredDocSlugs = Object.freeze([
  'docs',
  'docs/agent-api',
  'docs/agent-queries',
  'docs/agents',
  'docs/android',
  'docs/api-endpoint',
  'docs/cli',
  'docs/cli-direct',
  'docs/cli-extract',
  'docs/cli-jobs',
  'docs/configuration',
  'docs/daily-notes',
  'docs/export',
  'docs/folder-vault',
  'docs/format',
  'docs/individual-tracking',
  'docs/iphone-first-export',
  'docs/macos',
  'docs/mcp',
  'docs/metrics',
  'docs/onboarding',
  'docs/paywall',
  'docs/scheduling',
  'docs/shared-metric-registry',
  'docs/shortcuts',
  'docs/sync',
  'docs/visualizations-roadmap',
]);

function defineLocale(config) {
  if (!Array.isArray(config.translatedDocSlugs)) {
    throw new Error(`${config.code} must declare its translated documentation coverage`);
  }
  return Object.freeze({
    ...config,
    browser: Object.freeze(config.browser),
    marketplace: Object.freeze(config.marketplace),
    assets: Object.freeze(config.assets),
    assetFallbacks: Object.freeze(config.assetFallbacks ?? []),
    surfaces: Object.freeze(config.surfaces),
    ui: Object.freeze(config.ui),
    translatedDocSlugs: Object.freeze(config.translatedDocSlugs),
  });
}

export const locales = Object.freeze({
  en: defineLocale({
    code: 'en',
    path: '',
    lang: 'en',
    intlLocale: 'en-US',
    ogLocale: 'en_US',
    label: 'English',
    dir: 'ltr',
    browser: { exact: ['en'], aliases: ['en'] },
    marketplace: {
      appleUrl: 'https://apps.apple.com/us/app/health-md/id6757763969',
      googleUrl: 'https://play.google.com/store/apps/details?id=com.healthmd.android',
    },
    assets: {
      appStoreBadge: '/assets/store-badges/download-on-app-store.svg',
      playStoreBadge: '/assets/store-badges/get-it-on-google-play.png',
      scheduleScreenshot: '/assets/screenshots/showcase/scheduled-exports.png',
      firstExportOnboardingScreenshot: '/docs/assets/docs/iphone-first-export/onboarding-start.webp',
      firstExportMetricScreenshot: '/docs/assets/docs/iphone-first-export/metric-selection.webp',
      firstExportPreviewScreenshot: '/docs/assets/docs/iphone-first-export/export-preview.webp',
      docsOgImage: '/docs/social/docs-og.png',
    },
    translatedDocSlugs: authoredDocSlugs,
    surfaces: { landing: true, docs: true, legal: true, redirect: false },
    ui: {
      languageSelector: 'Language selector',
      docsPrimary: 'Primary',
      docsData: 'Data',
      docsHome: 'Home',
      builtBy: 'Built by',
      privacy: 'Privacy',
      terms: 'Terms',
      docsBreadcrumb: 'Documentation',
      docsOgImageAlt: 'Health.md documentation — export, query, automate, and build',
    },
  }),
  es: defineLocale({
    code: 'es',
    path: 'es',
    lang: 'es',
    intlLocale: 'es',
    ogLocale: 'es_ES',
    label: 'Español',
    dir: 'ltr',
    browser: { exact: ['es', 'es-es', 'es-419'], aliases: ['es'] },
    marketplace: {
      appleUrl: 'https://apps.apple.com/app/health-md/id6757763969?l=es',
      googleUrl: 'https://play.google.com/store/apps/details?id=com.healthmd.android&hl=es',
    },
    assets: {
      appStoreBadge: '/assets/store-badges/es/download-on-app-store.svg',
      playStoreBadge: '/assets/store-badges/es/get-it-on-google-play.png',
      scheduleScreenshot: '/assets/screenshots/showcase/es/scheduled-exports.png',
      firstExportOnboardingScreenshot: '/docs/assets/docs/iphone-first-export/onboarding-start.webp',
      firstExportMetricScreenshot: '/docs/assets/docs/es/iphone-first-export/metric-selection.webp',
      firstExportPreviewScreenshot: '/docs/assets/docs/es/iphone-first-export/export-preview.webp',
      docsOgImage: '/docs/social/docs-og-es.png',
    },
    assetFallbacks: ['firstExportOnboardingScreenshot'],
    translatedDocSlugs: authoredDocSlugs,
    surfaces: { landing: true, docs: true, legal: true, redirect: true },
    ui: {
      languageSelector: 'Selector de idioma',
      docsPrimary: 'Principal',
      docsData: 'Datos',
      docsHome: 'Inicio',
      builtBy: 'Creado por',
      privacy: 'Privacidad',
      terms: 'Términos',
      docsBreadcrumb: 'Documentación',
      docsOgImageAlt: 'Documentación de Health.md: exporta, consulta, automatiza y crea',
    },
  }),
  de: defineLocale({
    code: 'de',
    path: 'de',
    lang: 'de',
    intlLocale: 'de-DE',
    ogLocale: 'de_DE',
    label: 'Deutsch',
    dir: 'ltr',
    browser: { exact: ['de', 'de-de'], aliases: ['de'] },
    marketplace: {
      appleUrl: 'https://apps.apple.com/app/health-md/id6757763969?l=de',
      googleUrl: 'https://play.google.com/store/apps/details?id=com.healthmd.android&hl=de',
    },
    assets: {
      appStoreBadge: '/assets/store-badges/de/download-on-app-store.svg',
      playStoreBadge: '/assets/store-badges/de/get-it-on-google-play.png',
      scheduleScreenshot: '/assets/screenshots/showcase/de/scheduled-exports.png',
      firstExportOnboardingScreenshot: '/docs/assets/docs/iphone-first-export/onboarding-start.webp',
      firstExportMetricScreenshot: '/docs/assets/docs/de/iphone-first-export/metric-selection.webp',
      firstExportPreviewScreenshot: '/docs/assets/docs/de/iphone-first-export/export-preview.webp',
      docsOgImage: '/docs/social/docs-og-de.png',
    },
    assetFallbacks: ['firstExportOnboardingScreenshot'],
    translatedDocSlugs: authoredDocSlugs,
    surfaces: { landing: true, docs: true, legal: true, redirect: true },
    ui: {
      languageSelector: 'Sprachauswahl',
      docsPrimary: 'Hauptnavigation',
      docsData: 'Daten',
      docsHome: 'Startseite',
      builtBy: 'Erstellt von',
      privacy: 'Datenschutz',
      terms: 'Nutzungsbedingungen',
      docsBreadcrumb: 'Dokumentation',
      docsOgImageAlt: 'Health.md-Dokumentation — exportieren, abfragen, automatisieren und entwickeln',
    },
  }),
  fr: defineLocale({
    code: 'fr',
    path: 'fr',
    lang: 'fr',
    intlLocale: 'fr-FR',
    ogLocale: 'fr_FR',
    label: 'Français',
    dir: 'ltr',
    browser: { exact: ['fr', 'fr-fr'], aliases: ['fr'] },
    marketplace: {
      appleUrl: 'https://apps.apple.com/app/health-md/id6757763969?l=fr',
      googleUrl: 'https://play.google.com/store/apps/details?id=com.healthmd.android&hl=fr',
    },
    assets: {
      appStoreBadge: '/assets/store-badges/fr/download-on-app-store.svg',
      playStoreBadge: '/assets/store-badges/fr/get-it-on-google-play.png',
      scheduleScreenshot: '/assets/screenshots/showcase/fr/scheduled-exports.png',
      firstExportOnboardingScreenshot: '/docs/assets/docs/iphone-first-export/onboarding-start.webp',
      firstExportMetricScreenshot: '/docs/assets/docs/fr/iphone-first-export/metric-selection.webp',
      firstExportPreviewScreenshot: '/docs/assets/docs/fr/iphone-first-export/export-preview.webp',
      docsOgImage: '/docs/social/docs-og-fr.png',
    },
    assetFallbacks: ['firstExportOnboardingScreenshot'],
    translatedDocSlugs: authoredDocSlugs,
    surfaces: { landing: true, docs: true, legal: true, redirect: true },
    ui: {
      languageSelector: 'Sélecteur de langue',
      docsPrimary: 'Navigation principale',
      docsData: 'Données',
      docsHome: 'Accueil',
      builtBy: 'Créé par',
      privacy: 'Confidentialité',
      terms: 'Conditions d’utilisation',
      docsBreadcrumb: 'Documentation',
      docsOgImageAlt: 'Documentation Health.md — exporter, interroger, automatiser et développer',
    },
  }),
  'pt-br': defineLocale({
    code: 'pt-br',
    path: 'pt-br',
    lang: 'pt-BR',
    intlLocale: 'pt-BR',
    ogLocale: 'pt_BR',
    label: 'Português (Brasil)',
    dir: 'ltr',
    browser: { exact: ['pt-br'], aliases: ['pt'] },
    marketplace: {
      appleUrl: 'https://apps.apple.com/app/health-md/id6757763969?l=pt-BR',
      googleUrl: 'https://play.google.com/store/apps/details?id=com.healthmd.android&hl=pt_BR',
    },
    assets: {
      appStoreBadge: '/assets/store-badges/pt-br/download-on-app-store.svg',
      playStoreBadge: '/assets/store-badges/pt-br/get-it-on-google-play.png',
      scheduleScreenshot: '/assets/screenshots/showcase/pt-br/scheduled-exports.png',
      firstExportOnboardingScreenshot: '/docs/assets/docs/iphone-first-export/onboarding-start.webp',
      firstExportMetricScreenshot: '/docs/assets/docs/pt-br/iphone-first-export/metric-selection.webp',
      firstExportPreviewScreenshot: '/docs/assets/docs/pt-br/iphone-first-export/export-preview.webp',
      docsOgImage: '/docs/social/docs-og-pt-br.png',
    },
    assetFallbacks: ['firstExportOnboardingScreenshot'],
    translatedDocSlugs: authoredDocSlugs,
    surfaces: { landing: true, docs: true, legal: true, redirect: true },
    ui: {
      languageSelector: 'Seletor de idioma',
      docsPrimary: 'Navegação principal',
      docsData: 'Dados',
      docsHome: 'Início',
      builtBy: 'Criado por',
      privacy: 'Privacidade',
      terms: 'Termos',
      docsBreadcrumb: 'Documentação',
      docsOgImageAlt: 'Documentação do Health.md — exporte, consulte, automatize e desenvolva',
    },
  }),
  it: defineLocale({
    code: 'it',
    path: 'it',
    lang: 'it',
    intlLocale: 'it-IT',
    ogLocale: 'it_IT',
    label: 'Italiano',
    dir: 'ltr',
    browser: { exact: ['it', 'it-it'], aliases: ['it'] },
    marketplace: {
      appleUrl: 'https://apps.apple.com/app/health-md/id6757763969?l=it',
      googleUrl: 'https://play.google.com/store/apps/details?id=com.healthmd.android&hl=it',
    },
    assets: {
      appStoreBadge: '/assets/store-badges/it/download-on-app-store.svg',
      playStoreBadge: '/assets/store-badges/it/get-it-on-google-play.png',
      scheduleScreenshot: '/assets/screenshots/showcase/it/scheduled-exports.png',
      firstExportOnboardingScreenshot: '/docs/assets/docs/iphone-first-export/onboarding-start.webp',
      firstExportMetricScreenshot: '/docs/assets/docs/it/iphone-first-export/metric-selection.webp',
      firstExportPreviewScreenshot: '/docs/assets/docs/it/iphone-first-export/export-preview.webp',
      docsOgImage: '/docs/social/docs-og-it.png',
    },
    assetFallbacks: ['firstExportOnboardingScreenshot'],
    translatedDocSlugs: authoredDocSlugs,
    surfaces: { landing: true, docs: true, legal: true, redirect: true },
    ui: {
      languageSelector: 'Selettore della lingua',
      docsPrimary: 'Navigazione principale',
      docsData: 'Dati',
      docsHome: 'Home',
      builtBy: 'Sviluppato da',
      privacy: 'Privacy',
      terms: 'Termini',
      docsBreadcrumb: 'Documentazione',
      docsOgImageAlt: 'Documentazione Health.md — esporta, interroga, automatizza e sviluppa',
    },
  }),
  nl: defineLocale({
    code: 'nl',
    path: 'nl',
    lang: 'nl',
    intlLocale: 'nl-NL',
    ogLocale: 'nl_NL',
    label: 'Nederlands',
    dir: 'ltr',
    browser: { exact: ['nl', 'nl-nl'], aliases: ['nl'] },
    marketplace: {
      appleUrl: 'https://apps.apple.com/app/health-md/id6757763969?l=nl',
      googleUrl: 'https://play.google.com/store/apps/details?id=com.healthmd.android&hl=nl',
    },
    assets: {
      appStoreBadge: '/assets/store-badges/nl/download-on-app-store.svg',
      playStoreBadge: '/assets/store-badges/nl/get-it-on-google-play.png',
      scheduleScreenshot: '/assets/screenshots/showcase/nl/scheduled-exports.png',
      firstExportOnboardingScreenshot: '/docs/assets/docs/iphone-first-export/onboarding-start.webp',
      firstExportMetricScreenshot: '/docs/assets/docs/nl/iphone-first-export/metric-selection.webp',
      firstExportPreviewScreenshot: '/docs/assets/docs/nl/iphone-first-export/export-preview.webp',
      docsOgImage: '/docs/social/docs-og-nl.png',
    },
    assetFallbacks: ['firstExportOnboardingScreenshot'],
    translatedDocSlugs: authoredDocSlugs,
    surfaces: { landing: true, docs: true, legal: true, redirect: true },
    ui: {
      languageSelector: 'Taalkeuze',
      docsPrimary: 'Hoofdnavigatie',
      docsData: 'Gegevens',
      docsHome: 'Home',
      builtBy: 'Gemaakt door',
      privacy: 'Privacy',
      terms: 'Voorwaarden',
      docsBreadcrumb: 'Documentatie',
      docsOgImageAlt: 'Health.md-documentatie — exporteren, opvragen, automatiseren en ontwikkelen',
    },
  }),
  ja: defineLocale({
    code: 'ja',
    path: 'ja',
    lang: 'ja',
    intlLocale: 'ja-JP',
    ogLocale: 'ja_JP',
    label: '日本語',
    dir: 'ltr',
    browser: { exact: ['ja', 'ja-jp'], aliases: ['ja'] },
    marketplace: {
      appleUrl: 'https://apps.apple.com/app/health-md/id6757763969?l=ja',
      googleUrl: 'https://play.google.com/store/apps/details?id=com.healthmd.android&hl=ja',
    },
    assets: {
      appStoreBadge: '/assets/store-badges/ja/download-on-app-store.svg',
      playStoreBadge: '/assets/store-badges/ja/get-it-on-google-play.png',
      scheduleScreenshot: '/assets/screenshots/showcase/ja/scheduled-exports.png',
      firstExportOnboardingScreenshot: '/docs/assets/docs/iphone-first-export/onboarding-start.webp',
      firstExportMetricScreenshot: '/docs/assets/docs/ja/iphone-first-export/metric-selection.webp',
      firstExportPreviewScreenshot: '/docs/assets/docs/ja/iphone-first-export/export-preview.webp',
      docsOgImage: '/docs/social/docs-og-ja.png',
    },
    assetFallbacks: ['firstExportOnboardingScreenshot'],
    translatedDocSlugs: authoredDocSlugs,
    surfaces: { landing: true, docs: true, legal: true, redirect: true },
    ui: {
      languageSelector: '言語選択',
      docsPrimary: 'メインナビゲーション',
      docsData: 'データ',
      docsHome: 'ホーム',
      builtBy: '制作：',
      privacy: 'プライバシー',
      terms: '利用規約',
      docsBreadcrumb: 'ドキュメント',
      docsOgImageAlt: 'Health.md ドキュメント — エクスポート、照会、自動化、開発',
    },
  }),
  ko: defineLocale({
    code: 'ko',
    path: 'ko',
    lang: 'ko',
    intlLocale: 'ko-KR',
    ogLocale: 'ko_KR',
    label: '한국어',
    dir: 'ltr',
    browser: { exact: ['ko', 'ko-kr'], aliases: ['ko'] },
    marketplace: {
      appleUrl: 'https://apps.apple.com/app/health-md/id6757763969?l=ko',
      googleUrl: 'https://play.google.com/store/apps/details?id=com.healthmd.android&hl=ko',
    },
    assets: {
      appStoreBadge: '/assets/store-badges/ko/download-on-app-store.svg',
      playStoreBadge: '/assets/store-badges/ko/get-it-on-google-play.png',
      scheduleScreenshot: '/assets/screenshots/showcase/ko/scheduled-exports.png',
      firstExportOnboardingScreenshot: '/docs/assets/docs/iphone-first-export/onboarding-start.webp',
      firstExportMetricScreenshot: '/docs/assets/docs/ko/iphone-first-export/metric-selection.webp',
      firstExportPreviewScreenshot: '/docs/assets/docs/ko/iphone-first-export/export-preview.webp',
      docsOgImage: '/docs/social/docs-og-ko.png',
    },
    assetFallbacks: ['firstExportOnboardingScreenshot'],
    translatedDocSlugs: authoredDocSlugs,
    surfaces: { landing: true, docs: true, legal: true, redirect: true },
    ui: {
      languageSelector: '언어 선택',
      docsPrimary: '기본 탐색',
      docsData: '데이터',
      docsHome: '홈',
      builtBy: '제작:',
      privacy: '개인정보 처리방침',
      terms: '이용 약관',
      docsBreadcrumb: '문서',
      docsOgImageAlt: 'Health.md 문서 — 내보내기, 조회, 자동화 및 개발',
    },
  }),
  'zh-hans': defineLocale({
    code: 'zh-hans',
    path: 'zh-hans',
    lang: 'zh-Hans',
    intlLocale: 'zh-CN',
    ogLocale: 'zh_CN',
    label: '简体中文',
    dir: 'ltr',
    browser: { exact: ['zh-hans', 'zh-hans-cn', 'zh-hans-sg', 'zh-cn', 'zh-sg'], aliases: [] },
    marketplace: {
      appleUrl: 'https://apps.apple.com/app/health-md/id6757763969?l=zh-Hans',
      googleUrl: 'https://play.google.com/store/apps/details?id=com.healthmd.android&hl=zh_CN',
    },
    assets: {
      appStoreBadge: '/assets/store-badges/zh-hans/download-on-app-store.svg',
      playStoreBadge: '/assets/store-badges/zh-hans/get-it-on-google-play.png',
      scheduleScreenshot: '/assets/screenshots/showcase/zh-hans/scheduled-exports.png',
      firstExportOnboardingScreenshot: '/docs/assets/docs/iphone-first-export/onboarding-start.webp',
      firstExportMetricScreenshot: '/docs/assets/docs/zh-hans/iphone-first-export/metric-selection.webp',
      firstExportPreviewScreenshot: '/docs/assets/docs/zh-hans/iphone-first-export/export-preview.webp',
      docsOgImage: '/docs/social/docs-og-zh-hans.png',
    },
    assetFallbacks: ['firstExportOnboardingScreenshot'],
    translatedDocSlugs: authoredDocSlugs,
    surfaces: { landing: true, docs: true, legal: true, redirect: true },
    ui: {
      languageSelector: '语言选择',
      docsPrimary: '主导航',
      docsData: '数据',
      docsHome: '首页',
      builtBy: '由',
      privacy: '隐私政策',
      terms: '服务条款',
      docsBreadcrumb: '文档',
      docsOgImageAlt: 'Health.md 文档 — 导出、查询、自动化和开发',
    },
  }),
});

export const enabledLocales = Object.freeze(Object.keys(locales));

export function localeFor(code) {
  const locale = locales[code];
  if (!locale) throw new Error(`Unsupported website locale: ${code}`);
  return locale;
}

export function localeForLanguage(language) {
  const normalized = String(language ?? '').toLowerCase().replaceAll('_', '-');
  const exact = enabledLocales.find((code) => {
    const locale = localeFor(code);
    return locale.code.toLowerCase() === normalized
      || locale.lang.toLowerCase() === normalized
      || locale.browser.exact.some((value) => value.toLowerCase().replaceAll('_', '-') === normalized);
  });
  if (exact) return localeFor(exact);
  const base = normalized.split('-', 1)[0];
  const alias = enabledLocales.find((code) => localeFor(code).browser.aliases
    .some((value) => [normalized, base].includes(value.toLowerCase().replaceAll('_', '-'))));
  return localeFor(alias ?? defaultLocale);
}

export function publishedLocales(surface) {
  if (!surface) return enabledLocales.map(localeFor);
  return enabledLocales.map(localeFor).filter((locale) => locale.surfaces[surface] === true);
}

export function localizedPathname(pathname, locale = defaultLocale) {
  const config = localeFor(locale);
  const clean = `/${String(pathname || '/').replace(/^\/+/, '')}`;
  if (locale === defaultLocale) return clean;
  return `/${config.path}${clean === '/' ? '/' : clean}`;
}
