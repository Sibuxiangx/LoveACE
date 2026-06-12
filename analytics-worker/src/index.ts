interface Env {
  DB: D1Database;
  ASSETS: Fetcher;
  ANALYTICS_API_KEY: string;
  ANALYTICS_SIGNING_SECRET: string;
  ANALYTICS_IP_HASH_SALT: string;
  MAX_BODY_BYTES?: string;
  MAX_EVENTS_PER_REQUEST?: string;
  NONCE_TTL_SECONDS?: string;
  RATE_LIMIT_PER_MINUTE?: string;
  TIMESTAMP_SKEW_SECONDS?: string;
}

interface EventIn {
  name: string;
  time: string;
  properties?: Record<string, unknown>;
}

interface EventsIn {
  client_id: string;
  platform: "android" | "ios";
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
  last_event_at: string | null;
}

interface CountRow {
  label: string | null;
  count: number;
}

interface VersionRow {
  app_version: string | null;
  clients: number;
  events: number;
}

interface TrendRow {
  bucket: string;
  count: number;
}

interface AnalyticsDashboardData {
  summary: SummaryRow;
  eventDistribution: CountRow[];
  platformDistribution: CountRow[];
  gradeDistribution: CountRow[];
  screenDistribution: CountRow[];
  featureDistribution: CountRow[];
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

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);

    if (request.method === "GET" && url.pathname === "/healthz") {
      return json({ ok: true });
    }

    if (request.method === "GET" && url.pathname === "/bi/data") {
      const data = await loadDashboardData(env.DB);
      return json(data, 200, { "Cache-Control": "no-store" });
    }

    if (request.method === "GET" && (url.pathname === "/" || url.pathname === "/bi")) {
      return serveDashboard(request, env);
    }

    if (request.method === "POST" && url.pathname === "/v1/events") {
      return ingestEvents(request, env);
    }

    return json({ ok: false, error: "not_found" }, 404);
  },
};

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

async function loadDashboardData(db: D1Database): Promise<AnalyticsDashboardData> {
  const [
    summary,
    eventDistribution,
    platformDistribution,
    gradeDistribution,
    screenDistribution,
    featureDistribution,
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
        MAX(created_at) AS last_event_at
      FROM analytics_events
    `).first<SummaryRow>(),
    countRows(db, "event_name", 8),
    countRows(db, "platform", 4),
    countRows(db, "grade_prefix", 8, "grade_prefix IS NOT NULL"),
    jsonPropertyRows(db, "screen", 8),
    jsonPropertyRows(db, "feature", 8),
    db.prepare(`
      SELECT app_version, COUNT(DISTINCT client_id) AS clients, COUNT(*) AS events
      FROM analytics_events
      GROUP BY app_version
      ORDER BY events DESC, app_version DESC
      LIMIT 6
    `).all<VersionRow>(),
    db.prepare(`
      SELECT event_name AS label, COUNT(*) AS count
      FROM analytics_events
      WHERE event_name IN ('login_success', 'login_failed', 'session_expired', 'session_reconnect_success', 'session_reconnect_failed')
      GROUP BY event_name
      ORDER BY count DESC, event_name ASC
    `).all<CountRow>(),
    db.prepare(`
      SELECT event_name AS label, COUNT(*) AS count
      FROM analytics_events
      WHERE event_name IN ('ota_check', 'ota_update_click')
      GROUP BY event_name
      ORDER BY count DESC, event_name ASC
    `).all<CountRow>(),
    db.prepare(`
      SELECT strftime('%Y-%m-%d %H:00', created_at) AS bucket, COUNT(*) AS count
      FROM analytics_events
      WHERE created_at >= datetime('now', '-24 hours')
      GROUP BY bucket
      ORDER BY bucket ASC
    `).all<TrendRow>(),
  ]);

  return {
    summary: summary ?? emptySummary(),
    eventDistribution: eventDistribution.results ?? [],
    platformDistribution: platformDistribution.results ?? [],
    gradeDistribution: gradeDistribution.results ?? [],
    screenDistribution: screenDistribution.results ?? [],
    featureDistribution: featureDistribution.results ?? [],
    versions: versions.results ?? [],
    authStats: authStats.results ?? [],
    otaStats: otaStats.results ?? [],
    trend: trend.results ?? [],
    generatedAt: new Date().toISOString(),
  };
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

function jsonPropertyRows(db: D1Database, key: string, limit: number): Promise<D1Result<CountRow>> {
  return db.prepare(`
    SELECT json_extract(properties, ?) AS label, COUNT(*) AS count
    FROM analytics_events
    WHERE json_extract(properties, ?) IS NOT NULL AND json_extract(properties, ?) != ''
    GROUP BY label
    ORDER BY count DESC, label ASC
    LIMIT ?
  `).bind(`$.${key}`, `$.${key}`, `$.${key}`, limit).all<CountRow>();
}

function emptySummary(): SummaryRow {
  return { total_events: 0, clients: 0, users: 0, events_24h: 0, events_7d: 0, last_event_at: null };
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
  if (payload.platform !== "android" && payload.platform !== "ios") return "invalid_platform";
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
