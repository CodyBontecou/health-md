#!/usr/bin/env node
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

export function funnelReportSQL(days = 28) {
  if (!Number.isInteger(days) || days < 1 || days > 90) throw new Error('days must be an integer from 1 to 90');
  return `WITH totals AS (
    SELECT page, locale, source,
      SUM(CASE WHEN action = 'page_view' THEN count ELSE 0 END) AS page_views,
      SUM(CASE WHEN action = 'csv_sample_download' THEN count ELSE 0 END) AS csv_sample_actions,
      SUM(CASE WHEN action = 'starter_vault_download' THEN count ELSE 0 END) AS starter_vault_actions,
      SUM(CASE WHEN action = 'store_click' THEN count ELSE 0 END) AS store_clicks,
      SUM(CASE WHEN target = 'app_store' THEN count ELSE 0 END) AS app_store_clicks,
      SUM(CASE WHEN target = 'google_play' THEN count ELSE 0 END) AS google_play_clicks,
      SUM(CASE WHEN target = 'f_droid' THEN count ELSE 0 END) AS f_droid_clicks
    FROM web_funnel_daily
    WHERE day >= date('now', '-${days - 1} days') AND day <= date('now')
    GROUP BY page, locale, source
  ) SELECT *,
    ROUND(100.0 * csv_sample_actions / NULLIF(page_views, 0), 2) AS csv_actions_per_100_views,
    ROUND(100.0 * starter_vault_actions / NULLIF(page_views, 0), 2) AS starter_actions_per_100_views,
    ROUND(100.0 * store_clicks / NULLIF(page_views, 0), 2) AS store_clicks_per_100_views
  FROM totals ORDER BY page_views DESC, page, locale, source`;
}

export function reportOptions(args) {
  const options = { days: 28, mode: null };
  for (let i = 0; i < args.length; i++) {
    if (args[i] === '--days') {
      const value = args[++i];
      if (!/^\d+$/.test(value || '')) throw new Error('Use --days with an integer from 1 to 90');
      options.days = Number(value);
    } else if (args[i] === '--remote' || args[i] === '--local') {
      if (options.mode) throw new Error('Choose exactly one of --remote or --local');
      options.mode = args[i];
    } else throw new Error('Usage: npm run seo:funnel -- --remote|--local [--days 28]');
  }
  if (!options.mode) throw new Error('Choose --remote for production or --local for a local database');
  funnelReportSQL(options.days);
  return options;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  try {
    const { mode, days } = reportOptions(process.argv.slice(2));
    const config = fileURLToPath(new URL('../cloudflare/attribution-worker/wrangler.toml', import.meta.url));
    const result = spawnSync('wrangler', ['d1', 'execute', 'healthmd-campaigns', '--config', config, mode, '--json', '--command', funnelReportSQL(days)], {
      encoding: 'utf8', maxBuffer: 4 * 1024 * 1024,
    });
    if (result.error || result.status !== 0) throw new Error('Cannot read funnel counters. Check Wrangler sign-in, database access and migration 0003.');
    const response = JSON.parse(result.stdout);
    if (!Array.isArray(response) || response.some(item => item.success !== true || !Array.isArray(item.results))) throw new Error('Unexpected D1 report response');
    console.log(JSON.stringify({ days, time_zone: 'UTC', database: mode.slice(2),
      measure: 'Gate-permitted page views and action counts; no unique visitors, download completion or install attribution',
      rows: response.flatMap(item => item.results),
    }, null, 2));
  } catch (error) { console.error(error.message); process.exitCode = 1; }
}
