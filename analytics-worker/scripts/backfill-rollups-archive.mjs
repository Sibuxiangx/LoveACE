import { spawn } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { mkdir, rm, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const workerDir = path.resolve(scriptDir, "..");
const repoDir = path.resolve(workerDir, "..");

const options = parseArgs(process.argv.slice(2));
loadEnvFile(options.env ?? findEnvFile());

const token = requiredEnv("CLOUDFLARE_API_TOKEN");
const accountId = options.accountId ?? process.env.CLOUDFLARE_ACCOUNT_ID ?? await discoverAccountId();
const databaseId = options.databaseId ?? "6a58a4ca-21af-4cc4-8c2a-6101865c7985";
const bucket = options.bucket ?? "loveace-analytics-archive";
const pageSize = Number(options.pageSize ?? 5000);
const writeChunkSize = Number(options.writeChunkSize ?? 150);
const archivePageSize = Number(options.archivePageSize ?? 5000);
const archiveRetentionDays = Number(options.archiveRetentionDays ?? 1);
const archiveAll = options.archiveAll === true;
const tempDir = options.tempDir ?? path.join(os.tmpdir(), "loveace-analytics-archive");

if (!Number.isInteger(pageSize) || pageSize <= 0) throw new Error("Invalid --page-size");
if (!Number.isInteger(writeChunkSize) || writeChunkSize <= 0) throw new Error("Invalid --write-chunk-size");
if (!Number.isInteger(archivePageSize) || archivePageSize <= 0) throw new Error("Invalid --archive-page-size");
if (!archiveAll && (!Number.isFinite(archiveRetentionDays) || archiveRetentionDays < 0)) {
  throw new Error("Invalid --archive-retention-days");
}

await mkdir(tempDir, { recursive: true });

let unlocked = false;
try {
  await ensureRollupTables();
  await setState("maintenance:local_backfill", "1");
  await resetRollups();
  const rollup = await rebuildRollups();
  const archive = await archiveRawEvents(rollup.lastId);
  await setState("maintenance:local_backfill", "0");
  unlocked = true;
  console.log(JSON.stringify({ ok: true, rollup, archive }, null, 2));
} finally {
  if (!unlocked) {
    console.error("Local backfill did not finish; maintenance:local_backfill remains locked for safety.");
  }
}

async function ensureRollupTables() {
  await d1(`
    CREATE TABLE IF NOT EXISTS analytics_rollup_counts (
      bucket_hour TEXT NOT NULL,
      bucket_day TEXT NOT NULL,
      metric TEXT NOT NULL,
      label TEXT NOT NULL,
      platform TEXT NOT NULL DEFAULT '',
      app_version TEXT NOT NULL DEFAULT '',
      count INTEGER NOT NULL DEFAULT 0,
      PRIMARY KEY (bucket_hour, metric, label, platform, app_version)
    )
  `);
  await d1(`
    CREATE INDEX IF NOT EXISTS idx_rollup_counts_day_metric
      ON analytics_rollup_counts(bucket_day, metric)
  `);
  await d1(`
    CREATE INDEX IF NOT EXISTS idx_rollup_counts_hour_metric
      ON analytics_rollup_counts(bucket_hour, metric)
  `);
  await d1(`
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
    )
  `);
  await d1(`
    CREATE INDEX IF NOT EXISTS idx_rollup_identities_scope_metric_key
      ON analytics_rollup_identities(bucket_scope, metric, bucket_key)
  `);
  await d1(`
    CREATE TABLE IF NOT EXISTS analytics_rollup_state (
      key TEXT PRIMARY KEY,
      value TEXT NOT NULL,
      updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
    )
  `);
}

async function resetRollups() {
  await setState("rollup:ready", "0");
  await d1("DELETE FROM analytics_rollup_counts");
  await d1("DELETE FROM analytics_rollup_identities");
  await d1("DELETE FROM analytics_rollup_state WHERE key LIKE 'rollup:%'");
  await setState("rollup:ready", "0");
  console.log("Reset rollup tables.");
}

async function rebuildRollups() {
  let lastId = 0;
  let lastEventAt = "";
  let processed = 0;

  for (;;) {
    const rows = await d1(`
      SELECT
        id, client_id, platform, app_version, build, os_version, device_model,
        grade_prefix, student_hash, event_name, event_time, properties,
        ip_hash, user_agent, created_at
      FROM analytics_events
      WHERE id > ?
      ORDER BY id ASC
      LIMIT ?
    `, [lastId, pageSize]);

    if (rows.length === 0) break;

    const aggregate = aggregateRollupRows(rows);
    await writeRollupAggregate(aggregate);

    lastId = Number(rows.at(-1).id);
    lastEventAt = maxString(rows.map((row) => String(row.created_at))) ?? lastEventAt;
    processed += rows.length;
    await setState("rollup:last_event_id", String(lastId));
    await setState("rollup:last_event_at", lastEventAt);

    console.log(`Rolled ${processed} raw events through id ${lastId}.`);
  }

  await setState("rollup:last_event_id", String(lastId));
  if (lastEventAt) await setState("rollup:last_event_at", lastEventAt);
  await setState("rollup:ready", "1");
  return { processed, lastId, ready: true };
}

async function writeRollupAggregate(aggregate) {
  const counts = [...aggregate.counts.values()];
  for (let index = 0; index < counts.length; index += writeChunkSize) {
    const chunk = counts.slice(index, index + writeChunkSize);
    const placeholders = chunk.map(() => "(?, ?, ?, ?, ?, ?, ?)").join(", ");
    const params = chunk.flatMap((item) => [
      item.bucketHour,
      item.bucketDay,
      item.metric,
      item.label,
      item.platform,
      item.appVersion,
      item.count,
    ]);
    await d1(`
      INSERT INTO analytics_rollup_counts (
        bucket_hour, bucket_day, metric, label, platform, app_version, count
      ) VALUES ${placeholders}
      ON CONFLICT(bucket_hour, metric, label, platform, app_version)
      DO UPDATE SET count = count + excluded.count
    `, params);
  }

  const identities = [...aggregate.identities.values()];
  for (let index = 0; index < identities.length; index += writeChunkSize) {
    const chunk = identities.slice(index, index + writeChunkSize);
    const placeholders = chunk.map(() => "(?, ?, ?, ?, ?, ?, ?, ?)").join(", ");
    const params = chunk.flatMap((item) => [
      item.bucketScope,
      item.bucketKey,
      item.metric,
      item.label,
      item.platform,
      item.appVersion,
      item.identityType,
      item.identityValue,
    ]);
    await d1(`
      INSERT OR IGNORE INTO analytics_rollup_identities (
        bucket_scope, bucket_key, metric, label, platform, app_version,
        identity_type, identity_value
      ) VALUES ${placeholders}
    `, params);
  }
}

async function archiveRawEvents(lastRollupId) {
  if (lastRollupId <= 0) return { archivedRows: 0, archivedObjects: 0, deletedRows: 0 };
  const cutoff = archiveAll
    ? sqlTimestamp(Date.now() + 1000)
    : sqlTimestamp(Date.now() - archiveRetentionDays * 24 * 60 * 60 * 1000);
  let archivedRows = 0;
  let archivedObjects = 0;
  let deletedRows = 0;

  for (;;) {
    const rows = await d1(`
      SELECT
        id, client_id, platform, app_version, build, os_version, device_model,
        grade_prefix, student_hash, event_name, event_time, properties,
        ip_hash, user_agent, created_at
      FROM analytics_events
      WHERE created_at < ? AND id <= ?
      ORDER BY id ASC
      LIMIT ?
    `, [cutoff, lastRollupId, archivePageSize]);

    if (rows.length === 0) break;

    const firstId = Number(rows[0].id);
    const lastId = Number(rows.at(-1).id);
    for (const [createdDay, dayRows] of groupRowsByCreatedDay(rows)) {
      const dayFirstId = Number(dayRows[0].id);
      const dayLastId = Number(dayRows.at(-1).id);
      const key = `raw-events/created_day=${createdDay}/events_${dayFirstId}_${dayLastId}.ndjson`;
      const file = path.join(tempDir, `events_${dayFirstId}_${dayLastId}.ndjson`);
      await writeFile(file, dayRows.map((row) => JSON.stringify(row)).join("\n") + "\n");
      await uploadR2Object(key, file);
      await rm(file, { force: true });
      archivedObjects += 1;
    }

    await d1(`
      DELETE FROM analytics_events
      WHERE id >= ? AND id <= ? AND created_at < ? AND id <= ?
    `, [firstId, lastId, cutoff, lastRollupId]);

    archivedRows += rows.length;
    deletedRows += rows.length;
    console.log(`Archived and deleted ${archivedRows} raw events through id ${lastId}.`);
  }

  return { archivedRows, archivedObjects, deletedRows, cutoff };
}

function aggregateRollupRows(rows) {
  const counts = new Map();
  const identities = new Map();

  for (const row of rows) {
    const bucketValue = shanghaiBuckets(String(row.created_at));
    const platform = cleanLabel(row.platform);
    const appVersion = cleanLabel(row.app_version);
    const eventName = cleanLabel(row.event_name);
    const properties = parsePropertiesJson(String(row.properties ?? "{}"));
    const screen = stringProperty(properties, "screen");
    const feature = stringProperty(properties, "feature");
    const action = stringProperty(properties, "action");
    const normalized = normalizedUsageLabel(eventName, screen, feature, action);

    addCount(counts, bucketValue, "total", "", "", "", 1);
    addCount(counts, bucketValue, "event", eventName, "", "", 1);
    addCount(counts, bucketValue, "version", "", platform, appVersion, 1);
    if (screen) addCount(counts, bucketValue, "screen", screen, "", "", 1);
    if (feature) addCount(counts, bucketValue, "feature", feature, "", "", 1);
    if (normalized) addCount(counts, bucketValue, "normalized", normalized, platform, "", 1);
    if (isAuthEvent(eventName)) addCount(counts, bucketValue, "auth", eventName, "", "", 1);
    if (isOtaEvent(eventName)) addCount(counts, bucketValue, "ota", eventName, "", "", 1);

    if (row.client_id) {
      addIdentity(identities, "day", bucketValue.day, "total", "", "", "", "client", row.client_id);
      addIdentity(identities, "day", bucketValue.day, "version", "", platform, appVersion, "client", row.client_id);
    }

    if (row.student_hash) {
      addIdentity(identities, "day", bucketValue.day, "total", "", "", "", "user", row.student_hash);
      addIdentity(identities, "hour", bucketValue.hour, "trend", "", "", "", "user", row.student_hash);
      addIdentity(identities, "day", bucketValue.day, "platform", platform, platform, "", "user", row.student_hash);
      if (row.grade_prefix) {
        addIdentity(identities, "day", bucketValue.day, "grade", cleanLabel(row.grade_prefix), "", "", "user", row.student_hash);
      }
      if (normalized) {
        addIdentity(identities, "day", bucketValue.day, "normalized", normalized, platform, "", "user", row.student_hash);
      }
    }
  }

  return { counts, identities };
}

function addCount(counts, bucketValue, metric, label, platform, appVersion, count) {
  const key = [bucketValue.hour, metric, label, platform, appVersion].join("\u001f");
  const current = counts.get(key);
  if (current) current.count += count;
  else counts.set(key, { bucketHour: bucketValue.hour, bucketDay: bucketValue.day, metric, label, platform, appVersion, count });
}

function addIdentity(identities, bucketScope, bucketKey, metric, label, platform, appVersion, identityType, identityValue) {
  const cleanValue = cleanLabel(identityValue);
  if (!cleanValue) return;
  const key = [bucketScope, bucketKey, metric, label, platform, appVersion, identityType, cleanValue].join("\u001f");
  identities.set(key, { bucketScope, bucketKey, metric, label, platform, appVersion, identityType, identityValue: cleanValue });
}

function groupRowsByCreatedDay(rows) {
  const groups = new Map();
  for (const row of rows) {
    const day = String(row.created_at || "").slice(0, 10);
    const key = /^\d{4}-\d{2}-\d{2}$/.test(day) ? day : "unknown";
    if (!groups.has(key)) groups.set(key, []);
    groups.get(key).push(row);
  }
  return groups;
}

async function uploadR2Object(key, file) {
  await runCommand("npx", [
    "wrangler",
    "r2",
    "object",
    "put",
    `${bucket}/${key}`,
    "--file",
    file,
    "--content-type",
    "application/x-ndjson; charset=utf-8",
  ], {
    cwd: workerDir,
    env: {
      ...process.env,
      CLOUDFLARE_API_TOKEN: token,
      CLOUDFLARE_ACCOUNT_ID: accountId,
    },
  });
}

async function d1(sql, params = []) {
  const response = await fetch(
    `https://api.cloudflare.com/client/v4/accounts/${accountId}/d1/database/${databaseId}/query`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${token}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ sql, params }),
    },
  );
  const payload = await response.json().catch(() => ({}));
  if (!response.ok || payload.success === false) {
    throw new Error(`D1 query failed (${response.status}): ${JSON.stringify(payload.errors ?? payload)}`);
  }
  const result = Array.isArray(payload.result) ? payload.result[0] : payload.result;
  if (result?.success === false) {
    throw new Error(`D1 statement failed: ${JSON.stringify(result.error ?? result)}`);
  }
  return result?.results ?? [];
}

