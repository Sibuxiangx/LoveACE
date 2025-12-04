# 彩带小工具 (LoveACE)

一款为安徽财经大学学生打造的多功能校园助手 App，基于 Flutter 开发，支持 Android，将逐步支持 iOS、macOS、Windows、Linux 和 Web 平台。

## 功能特性

- 🎓 **学业信息查询** - 查看个人学业完成情况、学分统计
- 📊 **成绩查询** - 按学期查看课程成绩，支持 CSV 导出
- 📅 **考试安排** - 查看近期考试时间、地点
- 📚 **培养方案** - 查看专业培养方案完成进度
- 🏆 **竞赛信息** - 查看个人竞赛获奖记录
- ⚡ **电费查询** - 查询宿舍电费余额和用电记录
- 💼 **劳动俱乐部** - 查看劳动学分、扫码签到
- 🌟 **爱安财积分** - 查看爱安财平台积分明细

## 技术栈

- **框架**: Flutter 3.9+
- **状态管理**: Provider
- **网络请求**: Dio
- **本地存储**: SharedPreferences, FlutterSecureStorage
- **加密**: PointyCastle (RSA/DES)

## 开始使用

### 环境要求

- Flutter SDK ^3.9.2
- Dart SDK ^3.9.2

### 安装依赖

```bash
flutter pub get
```

### 生成代码

```bash
flutter pub run build_runner build --delete-conflicting-outputs
```

### 运行项目

```bash
# 调试模式
flutter run

# 发布模式
flutter run --release
```

### 构建发布版本

```bash
# Android APK
flutter build apk --release

# iOS
flutter build ios --release

# macOS
flutter build macos --release
```

## 项目结构

```
lib/
├── constants/       # 常量配置
├── models/          # 数据模型
├── providers/       # 状态管理
├── screens/         # 页面
├── services/        # 服务层
├── utils/           # 工具类
├── widgets/         # 通用组件
└── main.dart        # 入口文件
```

## 许可证

本项目采用 **GNU AGPL-3.0 许可证** 并附加 **严格禁止商业使用条款**。

### 项目性质

本软件是 **安徽财经大学教育服务的衍生项目**，专为教育和学习目的开发。

### 主要条款

- ✅ 可以自由使用、修改和分发本软件（仅限非商业用途）
- ✅ 必须开源所有修改和衍生作品
- ✅ 网络使用也需要提供源代码（AGPL特性）
- ❌ **严格禁止任何形式的商业使用**

### 严格禁止商业使用

本软件在任何情况下均不得用于商业目的，包括但不限于：
- 销售本软件或其衍生作品
- 将本软件作为商业服务的一部分提供
- 在商业产品中集成或捆绑本软件
- 通过本软件直接或间接获取商业利益
- 为商业实体提供基于本软件的服务
- 任何形式的商业化运营

### 允许的使用范围

本软件仅可用于：
- 个人学习和研究
- 教育机构的教学活动
- 非营利组织的非商业用途
- 开源社区的协作开发

### 重要声明

⚠️ **本软件不提供任何形式的商业使用许可。任何商业使用请求均将被拒绝。**

详细许可证内容请查看 [LICENSE](LICENSE) 文件。

---

Copyright (C) 2025 LoveACE

This project is a derivative of educational services at Anhui University of Finance and Economics.

Licensed under **GNU AGPL-3.0** with **Strict Prohibition of Commercial Use**.

⚠️ **Commercial use is strictly prohibited under any circumstances.**


### 字体许可

本应用使用 MiSans 字体，根据小米科技有限责任公司的授权条款使用。
