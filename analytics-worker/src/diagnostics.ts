export const DIAGNOSTIC_SCHEMA = "loveace.login-diagnostics/v1";
export const DIAGNOSTIC_MAX_BYTES = 1048576;
export const DIAGNOSTIC_TTL_MS = 3 * 24 * 60 * 60 * 1000;
export const DIAGNOSTIC_PUBLIC_BASE = "https://diagnostics.loveace.top";

const CLEANUP_PAGE_LIMIT = 1000;
const CLEANUP_MAX_SCANNED = 5000;

const OUTCOMES = [
  "success",
  "invalidCredentials",
  "captchaRequired",
  "captchaInvalid",
  "passwordChangeRequired",
  "network",
  "other",
  "cancelled",
  "unfinished",
] as const;

export type DiagnosticOutcome = (typeof OUTCOMES)[number];

export interface DiagnosticAttempt {
  id: string;
  startedAt: string;
  endedAt: string | null;
  account: string;
  mode: string;
  outcome: DiagnosticOutcome;
  message: string | null;
  httpCount: number;
  lines: string[];
}

export interface DiagnosticV1 {
  schema: string;
  createdAt: string;
  app: { platform: "ios" | "android"; version: string; build: string };
  device: { model: string; os: string; osVersion: string; timezone: string; locale: string };
  attempts: DiagnosticAttempt[];
}

export type DiagnosticParseResult =
  | { ok: true; value: DiagnosticV1 }
  | { ok: false; error: "invalid_schema" | "sensitive_content_detected" };

export interface StoredDiagnostic {
  id: string;
  url: string;
  llmUrl: string;
  expiresAt: string;
}

interface DiagnosticMeta {
  id: string;
  uploadedAt: string;
  expiresAt: string;
}

class InvalidSchema extends Error {}

function invalid(): never {
  throw new InvalidSchema();
}

function isPlainObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function objectWith(value: unknown, keys: readonly string[], optional: readonly string[] = []): Record<string, unknown> {
  if (!isPlainObject(value)) invalid();
  for (const key of Object.keys(value)) {
    if (!keys.includes(key)) invalid();
  }
  for (const key of keys) {
    if (!optional.includes(key) && !(key in value)) invalid();
  }
  return value;
}

function text(value: unknown, max: number): string {
  if (typeof value !== "string" || Array.from(value).length > max) invalid();
  return value;
}

function oneOf<T extends string>(value: unknown, values: readonly T[]): T {
  if (typeof value !== "string" || !values.includes(value as T)) invalid();
  return value as T;
}

function integer(value: unknown, min: number, max: number): number {
  if (typeof value !== "number" || !Number.isInteger(value) || value < min || value > max) invalid();
  return value;
}

const ISO_RE = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2}(\.\d{1,9})?)?(Z|[+-]\d{2}:\d{2})$/;

function isoTime(value: unknown): string {
  if (typeof value !== "string" || !ISO_RE.test(value) || Number.isNaN(Date.parse(value))) invalid();
  return value;
}

const UUID_RE = /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/;

function uuid(value: unknown): string {
  if (typeof value !== "string" || !UUID_RE.test(value)) invalid();
  return value;
}

function lines(value: unknown): string[] {
  if (!Array.isArray(value) || value.length > 300) invalid();
  return value.map((line) => text(line, 4000));
}

function buildAttempt(raw: unknown): DiagnosticAttempt {
  const attempt = objectWith(
    raw,
    ["id", "startedAt", "endedAt", "account", "mode", "outcome", "message", "httpCount", "lines"],
    ["endedAt", "message"],
  );
  return {
    id: uuid(attempt.id),
    startedAt: isoTime(attempt.startedAt),
    endedAt: attempt.endedAt == null ? null : isoTime(attempt.endedAt),
    account: text(attempt.account, 16),
    mode: text(attempt.mode, 16),
    outcome: oneOf(attempt.outcome, OUTCOMES),
    message: attempt.message == null ? null : text(attempt.message, 500),
    httpCount: integer(attempt.httpCount, 0, 10000),
    lines: lines(attempt.lines),
  };
}

