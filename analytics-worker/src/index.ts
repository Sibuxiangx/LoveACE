interface Env {
  DB: D1Database;
  ASSETS: Fetcher;
  ANALYTICS_ARCHIVE: R2Bucket;
  ANALYTICS_API_KEY: string;
  ANALYTICS_SIGNING_SECRET: string;
  ANALYTICS_IP_HASH_SALT: string;
  ARCHIVE_BATCH_SIZE?: string;
  ARCHIVE_MAX_BATCHES?: string;
  RAW_RETENTION_DAYS?: string;
  ROLLUP_BATCH_SIZE?: string;
  ROLLUP_MAX_BATCHES?: string;
  MAX_BODY_BYTES?: string;
  MAX_EVENTS_PER_REQUEST?: string;
  NONCE_TTL_SECONDS?: string;
  RATE_LIMIT_PER_MINUTE?: string;
  TIMESTAMP_SKEW_SECONDS?: string;
  BI_CACHE_TTL_SECONDS?: string;
}

interface EventIn {
  name: string;
  time: string;
  properties?: Record<string, unknown>;
}

interface EventsIn {
  client_id: string;
  platform: "android" | "ios" | "desktop" | "windows" | "macos" | "linux";
  app_version: string;
  build?: string | null;
  os_version?: string | null;
  device_model?: string | null;
  grade_prefix?: string | null;
  student_hash?: string | null;
  events: EventIn[];
}

interface SummaryRow {
  total_events: number;
  clients: number;
  users: number;
  events_24h: number;
  events_7d: number;
  dau: number;
  wau: number;
  mau: number;
  last_event_at: string | null;
}

interface CountRow {
  label: string | null;
  count: number;
}

interface VersionRow {
  platform: string | null;
  app_version: string | null;
  clients: number;
  events: number;
}

interface TrendRow {
  bucket: string;
  count: number;
  users: number;
}

interface AnalyticsEventRow {
  id: number;
  client_id: string;
  platform: string;
  app_version: string;
  build: string | null;
  os_version: string | null;
  device_model: string | null;
  grade_prefix: string | null;
  student_hash: string | null;
  event_name: string;
  event_time: string;
  properties: string;
  ip_hash: string | null;
  user_agent: string | null;
  created_at: string;
}

interface MaintenanceResult {
  rollup: RollupResult;
  archive: ArchiveResult;
}

interface RollupResult {
  processed: number;
  lastId: number;
  ready: boolean;
}

interface ArchiveResult {
  archivedRows: number;
  archivedObjects: number;
}

interface RollupCountValue {
  bucketHour: string;
  bucketDay: string;
  metric: string;
  label: string;
  platform: string;
  appVersion: string;
  count: number;
}

interface RollupIdentityValue {
  bucketScope: string;
  bucketKey: string;
  metric: string;
  label: string;
  platform: string;
  appVersion: string;
  identityType: string;
  identityValue: string;
}

interface RollupAggregate {
  counts: Map<string, RollupCountValue>;
  identities: Map<string, RollupIdentityValue>;
}

interface PeriodInfo {
  range: PeriodRange;
  label: string;
  bucketLabel: string;
}

interface UsageRow {
  label: string | null;
  count: number;
  users: number;
  android: number;
  ios: number;
  desktop: number;
}

interface AnalyticsDashboardData {
  period: PeriodInfo;
  summary: SummaryRow;
  eventDistribution: CountRow[];
  platformDistribution: CountRow[];
  gradeDistribution: CountRow[];
  screenDistribution: CountRow[];
  featureDistribution: CountRow[];
  normalizedUsage: UsageRow[];
  versions: VersionRow[];
  authStats: CountRow[];
  otaStats: CountRow[];
  trend: TrendRow[];
  generatedAt: string;
}

const ALLOWED_EVENTS = new Set([
  "app_start",
  "login_success",
  "login_failed",
  "session_expired",
  "session_reconnect_success",
  "session_reconnect_failed",
  "screen_view",
  "feature_action",
  "ota_check",
  "ota_update_click",
]);

const ALLOWED_PROPERTY_KEYS = new Set([
  "launch_source",
  "duration_ms",
  "reason",
  "feature",
  "screen",
  "action",
  "result",
  "current_version",
  "latest_version",
  "target_version",
]);

type PeriodRange = "day" | "week" | "month";

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);

    if (request.method === "GET" && url.pathname === "/healthz") {
      return json({ ok: true });
    }

    if (request.method === "GET" && url.pathname === "/bi/data") {
      return loadDashboardResponse(request, env, parsePeriodRange(url.searchParams.get("range")));
    }

    if (request.method === "POST" && url.pathname === "/admin/maintenance/run") {
      if (!env.ANALYTICS_API_KEY || !constantTimeEqual(header(request, "Authorization"), `Bearer ${env.ANALYTICS_API_KEY}`)) {
        return json({ ok: false, error: "unauthorized" }, 401);
      }
      const result = await runMaintenance(env, {
        rollupBatchSize: parsePositiveInt(url.searchParams.get("rollup_batch_size")),
        rollupMaxBatches: parsePositiveInt(url.searchParams.get("rollup_batches")),
        archiveBatchSize: parsePositiveInt(url.searchParams.get("archive_batch_size")),
        archiveMaxBatches: parsePositiveInt(url.searchParams.get("archive_batches")),
        archiveAll: url.searchParams.get("archive_all") === "true",
      });
      return json({ ok: true, ...result });
    }

    if (request.method === "GET" && (url.pathname === "/" || url.pathname === "/bi")) {
      return serveDashboard(request, env);
    }

    if (request.method === "POST" && url.pathname === "/v1/events") {
      return ingestEvents(request, env);
    }

    return json({ ok: false, error: "not_found" }, 404);
  },

  async scheduled(_controller: ScheduledController, env: Env, ctx: ExecutionContext): Promise<void> {
    ctx.waitUntil(runScheduledMaintenance(env));
  },
};

async function runScheduledMaintenance(env: Env): Promise<void> {
  if (await getState(env.DB, "maintenance:local_backfill") === "1") return;
  await runMaintenance(env);
}

async function runMaintenance(env: Env, options: {
  rollupBatchSize?: number;
  rollupMaxBatches?: number;
  archiveBatchSize?: number;
  archiveMaxBatches?: number;
  archiveAll?: boolean;
} = {}): Promise<MaintenanceResult> {
  const rollup = await rollupEvents(env, {
    batchSize: options.rollupBatchSize,
    maxBatches: options.rollupMaxBatches,
  });
  const archive = await archiveOldEvents(env, {
    batchSize: options.archiveBatchSize,
    maxBatches: options.archiveMaxBatches,
    retentionDays: options.archiveAll ? 0 : undefined,
  });
  return { rollup, archive };
}

