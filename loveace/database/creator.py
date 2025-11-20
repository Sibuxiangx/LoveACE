from typing import AsyncGenerator

import redis.asyncio as aioredis
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

from loveace.config.logger import logger
from loveace.config.manager import config_manager
from loveace.database.base import Base


class DatabaseManager:
    """数据库管理器，负责数据库连接和会话管理"""

    def __init__(self):
        self.engine = None
        self.async_session_maker = None
        self._config = None
        self.redis_client = None
        self._redis_config = None

    def _get_db_config(self):
        """获取数据库配置"""
        if self._config is None:
            self._config = config_manager.get_settings().database
        return self._config

    def _get_redis_config(self):
        """获取Redis配置"""
        if self._redis_config is None:
            self._redis_config = config_manager.get_settings().redis
        return self._redis_config

    async def init_db(self) -> bool:
        """初始化数据库连接"""
        db_config = self._get_db_config()

        logger.info("正在初始化数据库连接...")
        try:
            self.engine = create_async_engine(
                db_config.url,
                echo=db_config.echo,
                pool_size=db_config.pool_size,
                max_overflow=db_config.max_overflow,
                pool_timeout=db_config.pool_timeout,
                pool_recycle=db_config.pool_recycle,
                future=True,
            )

            self.async_session_maker = async_sessionmaker(
                self.engine, class_=AsyncSession, expire_on_commit=False
            )

            # 创建所有表
            async with self.engine.begin() as conn:
                await conn.run_sync(Base.metadata.create_all)
        except Exception as e:
            logger.error(f"数据库连接初始化失败: {e}")
            logger.error(f"数据库连接URL: {db_config.url}")
            db_config.url = "****"
            logger.error(f"数据库连接配置: {db_config}")
            logger.error("请启动config_tui.py来配置数据库连接")
            return False
        logger.info("数据库连接初始化完成")
        return True

    async def close_db(self):
        """关闭数据库连接"""
        if self.engine:
            logger.info("正在关闭数据库连接...")
            await self.engine.dispose()
            logger.info("数据库连接已关闭")

    async def get_redis_client(self) -> aioredis.Redis:
        """获取Redis客户端

        Returns:
            Redis客户端实例

        Raises:
            RuntimeError: 如果Redis初始化失败
        """
        if self.redis_client is None:
            success = await self._init_redis()
            if not success:
                raise RuntimeError(
                    "Failed to initialize Redis client. Check logs for details."
                )
        return self.redis_client  # type: ignore

    async def _init_redis(self) -> bool:
        """初始化Redis连接"""
        redis_config = self._get_redis_config()

        logger.info("正在初始化Redis连接...")
        try:
            self.redis_client = aioredis.Redis(
                host=redis_config.host,
                port=redis_config.port,
                db=redis_config.db,
                password=redis_config.password,
                encoding=redis_config.encoding,
                decode_responses=redis_config.decode_responses,
                max_connections=redis_config.max_connections,
                socket_keepalive=redis_config.socket_keepalive,
            )
            # 测试连接
            await self.redis_client.ping()
            logger.info("Redis连接初始化完成")
            return True
        except Exception as e:
            logger.error(f"Redis连接初始化失败: {e}")
            logger.error(
                f"Redis配置: host={redis_config.host}, port={redis_config.port}, db={redis_config.db}"
            )
            return False

    async def close_redis(self):
        """关闭Redis连接"""
        if self.redis_client:
            logger.info("正在关闭Redis连接...")
            await self.redis_client.close()
            self.redis_client = None
            logger.info("Redis连接已关闭")

    async def get_session(self) -> AsyncGenerator[AsyncSession, None]:
        """获取数据库会话"""
        if not self.async_session_maker:
            raise RuntimeError("Database not initialized. Call init_db() first.")

        async with self.async_session_maker() as session:
            try:
                yield session
            finally:
                await session.close()


# 全局数据库管理器实例
db_manager = DatabaseManager()


async def get_db_session() -> AsyncGenerator[AsyncSession, None]:
    """获取数据库会话的依赖函数，用于FastAPI路由"""
    async for session in db_manager.get_session():
        yield session


async def get_redis_instance() -> aioredis.Redis:
    """获取Redis实例的依赖函数，用于FastAPI路由"""
    return await db_manager.get_redis_client()
