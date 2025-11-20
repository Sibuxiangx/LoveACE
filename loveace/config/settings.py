from enum import Enum
from typing import Any, Dict, List, Optional

from pydantic import BaseModel, Field, field_validator


class LogLevel(str, Enum):
    """日志级别枚举"""

    TRACE = "TRACE"
    DEBUG = "DEBUG"
    INFO = "INFO"
    SUCCESS = "SUCCESS"
    WARNING = "WARNING"
    ERROR = "ERROR"
    CRITICAL = "CRITICAL"


class DatabaseConfig(BaseModel):
    """数据库配置"""

    url: str = Field(
        default="mysql+aiomysql://root:123456@localhost:3306/loveac",
        description="数据库连接URL",
    )
    echo: bool = Field(default=False, description="是否启用SQL日志")
    pool_size: int = Field(default=10, description="连接池大小")
    max_overflow: int = Field(default=20, description="连接池最大溢出")
    pool_timeout: int = Field(default=30, description="连接池超时时间(秒)")
    pool_recycle: int = Field(default=3600, description="连接回收时间(秒)")


class ISIMConfig(BaseModel):
    """ISIM后勤电费系统配置"""

    base_url: str = Field(
        default="http://hqkd-aufe-edu-cn.vpn2.aufe.edu.cn",
        description="ISIM系统基础URL",
    )
    room_cache_path: str = Field(
        default="data/isim_rooms.json", description="寝室信息缓存路径"
    )
    room_cache_expire: int = Field(
        default=86400, description="寝室信息刷新间隔(秒)"
    )  # 默认24小时刷新一次
    session_timeout: int = Field(default=1800, description="会话超时时间(秒)")
    retry_times: int = Field(default=3, description="请求重试次数")


class AUFEConfig(BaseModel):
    """AUFE连接配置"""

    default_timeout: int = Field(default=30, description="默认超时时间(秒)")
    max_retries: int = Field(default=3, description="最大重试次数")
    max_reconnect_retries: int = Field(default=2, description="最大重连次数")
    activity_timeout: int = Field(default=300, description="活动超时时间(秒)")
    monitor_interval: int = Field(default=60, description="监控间隔(秒)")
    retry_base_delay: float = Field(default=1.0, description="重试基础延迟(秒)")
    retry_max_delay: float = Field(default=60.0, description="重试最大延迟(秒)")
    retry_exponential_base: float = Field(default=2, description="重试指数基数")
    server_url: str = Field(
        default="https://vpn.aufe.edu.cn", description="AUFE服务器URL"
    )
    ec_check_url: str = Field(
        default="http://txzx-aufe-edu-cn-s.vpn2.aufe.edu.cn:8118/dzzy/list.htm",
        description="EC检查URL",
    )

    # UAAP配置
    uaap_base_url: str = Field(
        default="http://uaap-aufe-edu-cn.vpn2.aufe.edu.cn:8118/cas",
        description="UAAP基础URL",
    )
    uaap_login_url: str = Field(
        default="http://uaap-aufe-edu-cn.vpn2.aufe.edu.cn:8118/cas/login?service=http%3A%2F%2Fjwcxk2.aufe.edu.cn%2Fj_spring_cas_security_check",
        description="UAAP登录URL",
    )
    uaap_check_url: str = Field(
        default="http://jwcxk2-aufe-edu-cn.vpn2.aufe.edu.cn:8118/",
        description="UAAP检查链接",
    )

    # 默认请求头
    default_headers: Dict[str, str] = Field(
        default_factory=lambda: {
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36"
        },
        description="默认请求头",
    )