async function setState(key, value) {
  await d1(`
    INSERT INTO analytics_rollup_state (key, value, updated_at)
    VALUES (?, ?, CURRENT_TIMESTAMP)
    ON CONFLICT(key) DO UPDATE SET
      value = excluded.value,
      updated_at = excluded.updated_at
  `, [key, value]);
}

async function discoverAccountId() {
  const response = await fetch("https://api.cloudflare.com/client/v4/accounts", {
    headers: { Authorization: `Bearer ${token}` },
  });
  const payload = await response.json().catch(() => ({}));
  if (!response.ok || payload.success === false) {
    throw new Error(`Unable to discover Cloudflare account (${response.status}). Pass --account-id.`);
  }
  const accounts = payload.result ?? [];
  if (accounts.length !== 1) {
    throw new Error(`Expected one Cloudflare account, found ${accounts.length}. Pass --account-id.`);
  }
  return accounts[0].id;
}

function runCommand(command, args, { cwd, env }) {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, { cwd, env, stdio: ["ignore", "pipe", "pipe"] });
    let stdout = "";
    let stderr = "";
    child.stdout.on("data", (chunk) => { stdout += chunk; });
    child.stderr.on("data", (chunk) => { stderr += chunk; });
    child.on("error", reject);
    child.on("close", (code) => {
      if (code === 0) resolve({ stdout, stderr });
      else reject(new Error(`${command} ${args.join(" ")} failed with ${code}: ${stdout}${stderr}`));
    });
  });
}

