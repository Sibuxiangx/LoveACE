<p align="center">
  <img src="assets/logo.png" width="160" alt="LoveACE Logo" />
</p>

<h1 align="center">LoveACE</h1>

<p align="center">
  面向校园生活的一体化移动端工具箱，现已聚合 Android 与 iOS 原生客户端。
</p>

<p align="center">
  <a href="https://github.com/Sibuxiangx/LoveACE/actions/workflows/build-apk.yml"><img alt="Android Build" src="https://img.shields.io/github/actions/workflow/status/Sibuxiangx/LoveACE/build-apk.yml?branch=main&label=Android%20Release&style=flat-square"></a>
  <img alt="Android" src="https://img.shields.io/badge/Android-1.1.11-3DDC84?style=flat-square&logo=android&logoColor=white">
  <img alt="iOS" src="https://img.shields.io/badge/iOS-17%2B-000000?style=flat-square&logo=apple&logoColor=white">
  <img alt="License" src="https://img.shields.io/badge/license-private-lightgrey?style=flat-square">
</p>

---

## 简介

LoveACE 是一个围绕校园学习与生活场景构建的移动端项目，提供课程、成绩、考试、一卡通、电费、竞赛、劳动俱乐部、报修、门禁等常用能力的聚合入口。

当前仓库采用原生客户端聚合结构：

- **Android**：Kotlin + Jetpack Compose
- **iOS**：SwiftUI

历史版本和旧后端以分支形式保留，便于查阅与迁移。

## 仓库结构

```text
LoveACE/
├── android/              # Android 原生客户端
├── ios/                  # iOS 原生客户端
├── assets/               # README 与仓库展示资源
└── .github/workflows/    # 手动发布工作流
```

## 分支说明

| 分支 | 说明 |
| --- | --- |
| `main` | 当前原生客户端聚合主线，包含 `android/` 与 `ios/` |
| `flutter-ver` | 旧 Flutter 实现归档 |
| `backend-old` | 旧后端仓库归档 |

## 功能概览

- 课程表与学期周视图
- 成绩、考试、培养方案与教务信息
- 一卡通、电费、门禁与报修
- 竞赛、劳动俱乐部与评教辅助
- 课程表桌面组件与 OTA 更新能力

## Android 构建与发布

Android 发布通过 GitHub Actions 手动触发，不会在 push 时自动运行。

```bash
gh workflow run build-apk.yml \
  --ref main \
  -f version=1.1.11 \
  -f changelog="更新内容" \
  -f content="发现新版本" \
  -f force=false
```

工作流会依次完成：

1. 还原 release 签名密钥
2. 构建 debug / release APK
3. 上传 APK artifacts
4. 通过 `android/tools/publish` 发布 release APK 并更新 OTA manifest

> 签名密钥和 S3/CDN 配置均通过 GitHub Secrets 注入，禁止提交到仓库。

## iOS 构建

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

如需 TestFlight / App Store Connect 上传，请使用 Xcode 或项目内的 `ExportOptions.plist` 配合签名配置完成。

## 本地开发

```bash
git clone https://github.com/Sibuxiangx/LoveACE.git
cd LoveACE
```

- Android：用 Android Studio 打开 `android/`
- iOS：用 Xcode 打开 `ios/loveaceios.xcodeproj`

## 安全约定

- 不提交 `.env`、`local.properties`、keystore、证书、provisioning profile 等敏感文件。
- Android release 签名只在 GitHub Actions 中通过 Secrets 还原。
- 发布工具所需 S3/CDN 凭据只通过环境变量或本地 ignored `.env` 提供。

## 备注

该仓库已从多个历史 LoveACE 项目聚合而来。旧实现没有丢失，分别保留在 `flutter-ver` 与 `backend-old` 分支中。