class RedisConfig(BaseModel):
    """Redis客户端配置"""

    host: str = Field(default="localhost", description="Redis主机地址")
    port: int = Field(default=6379, description="Redis端口")
    db: int = Field(default=0, description="Redis数据库编号")
    password: Optional[str] = Field(default=None, description="Redis密码")
    encoding: str = Field(default="utf-8", description="字符编码")
    decode_responses: bool = Field(default=True, description="是否自动解码响应")
    max_connections: int = Field(default=50, description="连接池最大连接数")
    socket_keepalive: bool = Field(default=True, description="是否启用socket保活")
    socket_keepalive_options: Optional[Dict[str, Any]] = Field(
        default=None, description="Socket保活选项"
    )
    health_check_interval: int = Field(default=30, description="健康检查间隔(秒)")
    retry_on_timeout: bool = Field(default=True, description="超时时是否重试")


class S3Config(BaseModel):
    """S3客户端配置"""

    access_key_id: str = Field(default="", description="S3访问密钥ID")
    secret_access_key: str = Field(default="", description="S3秘密访问密钥")
    endpoint_url: str = Field(default="", description="S3终端节点URL")
    region_name: str = Field(default="us-east-1", description="S3区域名称")
    bucket_name: str = Field(default="", description="默认存储桶名称")
    use_ssl: bool = Field(default=True, description="是否使用SSL")
    signature_version: str = Field(default="s3v4", description="签名版本")
    addressing_style: str = Field(
        default="auto", description="地址风格（auto, path, virtual）"
    )

    @field_validator("access_key_id", "secret_access_key", "bucket_name")
    @classmethod
    def validate_required_fields(cls, v):
        """验证必填字段"""
        # 允许为空，但应在运行时检查
        return v


class LogConfig(BaseModel):
    """日志配置"""

    level: LogLevel = Field(default=LogLevel.INFO, description="日志级别")
    file_path: str = Field(default="logs/app.log", description="日志文件路径")
    rotation: str = Field(default="10 MB", description="日志轮转大小")
    retention: str = Field(default="30 days", description="日志保留时间")
    compression: str = Field(default="zip", description="日志压缩格式")
    backtrace: bool = Field(default=True, description="是否启用回溯")
    diagnose: bool = Field(default=True, description="是否启用诊断")
    console_output: bool = Field(default=True, description="是否输出到控制台")


class AppConfig(BaseModel):
    """应用程序配置"""

    title: str = Field(default="LoveACE API", description="应用标题")
    description: str = Field(default="LoveACE API", description="应用描述")
    version: str = Field(default="1.0.0", description="应用版本")
    debug: bool = Field(default=False, description="是否启用调试模式")

    # CORS配置
    cors_allow_origins: List[str] = Field(
        default_factory=lambda: ["*"], description="允许的CORS来源"
    )
    cors_allow_credentials: bool = Field(default=True, description="是否允许CORS凭据")
    cors_allow_methods: List[str] = Field(
        default_factory=lambda: ["*"], description="允许的CORS方法"
    )
    cors_allow_headers: List[str] = Field(
        default_factory=lambda: ["*"], description="允许的CORS头部"
    )

    # 服务器配置
    host: str = Field(default="0.0.0.0", description="服务器主机")
    port: int = Field(default=8000, description="服务器端口")
    workers: int = Field(default=1, description="工作进程数")

    # 安全配置
    rsa_private_key_path: str = Field(
        default="private_key.hex", description="RSA私钥路径"
    )
    rsa_protect_key_path: str = Field(
        default="data/keys/", description="RSA保护密钥存储路径"
    )


class Settings(BaseModel):
    """主配置类"""

    database: DatabaseConfig = Field(default_factory=DatabaseConfig)
    redis: RedisConfig = Field(default_factory=RedisConfig)
    aufe: AUFEConfig = Field(default_factory=AUFEConfig)
    isim: ISIMConfig = Field(default_factory=ISIMConfig)
    s3: S3Config = Field(default_factory=S3Config)
    log: LogConfig = Field(default_factory=LogConfig)
    app: AppConfig = Field(default_factory=AppConfig)

    class Config:
        json_encoders = {
            # 为枚举类型提供JSON编码器
            LogLevel: lambda v: v.value
        }
