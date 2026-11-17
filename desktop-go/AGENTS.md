# AGENTS.md · 桌面端（desktop-go）

给在这个目录里工作的代理（和人）的规则。界面规则见 `DESIGN.md`，这里只写怎么改代码。

## 构建与验证

- Go 在 `/Users/linnian/sdk/go/bin`，先 `export PATH=/Users/linnian/sdk/go/bin:$PATH`。
- 提交前必须过：`gofmt -l .` 为空，`go vet ./...`，`go test ./... -count=1`。
- 不要用 `xcodebuild`。mygo 要求 `CGO_ENABLED=0`，不引入 cgo。
- 改了界面，要渲染检查：临时测试里用 `ui.NewTester(a.view, 960, 680)`，
  `tt.Image()` 存成 PNG，用图片查看工具看。检查完**删掉**临时测试文件。
- dev 窗口由 `mygo dev` 热重建，日志在 `/tmp/mygo-dev.log`。
  每次改完，确认最后一条是 `Rebuilt`，不是 `✗`。
- 不提交，除非用户要求。
- 改了 `smartui/app/` 后，在该目录跑 `flutter build web --release --base-href / --pwa-strategy=none --no-web-resources-cdn`（CanvasKit 本地打包，不走 gstatic CDN；离线也能开）。然后把 `build/web` 拷成 `smartui/dist/`（先删旧的），再删 `dist/canvaskit/` 里的 `skwasm*`、`wimp*`、`webparagraph`、全部 `*.symbols`：加载器只用 `canvaskit.*` 与 `chromium/canvaskit.*`。改了带 `@JsonSerializable` 的模型后跑 `dart run build_runner build`。

## 文件分工

- 根目录是 `package main`，按文件名前缀分组。`app.go` 的状态与视图互相依赖，所以不拆子包。
- `main.go`：入口、窗口选项、字体、应用图标。
- `app.go`：`app` 状态、页面枚举、`view` 分发、登录/登出（登录时把账号交给 `SmartData`）。
- `nav.go`：左侧导航栏（首页 / 爱安财 / 培养方案 / 一卡通 / 智能排课（开窗口）/ 设置）。
- `m3e.go`：所有自绘组件（徽章、圆环、波浪条、卡片头、芯片、列表行、拖动条、圆形按钮）。
- `shapes.go`：花形与轮廓的几何（`cookie`、`scallop`）。
- `theme.go`：预设、配色方案缓存（`schemeOf`）、主题（`themeOf`）、成功/警告色（`extendedOf`）。
- `icons.go`：图标 embed 与解析表（SVG 在 `assets/icons/`）。
- `login.go`、`auth.go`：登录页与学校会话。
- `home.go`、`home_data.go`、`clock.go`：首页视图、数据与时钟（CookieClock 样式的移植，几何与配色见文件头注释）。
- `aac.go`、`aac_view.go`：爱安财数据、口径与页面。
- `card.go`、`card_view.go`：一卡通数据（余额、本月消费）与页面。
- `plan.go`、`plan_view.go`：培养方案数据（多方案、完成度）与页面。
- `labor.go`、`labor_view.go`：劳动俱乐部数据（进度、已报名、添加活动的分组、详情、签到）与页面。
- `settings.go`：设置页。
- `read.go`：后台读取的通用机制（`startRead`、`readRetry`、`readState`、`readErrText`）。
- `focus.go`：回到焦点时刷新当前页（mygo 的 `OnDidBecomeActive` / `OnDidResignActive`，离开满一分钟才刷新）。
- `store.go`、`throttle.go`：设置文件、登录冷却。
- `smart_window.go`：智能排课窗口，最大化的 webview；`init` 里把 `smartui` 设为应用的前端。
- `smart_data.go`：`SmartData` 绑定服务，webview 经它读学校数据，复用 loveace-go 的 jwc，返回其结构体的 JSON。
- `smartui/`：智能排课网页。`embed.go` 嵌入 `dist/`；`app/` 是 Flutter 源码（从旧 `desktop/lib` 剥离）；`dist/` 是构建产物，不手改。
- `assets/`：字体（MiSans）、图标（SVG）、应用图标。`internal/palette/`：配色算法。

## 读取学校数据

