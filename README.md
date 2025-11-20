# LoveACE - 财大自动化工具

<div align="center">

<img src="https://cdn.apifox.com/app/project-icon/custom/20251011/e20b3227-13dd-4057-b1d3-dc821294d914.jpeg" alt="LoveACE Logo" width="120" height="120" />

**Make It Easy**
</div>

## 🚀 项目简介

LoveACE 是一个面向安徽财经大学的教务系统自动化工具，专为安徽财经大学各类系统设计。通过 RESTful API 接口，提供课表查询、成绩查询、积分查询、宿舍管理等功能，大幅简化学生的日常操作流程。

### ✨ 主要特性

- **🔐 安全认证**: 基于 Token 的用户认证系统，RSA 加密保护敏感信息
- **📚 教务集成**: 深度集成教务系统，支持成绩、课表、考试、培养方案、学业信息查询
- **💯 积分查询**: 爱安财系统集成，实时查询积分和明细
- **🏠 宿舍管理**: ISIM系统集成，支持电费查询和房间信息查询
- **🚀 高性能**: 基于 FastAPI 构建，支持异步处理和高并发
- **📊 中间件支持**: 请求处理时间监控、CORS 配置
- **🔒 数据安全**: RSA 加密存储敏感信息，保护用户隐私

### 🛠️ 技术栈

