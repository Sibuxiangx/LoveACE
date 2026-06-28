CREATE INDEX IF NOT EXISTS idx_analytics_events_created_name
  ON analytics_events(created_at, event_name);

CREATE INDEX IF NOT EXISTS idx_analytics_events_created_platform_student
  ON analytics_events(created_at, platform, student_hash);

CREATE INDEX IF NOT EXISTS idx_analytics_events_created_grade_student
  ON analytics_events(created_at, grade_prefix, student_hash);

CREATE INDEX IF NOT EXISTS idx_analytics_events_created_platform_version_client
  ON analytics_events(created_at, platform, app_version, client_id);

CREATE INDEX IF NOT EXISTS idx_analytics_events_created_student
  ON analytics_events(created_at, student_hash);