async function rollupEvents(env: Env, options: {
  batchSize?: number;
  maxBatches?: number;
} = {}): Promise<RollupResult> {
  const batchSize = Math.min(options.batchSize ?? intEnv(env.ROLLUP_BATCH_SIZE, 5000), 5000);
  const maxBatches = options.maxBatches ?? intEnv(env.ROLLUP_MAX_BATCHES, 10);
  let lastId = await getNumberState(env.DB, "rollup:last_event_id", 0);
  let processed = 0;
  let ready = false;

  for (let batchIndex = 0; batchIndex < maxBatches; batchIndex += 1) {
    const result = await env.DB.prepare(`
      SELECT
        id, client_id, platform, app_version, build, os_version, device_model,
        grade_prefix, student_hash, event_name, event_time, properties,
        ip_hash, user_agent, created_at
      FROM analytics_events
      WHERE id > ?
      ORDER BY id ASC
      LIMIT ?
    `).bind(lastId, batchSize).all<AnalyticsEventRow>();
    const rows = result.results ?? [];
    if (rows.length === 0) {
      await setState(env.DB, "rollup:ready", "1");
      return { processed, lastId, ready: true };
    }

    const aggregate = aggregateRollupRows(rows);
    await writeRollupAggregate(env.DB, aggregate);

    lastId = rows[rows.length - 1].id;
    processed += rows.length;
    await setState(env.DB, "rollup:last_event_id", String(lastId));
    await setState(env.DB, "rollup:last_event_at", maxString(rows.map((row) => row.created_at)) ?? "");

    if (rows.length < batchSize) {
      await setState(env.DB, "rollup:ready", "1");
      ready = true;
      break;
    }
  }

  return { processed, lastId, ready };
}

function aggregateRollupRows(rows: AnalyticsEventRow[]): RollupAggregate {
  const counts = new Map<string, RollupCountValue>();
  const identities = new Map<string, RollupIdentityValue>();

  for (const row of rows) {
    const bucket = shanghaiBuckets(row.created_at);
    const platform = cleanLabel(row.platform);
    const appVersion = cleanLabel(row.app_version);
    const eventName = cleanLabel(row.event_name);
    const properties = parsePropertiesJson(row.properties);
    const screen = stringProperty(properties, "screen");
    const feature = stringProperty(properties, "feature");
    const action = stringProperty(properties, "action");
    const normalized = normalizedUsageLabel(row.event_name, screen, feature, action);

    addCount(counts, bucket, "total", "", "", "", 1);
    addCount(counts, bucket, "event", eventName, "", "", 1);
    addCount(counts, bucket, "version", "", platform, appVersion, 1);
    if (screen) addCount(counts, bucket, "screen", screen, "", "", 1);
    if (feature) addCount(counts, bucket, "feature", feature, "", "", 1);
    if (normalized) addCount(counts, bucket, "normalized", normalized, platform, "", 1);
    if (isAuthEvent(eventName)) addCount(counts, bucket, "auth", eventName, "", "", 1);
    if (isOtaEvent(eventName)) addCount(counts, bucket, "ota", eventName, "", "", 1);

    if (row.client_id) {
      addIdentity(identities, "day", bucket.day, "total", "", "", "", "client", row.client_id);
      addIdentity(identities, "day", bucket.day, "version", "", platform, appVersion, "client", row.client_id);
    }

    if (row.student_hash) {
      addIdentity(identities, "day", bucket.day, "total", "", "", "", "user", row.student_hash);
      addIdentity(identities, "hour", bucket.hour, "trend", "", "", "", "user", row.student_hash);
      addIdentity(identities, "day", bucket.day, "platform", platform, platform, "", "user", row.student_hash);
      if (row.grade_prefix) {
        addIdentity(identities, "day", bucket.day, "grade", cleanLabel(row.grade_prefix), "", "", "user", row.student_hash);
      }
      if (normalized) {
        addIdentity(identities, "day", bucket.day, "normalized", normalized, platform, "", "user", row.student_hash);
      }
    }
  }

  return { counts, identities };
}

async function writeRollupAggregate(
  db: D1Database,
  aggregate: RollupAggregate,
): Promise<void> {
  const statements: D1PreparedStatement[] = [];
  for (const item of aggregate.counts.values()) {
    statements.push(db.prepare(`
      INSERT INTO analytics_rollup_counts (
        bucket_hour, bucket_day, metric, label, platform, app_version, count
      ) VALUES (?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(bucket_hour, metric, label, platform, app_version)
      DO UPDATE SET count = count + excluded.count
    `).bind(
      item.bucketHour,
      item.bucketDay,
      item.metric,
      item.label,
      item.platform,
      item.appVersion,
      item.count,
    ));
  }
  for (const item of aggregate.identities.values()) {
    statements.push(db.prepare(`
      INSERT OR IGNORE INTO analytics_rollup_identities (
        bucket_scope, bucket_key, metric, label, platform, app_version,
        identity_type, identity_value
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    `).bind(
      item.bucketScope,
      item.bucketKey,
      item.metric,
      item.label,
      item.platform,
      item.appVersion,
      item.identityType,
      item.identityValue,
    ));
  }

  for (let index = 0; index < statements.length; index += 50) {
    await db.batch(statements.slice(index, index + 50));
  }
}

function addCount(
  counts: Map<string, RollupCountValue>,
  bucket: { day: string; hour: string },
  metric: string,
  label: string,
  platform: string,
  appVersion: string,
  count: number,
): void {
  const key = [bucket.hour, metric, label, platform, appVersion].join("\u001f");
  const current = counts.get(key);
  if (current) current.count += count;
  else counts.set(key, { bucketHour: bucket.hour, bucketDay: bucket.day, metric, label, platform, appVersion, count });
}

function addIdentity(
  identities: Map<string, RollupIdentityValue>,
  bucketScope: string,
  bucketKey: string,
  metric: string,
  label: string,
  platform: string,
  appVersion: string,
  identityType: string,
  identityValue: string,
): void {
  const cleanValue = cleanLabel(identityValue);
  if (!cleanValue) return;
  const key = [bucketScope, bucketKey, metric, label, platform, appVersion, identityType, cleanValue].join("\u001f");
  identities.set(key, { bucketScope, bucketKey, metric, label, platform, appVersion, identityType, identityValue: cleanValue });
}