- **后端框架**: [FastAPI](https://fastapi.tiangolo.com/) - 现代、快速的 Python Web 框架
- **数据库**: [SQLAlchemy](https://sqlalchemy.org/) (异步) + [aiomysql](https://aiomysql.readthedocs.io/) - 强大的异步 ORM
- **HTTP客户端**: [httpx](https://www.python-httpx.org/) - 现代化的异步 HTTP 客户端
- **日志系统**: [richuru](https://github.com/GreyElaina/richuru) - rich + loguru 的完美结合
- **包管理**: [uv](https://github.com/astral-sh/uv) - 极速 Python 包管理器
- **加密工具**: [cryptography](https://cryptography.io/) - RSA 加密支持
- **数据解析**: [BeautifulSoup4](https://www.crummy.com/software/BeautifulSoup/) + [lxml](https://lxml.de/) - HTML 解析

## 📚 API 功能

### 认证模块 (`/auth`)
- **用户注册**: 创建新用户账号
- **用户登录**: 获取访问令牌
- **身份验证**: 验证当前用户身份和令牌有效性

### 教务系统 (`/jwc`)
- **成绩查询**: 查询学期成绩和历史成绩
- **课表查询**: 获取当前学期课程表
- **考试安排**: 查看考试时间和地点
- **培养方案**: 查询专业培养方案
- **学业信息**: 获取学生基本学业信息
- **学期信息**: 查询学期列表

### 爱安财系统 (`/aac`)
- **学分查询**: 查询总的爱安财学分
- **学分明细**: 获取爱安财学分明细

### 宿舍管理 (`/isim`)
- **电费查询**: 查询宿舍剩余电费
- **房间信息**: 获取宿舍房间详细信息

## 📚 文档

### API 文档
启动服务后，在 debug 模式下访问：
- **Swagger UI**: http://localhost:4500/docs
- **ReDoc**: http://localhost:4500/redoc
- **OpenAPI Schema**: http://localhost:4500/openapi.json

> **注意**: 生产环境下，文档接口默认关闭，需在配置文件中设置 `app.debug = true` 启用。

## 🏗️ 项目结构

```
LoveACE-V2/
├── 📁 loveace/            # 主应用目录
│   ├── 📁 config/        # 配置管理
│   │   ├── logger.py     # 日志配置
│   │   ├── manager.py    # 配置管理器
│   │   └── settings.py   # 配置模型
│   ├── 📁 database/      # 数据库相关代码
│   │   ├── creator.py    # 数据库会话管理
│   │   ├── base/         # 基础模型定义
│   │   ├── auth/         # 认证相关模型 (用户、令牌、登录、注册)
│   │   ├── aac/          # 爱安财积分票据模型
│   │   └── isim/         # 宿舍管理模型
│   ├── 📁 router/        # API路由定义
│   │   ├── dependencies/ # 路由依赖项 (认证、日志等)
│   │   ├── endpoint/     # API端点
│   │   │   ├── auth/     # 认证路由 (登录、注册、authme)
│   │   │   ├── jwc/      # 教务系统路由 (成绩、课表、考试、培养方案等)
│   │   │   ├── aac/      # 爱安财系统路由 (积分查询)
│   │   │   └── isim/     # 宿舍管理路由 (电费、房间信息)
│   │   └── schemas/      # 通用响应模型和错误处理
│   ├── 📁 service/       # 服务层
│   │   ├── model/        # 服务模型
│   │   └── remote/       # 远程服务
│   │       └── aufe/     # 安徽财经大学服务集成
│   ├── 📁 middleware/    # 中间件
│   │   └── process_time.py # 请求处理时间中间件
│   └── 📁 utils/         # 工具函数
│       ├── richuru_hook.py # Rich + Loguru 集成
│       └── rsa.py        # RSA 加密工具
├── 📁 data/              # 数据文件
│   ├── isim_rooms.json   # 宿舍房间数据
│   └── keys/             # RSA密钥对
├── 📁 logs/              # 日志文件目录
├── 📄 main.py            # 应用入口文件
├── 📄 config.json        # 配置文件
├── 📄 pyproject.toml     # 项目依赖配置 (uv)
├── 📄 uv.lock            # 依赖锁定文件
└── 📄 README.md          # 项目说明文档
```

## 🤝 贡献

我们欢迎所有形式的贡献！

### 贡献方式

- 🐛 **Bug报告**: [创建Issue](https://github.com/LoveACE-Team/LoveACE/issues/new)
- 💡 **功能建议**: [发起Issue](https://github.com/LoveACE-Team/LoveACE/issues/new)
- 📝 **代码贡献**: 提交Pull Request
- 📖 **文档改进**: 帮助完善文档

### 开发指南

```bash
# 克隆项目
git clone https://github.com/LoveACE-Team/LoveACE.git
cd LoveACE

# 安装开发依赖
uv sync --group dev

# 代码格式化
black .
isort .

# 代码检查
ruff check .
```

## ⚖️ 免责声明

**重要提醒**: 本软件仅供学习、研究和个人非商业用途使用。

### 使用条款

- ✅ **开源性质**: 本软件为教育目的开发的开源项目，遵循 MIT 许可证
- 📚 **用途限制**: 仅限于学习交流、技术研究等非商业用途
- ⚠️ **合规使用**: 使用时请严格遵守学校相关规定、服务条款及您所在地的法律法规
- 🛡️ **账户安全**: 请妥善保管个人账户信息，不要与他人共享，避免账号泄露
- 🔒 **隐私保护**: 本软件不会主动收集、存储或泄露用户的个人信息

### 商业使用禁止

- ❌ **严禁商用**: 本软件不得用于任何形式的商业用途，包括但不限于：
  - 收费服务或产品
  - 商业广告和推广
  - 未经授权的数据采集和销售
- ⚠️ **风险自负**: 任何未经授权的商业使用所产生的法律责任、经济损失、侵权纠纷及其他风险，均由商业使用者自行承担，与本软件作者及所有贡献者无关

### 免责条款

- 🚫 **后果免责**: 开发者及贡献者不对使用本软件造成的任何直接或间接后果负责，包括但不限于：
  - 账号封禁或处罚
  - 数据丢失或泄露
  - 服务中断或错误
  - 学业或经济损失
- 🔧 **无担保**: 本软件按"现状"提供，不提供任何明示或暗示的担保，包括但不限于适销性、特定用途适用性的担保
- 📋 **自行判断**: 用户应自行判断使用本软件的风险，并承担使用本软件的全部责任

### 接受条款

- 📜 **视为同意**: 下载、安装、使用本软件或对本软件进行任何形式的操作，即表示您已充分阅读、理解并同意接受本免责声明的所有条款
- ⛔ **不同意则停止**: 如果您不同意本免责声明的任何条款，请立即停止使用本软件并删除所有相关文件

## 📞 支持与联系

- 📧 **邮箱**: [sibuxiang@proton.me](mailto:sibuxiang@proton.me)
- 🐛 **Bug报告**: [GitHub Issues](https://github.com/LoveACE-Team/LoveACE/issues)
- 💬 **讨论交流**: [GitHub Discussions](https://github.com/LoveACE-Team/LoveACE/discussions)

## 📄 许可证

本项目采用 [MIT许可证](LICENSE) 开源。

**重要商业使用限制**: 本软件不得用于商业用途。任何未经授权的商业使用所产生的一切法律责任、经济损失及其他风险，均由商业使用者自行承担，与本软件作者及贡献者无关。

```bash
MIT License

Copyright (c) 2025 LoveACE Team

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

COMMERCIAL USE RESTRICTION:
This software is NOT intended for commercial use. Any unauthorized commercial
use of this software is strictly prohibited. All legal liabilities, financial
losses, and other risks arising from unauthorized commercial use shall be 
borne solely by the commercial user and are not the responsibility of the 
software authors or contributors.

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```
---

<div align="center">

**如果这个项目对你有帮助，请给它一个 ⭐️**

Made with ❤️ by [Sibuxiangx](https://github.com/Sibuxiangx)

</div>