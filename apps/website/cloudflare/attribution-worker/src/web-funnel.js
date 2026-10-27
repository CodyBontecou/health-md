import { validFunnelEvent } from '../../../assets/funnel-contract.js';

const MAX_BYTES = 1024;
const MAX_PER_MINUTE = 600;
function response(status) {
  return new Response(null, { status, headers: {
    'cache-control': 'no-store', 'x-content-type-options': 'nosniff', 'x-robots-tag': 'noindex',
    ...(status === 405 ? { allow: 'POST' } : {}),
    ...(status === 429 ? { 'retry-after': '60' } : {}),
  } });
}

export async function handleWebFunnel(request, env, now = new Date()) {
  const url = new URL(request.url);
  if (url.search) return response(400);
  if (request.method !== 'POST') return response(405);
  if (!['https://healthmd.app', 'https://www.healthmd.app'].includes(url.origin) ||
      request.headers.get('origin') !== url.origin ||
      (request.headers.has('sec-fetch-site') && request.headers.get('sec-fetch-site') !== 'same-origin')) return response(403);
  if (request.headers.get('sec-gpc') === '1' || request.headers.get('dnt') === '1') return response(204);
  if (request.headers.get('content-type')?.split(';')[0].trim().toLowerCase() !== 'application/json') return response(415);
  if (Number(request.headers.get('content-length')) > MAX_BYTES) return response(413);
  if (!request.body) return response(400);
  let event;
  const reader = request.body.getReader(), chunks = [];
  let length = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      length += value.byteLength;
      if (length > MAX_BYTES) { await reader.cancel(); return response(413); }
      chunks.push(value);
    }
    const bytes = new Uint8Array(length);
    let offset = 0;
    for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength; }
    event = JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(bytes));
  } catch { return response(400); }
  if (!validFunnelEvent(event)) return response(400);
  if (!env.DB) return response(503);
  try {
    const minute = new Date(now);
    minute.setUTCSeconds(0, 0);
    const rate = await env.DB.prepare(`
      INSERT INTO web_funnel_ingest_windows (window_start, request_count) VALUES (?, 1)
      ON CONFLICT(window_start) DO UPDATE SET request_count = request_count + 1
      RETURNING request_count
    `).bind(minute.toISOString()).first();
    if (!rate || Number(rate.request_count) > MAX_PER_MINUTE) return response(429);
    await env.DB.prepare(`
      INSERT INTO web_funnel_daily (day, page, locale, source, action, target, placement, count)
      VALUES (?, ?, ?, ?, ?, ?, ?, 1)
      ON CONFLICT(day, page, locale, source, action, target, placement) DO UPDATE SET count = count + 1
    `).bind(now.toISOString().slice(0, 10), event.page, event.locale, event.source, event.action, event.target, event.placement).run();
    return response(204);
  } catch { return response(503); }
}