function loadEnvFile(file) {
  if (!file) return;
  if (!existsSync(file)) return;
  for (const rawLine of readFileSync(file, "utf8").split(/\r?\n/)) {
    const line = rawLine.trim();
    if (!line || line.startsWith("#") || !line.includes("=")) continue;
    const [rawKey, ...rest] = line.split("=");
    const key = rawKey.trim().replace(/^export\s+/, "");
    let value = rest.join("=").trim();
    if ((value.startsWith('"') && value.endsWith('"')) || (value.startsWith("'") && value.endsWith("'"))) {
      value = value.slice(1, -1);
    }
    if (!(key in process.env)) process.env[key] = value;
  }
}

function findEnvFile() {
  const candidates = [
    path.join(repoDir, ".agents/env/cf.env"),
    path.join(repoDir, "../.agents/env/cf.env"),
    path.join(process.cwd(), ".agents/env/cf.env"),
    path.join(process.cwd(), "../.agents/env/cf.env"),
  ];
  return candidates.find((candidate) => existsSync(candidate));
}

function requiredEnv(key) {
  const value = process.env[key];
  if (!value) throw new Error(`Missing ${key}`);
  return value;
}

function parseArgs(argv) {
  const parsed = {};
  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    if (!arg.startsWith("--")) continue;
    const key = arg.slice(2).replace(/-([a-z])/g, (_, char) => char.toUpperCase());
    if (argv[index + 1] && !argv[index + 1].startsWith("--")) parsed[key] = argv[++index];
    else parsed[key] = true;
  }
  return parsed;
}