function buildDiagnostic(raw: unknown): DiagnosticV1 {
  const root = objectWith(raw, ["schema", "createdAt", "app", "device", "attempts"]);
  if (root.schema !== DIAGNOSTIC_SCHEMA) invalid();
  const app = objectWith(root.app, ["platform", "version", "build"]);
  const device = objectWith(root.device, ["model", "os", "osVersion", "timezone", "locale"]);
  if (!Array.isArray(root.attempts) || root.attempts.length < 1 || root.attempts.length > 10) invalid();

  return {
    schema: DIAGNOSTIC_SCHEMA,
    createdAt: isoTime(root.createdAt),
    app: {
      platform: oneOf(app.platform, ["ios", "android"] as const),
      version: text(app.version, 20),
      build: text(app.build, 20),
    },
    device: {
      model: text(device.model, 64),
      os: text(device.os, 32),
      osVersion: text(device.osVersion, 32),
      timezone: text(device.timezone, 8),
      locale: text(device.locale, 32),
    },
    attempts: root.attempts.map(buildAttempt),
  };
}

function validateDiagnostic(raw: unknown): DiagnosticV1 | null {
  try {
    return buildDiagnostic(raw);
  } catch (error) {
    if (error instanceof InvalidSchema) return null;
    throw error;
  }
}

// Section 3: server-side sensitive-content guard.
const PLACEHOLDER_START_RE = /^<[^<>]+>/;
const PLACEHOLDER_RE = /<[^<>]*>/g;
const SENSITIVE_KV_RULES: readonly RegExp[] = [
  /(?:password|passwd|pwd)\s*=\s*/gi,
  /cookie\s*[:=]\s*/gi,
  /(?:jsessionid|twfid|ticket|token|captcha|rand_code)\s*=\s*/gi,
];
// XML 标签形式，如 <TwfID>728cd31bc89a7a1c</TwfID>：标签内文本只允许为空或占位符
const SENSITIVE_XML_RE = /<(?:twfid|jsessionid|token|password|passwd|pwd|cookie|ticket)\b[^>]*>([^<]*)/gi;
const LONG_TOKEN_RE = /[A-Za-z0-9+/=_-]{40,}/;

