import QRCode from "qrcode";

interface Env {
  DB: D1Database;
  ASSETS: Fetcher;
  SMART_SELECT_SESSIONS: DurableObjectNamespace;
  ANALYTICS_API_KEY: string;
  ANALYTICS_SIGNING_SECRET: string;
  ANALYTICS_IP_HASH_SALT: string;
  MAX_BODY_BYTES?: string;
  MAX_EVENTS_PER_REQUEST?: string;
  NONCE_TTL_SECONDS?: string;
  RATE_LIMIT_PER_MINUTE?: string;
  TIMESTAMP_SKEW_SECONDS?: string;
  SMART_SELECT_SESSION_TTL_SECONDS?: string;
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

interface SmartSelectSessionRow {
  session_id: string;
  web_token_hash: string;
  pairing_token_hash: string;
  status: SmartSelectStatus;
  schema_version: number;
  selected_term_code: string | null;
  created_at: string;
  expires_at: string;
  connected_at: string | null;
  ready_at: string | null;
  last_heartbeat_at: string | null;
  error_message: string | null;
}

interface SmartSelectPayloadRow {
  dataset: string;
  payload_json: string;
  updated_at: string;
}

type SmartSelectStatus =
  | "waiting_mobile"
  | "mobile_connected"
  | "fetching_terms"
  | "fetching_schedule"
  | "fetching_plan"
  | "fetching_courses"
  | "uploading"
  | "ready"
  | "error"
  | "expired";

const SMART_SELECT_DATASETS = new Set([
  "terms",
  "selected_term",
  "student_schedule",
  "plan_options",
  "selected_plan_id",
  "plan_completion",
  "available_courses",
]);

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
      const data = await loadDashboardData(env.DB, parsePeriodRange(url.searchParams.get("range")));
      return json(data, 200, { "Cache-Control": "no-store" });
    }

    if (request.method === "GET" && url.pathname === "/smart-select") {
      return serveSmartSelect(request, env);
    }

    if (request.method === "POST" && url.pathname === "/v1/smart-select/sessions") {
      return createSmartSelectSession(request, env);
    }

    if (request.method === "GET" && url.pathname === "/v1/smart-select/session-data") {
      return loadSmartSelectSessionData(request, env);
    }

    if (request.method === "POST" && url.pathname === "/v1/smart-select/actions") {
      return saveSmartSelectActions(request, env);
    }

    if (request.method === "GET" && url.pathname.startsWith("/v1/smart-select/ws/")) {
      const sessionId = url.searchParams.get("session_id") ?? "";
      if (!isSmartSelectSessionId(sessionId)) return json({ ok: false, error: "invalid_session" }, 400);
      const id = env.SMART_SELECT_SESSIONS.idFromName(sessionId);
      return env.SMART_SELECT_SESSIONS.get(id).fetch(request);
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

export class SmartSelectSession {
  private webSockets = new Set<WebSocket>();
  private mobileSocket: WebSocket | null = null;

  constructor(private state: DurableObjectState, private env: Env) {}

  async fetch(request: Request): Promise<Response> {
    const url = new URL(request.url);
    if (request.headers.get("Upgrade") !== "websocket") {
      return json({ ok: false, error: "expected_websocket" }, 426);
    }

    const role = url.pathname.endsWith("/web") ? "web" : url.pathname.endsWith("/mobile") ? "mobile" : null;
    const sessionId = url.searchParams.get("session_id") ?? "";
    const token = url.searchParams.get("token") ?? "";
    if (!role || !isSmartSelectSessionId(sessionId) || token.length < 16) {
      return json({ ok: false, error: "invalid_pairing" }, 400);
    }

    const session = await loadSmartSelectSession(this.env.DB, sessionId);
    if (!session) return json({ ok: false, error: "session_not_found" }, 404);
    if (new Date(session.expires_at).getTime() <= Date.now()) {
      await updateSmartSelectStatus(this.env.DB, sessionId, "expired");
      return json({ ok: false, error: "session_expired" }, 410);
    }

    const tokenHash = await sha256Hex(token);
    const expectedHash = role === "web" ? session.web_token_hash : session.pairing_token_hash;
    if (!constantTimeEqual(tokenHash, expectedHash)) return json({ ok: false, error: "invalid_token" }, 401);

    const pair = new WebSocketPair();
    const [client, server] = Object.values(pair) as [WebSocket, WebSocket];
    server.accept();

    if (role === "web") this.attachWebSocket(server, session);
    else await this.attachMobileSocket(server, session);

    return new Response(null, { status: 101, webSocket: client });
  }

  private attachWebSocket(socket: WebSocket, session: SmartSelectSessionRow) {
    this.webSockets.add(socket);
    this.send(socket, { type: "status", status: session.status, message: smartSelectStatusMessage(session.status), session_id: session.session_id });
    socket.addEventListener("close", () => this.webSockets.delete(socket));
    socket.addEventListener("error", () => this.webSockets.delete(socket));
  }

  private async attachMobileSocket(socket: WebSocket, session: SmartSelectSessionRow) {
    this.mobileSocket?.close(1000, "replaced_by_new_mobile");
    this.mobileSocket = socket;
    await this.setStatus(session.session_id, "mobile_connected", "手机已连接，准备接收课表数据。", { connected: true });
    socket.addEventListener("message", (event) => {
      this.state.waitUntil(this.handleMobileMessage(session.session_id, String(event.data)));
    });
    socket.addEventListener("close", () => {
      if (this.mobileSocket === socket) this.mobileSocket = null;
      this.broadcast({ type: "status", status: "waiting_mobile", message: "手机连接已断开，请重新扫码。" });
    });
    socket.addEventListener("error", () => {
      if (this.mobileSocket === socket) this.mobileSocket = null;
      this.broadcast({ type: "error", message: "手机连接异常，请重新扫码。" });
    });
  }

  private async handleMobileMessage(sessionId: string, raw: string) {
    let message: Record<string, unknown>;
    try {
      message = JSON.parse(raw) as Record<string, unknown>;
    } catch {
      this.broadcast({ type: "error", message: "收到无法解析的手机消息。" });
      return;
    }

    const type = message.type;
    if (type === "hello") {
      await this.setStatus(sessionId, "mobile_connected", "手机已连接，正在准备数据。", { connected: true });
      return;
    }

    if (type === "heartbeat") {
      await this.env.DB.prepare("UPDATE smart_select_sessions SET last_heartbeat_at = CURRENT_TIMESTAMP WHERE session_id = ?").bind(sessionId).run();
      this.broadcast({ type: "heartbeat", time: new Date().toISOString() });
      return;
    }

    if (type === "upload_start") {
      const termCode = cleanString(typeof message.term_code === "string" ? message.term_code : null, 64);
      await this.env.DB.prepare(
        "UPDATE smart_select_sessions SET status = 'uploading', selected_term_code = ?, error_message = NULL WHERE session_id = ?",
      ).bind(termCode, sessionId).run();
      this.broadcast({ type: "status", status: "uploading", message: "手机正在上传智能选课数据。" });
      return;
    }

    if (type === "upload_dataset") {
      const dataset = typeof message.dataset === "string" ? message.dataset : "";
      if (!SMART_SELECT_DATASETS.has(dataset)) {
        this.broadcast({ type: "error", message: `忽略未知数据集：${dataset}` });
        return;
      }
      await this.env.DB.prepare(
        `INSERT INTO smart_select_payloads (session_id, dataset, payload_json, updated_at)
         VALUES (?, ?, ?, CURRENT_TIMESTAMP)
         ON CONFLICT(session_id, dataset) DO UPDATE SET payload_json = excluded.payload_json, updated_at = CURRENT_TIMESTAMP`,
      ).bind(sessionId, dataset, JSON.stringify(message.payload ?? null)).run();
      await this.setStatus(sessionId, smartSelectStatusForDataset(dataset), smartSelectDatasetMessage(dataset));
      this.broadcast({ type: "dataset", dataset, message: smartSelectDatasetMessage(dataset) });
      return;
    }

    if (type === "upload_done") {
      await this.env.DB.prepare(
        "UPDATE smart_select_sessions SET status = 'ready', ready_at = CURRENT_TIMESTAMP, error_message = NULL WHERE session_id = ?",
      ).bind(sessionId).run();
      this.broadcast({ type: "ready", session_id: sessionId, message: "数据已就绪，可以开始选课。" });
      return;
    }

    if (type === "error") {
      const errorMessage = cleanString(typeof message.message === "string" ? message.message : "手机端上传失败", 512);
      await this.setStatus(sessionId, "error", errorMessage ?? "手机端上传失败", { error: errorMessage });
    }
  }

  private async setStatus(sessionId: string, status: SmartSelectStatus, message: string, extra: { connected?: boolean; error?: string | null } = {}) {
    await updateSmartSelectStatus(this.env.DB, sessionId, status, extra.error);
    if (extra.connected) {
      await this.env.DB.prepare("UPDATE smart_select_sessions SET connected_at = COALESCE(connected_at, CURRENT_TIMESTAMP) WHERE session_id = ?").bind(sessionId).run();
    }
    this.broadcast({ type: "status", status, message });
  }

  private broadcast(data: unknown) {
    for (const socket of this.webSockets) this.send(socket, data);
  }

  private send(socket: WebSocket, data: unknown) {
    try {
      socket.send(JSON.stringify(data));
    } catch {
      this.webSockets.delete(socket);
    }
  }
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

async function serveSmartSelect(request: Request, env: Env): Promise<Response> {
  const url = new URL(request.url);
  url.pathname = "/smart-select.html";
  const response = await env.ASSETS.fetch(new Request(url, request));
  const headers = new Headers(response.headers);
  headers.set("Content-Type", "text/html; charset=utf-8");
  headers.set("Cache-Control", "public, max-age=120");
  return new Response(response.body, { status: response.status, headers });
}

async function createSmartSelectSession(request: Request, env: Env): Promise<Response> {
  await env.DB.prepare("DELETE FROM smart_select_sessions WHERE expires_at < CURRENT_TIMESTAMP").run();
  const sessionId = `ss_${randomToken(18)}`;
  const webToken = randomToken(32);
  const pairingToken = randomToken(32);
  const ttl = intEnv(env.SMART_SELECT_SESSION_TTL_SECONDS, 7200);
  const expiresAt = new Date(Date.now() + ttl * 1000).toISOString();
  await env.DB.prepare(
    `INSERT INTO smart_select_sessions (
      session_id, web_token_hash, pairing_token_hash, status, schema_version, expires_at
    ) VALUES (?, ?, ?, 'waiting_mobile', 1, ?)`,
  ).bind(sessionId, await sha256Hex(webToken), await sha256Hex(pairingToken), expiresAt).run();

  const origin = new URL(request.url).origin;
  const qrPayload = `loveace://smart-select?session_id=${encodeURIComponent(sessionId)}&token=${encodeURIComponent(pairingToken)}`;
  const qrSvg = await QRCode.toString(qrPayload, {
    type: "svg",
    margin: 1,
    width: 220,
    color: { dark: "#2C3333", light: "#F9FBFC" },
  });
  return json({
    ok: true,
    session_id: sessionId,
    web_token: webToken,
    pairing_token: pairingToken,
    expires_at: expiresAt,
    qr_payload: qrPayload,
    qr_svg: qrSvg,
    web_ws_url: `${origin.replace(/^http/, "ws")}/v1/smart-select/ws/web?session_id=${encodeURIComponent(sessionId)}&token=${encodeURIComponent(webToken)}`,
  }, 200, { "Cache-Control": "no-store" });
}

async function loadSmartSelectSessionData(request: Request, env: Env): Promise<Response> {
  const url = new URL(request.url);
  const sessionId = url.searchParams.get("session_id") ?? "";
  const token = url.searchParams.get("token") ?? "";
  const auth = await authenticateSmartSelectWeb(env.DB, sessionId, token);
  if (auth instanceof Response) return auth;
  const payloads = await env.DB.prepare(
    "SELECT dataset, payload_json, updated_at FROM smart_select_payloads WHERE session_id = ?",
  ).bind(sessionId).all<SmartSelectPayloadRow>();
  const actions = await env.DB.prepare(
    "SELECT selected_courses_json, removed_courses_json, updated_at FROM smart_select_actions WHERE session_id = ?",
  ).bind(sessionId).first<{ selected_courses_json: string; removed_courses_json: string; updated_at: string }>();
  const data: Record<string, unknown> = {};
  for (const row of payloads.results ?? []) {
    try {
      data[row.dataset] = JSON.parse(row.payload_json) as unknown;
    } catch {
      data[row.dataset] = null;
    }
  }
  return json({
    ok: true,
    session: publicSmartSelectSession(auth),
    data,
    actions: actions ? {
      selected_courses: safeJsonArray(actions.selected_courses_json),
      removed_courses: safeJsonArray(actions.removed_courses_json),
      updated_at: actions.updated_at,
    } : { selected_courses: [], removed_courses: [] },
  }, 200, { "Cache-Control": "no-store" });
}

async function saveSmartSelectActions(request: Request, env: Env): Promise<Response> {
  const body = await request.text();
  if (new TextEncoder().encode(body).byteLength > 65536) return json({ ok: false, error: "request_body_too_large" }, 413);
  let payload: { session_id?: string; token?: string; selected_courses?: unknown; removed_courses?: unknown };
  try {
    payload = JSON.parse(body) as { session_id?: string; token?: string; selected_courses?: unknown; removed_courses?: unknown };
  } catch {
    return json({ ok: false, error: "invalid_payload" }, 400);
  }
  const auth = await authenticateSmartSelectWeb(env.DB, payload.session_id ?? "", payload.token ?? "");
  if (auth instanceof Response) return auth;
  const selectedCourses = sanitizeCourseKeys(payload.selected_courses);
  const removedCourses = sanitizeCourseKeys(payload.removed_courses);
  await env.DB.prepare(
    `INSERT INTO smart_select_actions (session_id, selected_courses_json, removed_courses_json, updated_at)
     VALUES (?, ?, ?, CURRENT_TIMESTAMP)
     ON CONFLICT(session_id) DO UPDATE SET
       selected_courses_json = excluded.selected_courses_json,
       removed_courses_json = excluded.removed_courses_json,
       updated_at = CURRENT_TIMESTAMP`,
  ).bind(auth.session_id, JSON.stringify(selectedCourses), JSON.stringify(removedCourses)).run();
  return json({ ok: true });
}

async function authenticateSmartSelectWeb(db: D1Database, sessionId: string, token: string): Promise<SmartSelectSessionRow | Response> {
  if (!isSmartSelectSessionId(sessionId) || token.length < 16) return json({ ok: false, error: "invalid_session" }, 400);
  const session = await loadSmartSelectSession(db, sessionId);
  if (!session) return json({ ok: false, error: "session_not_found" }, 404);
  if (new Date(session.expires_at).getTime() <= Date.now()) {
    await updateSmartSelectStatus(db, sessionId, "expired");
    return json({ ok: false, error: "session_expired" }, 410);
  }
  const tokenHash = await sha256Hex(token);
  if (!constantTimeEqual(tokenHash, session.web_token_hash)) return json({ ok: false, error: "invalid_token" }, 401);
  return session;
}

function publicSmartSelectSession(session: SmartSelectSessionRow) {
  return {
    session_id: session.session_id,
    status: session.status,
    schema_version: session.schema_version,
    selected_term_code: session.selected_term_code,
    created_at: session.created_at,
    expires_at: session.expires_at,
    connected_at: session.connected_at,
    ready_at: session.ready_at,
    last_heartbeat_at: session.last_heartbeat_at,
    error_message: session.error_message,
  };
}

async function loadSmartSelectSession(db: D1Database, sessionId: string): Promise<SmartSelectSessionRow | null> {
  return db.prepare("SELECT * FROM smart_select_sessions WHERE session_id = ?").bind(sessionId).first<SmartSelectSessionRow>();
}

async function updateSmartSelectStatus(db: D1Database, sessionId: string, status: SmartSelectStatus, errorMessage: string | null = null) {
  await db.prepare("UPDATE smart_select_sessions SET status = ?, error_message = ? WHERE session_id = ?")
    .bind(status, errorMessage, sessionId)
    .run();
}

function smartSelectStatusForDataset(dataset: string): SmartSelectStatus {
  if (dataset === "terms" || dataset === "selected_term") return "fetching_schedule";
  if (dataset === "student_schedule") return "fetching_plan";
  if (dataset === "plan_completion" || dataset === "plan_options" || dataset === "selected_plan_id") return "fetching_courses";
  return "uploading";
}

function smartSelectDatasetMessage(dataset: string): string {
  if (dataset === "terms") return "学期列表已收到。";
  if (dataset === "selected_term") return "当前学期已确认。";
  if (dataset === "student_schedule") return "当前课表已收到。";
  if (dataset === "plan_options") return "培养方案选项已收到。";
  if (dataset === "selected_plan_id") return "当前培养方案已确认。";
  if (dataset === "plan_completion") return "培养方案完成情况已收到。";
  if (dataset === "available_courses") return "开课数据已收到，正在整理课程卡片。";
  return "数据已收到。";
}

function smartSelectStatusMessage(status: SmartSelectStatus): string {
  const messages: Record<SmartSelectStatus, string> = {
    waiting_mobile: "正在等待手机端连线中...",
    mobile_connected: "手机已连接。",
    fetching_terms: "正在获取学期列表。",
    fetching_schedule: "正在整理当前课表。",
    fetching_plan: "正在读取培养方案。",
    fetching_courses: "正在整理本学期的课程卡片。",
    uploading: "手机正在上传数据。",
    ready: "数据已就绪，可以开始选课。",
    error: "连接出现问题。",
    expired: "二维码已过期。",
  };
  return messages[status];
}

function sanitizeCourseKeys(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  return value
    .filter((item): item is string => typeof item === "string" && /^[^_\s]{1,64}_[^_\s]{0,64}$/.test(item))
    .slice(0, 200);
}

function safeJsonArray(value: string): unknown[] {
  try {
    const parsed = JSON.parse(value) as unknown;
    return Array.isArray(parsed) ? parsed : [];
  } catch {
    return [];
  }
}

async function loadDashboardData(db: D1Database, range: PeriodRange): Promise<AnalyticsDashboardData> {
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
    jsonPropertyRows(db, "screen", 8, where),
    jsonPropertyRows(db, "feature", 8, where),
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

function jsonPropertyRows(db: D1Database, key: string, limit: number, where: string): Promise<D1Result<CountRow>> {
  return db.prepare(`
    SELECT json_extract(properties, ?) AS label, COUNT(*) AS count
    FROM analytics_events
    WHERE ${where} AND json_extract(properties, ?) IS NOT NULL AND json_extract(properties, ?) != ''
    GROUP BY label
    ORDER BY count DESC, label ASC
    LIMIT ?
  `).bind(`$.${key}`, `$.${key}`, `$.${key}`, limit).all<CountRow>();
}

function normalizedUsageRows(db: D1Database, limit: number, where: string): Promise<D1Result<UsageRow>> {
  return db.prepare(`
    SELECT
      label,
      COUNT(*) AS count,
      COUNT(DISTINCT student_hash) AS users,
      SUM(CASE WHEN platform = 'android' THEN 1 ELSE 0 END) AS android,
      SUM(CASE WHEN platform = 'ios' THEN 1 ELSE 0 END) AS ios
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
              ELSE '查看' || json_extract(properties, '$.screen')
            END
          WHEN event_name = 'feature_action' THEN
            CASE json_extract(properties, '$.feature')
              WHEN '课表查询' THEN '课表查询'
              WHEN '课程表' THEN '课表查询'
              WHEN '学期课表' THEN '课表查询'
              WHEN '电费查询' THEN '电费查询'
              WHEN '宿舍电费' THEN '电费查询'
              WHEN '自动教师评价' THEN '教师评价'
              WHEN '教师评价' THEN '教师评价'
              WHEN '自动评教' THEN '教师评价'
              WHEN '宿舍门卡' THEN '宿舍门卡'
              WHEN '门卡' THEN '宿舍门卡'
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

function isSmartSelectSessionId(value: string): boolean {
  return /^ss_[A-Za-z0-9_-]{12,64}$/.test(value);
}

function randomToken(bytes: number): string {
  const data = new Uint8Array(bytes);
  crypto.getRandomValues(data);
  let binary = "";
  for (const byte of data) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
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