async function archiveOldEvents(env: Env, options: {
  batchSize?: number;
  maxBatches?: number;
  retentionDays?: number;
} = {}): Promise<ArchiveResult> {
  if (await getState(env.DB, "rollup:ready") !== "1") return { archivedRows: 0, archivedObjects: 0 };
  const retentionDays = options.retentionDays ?? intEnv(env.RAW_RETENTION_DAYS, 1);
  const batchSize = Math.min(options.batchSize ?? intEnv(env.ARCHIVE_BATCH_SIZE, 5000), 5000);
  const maxBatches = options.maxBatches ?? intEnv(env.ARCHIVE_MAX_BATCHES, 10);
  const lastRollupId = await getNumberState(env.DB, "rollup:last_event_id", 0);
  if (lastRollupId <= 0) return { archivedRows: 0, archivedObjects: 0 };
  const cutoff = sqlTimestamp(Date.now() - retentionDays * 24 * 60 * 60 * 1000);
  let archivedRows = 0;
  let archivedObjects = 0;

  for (let batchIndex = 0; batchIndex < maxBatches; batchIndex += 1) {
    const result = await env.DB.prepare(`
      SELECT
        id, client_id, platform, app_version, build, os_version, device_model,
        grade_prefix, student_hash, event_name, event_time, properties,
        ip_hash, user_agent, created_at
      FROM analytics_events
      WHERE created_at < ? AND id <= ?
      ORDER BY id ASC
      LIMIT ?
    `).bind(cutoff, lastRollupId, batchSize).all<AnalyticsEventRow>();
    const rows = result.results ?? [];
    if (rows.length === 0) return { archivedRows, archivedObjects };

    const firstId = rows[0].id;
    const lastId = rows[rows.length - 1].id;
    const createdDay = (rows[0].created_at || cutoff).slice(0, 10);
    const key = `raw-events/created_day=${createdDay}/events_${firstId}_${lastId}.ndjson`;
    const body = rows.map((row) => JSON.stringify(row)).join("\n") + "\n";

    await env.ANALYTICS_ARCHIVE.put(key, body, {
      httpMetadata: { contentType: "application/x-ndjson; charset=utf-8" },
      customMetadata: {
        first_id: String(firstId),
        last_id: String(lastId),
        row_count: String(rows.length),
        cutoff,
        archived_at: new Date().toISOString(),
      },
    });

    await env.DB.prepare(`
      DELETE FROM analytics_events
      WHERE id >= ? AND id <= ? AND created_at < ? AND id <= ?
    `).bind(firstId, lastId, cutoff, lastRollupId).run();

    archivedRows += rows.length;
    archivedObjects += 1;

    if (rows.length < batchSize) return { archivedRows, archivedObjects };
  }
  return { archivedRows, archivedObjects };
}

async function loadDashboardResponse(request: Request, env: Env, range: PeriodRange): Promise<Response> {
  const ttlSeconds = intEnv(env.BI_CACHE_TTL_SECONDS, 60);
  const cacheUrl = new URL(request.url);
  cacheUrl.search = `?range=${encodeURIComponent(range)}`;
  const cacheKey = new Request(cacheUrl.toString(), { method: "GET" });
  const cache = defaultCache();

  if (ttlSeconds > 0) {
    const cached = await cache.match(cacheKey);
    if (cached) {
      const headers = new Headers(cached.headers);
      headers.set("X-LoveACE-Cache", "HIT");
      return new Response(cached.body, {
        status: cached.status,
        statusText: cached.statusText,
        headers,
      });
    }
  }

  const startedAt = Date.now();
  const data = await loadDashboardData(env.DB, range);
  const response = json(data, 200, {
    "Cache-Control": ttlSeconds > 0
      ? `public, max-age=${ttlSeconds}, s-maxage=${ttlSeconds}`
      : "no-store",
    "Server-Timing": `bi;dur=${Date.now() - startedAt}`,
    "X-LoveACE-Cache": "MISS",
  });
  if (ttlSeconds > 0) await cache.put(cacheKey, response.clone());
  return response;
}

function defaultCache(): Cache {
  return (caches as unknown as { default: Cache }).default;
}

