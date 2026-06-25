<p align="center">
  <img src="assets/logo.png" width="160" alt="LoveACE 标志" />
</p>

<h1 align="center">LoveACE</h1>

<p align="center">
  面向校园学习与生活的一体化工具箱，覆盖 Android、iOS 与桌面端。
</p>

<p align="center">
  <a href="https://github.com/Sibuxiangx/LoveACE/actions/workflows/build-apk.yml"><img alt="安卓发布构建" src="https://img.shields.io/github/actions/workflow/status/Sibuxiangx/LoveACE/build-apk.yml?branch=main&label=%E5%AE%89%E5%8D%93%E5%8F%91%E5%B8%83&style=flat-square"></a>
  <a href="https://github.com/Sibuxiangx/LoveACE/actions/workflows/ios-testflight.yml"><img alt="iOS TestFlight" src="https://img.shields.io/github/actions/workflow/status/Sibuxiangx/LoveACE/ios-testflight.yml?branch=main&label=iOS%20TestFlight&style=flat-square&logo=apple"></a>
  <a href="https://github.com/Sibuxiangx/LoveACE/actions/workflows/build-desktop-macos.yml"><img alt="macOS Desktop" src="https://img.shields.io/github/actions/workflow/status/Sibuxiangx/LoveACE/build-desktop-macos.yml?branch=main&label=macOS&style=flat-square&logo=apple"></a>
  <a href="https://github.com/Sibuxiangx/LoveACE/actions/workflows/build-desktop-windows.yml"><img alt="Windows Desktop" src="https://img.shields.io/github/actions/workflow/status/Sibuxiangx/LoveACE/build-desktop-windows.yml?branch=main&label=Windows&style=flat-square&logo=windows"></a>
  <img alt="安卓版本" src="https://img.shields.io/badge/Android-1.1.16-3DDC84?style=flat-square&logo=android&logoColor=white">
  <img alt="桌面端版本" src="https://img.shields.io/badge/Desktop-1.1.11-6F42C1?style=flat-square&logo=flutter&logoColor=white">
  <img alt="iOS" src="https://img.shields.io/badge/iOS-17%2B-000000?style=flat-square&logo=apple&logoColor=white">
  <img alt="许可证" src="https://img.shields.io/badge/%E8%AE%B8%E5%8F%AF%E8%AF%81-Apache--2.0-blue?style=flat-square">
</p>

---

## 简介

LoveACE 是一个围绕校园学习与生活场景构建的多端项目，提供课程、成绩、考试、一卡通、电费、竞赛、劳动俱乐部、报修、门禁、评教辅助等常用能力的聚合入口。

当前仓库采用多端聚合结构：

- **Android**：Kotlin + Jetpack Compose
- **iOS**：SwiftUI
- **Desktop**：Flutter，覆盖 macOS 与 Windows
- **Analytics Worker**：Cloudflare Worker + D1，用于匿名统计聚合展示

历史版本和旧后端以分支形式保留，便于查阅与迁移。

## 匿名使用统计

匿名遥测 BI 由 Cloudflare Worker 实时读取 D1 聚合结果生成，只展示汇总数据，不展示明文学号、原始事件或任何业务内容。

