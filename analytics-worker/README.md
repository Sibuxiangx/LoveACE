# LoveACE 遥测 Worker

这是 LoveACE 客户端使用的隐私友好遥测入口，部署在 Cloudflare Workers，并使用 D1 存储事件数据。

## 接口

- `GET /healthz`
- `GET /bi`
- `POST /v1/events`
- `POST /v1/diagnostics`

请求 `/v1/events` 时必须带上以下鉴权头：

- `Authorization: Bearer <ANALYTICS_API_KEY>`
- `X-LoveACE-Timestamp`
- `X-LoveACE-Nonce`
- `X-LoveACE-Signature`

签名内容：

```text
HMAC_SHA256(ANALYTICS_SIGNING_SECRET, timestamp + "." + nonce + "." + sha256(raw_body))
```

服务端只保存 `grade_prefix` 和加盐后的 `student_hash`，不会保存完整明文学号。

## 数据边界

- 不接收密码、完整学号或业务接口原始返回。
- 不接收成绩、课表、一卡通消费、门禁、评教等具体业务内容。
- 遥测不可用时客户端会静默忽略，不影响正常使用。

## 匿名统计 BI

`/bi` 会实时读取 D1 的聚合统计并渲染 Worker 托管的只读 BI 页面。页面展示事件、版本、平台、年级前缀、功能/页面、登录与 OTA 的汇总指标，不展示原始事件、明文学号、`client_id`、`student_hash`、IP 或 User-Agent 明细。

## 登录诊断存储

`POST /v1/diagnostics` 接收客户端的脱敏登录诊断（`loveace.login-diagnostics/v1`），在 R2 桶 `loveace-diagnostics` 中写入 `<id>/diagnostic.json`、`<id>/diag.html`、`<id>/llm.md` 三个对象，公开访问地址为 `https://diagnostics.loveace.top/<id>/diag.html`。接口鉴权与 `/v1/events` 相同，并复用同一组 `ANALYTICS_API_KEY`、`ANALYTICS_SIGNING_SECRET`、`ANALYTICS_IP_HASH_SALT` 密钥，无需新增密钥。

部署前的配置步骤：

1. 创建 R2 桶：`wrangler r2 bucket create loveace-diagnostics`（或在 Cloudflare 后台 R2 中创建同名桶）。`wrangler.toml` 中的 `DIAGNOSTICS` 绑定已指向该桶。
2. 在 Cloudflare 后台为该桶绑定自定义域名 `diagnostics.loveace.top`（R2 → 桶 → Settings → Custom Domains），使链接可以公开访问。
3. 有效期为 3 天。Worker 的 `*/5 * * * *` 定时任务会分批删除上传时间超过 3 天的对象（按 R2 对象的 `uploaded` 时间判断）。可选：在 Cloudflare 后台为该桶设置生命周期规则（3 天后自动过期），作为对定时清理的补充或替代。

诊断页与日志内容会在上传时完成脱敏校验，服务端发现密码、Cookie、令牌、验证码等明文时直接返回 `400 sensitive_content_detected`。
