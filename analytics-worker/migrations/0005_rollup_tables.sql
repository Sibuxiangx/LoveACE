CREATE TABLE IF NOT EXISTS analytics_rollup_counts (
  bucket_hour TEXT NOT NULL,
  bucket_day TEXT NOT NULL,
  metric TEXT NOT NULL,
  label TEXT NOT NULL,
  platform TEXT NOT NULL DEFAULT '',
  app_version TEXT NOT NULL DEFAULT '',
  count INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (bucket_hour, metric, label, platform, app_version)
);

CREATE INDEX IF NOT EXISTS idx_rollup_counts_day_metric
  ON analytics_rollup_counts(bucket_day, metric);

CREATE INDEX IF NOT EXISTS idx_rollup_counts_hour_metric
  ON analytics_rollup_counts(bucket_hour, metric);

CREATE TABLE IF NOT EXISTS analytics_rollup_identities (
  bucket_scope TEXT NOT NULL,
  bucket_key TEXT NOT NULL,
  metric TEXT NOT NULL,
  label TEXT NOT NULL,
  platform TEXT NOT NULL DEFAULT '',
  app_version TEXT NOT NULL DEFAULT '',
  identity_type TEXT NOT NULL,
  identity_value TEXT NOT NULL,
  PRIMARY KEY (
    bucket_scope, bucket_key, metric, label, platform,
    app_version, identity_type, identity_value
  )
);

CREATE INDEX IF NOT EXISTS idx_rollup_identities_scope_metric_key
  ON analytics_rollup_identities(bucket_scope, metric, bucket_key);

CREATE TABLE IF NOT EXISTS analytics_rollup_state (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL,
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);