- [查看 LoveACE Telemetry BI](https://analyst-api.linota.cn/bi)

## 仓库结构

```text
LoveACE/
├── android/              # Android 原生客户端
├── ios/                  # iOS 原生客户端
├── desktop/              # Flutter 桌面端（macOS / Windows）
├── analytics-worker/     # 匿名统计 Worker 与 BI 页面
├── assets/               # README 与仓库展示资源
└── .github/workflows/    # 手动发布工作流
```

## 分支说明

| 分支 | 说明 |
| --- | --- |
| `main` | 当前多端聚合主线，包含 Android、iOS、Desktop 与 Worker |
| `flutter-ver` | 旧 Flutter 实现归档 |
| `backend-old` | 旧后端仓库归档 |

## 功能概览

- 课程表与学期周视图
- 成绩、考试、培养方案、智能排课与教务信息
- 一卡通、电费、门禁与报修
- 竞赛、劳动俱乐部与自动评教辅助
- Android / iOS 小组件与桌面端课程表
- 多端 OTA 清单、下载页与匿名使用统计

## 反馈与路线图

Issues 已配置分类模板和标签，提交前请选择最接近的入口：

- **问题反馈**：崩溃、异常、无法使用或体验问题，会自动标记 `bug`。
- **功能建议**：新功能或体验优化建议，会自动标记 `enhancement`。
- **通用 Issue**：不确定分类时使用；也允许直接创建空白 issue。
- **内部使用**：维护者记录待办、技术债、发版和后续规划。

常用分类标签：

- `status: triage` / `status: planned` / `status: in progress`
- `area: android` / `area: ios` / `area: desktop` / `area: all-platforms`
- `area: release-ci` / `area: backend` / `area: product-ux`
- `future`：路线图与后续规划

提交 issue 时请不要包含账号、密码、Cookie、Token 等敏感信息。

## Android 构建与发布

Android 发布通过 GitHub Actions 手动触发，不会在推送代码时自动运行。

```bash
gh workflow run build-apk.yml \
  --ref main \
  -f version=1.1.16 \
  -f changelog="更新内容" \
  -f content="发现新版本" \
  -f force=false
```

工作流会依次完成：

1. 还原正式版签名密钥
2. 构建调试版和正式版 APK
3. 上传 APK 构建产物
4. 通过 `android/tools/publish` 发布正式版 APK 并更新 OTA 清单

> 签名密钥和 S3/CDN 配置均通过 GitHub Secrets 注入，禁止提交到仓库。

## iOS 构建与发布

iOS 项目位于：

```text
ios/loveaceios.xcodeproj
```

常用命令：

```bash
cd ios
xcodebuild -project loveaceios.xcodeproj \
  -scheme loveaceios \
  -configuration Debug \
  -destination 'generic/platform=iOS' \
  build
```

iOS TestFlight 发布通过 GitHub Actions 手动触发：

```bash
gh workflow run ios-testflight.yml --ref main -f dry_run=false
```

本地构建、归档和上传仍可通过 Xcode，或配合项目内的 `ExportOptions.plist` 与签名配置完成。

## Desktop 构建与发布

Desktop 项目位于：

```text
desktop/
```

本地调试：

```bash
cd desktop
flutter pub get
flutter run -d macos      # macOS
flutter run -d windows    # Windows
```

桌面端发布通过手动 workflow 完成。macOS 会完成 Developer ID 签名、公证与 stapling；Windows 会生成 Inno Setup 安装器。两个桌面端发布都会更新 OTA manifest，因此如需同时发版应串行触发，避免 manifest 覆盖竞态。

```bash
gh workflow run build-desktop-macos.yml \
  --ref main \
  -f dry_run=false \
  -f changelog="更新内容" \
  -f content="发现新版本" \
  -f force=false

gh workflow run build-desktop-windows.yml \
  --ref main \
  -f dry_run=false \
  -f changelog="更新内容" \
  -f content="发现新版本" \
  -f force=false
```

如需临时切换 manifest 下载 URL 的网络出口，可使用：

```bash
gh workflow run network-guard-ci.yml --ref main -f mode=cloudflare -f dry_run=false
gh workflow run network-guard-ci.yml --ref main -f mode=edgeone -f dry_run=false
```

## 本地开发

```bash
git clone https://github.com/Sibuxiangx/LoveACE.git
cd LoveACE
```

- Android：用 Android Studio 打开 `android/`
- iOS：用 Xcode 打开 `ios/loveaceios.xcodeproj`
- Desktop：用支持 Flutter 的 IDE 打开 `desktop/`
- Worker：进入 `analytics-worker/` 后按该目录 README 配置与部署

## 许可证

本仓库源码基于 [Apache License 2.0](LICENSE) 开源。

项目名称、Logo、图标、截图、捐赠二维码等品牌与视觉资源的使用不由 Apache License 2.0 授权；如需使用相关品牌资源，请先取得授权。详见 [NOTICE](NOTICE)。

## 备注

该仓库已从多个历史 LoveACE 项目聚合而来。旧实现没有丢失，分别保留在 `flutter-ver` 与 `backend-old` 分支中。
