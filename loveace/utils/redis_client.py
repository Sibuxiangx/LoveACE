"""
Redis客户端工具模块

提供类型完整的Redis客户端包装器，支持内容验证和序列化
"""

import json
from typing import Any, Optional, Type, TypeVar, Union

import redis.asyncio as aioredis
from pydantic import BaseModel, ValidationError

from loveace.config.logger import logger
from loveace.database.creator import db_manager

T = TypeVar("T", bound=BaseModel)


class RedisClient:
    """类型完整的Redis客户端包装器

    提供带有数据验证和序列化的Redis操作接口

    Example:
        >>> client = RedisClient(redis_instance)
        >>> # 存储对象
        >>> await client.set_object("user:1", user_data, User)
        >>> # 获取对象
        >>> user = await client.get_object("user:1", User)
    """

    def __init__(self, redis_client: aioredis.Redis):
        """初始化Redis客户端包装器

        Args:
            redis_client: aioredis.Redis 实例
        """
        self.client = redis_client

    async def set_object(
        self,
        key: str,
        value: Union[BaseModel, dict, Any],
        model_class: Optional[Type[T]] = None,
        expire: Optional[int] = None,
    ) -> bool:
        """设置对象到Redis，支持自动验证和序列化

        Args:
            key: Redis键
            value: 要存储的值（BaseModel、dict或其他可序列化对象）
            model_class: 对象模型类，用于验证。如果提供，会先验证value
            expire: 过期时间（秒），None表示不设置过期时间

        Returns:
            是否成功设置

        Raises:
            ValidationError: 当model_class验证失败时
            TypeError: 当value无法序列化时
        """
        try:
            # 验证数据
            if model_class is not None:
                if isinstance(value, model_class):
                    validated_value = value
                else:
                    validated_value = model_class(
                        **value if isinstance(value, dict) else value.dict()
                    )
            else:
                validated_value = value

            # 序列化
            if isinstance(validated_value, BaseModel):
                data = validated_value.model_dump_json()
            elif isinstance(validated_value, dict):
                data = json.dumps(validated_value, ensure_ascii=False)
            else:
                data = json.dumps(validated_value, ensure_ascii=False)

            # 存储到Redis
            if expire:
                await self.client.setex(key, expire, data)
            else:
                await self.client.set(key, data)

            logger.debug(f"成功存储Redis键: {key}")
            return True

        except ValidationError as e:
            logger.error(f"Redis对象验证失败 {key}: {e}")
            raise
        except Exception as e:
            logger.error(f"Redis存储失败 {key}: {e}")
            raise

    async def get_object(
        self,
        key: str,
        model_class: Type[T],
    ) -> Optional[T]:
        """从Redis获取对象，并通过指定的模型类进行验证

        Args:
            key: Redis键
            model_class: 对象模型类，用于反序列化和验证

        Returns:
            反序列化并验证后的对象，如果键不存在则返回None

        Raises:
            ValidationError: 当数据验证失败时
        """
        try:
            data = await self.client.get(key)

            if data is None:
                logger.debug(f"Redis键不存在: {key}")
                return None

            # 反序列化
            if isinstance(data, bytes):
                data = data.decode("utf-8")

            parsed_data = json.loads(data)

            # 验证并创建模型实例
            validated_value = model_class(**parsed_data)
            logger.debug(f"成功获取并验证Redis键: {key}")
            return validated_value

        except ValidationError as e:
            logger.error(f"Redis对象验证失败 {key}: {e}")
            raise
        except json.JSONDecodeError as e:
            logger.error(f"Redis JSON解析失败 {key}: {e}")
            raise
        except Exception as e:
            logger.error(f"Redis获取失败 {key}: {e}")
            raise

    async def get_object_safe(
        self,
        key: str,
        model_class: Type[T],
        default: Optional[T] = None,
    ) -> Optional[T]:
        """安全地从Redis获取对象，验证失败时返回默认值

        Args:
            key: Redis键
            model_class: 对象模型类，用于反序列化和验证
            default: 验证失败时的默认返回值

        Returns:
            反序列化并验证后的对象，验证失败返回default
        """
        try:
            return await self.get_object(key, model_class)
        except (ValidationError, json.JSONDecodeError, Exception) as e:
            logger.warning(f"Redis安全获取失败，返回默认值 {key}: {e}")
            return default

    async def set_raw(
        self,
        key: str,
        value: Union[str, bytes],
        expire: Optional[int] = None,
    ) -> bool:
        """设置原始字符串值到Redis

        Args:
            key: Redis键
            value: 要存储的值（字符串或字节）
            expire: 过期时间（秒）

        Returns:
            是否成功设置
        """
        try:
            if expire:
                await self.client.setex(key, expire, value)
            else:
                await self.client.set(key, value)
            logger.debug(f"成功存储原始值到Redis: {key}")
            return True
        except Exception as e:
            logger.error(f"Redis原始值存储失败 {key}: {e}")
            raise

    async def get_raw(self, key: str) -> Optional[Union[str, bytes]]:
        """获取原始字符串值

        Args:
            key: Redis键

        Returns:
            存储的值，如果键不存在则返回None
        """
        try:
            data = await self.client.get(key)
            if data is None:
                logger.debug(f"Redis键不存在: {key}")
                return None
            logger.debug(f"成功获取原始值: {key}")
            return data
        except Exception as e:
            logger.error(f"Redis获取失败 {key}: {e}")
            raise

    async def delete(self, key: str) -> int:
        """删除Redis键

        Args:
            key: 要删除的键

        Returns:
            删除的键数量
        """
        try:
            result = await self.client.delete(key)
            logger.debug(f"成功删除Redis键: {key}")
            return result
        except Exception as e:
            logger.error(f"Redis删除失败 {key}: {e}")
            raise

    async def exists(self, key: str) -> bool:
        """检查键是否存在

        Args:
            key: 要检查的键

        Returns:
            键是否存在
        """
        try:
            return await self.client.exists(key) > 0
        except Exception as e:
            logger.error(f"Redis检查失败 {key}: {e}")
            raise

    async def expire(self, key: str, seconds: int) -> bool:
        """设置键的过期时间

        Args:
            key: Redis键
            seconds: 过期时间（秒）

        Returns:
            是否成功设置
        """
        try:
            result = await self.client.expire(key, seconds)
            logger.debug(f"成功设置Redis键过期时间: {key}, {seconds}秒")
            return result > 0
        except Exception as e:
            logger.error(f"Redis设置过期失败 {key}: {e}")
            raise

    async def ttl(self, key: str) -> int:
        """获取键的剩余生存时间

        Args:
            key: Redis键

        Returns:
            剩余生存时间（秒），-1表示永不过期，-2表示键不存在
        """
        try:
            return await self.client.ttl(key)
        except Exception as e:
            logger.error(f"Redis获取TTL失败 {key}: {e}")
            raise

    async def increment(
        self,
        key: str,
        amount: int = 1,
    ) -> int:
        """增加键的值

        Args:
            key: Redis键
            amount: 增加的数量

        Returns:
            增加后的值
        """
        try:
            result = await self.client.incrby(key, amount)
            logger.debug(f"成功增加Redis键: {key}")
            return result
        except Exception as e:
            logger.error(f"Redis增加失败 {key}: {e}")
            raise

    async def decrement(
        self,
        key: str,
        amount: int = 1,
    ) -> int:
        """减少键的值

        Args:
            key: Redis键
            amount: 减少的数量

        Returns:
            减少后的值
        """
        try:
            result = await self.client.decrby(key, amount)
            logger.debug(f"成功减少Redis键: {key}")
            return result
        except Exception as e:
            logger.error(f"Redis减少失败 {key}: {e}")
            raise

    async def list_push(
        self,
        key: str,
        values: list[Union[BaseModel, dict, str]],
        model_class: Optional[Type[T]] = None,
    ) -> int:
        """向列表推入元素

        Args:
            key: Redis键
            values: 要推入的值列表
            model_class: 对象模型类，用于验证每个值

        Returns:
            推入后列表的长度
        """
        try:
            serialized_values = []
            for value in values:
                if model_class is not None:
                    if isinstance(value, model_class):
                        validated_value = value
                    else:
                        if isinstance(value, dict):
                            validated_value = model_class(**value)
                        else:
                            validated_value = value
                else:
                    validated_value = value

                if isinstance(validated_value, BaseModel):
                    serialized_values.append(validated_value.model_dump_json())
                elif isinstance(validated_value, dict):
                    serialized_values.append(
                        json.dumps(validated_value, ensure_ascii=False)
                    )
                else:
                    serialized_values.append(str(validated_value))

            result: int = await self.client.rpush(key, *serialized_values)  # type: ignore
            logger.debug(f"成功推入Redis列表: {key}")
            return result
        except Exception as e:
            logger.error(f"Redis列表推入失败 {key}: {e}")
            raise

    async def list_range(
        self,
        key: str,
        start: int = 0,
        end: int = -1,
        model_class: Optional[Type[T]] = None,
    ) -> list[Union[T, str]]:
        """获取列表范围内的元素

        Args:
            key: Redis键
            start: 开始索引
            end: 结束索引
            model_class: 对象模型类，用于反序列化。如果为None则返回原始字符串

        Returns:
            列表中指定范围的元素
        """
        try:
            data: list[Any] = await self.client.lrange(key, start, end)  # type: ignore

            if model_class is None:
                return data

            result = []
            for item in data:
                if isinstance(item, bytes):
                    item = item.decode("utf-8")
                try:
                    parsed = json.loads(item)
                    result.append(model_class(**parsed))
                except (json.JSONDecodeError, ValidationError):
                    result.append(item)

            return result
        except Exception as e:
            logger.error(f"Redis列表获取失败 {key}: {e}")
            raise

    async def hash_set(
        self,
        key: str,
        mapping: dict[str, Union[BaseModel, dict, str, int]],
        model_class: Optional[Type[T]] = None,
    ) -> int:
        """设置哈希表字段

        Args:
            key: Redis键
            mapping: 字段值映射
            model_class: 对象模型类，用于验证值

        Returns:
            新添加的字段数
        """
        try:
            serialized_mapping = {}
            for field, value in mapping.items():
                if model_class is not None and not isinstance(value, (str, int, float)):
                    if isinstance(value, dict):
                        validated_value = model_class(**value)
                    else:
                        validated_value = value
                    if isinstance(validated_value, BaseModel):
                        serialized_mapping[field] = validated_value.model_dump_json()
                    else:
                        serialized_mapping[field] = str(value)
                else:
                    serialized_mapping[field] = str(value)

            result: int = await self.client.hset(key, mapping=serialized_mapping)  # type: ignore
            logger.debug(f"成功设置Redis哈希表: {key}")
            return result
        except Exception as e:
            logger.error(f"Redis哈希表设置失败 {key}: {e}")
            raise

    async def hash_get(
        self,
        key: str,
        field: str,
        model_class: Optional[Type[T]] = None,
    ) -> Optional[Union[T, str]]:
        """获取哈希表字段值

        Args:
            key: Redis键
            field: 字段名
            model_class: 对象模型类，用于反序列化

        Returns:
            字段值，如果不存在则返回None
        """
        try:
            data: Optional[Any] = await self.client.hget(key, field)  # type: ignore

            if data is None:
                return None

            if isinstance(data, bytes):
                data = data.decode("utf-8")

            if model_class is None:
                return data

            try:
                parsed = json.loads(data)
                return model_class(**parsed)
            except (json.JSONDecodeError, ValidationError):
                return data
        except Exception as e:
            logger.error(f"Redis哈希表获取失败 {key}:{field}: {e}")
            raise

    async def hash_get_all(
        self,
        key: str,
        model_class: Optional[Type[T]] = None,
    ) -> dict[str, Union[T, str]]:
        """获取所有哈希表字段

        Args:
            key: Redis键
            model_class: 对象模型类，用于反序列化值

        Returns:
            哈希表中的所有字段值
        """
        try:
            data: dict[Any, Any] = await self.client.hgetall(key)  # type: ignore

            if model_class is None:
                return data

            result = {}
            for field, value in data.items():
                if isinstance(value, bytes):
                    value = value.decode("utf-8")
                try:
                    parsed = json.loads(value)
                    result[field] = model_class(**parsed)
                except (json.JSONDecodeError, ValidationError):
                    result[field] = value

            return result
        except Exception as e:
            logger.error(f"Redis哈希表全量获取失败 {key}: {e}")
            raise

    async def hash_delete(
        self,
        key: str,
        *fields: str,
    ) -> int:
        """删除哈希表字段

        Args:
            key: Redis键
            fields: 要删除的字段名

        Returns:
            删除的字段数
        """
        try:
            result: int = await self.client.hdel(key, *fields)  # type: ignore
            logger.debug(f"成功删除Redis哈希表字段: {key}")
            return result
        except Exception as e:
            logger.error(f"Redis哈希表删除失败 {key}: {e}")
            raise


async def get_redis_client() -> RedisClient:
    """获取全局Redis客户端实例

    Returns:
        aioredis.Redis 实例
    """
    redis_instance = await db_manager.get_redis_client()
    redis_client = RedisClient(redis_instance)
    return redis_client
