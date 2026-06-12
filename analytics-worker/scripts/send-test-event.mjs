import { createHmac, createHash, randomUUID } from "node:crypto";

const endpoint = process.env.ANALYTICS_ENDPOINT || "https://analyst-api.linota.cn/v1/events";
const apiKey = requiredEnv("ANALYTICS_API_KEY");
const signingSecret = requiredEnv("ANALYTICS_SIGNING_SECRET");

const body = JSON.stringify({
  client_id: `diagnostic-${randomUUID()}`,
  platform: "android",
  app_version: "diagnostic",
  build: "github-actions",
  os_version: "diagnostic",
  device_model: "github-actions",
  grade_prefix: null,
  student_hash: null,
  events: [
    {
      name: "app_start",
      time: new Date().toISOString(),
      properties: {
        launch_source: "diagnostic",
      },
    },
  ],
});

const timestamp = Math.floor(Date.now() / 1000).toString();
const nonce = randomUUID();
const bodyHash = createHash("sha256").update(body, "utf8").digest("hex");
const signature = createHmac("sha256", signingSecret)
  .update(`${timestamp}.${nonce}.${bodyHash}`, "utf8")
  .digest("hex");

const response = await fetch(endpoint, {
  method: "POST",
  headers: {
    Authorization: `Bearer ${apiKey}`,
    "Content-Type": "application/json; charset=utf-8",
    "X-LoveACE-Timestamp": timestamp,
    "X-LoveACE-Nonce": nonce,
    "X-LoveACE-Signature": signature,
  },
  body,
});

const text = await response.text();
console.log(`诊断请求状态：${response.status}`);
console.log(`诊断请求响应：${text}`);

if (!response.ok) {
  process.exit(1);
}

function requiredEnv(name) {
  const value = process.env[name];
  if (!value) throw new Error(`缺少环境变量：${name}`);
  return value;
}
