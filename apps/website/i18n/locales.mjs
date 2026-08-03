export const defaultLocale = 'en';

export const locales = Object.freeze({
  en: Object.freeze({
    code: 'en',
    path: '',
    lang: 'en',
    intlLocale: 'en-US',
    ogLocale: 'en_US',
    label: 'English',
    dir: 'ltr',
  }),
  es: Object.freeze({
    code: 'es',
    path: 'es',
    lang: 'es',
    intlLocale: 'es',
    ogLocale: 'es_ES',
    label: 'Español',
    dir: 'ltr',
  }),
});

export const enabledLocales = Object.freeze(Object.keys(locales));

export function localeFor(code) {
  const locale = locales[code];
  if (!locale) throw new Error(`Unsupported website locale: ${code}`);
  return locale;
}