async function ingestEvents(request: Request, env: Env): Promise<Response> {
  const body = await request.text();
  if (new TextEncoder().encode(body).byteLength > intEnv(env.MAX_BODY_BYTES, 32768)) {
    return json({ ok: false, error: "request_body_too_large" }, 413);
  }

  const authError = await authenticateRequest(request, body, env);
  if (authError) return authError;

  let payload: EventsIn;
  try {
    payload = JSON.parse(body) as EventsIn;
  } catch {
    return json({ ok: false, error: "invalid_payload" }, 400);
  }

  const validationError = validatePayload(payload, intEnv(env.MAX_EVENTS_PER_REQUEST, 50));
  if (validationError) return json({ ok: false, error: validationError }, 400);
  if (payload.events.length === 0) return json({ ok: true, accepted: 0 });
  if (!env.ANALYTICS_IP_HASH_SALT) return json({ ok: false, error: "server_misconfigured" }, 503);

  const ip = request.headers.get("CF-Connecting-IP") ?? "";
  const ipHash = ip ? await sha256Hex(`${env.ANALYTICS_IP_HASH_SALT}:${ip}`) : null;
  const rateLimit = intEnv(env.RATE_LIMIT_PER_MINUTE, 60);
  const rateError = await checkRateLimits(env.DB, rateLimit, [
    `ip:${ipHash ?? "unknown"}`,
    `client:${payload.client_id}`,
    ...(payload.student_hash ? [`student:${payload.student_hash}`] : []),
  ]);
  if (rateError) return rateError;

  const nonce = header(request, "X-LoveACE-Nonce");
  const replayError = await recordNonce(env.DB, nonce, intEnv(env.NONCE_TTL_SECONDS, 600));
  if (replayError) return replayError;

  const userAgent = request.headers.get("User-Agent");
  const statements = payload.events.map((event) => {
    return env.DB.prepare(
      `INSERT INTO analytics_events (
        client_id, platform, app_version, build, os_version, device_model,
        grade_prefix, student_hash, event_name, event_time, properties,
        ip_hash, user_agent
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
    ).bind(
      payload.client_id,
      payload.platform,
      payload.app_version,
      cleanString(payload.build, 64),
      cleanString(payload.os_version, 128),
      cleanString(payload.device_model, 128),
      payload.grade_prefix ?? null,
      payload.student_hash ?? null,
      event.name,
      new Date(event.time).toISOString(),
      JSON.stringify(sanitizeProperties(event.properties ?? {})),
      ipHash,
      cleanString(userAgent, 512),
    );
  });

  await env.DB.batch(statements);
  return json({ ok: true, accepted: payload.events.length });
}

async function serveDashboard(request: Request, env: Env): Promise<Response> {
  const url = new URL(request.url);
  url.pathname = "/bi.html";
  const response = await env.ASSETS.fetch(new Request(url, request));
  const headers = new Headers(response.headers);
  headers.set("Content-Type", "text/html; charset=utf-8");
  headers.set("Cache-Control", "public, max-age=300");
  return new Response(response.body, {
    status: response.status,
    headers,
  });
}

async function loadDashboardData(db: D1Database, range: PeriodRange): Promise<AnalyticsDashboardData> {
  const rollupReady = await getState(db, "rollup:ready") === "1";
  if (rollupReady) return loadRollupDashboardData(db, range);
  return loadRawDashboardData(db, range);
}

async function loadRollupDashboardData(db: D1Database, range: PeriodRange): Promise<AnalyticsDashboardData> {
  const period = periodInfo(range);
  const startDay = shanghaiPeriodStartDay(range);
  const dayStart = shanghaiPeriodStartDay("day");
  const weekStart = shanghaiPeriodStartDay("week");
  const monthStart = shanghaiPeriodStartDay("month");
  const last24Hour = shanghaiHourOffset(-23);
  const lastEventAtUtc = await getState(db, "rollup:last_event_at");

  const [
    totalEvents,
    clients,
    users,
    events24h,
    events7d,
    dau,
    wau,
    mau,
    eventDistribution,
    platformDistribution,
    gradeDistribution,
    screenDistribution,
    featureDistribution,
    normalizedUsage,
    versions,
    authStats,
    otaStats,
    trend,
  ] = await Promise.all([
    rollupCountSum(db, "total", startDay),
    rollupIdentityDistinct(db, "total", "client", startDay),
    rollupIdentityDistinct(db, "total", "user", startDay),
    rollupHourlyCountSum(db, "total", last24Hour),
    rollupCountSum(db, "total", weekStart),
    rollupIdentityDistinct(db, "total", "user", dayStart),
    rollupIdentityDistinct(db, "total", "user", weekStart),
    rollupIdentityDistinct(db, "total", "user", monthStart),
    rollupCountRows(db, "event", 8, startDay),
    rollupIdentityRows(db, "platform", 4, startDay),
    rollupIdentityRows(db, "grade", 8, startDay),
    rollupCountRows(db, "screen", 8, startDay),
    rollupCountRows(db, "feature", 8, startDay),
    rollupNormalizedUsageRows(db, 10, startDay),
    rollupVersionRows(db, 6, startDay),
    rollupCountRows(db, "auth", 8, startDay),
    rollupCountRows(db, "ota", 8, startDay),
    rollupTrendRows(db, range, startDay),
  ]);

  return {
    period,
    summary: {
      total_events: totalEvents,
      clients,
      users,
      events_24h: events24h,
      events_7d: events7d,
      dau,
      wau,
      mau,
      last_event_at: lastEventAtUtc ? utcSqlToShanghai(lastEventAtUtc) : null,
    },
    eventDistribution,
    platformDistribution,
    gradeDistribution,
    screenDistribution,
    featureDistribution,
    normalizedUsage,
    versions,
    authStats,
    otaStats,
    trend,
    generatedAt: new Date().toISOString(),
  };
}

async function rollupCountSum(db: D1Database, metric: string, startDay: string): Promise<number> {
  const row = await db.prepare(`
    SELECT COALESCE(SUM(count), 0) AS count
    FROM analytics_rollup_counts
    WHERE metric = ? AND bucket_day >= ?
  `).bind(metric, startDay).first<{ count: number }>();
  return Number(row?.count ?? 0);
}

async function rollupHourlyCountSum(db: D1Database, metric: string, startHour: string): Promise<number> {
  const row = await db.prepare(`
    SELECT COALESCE(SUM(count), 0) AS count
    FROM analytics_rollup_counts
    WHERE metric = ? AND bucket_hour >= ?
  `).bind(metric, startHour).first<{ count: number }>();
  return Number(row?.count ?? 0);
}

async function rollupIdentityDistinct(
  db: D1Database,
  metric: string,
  identityType: string,
  startDay: string,
): Promise<number> {
  const row = await db.prepare(`
    SELECT COUNT(DISTINCT identity_value) AS count
    FROM analytics_rollup_identities
    WHERE bucket_scope = 'day'
      AND metric = ?
      AND identity_type = ?
      AND bucket_key >= ?
  `).bind(metric, identityType, startDay).first<{ count: number }>();
  return Number(row?.count ?? 0);
}

async function rollupCountRows(
  db: D1Database,
  metric: string,
  limit: number,
  startDay: string,
): Promise<CountRow[]> {
  const result = await db.prepare(`
    SELECT NULLIF(label, '') AS label, SUM(count) AS count
    FROM analytics_rollup_counts
    WHERE metric = ? AND bucket_day >= ? AND label != ''
    GROUP BY label
    ORDER BY count DESC, label ASC
    LIMIT ?
  `).bind(metric, startDay, limit).all<CountRow>();
  return result.results ?? [];
}

async function rollupIdentityRows(
  db: D1Database,
  metric: string,
  limit: number,
  startDay: string,
): Promise<CountRow[]> {
  const result = await db.prepare(`
    SELECT NULLIF(label, '') AS label, COUNT(DISTINCT identity_value) AS count
    FROM analytics_rollup_identities
    WHERE bucket_scope = 'day'
      AND metric = ?
      AND identity_type = 'user'
      AND bucket_key >= ?
      AND label != ''
    GROUP BY label
    ORDER BY count DESC, label ASC
    LIMIT ?
  `).bind(metric, startDay, limit).all<CountRow>();
  return result.results ?? [];
}

async function rollupVersionRows(
  db: D1Database,
  limit: number,
  startDay: string,
): Promise<VersionRow[]> {
  const result = await db.prepare(`
    WITH events AS (
      SELECT platform, app_version, SUM(count) AS events
      FROM analytics_rollup_counts
      WHERE metric = 'version' AND bucket_day >= ?
      GROUP BY platform, app_version
    ), clients AS (
      SELECT platform, app_version, COUNT(DISTINCT identity_value) AS clients
      FROM analytics_rollup_identities
      WHERE bucket_scope = 'day'
        AND metric = 'version'
        AND identity_type = 'client'
        AND bucket_key >= ?
      GROUP BY platform, app_version
    )
    SELECT
      events.platform,
      events.app_version,
      COALESCE(clients.clients, 0) AS clients,
      events.events
    FROM events
    LEFT JOIN clients
      ON clients.platform = events.platform
      AND clients.app_version = events.app_version
    ORDER BY events.events DESC, events.platform ASC, events.app_version DESC
    LIMIT ?
  `).bind(startDay, startDay, limit).all<VersionRow>();
  return result.results ?? [];
}

async function rollupNormalizedUsageRows(
  db: D1Database,
  limit: number,
  startDay: string,
): Promise<UsageRow[]> {
  const result = await db.prepare(`
    WITH events AS (
      SELECT
        label,
        SUM(count) AS count,
        SUM(CASE WHEN platform = 'android' THEN count ELSE 0 END) AS android,
        SUM(CASE WHEN platform = 'ios' THEN count ELSE 0 END) AS ios,
        SUM(CASE WHEN platform IN ('windows', 'macos', 'linux', 'desktop') THEN count ELSE 0 END) AS desktop
      FROM analytics_rollup_counts
      WHERE metric = 'normalized' AND bucket_day >= ? AND label != ''
      GROUP BY label
    ), users AS (
      SELECT label, COUNT(DISTINCT identity_value) AS users
      FROM analytics_rollup_identities
      WHERE bucket_scope = 'day'
        AND metric = 'normalized'
        AND identity_type = 'user'
        AND bucket_key >= ?
        AND label != ''
      GROUP BY label
    )
    SELECT
      NULLIF(events.label, '') AS label,
      events.count,
      COALESCE(users.users, 0) AS users,
      events.android,
      events.ios,
      events.desktop
    FROM events
    LEFT JOIN users ON users.label = events.label
    ORDER BY users DESC, count DESC, label ASC
    LIMIT ?
  `).bind(startDay, startDay, limit).all<UsageRow>();
  return result.results ?? [];
}

async function rollupTrendRows(db: D1Database, range: PeriodRange, startDay: string): Promise<TrendRow[]> {
  if (range === "day") {
    const startHour = `${startDay} 00`;
    const result = await db.prepare(`
      WITH events AS (
        SELECT bucket_hour AS bucket_key, substr(bucket_hour, 12, 2) || ':00' AS bucket, SUM(count) AS count
        FROM analytics_rollup_counts
        WHERE metric = 'total' AND bucket_hour >= ?
        GROUP BY bucket_hour
      ), users AS (
        SELECT bucket_key, COUNT(DISTINCT identity_value) AS users
        FROM analytics_rollup_identities
        WHERE bucket_scope = 'hour'
          AND metric = 'trend'
          AND identity_type = 'user'
          AND bucket_key >= ?
        GROUP BY bucket_key
      )
      SELECT events.bucket, events.count, COALESCE(users.users, 0) AS users
      FROM events
      LEFT JOIN users ON users.bucket_key = events.bucket_key
      ORDER BY events.bucket_key ASC
    `).bind(startHour, startHour).all<TrendRow>();
    return result.results ?? [];
  }

  const result = await db.prepare(`
    WITH events AS (
      SELECT bucket_day AS bucket, SUM(count) AS count
      FROM analytics_rollup_counts
      WHERE metric = 'total' AND bucket_day >= ?
      GROUP BY bucket_day
    ), users AS (
      SELECT bucket_key AS bucket, COUNT(DISTINCT identity_value) AS users
      FROM analytics_rollup_identities
      WHERE bucket_scope = 'day'
        AND metric = 'total'
        AND identity_type = 'user'
        AND bucket_key >= ?
      GROUP BY bucket_key
    )
    SELECT events.bucket, events.count, COALESCE(users.users, 0) AS users
    FROM events
    LEFT JOIN users ON users.bucket = events.bucket
    ORDER BY events.bucket ASC
  `).bind(startDay, startDay).all<TrendRow>();
  return result.results ?? [];
}

async function loadRawDashboardData(db: D1Database, range: PeriodRange): Promise<AnalyticsDashboardData> {
  const period = periodInfo(range);
  const where = periodWhere(range);
  const trendBucket = trendBucketExpression(range);
  const [
    summary,
    eventDistribution,
    platformDistribution,
    gradeDistribution,
    screenDistribution,
    featureDistribution,
    normalizedUsage,
    versions,
    authStats,
    otaStats,
    trend,
  ] = await Promise.all([
    db.prepare(`
      SELECT
        COUNT(*) AS total_events,
        COUNT(DISTINCT client_id) AS clients,
        COUNT(DISTINCT student_hash) AS users,
        SUM(CASE WHEN created_at >= datetime('now', '-24 hours') THEN 1 ELSE 0 END) AS events_24h,
        SUM(CASE WHEN created_at >= datetime('now', '-7 days') THEN 1 ELSE 0 END) AS events_7d,
        (SELECT COUNT(DISTINCT student_hash) FROM analytics_events WHERE created_at >= ${shanghaiDayStartUtc()}) AS dau,
        (SELECT COUNT(DISTINCT student_hash) FROM analytics_events WHERE created_at >= ${shanghaiWeekStartUtc()}) AS wau,
        (SELECT COUNT(DISTINCT student_hash) FROM analytics_events WHERE created_at >= ${shanghaiMonthStartUtc()}) AS mau,
        MAX(datetime(created_at, '+8 hours')) AS last_event_at
      FROM analytics_events
      WHERE ${where}
    `).first<SummaryRow>(),
    countRows(db, "event_name", 8, where),
    platformRows(db, 4, where),
    gradeRows(db, 8, where),
    jsonPropertyRows(db, "screen", "screen_view", 8, where),
    jsonPropertyRows(db, "feature", "feature_action", 8, where),
    normalizedUsageRows(db, 10, where),
    db.prepare(`
      SELECT platform, app_version, COUNT(DISTINCT client_id) AS clients, COUNT(*) AS events
      FROM analytics_events
      WHERE ${where}
      GROUP BY platform, app_version
      ORDER BY events DESC, platform ASC, app_version DESC
      LIMIT 6
    `).all<VersionRow>(),
    db.prepare(`
      SELECT event_name AS label, COUNT(*) AS count
      FROM analytics_events
      WHERE ${where} AND event_name IN ('login_success', 'login_failed', 'session_expired', 'session_reconnect_success', 'session_reconnect_failed')
      GROUP BY event_name
      ORDER BY count DESC, event_name ASC
    `).all<CountRow>(),
    db.prepare(`
      SELECT event_name AS label, COUNT(*) AS count
      FROM analytics_events
      WHERE ${where} AND event_name IN ('ota_check', 'ota_update_click')
      GROUP BY event_name
      ORDER BY count DESC, event_name ASC
    `).all<CountRow>(),
    db.prepare(`
      SELECT ${trendBucket} AS bucket, COUNT(*) AS count, COUNT(DISTINCT student_hash) AS users
      FROM analytics_events
      WHERE ${where}
      GROUP BY bucket
      ORDER BY bucket ASC
    `).all<TrendRow>(),
  ]);

  return {
    period,
    summary: summary ?? emptySummary(),
    eventDistribution: eventDistribution.results ?? [],
    platformDistribution: platformDistribution.results ?? [],
    gradeDistribution: gradeDistribution.results ?? [],
    screenDistribution: screenDistribution.results ?? [],
    featureDistribution: featureDistribution.results ?? [],
    normalizedUsage: normalizedUsage.results ?? [],
    versions: versions.results ?? [],
    authStats: authStats.results ?? [],
    otaStats: otaStats.results ?? [],
    trend: trend.results ?? [],
    generatedAt: new Date().toISOString(),
  };
}

function gradeRows(db: D1Database, limit: number, where: string): Promise<D1Result<CountRow>> {
  return db.prepare(`
    SELECT grade_prefix AS label, COUNT(DISTINCT student_hash) AS count
    FROM analytics_events
    WHERE ${where} AND grade_prefix IS NOT NULL AND student_hash IS NOT NULL
    GROUP BY grade_prefix
    ORDER BY count DESC, grade_prefix ASC
    LIMIT ?
  `).bind(limit).all<CountRow>();
}

function platformRows(db: D1Database, limit: number, where: string): Promise<D1Result<CountRow>> {
  return db.prepare(`
    SELECT platform AS label, COUNT(DISTINCT student_hash) AS count
    FROM analytics_events
    WHERE ${where} AND platform IS NOT NULL AND student_hash IS NOT NULL
    GROUP BY platform
    ORDER BY count DESC, platform ASC
    LIMIT ?
  `).bind(limit).all<CountRow>();
}

function countRows(db: D1Database, column: string, limit: number, where = "1 = 1"): Promise<D1Result<CountRow>> {
  return db.prepare(`
    SELECT ${column} AS label, COUNT(*) AS count
    FROM analytics_events
    WHERE ${where}
    GROUP BY ${column}
    ORDER BY count DESC, ${column} ASC
    LIMIT ?
  `).bind(limit).all<CountRow>();
}

function jsonPropertyRows(db: D1Database, key: string, eventName: string, limit: number, where: string): Promise<D1Result<CountRow>> {
  return db.prepare(`
    SELECT json_extract(properties, ?) AS label, COUNT(*) AS count
    FROM analytics_events
    WHERE ${where} AND event_name = ? AND json_extract(properties, ?) IS NOT NULL AND json_extract(properties, ?) != ''
    GROUP BY label
    ORDER BY count DESC, label ASC
    LIMIT ?
  `).bind(`$.${key}`, eventName, `$.${key}`, `$.${key}`, limit).all<CountRow>();
}

function normalizedUsageRows(db: D1Database, limit: number, where: string): Promise<D1Result<UsageRow>> {
  return db.prepare(`
    SELECT
      label,
      COUNT(*) AS count,
      COUNT(DISTINCT student_hash) AS users,
      SUM(CASE WHEN platform = 'android' THEN 1 ELSE 0 END) AS android,
      SUM(CASE WHEN platform = 'ios' THEN 1 ELSE 0 END) AS ios,
      SUM(CASE WHEN platform IN ('windows', 'macos', 'linux', 'desktop') THEN 1 ELSE 0 END) AS desktop
    FROM (
      SELECT
        platform,
        student_hash,
        CASE
          WHEN event_name = 'screen_view' THEN
            CASE json_extract(properties, '$.screen')
              WHEN 'HomeRoute' THEN '查看首页'
              WHEN '首页' THEN '查看首页'
              WHEN 'AACRoute' THEN '查看爱安财'
              WHEN '爱安财' THEN '查看爱安财'
              WHEN 'MoreRoute' THEN '查看更多'
              WHEN '更多' THEN '查看更多'
              WHEN 'SettingsRoute' THEN '查看我的'
              WHEN '我的' THEN '查看我的'
              WHEN '设置' THEN '查看我的'
              WHEN '成绩查询' THEN '查看成绩查询'
              WHEN '学期成绩' THEN '查看成绩查询'
              WHEN '考试安排' THEN '查看考试安排'
              WHEN '课表查询' THEN '查看课表查询'
              WHEN '课程表' THEN '查看课表查询'
              WHEN '学期课表' THEN '查看课表查询'
              WHEN '培养方案' THEN '查看培养方案'
              WHEN '自动教师评价' THEN '查看教师评价'
              WHEN '教师评价' THEN '查看教师评价'
              WHEN '自动评教' THEN '查看教师评价'
              WHEN '一卡通' THEN '查看一卡通'
              WHEN '电费查询' THEN '查看电费查询'
              WHEN '宿舍电费' THEN '查看电费查询'
              WHEN '零星维修' THEN '查看零星维修'
              WHEN '报修' THEN '查看零星维修'
              WHEN '宿舍门卡' THEN '查看宿舍门卡'
              WHEN '门卡' THEN '查看宿舍门卡'
              WHEN '竞赛信息' THEN '查看竞赛信息'
              WHEN '竞赛获奖' THEN '查看竞赛信息'
              WHEN '劳动俱乐部' THEN '查看劳动俱乐部'
              ELSE '查看' || json_extract(properties, '$.screen')
            END
          WHEN event_name = 'feature_action' THEN
            CASE
              WHEN json_extract(properties, '$.feature') IN ('成绩查询', '学期成绩') THEN '成绩查询'
              WHEN json_extract(properties, '$.feature') = '考试安排' THEN '考试安排'
              WHEN json_extract(properties, '$.feature') IN ('课表查询', '课程表', '学期课表') THEN '课表查询'
              WHEN json_extract(properties, '$.feature') = '培养方案' THEN '培养方案'
              WHEN json_extract(properties, '$.feature') IN ('自动教师评价', '教师评价', '自动评教') THEN '教师评价'
              WHEN json_extract(properties, '$.feature') = '一卡通' THEN '一卡通'
              WHEN json_extract(properties, '$.feature') IN ('电费查询', '宿舍电费') THEN '电费查询'
              WHEN json_extract(properties, '$.feature') IN ('零星维修', '报修') THEN '零星维修'
              WHEN json_extract(properties, '$.feature') IN ('宿舍门卡', '门卡') THEN '宿舍门卡'
              WHEN json_extract(properties, '$.feature') IN ('竞赛信息', '竞赛获奖') THEN '竞赛信息'
              WHEN json_extract(properties, '$.feature') = '劳动俱乐部' THEN '劳动俱乐部'
              WHEN json_extract(properties, '$.feature') = '学业分析' THEN '学业分析'
              WHEN json_extract(properties, '$.feature') = 'auth' AND json_extract(properties, '$.action') = 'logout' THEN '退出登录'
              ELSE json_extract(properties, '$.feature')
            END
          ELSE NULL
        END AS label
      FROM analytics_events
      WHERE ${where} AND event_name IN ('screen_view', 'feature_action')
    ) AS normalized
    WHERE label IS NOT NULL AND label != ''
    GROUP BY label
    ORDER BY users DESC, count DESC, label ASC
    LIMIT ?
  `).bind(limit).all<UsageRow>();
}

function parsePeriodRange(value: string | null): PeriodRange {
  if (value === "week" || value === "month") return value;
  return "day";
}

function periodInfo(range: PeriodRange): PeriodInfo {
  if (range === "week") return { range, label: "近 7 天", bucketLabel: "DAY" };
  if (range === "month") return { range, label: "本月", bucketLabel: "DAY" };
  return { range, label: "今日", bucketLabel: "HOUR" };
}

function periodWhere(range: PeriodRange): string {
  if (range === "week") return `created_at >= ${shanghaiWeekStartUtc()}`;
  if (range === "month") return `created_at >= ${shanghaiMonthStartUtc()}`;
  return `created_at >= ${shanghaiDayStartUtc()}`;
}

function trendBucketExpression(range: PeriodRange): string {
  if (range === "day") return "strftime('%H:00', datetime(created_at, '+8 hours'))";
  return "strftime('%Y-%m-%d', datetime(created_at, '+8 hours'))";
}

function shanghaiDayStartUtc(): string {
  return "datetime('now', '+8 hours', 'start of day', '-8 hours')";
}

function shanghaiWeekStartUtc(): string {
  return "datetime('now', '+8 hours', '-6 days', 'start of day', '-8 hours')";
}

function shanghaiMonthStartUtc(): string {
  return "datetime('now', '+8 hours', 'start of month', '-8 hours')";
}

function emptySummary(): SummaryRow {
  return { total_events: 0, clients: 0, users: 0, events_24h: 0, events_7d: 0, dau: 0, wau: 0, mau: 0, last_event_at: null };
}

async function authenticateRequest(request: Request, body: string, env: Env): Promise<Response | null> {
  if (!env.ANALYTICS_API_KEY || !env.ANALYTICS_SIGNING_SECRET) {
    return json({ ok: false, error: "server_misconfigured" }, 503);
  }

  if (!constantTimeEqual(header(request, "Authorization"), `Bearer ${env.ANALYTICS_API_KEY}`)) {
    return json({ ok: false, error: "invalid_api_key" }, 401);
  }

  const timestampRaw = header(request, "X-LoveACE-Timestamp");
  const nonce = header(request, "X-LoveACE-Nonce");
  const signature = header(request, "X-LoveACE-Signature");
  if (!timestampRaw || !nonce || !signature) {
    return json({ ok: false, error: "missing_auth_header" }, 401);
  }

  const timestamp = Number(timestampRaw);
  if (!Number.isInteger(timestamp)) return json({ ok: false, error: "invalid_timestamp" }, 401);
  const skew = intEnv(env.TIMESTAMP_SKEW_SECONDS, 300);
  if (Math.abs(Math.floor(Date.now() / 1000) - timestamp) > skew) {
    return json({ ok: false, error: "expired_timestamp" }, 401);
  }

  const bodyHash = await sha256Hex(body);
  const expected = await hmacSha256Hex(env.ANALYTICS_SIGNING_SECRET, `${timestampRaw}.${nonce}.${bodyHash}`);
  if (!constantTimeEqual(signature, expected)) {
    return json({ ok: false, error: "invalid_signature" }, 401);
  }

  return null;
}

async function checkRateLimits(db: D1Database, limit: number, keys: string[]): Promise<Response | null> {
  const windowStart = Math.floor(Date.now() / 60000) * 60;
  for (const key of keys) {
    const current = await db.prepare(
      "SELECT count FROM analytics_rate_limits WHERE key = ? AND window_start = ?",
    ).bind(key, windowStart).first<{ count: number }>();

    if ((current?.count ?? 0) >= limit) {
      return json({ ok: false, error: "rate_limited" }, 429);
    }

    await db.prepare(
      `INSERT INTO analytics_rate_limits (key, window_start, count)
       VALUES (?, ?, 1)
       ON CONFLICT(key, window_start) DO UPDATE SET count = count + 1`,
    ).bind(key, windowStart).run();
  }

  await db.prepare("DELETE FROM analytics_rate_limits WHERE window_start < ?").bind(windowStart - 3600).run();
  return null;
}

async function recordNonce(db: D1Database, nonce: string, ttlSeconds: number): Promise<Response | null> {
  const now = Math.floor(Date.now() / 1000);
  await db.prepare("DELETE FROM analytics_nonces WHERE expires_at < ?").bind(now).run();

  try {
    await db.prepare("INSERT INTO analytics_nonces (nonce, expires_at) VALUES (?, ?)")
      .bind(nonce, now + ttlSeconds)
      .run();
  } catch {
    return json({ ok: false, error: "replay_detected" }, 401);
  }

  return null;
}

function validatePayload(payload: EventsIn, maxEvents: number): string | null {
  if (!isString(payload.client_id, 8, 128)) return "invalid_client_id";
  if (!["android", "ios", "desktop", "windows", "macos", "linux"].includes(payload.platform)) return "invalid_platform";
  if (!isString(payload.app_version, 1, 64)) return "invalid_app_version";
  if (payload.build != null && !isString(payload.build, 0, 64)) return "invalid_build";
  if (payload.os_version != null && !isString(payload.os_version, 0, 128)) return "invalid_os_version";
  if (payload.device_model != null && !isString(payload.device_model, 0, 128)) return "invalid_device_model";
  if (payload.grade_prefix != null && !/^\d{4}$/.test(payload.grade_prefix)) return "invalid_grade_prefix";
  if (payload.student_hash != null && !isString(payload.student_hash, 32, 64)) return "invalid_student_hash";
  if (!Array.isArray(payload.events)) return "invalid_events";
  if (payload.events.length > maxEvents) return "too_many_events";

  for (const event of payload.events) {
    if (!ALLOWED_EVENTS.has(event.name)) return "unknown_event";
    if (Number.isNaN(new Date(event.time).getTime())) return "invalid_event_time";
    if (event.properties != null && !isPlainObject(event.properties)) return "invalid_properties";
  }

  return null;
}

function sanitizeProperties(properties: Record<string, unknown>): Record<string, unknown> {
  const clean: Record<string, unknown> = {};
  for (const [key, value] of Object.entries(properties)) {
    if (!ALLOWED_PROPERTY_KEYS.has(key)) continue;
    if (typeof value === "string") clean[key] = value.slice(0, 128);
    else if (typeof value === "number" || typeof value === "boolean" || value === null) clean[key] = value;
  }
  return clean;
}

function header(request: Request, name: string): string {
  return request.headers.get(name) ?? "";
}

function intEnv(value: string | undefined, fallback: number): number {
  const parsed = Number(value);
  return Number.isInteger(parsed) && parsed > 0 ? parsed : fallback;
}

function parsePositiveInt(value: string | null): number | undefined {
  const parsed = Number(value);
  return Number.isInteger(parsed) && parsed > 0 ? parsed : undefined;
}

async function getState(db: D1Database, key: string): Promise<string | null> {
  const row = await db.prepare("SELECT value FROM analytics_rollup_state WHERE key = ?")
    .bind(key)
    .first<{ value: string }>();
  return row?.value ?? null;
}

async function getNumberState(db: D1Database, key: string, fallback: number): Promise<number> {
  const value = await getState(db, key);
  const parsed = Number(value);
  return Number.isInteger(parsed) && parsed >= 0 ? parsed : fallback;
}

async function setState(db: D1Database, key: string, value: string): Promise<void> {
  await db.prepare(`
    INSERT INTO analytics_rollup_state (key, value, updated_at)
    VALUES (?, ?, CURRENT_TIMESTAMP)
    ON CONFLICT(key) DO UPDATE SET
      value = excluded.value,
      updated_at = excluded.updated_at
  `).bind(key, value).run();
}

function sqlTimestamp(value: number): string {
  return new Date(value).toISOString().slice(0, 19).replace("T", " ");
}

function shanghaiBuckets(value: string): { day: string; hour: string } {
  const shifted = parseUtcTimestamp(value) + 8 * 60 * 60 * 1000;
  const iso = new Date(shifted).toISOString();
  return {
    day: iso.slice(0, 10),
    hour: iso.slice(0, 13).replace("T", " "),
  };
}

function shanghaiPeriodStartDay(range: PeriodRange): string {
  if (range === "week") return shanghaiDayOffset(-6);
  if (range === "month") return shanghaiMonthStartDay();
  return shanghaiDayOffset(0);
}

function shanghaiDayOffset(offsetDays: number): string {
  return shiftedShanghaiIso(Date.now() + offsetDays * 24 * 60 * 60 * 1000).slice(0, 10);
}

function shanghaiHourOffset(offsetHours: number): string {
  return shiftedShanghaiIso(Date.now() + offsetHours * 60 * 60 * 1000).slice(0, 13).replace("T", " ");
}

function shanghaiMonthStartDay(): string {
  const shifted = new Date(Date.now() + 8 * 60 * 60 * 1000);
  const year = shifted.getUTCFullYear();
  const month = String(shifted.getUTCMonth() + 1).padStart(2, "0");
  return `${year}-${month}-01`;
}

function shiftedShanghaiIso(utcMs: number): string {
  return new Date(utcMs + 8 * 60 * 60 * 1000).toISOString();
}

function parseUtcTimestamp(value: string): number {
  if (value.includes("T")) {
    const parsed = Date.parse(value.endsWith("Z") || /[+-]\d\d:?\d\d$/.test(value) ? value : `${value}Z`);
    return Number.isNaN(parsed) ? Date.now() : parsed;
  }
  const match = /^(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2}):(\d{2})$/.exec(value);
  if (!match) return Date.now();
  return Date.UTC(
    Number(match[1]),
    Number(match[2]) - 1,
    Number(match[3]),
    Number(match[4]),
    Number(match[5]),
    Number(match[6]),
  );
}

function utcSqlToShanghai(value: string): string {
  return sqlTimestamp(parseUtcTimestamp(value) + 8 * 60 * 60 * 1000);
}

function maxString(values: string[]): string | null {
  let current: string | null = null;
  for (const value of values) {
    if (!current || value > current) current = value;
  }
  return current;
}

function cleanLabel(value: string | null | undefined): string {
  if (typeof value !== "string") return "";
  return value.trim().replace(/\u001f/g, "").slice(0, 128);
}

function parsePropertiesJson(value: string): Record<string, unknown> {
  try {
    const parsed = JSON.parse(value) as unknown;
    return isPlainObject(parsed) ? parsed : {};
  } catch {
    return {};
  }
}

function stringProperty(properties: Record<string, unknown>, key: string): string {
  const value = properties[key];
  return typeof value === "string" ? cleanLabel(value) : "";
}

function isAuthEvent(eventName: string): boolean {
  return [
    "login_success",
    "login_failed",
    "session_expired",
    "session_reconnect_success",
    "session_reconnect_failed",
  ].includes(eventName);
}

function isOtaEvent(eventName: string): boolean {
  return eventName === "ota_check" || eventName === "ota_update_click";
}

function normalizedUsageLabel(eventName: string, screen: string, feature: string, action: string): string {
  if (eventName === "screen_view") {
    if (!screen) return "";
    const screenLabels: Record<string, string> = {
      HomeRoute: "查看首页",
      首页: "查看首页",
      AACRoute: "查看爱安财",
      爱安财: "查看爱安财",
      MoreRoute: "查看更多",
      更多: "查看更多",
      SettingsRoute: "查看我的",
      我的: "查看我的",
      设置: "查看我的",
      成绩查询: "查看成绩查询",
      学期成绩: "查看成绩查询",
      考试安排: "查看考试安排",
      课表查询: "查看课表查询",
      课程表: "查看课表查询",
      学期课表: "查看课表查询",
      培养方案: "查看培养方案",
      自动教师评价: "查看教师评价",
      教师评价: "查看教师评价",
      自动评教: "查看教师评价",
      一卡通: "查看一卡通",
      电费查询: "查看电费查询",
      宿舍电费: "查看电费查询",
      零星维修: "查看零星维修",
      报修: "查看零星维修",
      宿舍门卡: "查看宿舍门卡",
      门卡: "查看宿舍门卡",
      竞赛信息: "查看竞赛信息",
      竞赛获奖: "查看竞赛信息",
      劳动俱乐部: "查看劳动俱乐部",
    };
    return screenLabels[screen] ?? `查看${screen}`;
  }

  if (eventName === "feature_action") {
    if (feature === "auth" && action === "logout") return "退出登录";
    if (!feature) return "";
    const featureLabels: Record<string, string> = {
      成绩查询: "成绩查询",
      学期成绩: "成绩查询",
      考试安排: "考试安排",
      课表查询: "课表查询",
      课程表: "课表查询",
      学期课表: "课表查询",
      培养方案: "培养方案",
      自动教师评价: "教师评价",
      教师评价: "教师评价",
      自动评教: "教师评价",
      一卡通: "一卡通",
      电费查询: "电费查询",
      宿舍电费: "电费查询",
      零星维修: "零星维修",
      报修: "零星维修",
      宿舍门卡: "宿舍门卡",
      门卡: "宿舍门卡",
      竞赛信息: "竞赛信息",
      竞赛获奖: "竞赛信息",
      劳动俱乐部: "劳动俱乐部",
      学业分析: "学业分析",
    };
    return featureLabels[feature] ?? feature;
  }

  return "";
}

function isString(value: unknown, min: number, max: number): value is string {
  return typeof value === "string" && value.length >= min && value.length <= max;
}

function cleanString(value: string | null | undefined, max: number): string | null {
  if (typeof value !== "string") return null;
  return value.slice(0, max);
}

function isPlainObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function json(data: unknown, status = 200, headers: Record<string, string> = {}): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json; charset=utf-8", ...headers },
  });
}

async function sha256Hex(value: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return bytesToHex(new Uint8Array(digest));
}

async function hmacSha256Hex(secret: string, message: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(message));
  return bytesToHex(new Uint8Array(signature));
}

function bytesToHex(bytes: Uint8Array): string {
  return [...bytes].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

function constantTimeEqual(left: string, right: string): boolean {
  const max = Math.max(left.length, right.length);
  let diff = left.length ^ right.length;
  for (let index = 0; index < max; index += 1) {
    diff |= (left.charCodeAt(index) || 0) ^ (right.charCodeAt(index) || 0);
  }
  return diff === 0;
}
