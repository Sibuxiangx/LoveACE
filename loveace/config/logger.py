from pathlib import Path

from loguru import logger

from loveace.config.manager import config_manager
from loveace.utils.richuru_hook import install


def setup_logger():
    """根据配置文件设置loguru日志"""

    settings = config_manager.get_settings()
    log_config = settings.log

    # 移除默认的logger配置
    logger.remove()
    # 安装 richuru 并配置更详细的堆栈跟踪信息
    install()
    # 确保日志目录存在
    log_dir = Path(log_config.file_path).parent
    log_dir.mkdir(parents=True, exist_ok=True)

    # 设置主日志文件 - 带有详细路径信息
    logger.add(
        log_config.file_path,
        level=log_config.level.value,
        rotation=log_config.rotation,
        retention=log_config.retention,
        compression=log_config.compression,
        backtrace=log_config.backtrace,
        diagnose=log_config.diagnose,
        # 自定义格式，显示完整的文件路径和行号
        format="{time:YYYY-MM-DD HH:mm:ss.SSS} | {level: <8} | {name}:{function}:{line} | {message}",
    )
    logger.info("日志系统初始化完成")


def get_logger():
    """获取配置好的logger实例"""
    return logger


class LoggerMixin:
    """用户日志混合类"""

    user_id: str = ""
    trace_id: str = ""

    def __init__(self, user_id: str = "", trace_id: str = ""):
        self.user_id = user_id
        self.trace_id = trace_id

    def _build_message(self, message: str):
        if self.user_id and self.trace_id:
            return f"[{self.user_id}] [{self.trace_id}] {message}"

        elif self.user_id:
            return f"[{self.user_id}] {message}"

        elif self.trace_id:
            return f"[{self.trace_id}] {message}"

        else:
            return message

    def _build_alt_message(self, alt: str):
        if self.user_id and self.trace_id:
            return f"[bold green][{self.user_id}][/bold green] [bold blue][{self.trace_id}][/bold blue] {alt}"
        elif self.user_id:
            return f"[bold green][{self.user_id}][/bold green] {alt}"
        elif self.trace_id:
            return f"[bold blue][{self.trace_id}][/bold blue] {alt}"
        else:
            return alt

    def info(self, message: str, alt: str = ""):
        logger.opt(depth=1).info(
            self._build_message(message),
            alt=self._build_alt_message(alt if alt else message),
        )

    def debug(self, message: str, alt: str = ""):
        logger.opt(depth=1).debug(
            self._build_message(message),
            alt=self._build_alt_message(alt if alt else message),
        )

    def warning(self, message: str, alt: str = ""):
        logger.opt(depth=1).warning(
            self._build_message(message),
            alt=self._build_alt_message(alt if alt else message),
        )

    def error(self, message: str, alt: str = ""):
        logger.opt(depth=1).error(
            self._build_message(message),
            alt=self._build_alt_message(alt if alt else message),
        )

    def success(self, message: str, alt: str = ""):
        logger.opt(depth=1).success(
            self._build_message(message),
            alt=self._build_alt_message(alt if alt else message),
        )

    def exception(self, e: Exception):
        logger.opt(depth=1).exception(e)


def get_user_logger(user_id: str):
    return LoggerMixin(user_id)


setup_logger()