- 所有读取用 `a.startRead(acc, func(ctx, apply) { ... })`。
  `apply` 里的改动回到主线程，账号变了（登出、换号）会被丢弃。
- 劳动俱乐部的读取一个接一个做（进度、已报名、添加活动、每个已报名活动的详情与签到），每个结果单独 `apply`。添加活动只在已报名列表成功时读取，否则会把已报名的活动也列进来。
- 报名是写操作：与读取一样经 `startRead`，但不经 `readRetry`，只发一次，失败不重试。
- 读取分开做：一块失败，不影响别的块。不要把两块放进同一个 `apply`。
- 首页的读取计数用 `home.pending`，最后一个结束时写 `stamp`。
- 页面何时读：登录时读首页、爱安财、一卡通；培养方案在第一次打开时读（`openPage`）。页头的刷新只读当前页，首页的刷新同时读一卡通余额（`refreshHome`）。
- 学校读取都经 `readRetry` 包住：可修复的错误（如网络、超时、页面解析失败）间隔 2 秒、5 秒重试，凭据、取消类错误不重试（见 `neverRetried`）。最终失败时写一行错误码日志，不写消息。
- 错误文案用 `readErrText`，不要自己写新的错误判断。
- 学校接口能用 `loveace-go` 的服务就用它，不自己发请求。拿不到的字段，
  才在 `home_data.go` 里读同一个接口（如 `academicAverage`），并注释原因。
- 智能排课的读取经 `SmartData`，由 webview 发起，不走 `startRead`。`SmartData` 的 JSON 键是 loveace-go 结构体的 snake_case 标签，`smartui/app` 模型的 `@JsonKey` 必须与之一致。账号随 `signedIn` / `signOut` 写入 `SmartData.acc`。

## 凭据与隐私

- 密码只在 `mygo.Secrets`（钥匙串）里，键是 `school-password:<学号>`。
- `settings.json` 只存学号（`remember_id`），不存密码。
- 不打印、不记录：密码、Cookie、TWFID、验证码图片字节、学校原始响应。
  日志只写错误码或固定说明。

## 界面规则（摘要，全文在 DESIGN.md）

- 用列，不用固定宽度堆叠。`Row` 里 `Grow` 的子元素必须加 `MinWidth(0)`，
  否则内容的最小宽度会打乱分栏比例（这是首页上下两行分界对不齐的原因）。
- 芯片放在 `Row` 里，不直接放进会拉伸的 `Column`。
- 每页最上方放 `dragStrip(c)`。拖动条上不放控件。
- 加载态用 `shapeLoader`，不用 `ui.Spinner`。原生圆点与设计不符。
- 卡片头用 `cardHeader`；圆角、内边距、间距用 `m3e.go` 的常量，不写魔法数字。
  （`home.go` 里的 `Padding(8, 4)` 之类的小块内边距允许，但要在 DESIGN.md 里有对应。）
- 颜色只从 `palette.Scheme`（经 `uiColor`）和 `extended` 来。不要写 `ui.Hex("#...")`。
- 默认窗口里要能看到主要信息。新增内容时，先检查渲染，再决定要不要滚动。

## 图标

- 图标是 Material Symbols Rounded 24px，放在 `assets/icons/`，文件名与符号名一致。
  下载地址格式：`https://raw.githubusercontent.com/google/material-design-icons/master/symbols/web/<name>/materialsymbolsrounded/<name>_24px.svg`
  填充版是 `<name>_fill1_24px.svg`。
- 新图标：加文件、在 `icons.go` 里加 `go:embed` 和 `iconXxx` 变量。
- 删图标：删文件、删 embed、删变量，并确认没有引用。
- 只保留被引用的图标。改完后检查：`icons.go` 里每个 embed 文件都存在，
  `assets/icons/` 里没有未引用的文件。

## 测试

- 永久测试只测逻辑（口径、学期推导、冷却、选择规则），确定性的，不触网。
- 界面测试用 `ui.NewTester`，不需要窗口。点击用 `tt.Click(label)`。
- 渲染检查用临时测试，检查完删掉，不提交。
- 不要为了通过测试而降低断言。

## 文档

- 改了界面规则，同步 `DESIGN.md`。
- 改了代码结构或约定，同步本文件。
- 不写未实现的设想。