function sqlTimestamp(value) {
  return new Date(value).toISOString().slice(0, 19).replace("T", " ");
}

function shanghaiBuckets(value) {
  const shifted = parseUtcTimestamp(value) + 8 * 60 * 60 * 1000;
  const iso = new Date(shifted).toISOString();
  return {
    day: iso.slice(0, 10),
    hour: iso.slice(0, 13).replace("T", " "),
  };
}

function parseUtcTimestamp(value) {
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

function maxString(values) {
  let current = null;
  for (const value of values) {
    if (!current || value > current) current = value;
  }
  return current;
}

function cleanLabel(value) {
  if (typeof value !== "string") return "";
  return value.trim().replace(/\u001f/g, "").slice(0, 128);
}

function parsePropertiesJson(value) {
  try {
    const parsed = JSON.parse(value);
    return parsed && typeof parsed === "object" && !Array.isArray(parsed) ? parsed : {};
  } catch {
    return {};
  }
}

function stringProperty(properties, key) {
  const value = properties[key];
  return typeof value === "string" ? cleanLabel(value) : "";
}

function isAuthEvent(eventName) {
  return [
    "login_success",
    "login_failed",
    "session_expired",
    "session_reconnect_success",
    "session_reconnect_failed",
  ].includes(eventName);
}

function isOtaEvent(eventName) {
  return eventName === "ota_check" || eventName === "ota_update_click";
}

function normalizedUsageLabel(eventName, screen, feature, action) {
  if (eventName === "screen_view") {
    if (!screen) return "";
    const screenLabels = {
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
    const featureLabels = {
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