function hasSensitiveText(value: string): boolean {
  for (const rule of SENSITIVE_KV_RULES) {
    for (const match of value.matchAll(rule)) {
      // 只看 = 之后紧跟的值（到空白或 & 为止）：空值不算敏感，占位符合规
      const rest = value.slice((match.index ?? 0) + match[0].length).replace(/^["']/, "");
      const token = rest.match(/^[^\s&"']*/)?.[0] ?? "";
      if (token !== "" && !PLACEHOLDER_START_RE.test(token)) return true;
    }
  }
  for (const match of value.matchAll(SENSITIVE_XML_RE)) {
    if ((match[1] ?? "").trim() !== "") return true;
  }
  return LONG_TOKEN_RE.test(value.replace(PLACEHOLDER_RE, " "));
}

function attemptHasSensitiveContent(attempt: DiagnosticAttempt): boolean {
  if (attempt.message !== null && hasSensitiveText(attempt.message)) return true;
  return attempt.lines.some((line) => hasSensitiveText(line));
}

export function parseDiagnostic(body: string): DiagnosticParseResult {
  let raw: unknown;
  try {
    raw = JSON.parse(body);
  } catch {
    return { ok: false, error: "invalid_schema" };
  }

  const value = validateDiagnostic(raw);
  if (!value) return { ok: false, error: "invalid_schema" };
  if (value.attempts.some(attemptHasSensitiveContent)) {
    return { ok: false, error: "sensitive_content_detected" };
  }
  return { ok: true, value };
}

// Section 4: IDs and R2 storage.
export function createDiagnosticId(): string {
  const bytes = new Uint8Array(12);
  crypto.getRandomValues(bytes);
  return [...bytes].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

export async function storeDiagnostic(
  bucket: R2Bucket,
  body: string,
  value: DiagnosticV1,
  now: number,
): Promise<StoredDiagnostic> {
  const id = createDiagnosticId();
  const expiresMs = now + DIAGNOSTIC_TTL_MS;
  const meta: DiagnosticMeta = {
    id,
    uploadedAt: new Date(now).toISOString(),
    expiresAt: new Date(expiresMs).toISOString(),
  };
  const customMetadata = { expiresAt: String(expiresMs) };

  await Promise.all([
    bucket.put(`${id}/diagnostic.json`, body, {
      customMetadata,
      httpMetadata: { contentType: "application/json; charset=utf-8" },
    }),
    bucket.put(`${id}/diag.html`, renderDiagHtml(value, meta), {
      customMetadata,
      httpMetadata: { contentType: "text/html; charset=utf-8" },
    }),
    bucket.put(`${id}/llm.md`, renderLlmMarkdown(value, meta), {
      customMetadata,
      httpMetadata: { contentType: "text/markdown; charset=utf-8" },
    }),
  ]);

  return {
    id,
    url: `${DIAGNOSTIC_PUBLIC_BASE}/${id}/diag.html`,
    llmUrl: `${DIAGNOSTIC_PUBLIC_BASE}/${id}/llm.md`,
    expiresAt: meta.expiresAt,
  };
}

// Section 5: batch-limited expiry cleanup. Returns the number of deleted objects.
export async function cleanupExpiredDiagnostics(bucket: R2Bucket, now: number): Promise<number> {
  let cursor: string | undefined;
  let scanned = 0;
  let deleted = 0;

  do {
    const page = await bucket.list({ limit: CLEANUP_PAGE_LIMIT, cursor });
    const expiredKeys = page.objects
      .filter((object) => object.uploaded.getTime() < now - DIAGNOSTIC_TTL_MS)
      .map((object) => object.key);
    if (expiredKeys.length > 0) {
      await bucket.delete(expiredKeys);
      deleted += expiredKeys.length;
    }
    scanned += page.objects.length;
    cursor = page.truncated ? page.cursor : undefined;
  } while (cursor !== undefined && scanned < CLEANUP_MAX_SCANNED);

  return deleted;
}

// Section 6 and 7: renderers.
const OUTCOME_LABEL: Record<DiagnosticOutcome, string> = {
  success: "登录成功",
  invalidCredentials: "账号或密码错误",
  captchaRequired: "需要验证码",
  captchaInvalid: "验证码错误",
  passwordChangeRequired: "需要修改密码",
  network: "网络错误",
  other: "其他失败",
  cancelled: "已取消",
  unfinished: "未完成",
};

type OutcomeTone = "ok" | "fail" | "muted";

function outcomeTone(outcome: DiagnosticOutcome): OutcomeTone {
  if (outcome === "success") return "ok";
  if (outcome === "cancelled" || outcome === "unfinished") return "muted";
  return "fail";
}

const HTML_ESCAPES: Record<string, string> = {
  "&": "&amp;",
  "<": "&lt;",
  ">": "&gt;",
  '"': "&quot;",
  "'": "&#39;",
};

function esc(value: string | number): string {
  return String(value).replace(/[&<>"']/g, (char) => HTML_ESCAPES[char] ?? char);
}

const DIAG_CSS = `
:root{color-scheme:light;--shell:#16161a;--paper:#f5f4f1;--card:#fffefa;--ink:#1c1c1e;--muted:#6e6e73;--line:#e7e2dc;--soft:#ece8e1;--orange:#f4511e;--ok:#2e7d4f;--fail:#c62828;--mono:ui-monospace,"SFMono-Regular","JetBrains Mono",Menlo,Consolas,monospace;--sans:ui-sans-serif,-apple-system,BlinkMacSystemFont,"Segoe UI","PingFang SC","Microsoft YaHei",sans-serif}
*{box-sizing:border-box}
body{margin:0;min-height:100vh;background:radial-gradient(circle at 12% 0%,rgba(244,81,30,.18),transparent 28rem),linear-gradient(135deg,#101014 0%,var(--shell) 48%,#24201d 100%);color:var(--ink);font-family:var(--sans)}
.shell{width:min(1100px,calc(100vw - 32px));margin:24px auto;border:1px solid rgba(255,255,255,.12);background:rgba(22,22,26,.72);box-shadow:0 24px 80px rgba(0,0,0,.28)}
.topbar{padding:16px 20px;display:flex;justify-content:space-between;align-items:center;gap:16px;flex-wrap:wrap;color:#f8f3ed}
.brand-title{font-size:15px;font-weight:760;letter-spacing:.02em}
.brand-subtitle{margin-top:2px;color:rgba(248,243,237,.62);font:12px/1.2 var(--mono);overflow-wrap:anywhere}
.dot{display:inline-block;width:8px;height:8px;margin-right:8px;border-radius:999px;background:var(--orange);box-shadow:0 0 18px rgba(244,81,30,.64)}
.live{color:rgba(248,243,237,.78);font:12px/1 var(--mono)}
.workspace{background:var(--paper);padding:18px}
.grid{display:grid;gap:14px}
.metrics{grid-template-columns:repeat(6,minmax(0,1fr))}
.card{min-width:0;background:var(--card);border:1px solid var(--line);border-radius:8px;box-shadow:0 1px 0 rgba(28,28,30,.04),0 10px 28px rgba(28,28,30,.045)}
.metric{padding:14px 16px;min-height:96px}
.label{color:var(--muted);font-size:12px;font-weight:680;letter-spacing:.08em;text-transform:uppercase}
.value{margin-top:10px;font:700 16px/1.35 var(--mono);overflow-wrap:anywhere}
.attempts{display:grid;gap:14px;margin-top:14px}
.attempt{padding:16px 18px}
.attempt-head{display:flex;justify-content:space-between;align-items:center;gap:12px;flex-wrap:wrap;margin-bottom:12px}
.badge{display:inline-block;border-radius:999px;padding:6px 11px;font:700 12px/1 var(--mono);color:#fff}
.badge.ok{background:var(--ok)}
.badge.fail{background:var(--fail)}
.badge.muted{background:#8a8a8f}
.stamp{color:var(--muted);font:12px/1.4 var(--mono);overflow-wrap:anywhere}
.kv{display:grid;grid-template-columns:96px minmax(0,1fr);gap:8px 12px;margin:0 0 12px;font-size:14px}
.kv dt{color:var(--muted)}
.kv dd{margin:0;overflow-wrap:anywhere}
details{border-top:1px dashed #ddd6ce;padding-top:10px}
summary{cursor:pointer;color:var(--muted);font:12px/1.4 var(--mono)}
pre{margin:10px 0 0;padding:12px;background:var(--soft);border:1px solid var(--line);border-radius:6px;font:12px/1.5 var(--mono);white-space:pre-wrap;overflow-wrap:anywhere;word-break:break-word}
.privacy{margin-top:16px;padding-top:14px;border-top:1px dashed #ddd6ce;color:var(--muted);font:11px/1.45 var(--mono);overflow-wrap:anywhere}
@media (max-width:900px){.metrics{grid-template-columns:repeat(2,minmax(0,1fr))}}
@media (max-width:560px){.shell{width:min(100vw - 20px,760px);margin:10px auto}.workspace{padding:10px}.metrics{grid-template-columns:1fr}.kv{grid-template-columns:1fr}}
`;

function renderMetric(label: string, value: string): string {
  return `<article class="card metric"><div class="label">${esc(label)}</div><div class="value">${esc(value)}</div></article>`;
}

function renderAttempt(attempt: DiagnosticAttempt, index: number): string {
  const tone = outcomeTone(attempt.outcome);
  const label = OUTCOME_LABEL[attempt.outcome];
  return `<article class="card attempt">
<div class="attempt-head"><span class="badge ${tone}">${esc(label)}</span><span class="stamp">第 ${index + 1} 次 · ${esc(attempt.startedAt)}</span></div>
<dl class="kv">
<dt>结束时间</dt><dd>${esc(attempt.endedAt ?? "未结束")}</dd>
<dt>账号</dt><dd>${esc(attempt.account)}</dd>
<dt>模式</dt><dd>${esc(attempt.mode)}</dd>
<dt>原因</dt><dd>${esc(attempt.message ?? label)}</dd>
<dt>HTTP 请求</dt><dd>${esc(attempt.httpCount)} 次</dd>
</dl>
<details><summary>查看日志（${esc(attempt.lines.length)} 行）</summary><pre>${esc(attempt.lines.join("\n"))}</pre></details>
</article>`;
}

export function renderDiagHtml(value: DiagnosticV1, meta: DiagnosticMeta): string {
  const { app, device, attempts } = value;
  const failures = attempts.filter((attempt) => outcomeTone(attempt.outcome) === "fail").length;
  return `<!doctype html>
<html lang="zh-CN">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width, initial-scale=1" />
<meta name="robots" content="noindex,nofollow" />
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'" />
<title>LoveACE 登录诊断</title>
<style>${DIAG_CSS}</style>
</head>
<body>
<main class="shell">
<header class="topbar">
<div><div class="brand-title">LoveACE 登录诊断</div><div class="brand-subtitle">LOGIN_DIAGNOSTIC · ${esc(meta.id)}</div></div>
<div class="live"><span class="dot"></span>${esc(`上传于 ${value.createdAt}`)}</div>
</header>
<section class="workspace">
<section class="grid metrics">
${renderMetric("应用版本", `${app.platform} ${app.version} (${app.build})`)}
${renderMetric("设备", `${device.model} · ${device.os} ${device.osVersion}`)}
${renderMetric("上传时间", value.createdAt)}
${renderMetric("过期时间", meta.expiresAt)}
${renderMetric("登录次数", String(attempts.length))}
${renderMetric("失败次数", String(failures))}
</section>
<section class="attempts">
${attempts.map(renderAttempt).join("\n")}
</section>
<footer class="privacy">内容已脱敏：学号仅显示部分，密码、Cookie、令牌等已替换为占位符。链接 3 天后失效。</footer>
</section>
</main>
</body>
</html>
`;
}

// Prose: collapse line breaks and escape backticks so user text cannot break Markdown structure.
function mdText(value: string): string {
  return value.replace(/\r?\n/g, " ").replace(/`/g, "\\`");
}

function renderLlmAttempt(attempt: DiagnosticAttempt, index: number): string {
  const label = OUTCOME_LABEL[attempt.outcome];
  const body = attempt.lines.length > 0 ? attempt.lines.join("\n").replace(/```/g, "\\`\\`\\`") : "（无日志）";
  return [
    `### 第 ${index + 1} 次登录 · ${mdText(attempt.startedAt)}`,
    "",
    `- 结果：${mdText(label)}（outcome: ${mdText(attempt.outcome)}）`,
    `- 原因：${attempt.message !== null ? mdText(attempt.message) : "无"}`,
    `- 账号：${mdText(attempt.account)}`,
    `- 模式：${mdText(attempt.mode)}`,
    `- 开始：${mdText(attempt.startedAt)}；结束：${attempt.endedAt !== null ? mdText(attempt.endedAt) : "未结束"}`,
    `- httpCount：${attempt.httpCount}`,
    `- 日志（${attempt.lines.length} 行）：`,
    "",
    "```text",
    body,
    "```",
    "",
  ].join("\n");
}

export function renderLlmMarkdown(value: DiagnosticV1, meta: DiagnosticMeta): string {
  const { app, device, attempts } = value;
  const failures = attempts.filter((attempt) => outcomeTone(attempt.outcome) === "fail").length;
  return [
    `# LoveACE 登录诊断 ${mdText(meta.id)}`,
    "",
    "## 用途说明",
    "",
    "本文件是用户在 LoveACE 登录失败后主动分享的脱敏诊断日志，用于分析登录失败原因。内容已脱敏，链接 3 天后失效。",
    "",
    "## 占位符图例",
    "",
    "- `<Password>`、`<SetCookie>`、`<Lt>` 等 `<…>`：该字段已被遮挡（密码、Cookie、令牌、验证码等）。",
    "- `xx****xx`：学号，中间部分已被遮挡。",
    "- `[服务名]/路径`：压缩后的服务地址，例如 `[vpn]/por/login_auth.csp`。",
    "",
    "## 设备与应用",
    "",
    `- 应用：${mdText(app.platform)} ${mdText(app.version)} (build ${mdText(app.build)})`,
    `- 设备：${mdText(device.model)}，${mdText(device.os)} ${mdText(device.osVersion)}`,
    `- 时区：${mdText(device.timezone)}；语言：${mdText(device.locale)}`,
    `- 上传时间：${mdText(value.createdAt)}；过期时间：${mdText(meta.expiresAt)}`,
    `- 登录次数：${attempts.length}；失败次数：${failures}`,
    "",
    "## 登录记录",
    "",
    ...attempts.map((attempt, index) => renderLlmAttempt(attempt, index)),
    "## 分析清单",
    "",
    "1. 先看 EC/UAAP 存在性标志：对照各次登录的模式字段与日志中的 EC、UAAP 相关记录，判断学校入口是否存在。",
    "2. 再看网络错误与超时：outcome 为 network，或日志中出现超时、连接失败、非 200 状态的记录。",
    "3. 验证码流程：关注 captchaRequired、captchaInvalid 及日志中验证码相关步骤。",
    "4. 学校改密：关注 passwordChangeRequired 及日志中的改密提示。",
    "5. 结论与建议：综合以上信息给出可能原因与处理建议；若信息不足，说明还需要哪些日志。",
    "",
  ].join("\n");
}
