/// 应用常量配置
///
/// 集中管理应用名称、版本号、许可证等配置信息
class AppConstants {
  // 应用信息
  static const String appName = '彩带小工具';
  static const String appVersion = '1.1.11';
  static const String appDescription = '快速查看个人信息中...';

  // Manifest 服务
  static const String manifestUrl = 'https://loveace.linota.cn/loveace/manifest.json';

  // 许可证信息
  static const List<LicenseInfo> licenses = [
    LicenseInfo(
      name: 'MiSans 字体',
      description: '小米科技有限责任公司',
      licenseText: '''
本应用在 Windows 平台使用 MiSans 字体。

根据小米科技有限责任公司的授权，MiSans 字体可免费用于个人和商业用途。

使用条件：
• 应特别注明使用了 MiSans 字体
• 不得对字体进行改编或二次开发
• 不得单独分发或售卖字体文件
• 可自由分发使用该字体创作的作品

本应用遵守以上使用条款。
      ''',
    ),
  ];

  // 开发者信息
  static const String developerName = 'LoveACE Team';
  static const String developerEmail = 'dev@loveace.tech';

  // 用户协议
  static const String userAgreement = '''
欢迎使用彩带小工具！在使用本应用前，请仔细阅读以下用户协议：

一、数据存储与安全

1. 账号密码存储
本应用会在您的设备本地加密存储您的账号和密码，以便实现快速启动和自动登录功能。

2. 加密方式说明
本应用使用各平台提供的安全存储机制：
• iOS/macOS：使用 Apple Keychain 安全存储
• Android：使用 EncryptedSharedPreferences（基于 AES-256 加密）
• Windows/Linux：使用平台安全存储机制

3. Token 存储
为了提供更好的使用体验和连接重建功能，本应用会在本地存储部分认证 Token。

4. 数据安全
所有敏感数据均采用加密方式存储，不会上传至任何第三方服务器。

5. 安全风险提示
请注意，以下情况可能导致您的账号密码泄露：
• 设备被 Root/越狱后安全机制可能失效
• 设备感染恶意软件或病毒
• 将设备借给他人使用
• 使用不安全的公共网络
• 设备丢失或被盗
本应用无法对上述情况导致的信息泄露负责，请妥善保管您的设备。

二、权限使用说明

本应用可能需要以下权限：

• 网络访问权限：用于连接学校服务器获取数据
• 相机权限：用于扫码签到功能（劳动俱乐部）
• 存储权限：用于导出成绩等数据到本地文件

三、LoveACE Manifest 服务

本应用集成了 LoveACE Manifest 服务，用于提供应用公告和 OTA 更新功能：

1. 公告服务
• 应用会定期从 Manifest 服务器获取最新公告
• 公告内容仅用于向用户传达重要信息
• 公告数据不包含任何个人信息

2. OTA 更新服务
• 应用会检查是否有新版本可用
• 用户可以选择立即更新或稍后更新
• 强制更新时用户必须更新才能继续使用应用
• 更新过程中会显示更新日志和下载进度

3. 数据收集
• Manifest 服务不收集任何用户个人信息
• 仅记录基本的访问日志用于服务监控
• 所有通信均通过 HTTPS 加密传输

四、匿名使用统计

本应用集成了匿名使用统计功能，用于了解功能使用情况和版本分布，以便持续改进：

1. 收集内容
• 应用启动、页面浏览、功能使用等基本操作事件
• 应用版本号、操作系统版本和设备平台信息
• 匿名化年级前缀（学号前4位）和哈希处理后的学号标识

2. 不收集内容
• 不收集任何明文学号、密码、姓名等个人身份信息
• 不收集位置信息、通讯录、短信等敏感信息
• 不收集任何业务数据（课程详情、成绩、校园卡余额等）
• 不记录 IP 地址或 User-Agent 等网络标识

3. 数据用途
• 统计各功能模块使用频率，指导产品优化
• 统计版本分布，评估兼容性和升级策略
• 监控异常和会话健康度

4. 数据控制
• 统计结果仅展示聚合数据，无法追溯到个人
• 数据通过 HTTPS 加密传输
• 所有数据存储于 Cloudflare D1 数据库
• 用户无需任何操作即可关闭统计（删除/阻止统计相关网络请求）

5. 隐私保障
• 所有收集的标识均经过单向哈希处理，不可逆推回原始学号
• 不设置跨应用追踪标识
• 不向任何第三方共享原始事件数据

五、开源许可

本应用基于 GNU AGPL-3.0 许可证开源，附加禁止商业使用条款：

• 本软件仅可用于个人学习、教育活动和非商业用途
• 严格禁止任何形式的商业使用
• 您可以自由查看、修改和分发源代码，但必须遵守相同的许可条款
• 完整许可证请访问：https://www.gnu.org/licenses/agpl-3.0.html

六、服务条款

1. 本应用为第三方开发，与学校官方无关
2. 本应用不保证服务的持续可用性
3. 如学校接口变更，本应用可能无法正常使用
4. 开发者保留随时修改或终止服务的权利
5. 使用本应用产生的任何风险由用户自行承担

继续使用本应用即表示您同意以上条款。
''';

  // 隐私构造函数，防止实例化
  AppConstants._();
}

/// 许可证信息模型
class LicenseInfo {
  final String name;
  final String description;
  final String licenseText;

  const LicenseInfo({
    required this.name,
    required this.description,
    required this.licenseText,
  });
}
