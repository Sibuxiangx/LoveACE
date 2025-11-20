import json
from pathlib import Path
from typing import Any, Dict, Optional

from loguru import logger
from pydantic import ValidationError

from loveace.config.settings import Settings


class ConfigManager:
    """配置文件管理器"""

    def __init__(self, config_file: str = "config.json"):
        self.config_file = Path(config_file)
        self._settings: Optional[Settings] = None
        self._ensure_config_dir()

    def _ensure_config_dir(self):
        """确保配置文件目录存在"""
        self.config_file.parent.mkdir(parents=True, exist_ok=True)

    def _create_default_config(self) -> Settings:
        """创建默认配置"""
        logger.info("正在创建默认配置文件...")
        return Settings()

    def _save_config(self, settings: Settings):
        """保存配置到文件"""
        try:
            config_dict = settings.dict()
            with open(self.config_file, "w", encoding="utf-8") as f:
                json.dump(config_dict, f, indent=2, ensure_ascii=False)
            logger.info(f"配置已保存到 {self.config_file}")
        except Exception as e:
            logger.error(f"保存配置文件失败: {e}")
            raise

    def _load_config(self) -> Settings:
        """从文件加载配置"""
        if not self.config_file.exists():
            logger.warning(f"配置文件 {self.config_file} 不存在，将创建默认配置")
            settings = self._create_default_config()
            self._save_config(settings)
            return settings

        try:
            with open(self.config_file, "r", encoding="utf-8") as f:
                config_data = json.load(f)

            # 验证并创建Settings对象
            settings = Settings(**config_data)
            logger.info(f"成功加载配置文件: {self.config_file}")
            return settings

        except json.JSONDecodeError as e:
            logger.error(f"配置文件JSON格式错误: {e}")
            raise
        except ValidationError as e:
            logger.error(f"配置文件验证失败: {e}")
            raise
        except Exception as e:
            logger.error(f"加载配置文件失败: {e}")
            raise

    def get_settings(self) -> Settings:
        """获取配置设置"""
        if self._settings is None:
            self._settings = self._load_config()
        return self._settings

    def reload_config(self) -> Settings:
        """重新加载配置"""
        logger.info("正在重新加载配置...")
        self._settings = self._load_config()
        return self._settings

    def update_config(self, **kwargs) -> Settings:
        """更新配置"""
        settings = self.get_settings()

        # 创建新的配置字典
        config_dict = settings.dict()

        # 更新指定的配置项
        for key, value in kwargs.items():
            if "." in key:
                # 支持嵌套键，如 'database.url'
                keys = key.split(".")
                current = config_dict
                for k in keys[:-1]:
                    if k not in current:
                        current[k] = {}
                    current = current[k]
                current[keys[-1]] = value
            else:
                config_dict[key] = value

        try:
            # 验证更新后的配置
            new_settings = Settings(**config_dict)
            self._save_config(new_settings)
            self._settings = new_settings
            logger.info("配置更新成功")
            return new_settings
        except ValidationError as e:
            logger.error(f"配置更新失败，验证错误: {e}")
            raise

    def validate_config(self) -> bool:
        """验证配置完整性"""
        try:
            settings = self.get_settings()

            # 检查关键配置项
            issues = []

            # 检查数据库配置
            if not settings.database.url:
                issues.append("数据库URL未配置")

            # 检查S3配置（如果需要使用）
            if settings.s3.bucket_name and not settings.s3.access_key_id:
                issues.append("S3配置不完整：缺少access_key_id")
            if settings.s3.bucket_name and not settings.s3.secret_access_key:
                issues.append("S3配置不完整：缺少secret_access_key")

            # 检查日志配置
            log_dir = Path(settings.log.file_path).parent
            if not log_dir.exists():
                try:
                    log_dir.mkdir(parents=True, exist_ok=True)
                    logger.info(f"创建日志目录: {log_dir}")
                except Exception as e:
                    issues.append(f"无法创建日志目录 {log_dir}: {e}")

            if issues:
                logger.warning("配置验证发现问题:")
                for issue in issues:
                    logger.warning(f"  - {issue}")
                return False

            logger.info("配置验证通过")
            return True

        except Exception as e:
            logger.error(f"配置验证失败: {e}")
            return False

    def get_config_summary(self) -> Dict[str, Any]:
        """获取配置摘要（隐藏敏感信息）"""
        settings = self.get_settings()
        config_dict = settings.dict()

        # 隐藏敏感信息
        sensitive_keys = ["database.url", "s3.access_key_id", "s3.secret_access_key"]

        def hide_sensitive(data: Dict[str, Any], keys: list, prefix: str = ""):
            for key, value in data.items():
                current_key = f"{prefix}.{key}" if prefix else key
                if current_key in sensitive_keys:
                    if isinstance(value, str) and value:
                        data[key] = value[:8] + "..." if len(value) > 8 else "***"
                elif isinstance(value, dict):
                    hide_sensitive(value, keys, current_key)

        summary = config_dict.copy()
        hide_sensitive(summary, sensitive_keys)
        return summary


# 全局配置管理器实例
config_manager = ConfigManager()
