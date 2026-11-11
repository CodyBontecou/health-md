-- Daily, fixed-vocabulary counters; no per-event rows or visitor identifiers.
CREATE TABLE web_funnel_daily (
  day TEXT NOT NULL,
  page TEXT NOT NULL,
  locale TEXT NOT NULL,
  source TEXT NOT NULL,
  action TEXT NOT NULL,
  target TEXT NOT NULL,
  placement TEXT NOT NULL,
  count INTEGER NOT NULL CHECK (count > 0),
  PRIMARY KEY (day, page, locale, source, action, target, placement)
) WITHOUT ROWID;

CREATE TABLE web_funnel_ingest_windows (
  window_start TEXT PRIMARY KEY,
  request_count INTEGER NOT NULL
);
