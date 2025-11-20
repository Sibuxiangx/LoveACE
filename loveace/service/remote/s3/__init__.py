import os
from contextlib import asynccontextmanager
from typing import Any, AsyncGenerator, BinaryIO, Dict, Optional

import aioboto3
from botocore.client import Config as BotoCoreConfig
from types_aiobotocore_s3 import S3Client

from loveace.config.logger import logger
from loveace.config.manager import config_manager
from loveace.service.model.service import Service
from loveace.service.remote.s3.model.s3 import (
    S3CopyResult,
    S3ListResult,
    S3Object,
    S3UploadResult,
)

s3_config = config_manager.get_settings().s3

# Boto3 很诡异的问题，不把这两个参数设为 when_required 他会把 check 直接塞到 rawfile 里
# 阅读了一下应该是国内的一些 S3 兼容服务不能识读 checksum 导致的

os.environ["AWS_REQUEST_CHECKSUM_CALCULATION"] = "when_required"
os.environ["AWS_RESPONSE_CHECKSUM_VALIDATION"] = "when_required"

# 验证 S3 配置
if not all(
    [
        s3_config.endpoint_url,
        s3_config.access_key_id,
        s3_config.secret_access_key,
        s3_config.bucket_name,
    ]
):
    logger.warning("S3 配置不完整，S3 功能将不可用")
    raise ValueError("S3 配置不完整，S3 功能将不可用")


class S3Service(Service):
    """类型提示完善的 aioboto3 S3 管理器"""

    def __init__(self):
        self._session: aioboto3.Session = aioboto3.Session()
        self._bucket_name = s3_config.bucket_name
        self._endpoint_url = s3_config.endpoint_url
        self._client_config = {
            "aws_access_key_id": s3_config.access_key_id,
            "aws_secret_access_key": s3_config.secret_access_key,
            "endpoint_url": s3_config.endpoint_url,
            "region_name": s3_config.region_name,
            "use_ssl": s3_config.use_ssl,
            "config": BotoCoreConfig(
                s3={
                    "addressing_style": s3_config.addressing_style,
                    "signature_version": s3_config.signature_version,
                }
            ),
        }

    @asynccontextmanager
    async def get_client(self) -> AsyncGenerator[S3Client, None]:
        """获取 S3 客户端上下文管理器"""
        async with self._session.client("s3", **self._client_config) as client:  # type: ignore
            yield client

    def _get_object_url(self, s3_key: str, bucket: Optional[str] = None) -> str:
        """
        生成对象的直链 URL（非预签名）

        Args:
            s3_key: S3 对象键
            bucket: 存储桶名称

        Returns:
            str: 直链 URL
        """
        bucket_name = bucket or self._bucket_name
        # 根据寻址风格构建 URL
        if s3_config.addressing_style == "virtual":
            # 虚拟主机风格：https://bucket-name.endpoint/key
            return f"https://{bucket_name}.{self._endpoint_url.replace('https://', '').replace('http://', '')}/{s3_key}"
        else:
            # 路径风格：https://endpoint/bucket-name/key
            return f"{self._endpoint_url}/{bucket_name}/{s3_key}"

    async def upload_obj(
        self,
        file_obj: BinaryIO,
        s3_key: str,
        bucket: Optional[str] = None,
        extra_args: Optional[Dict[str, Any]] = None,
    ) -> S3UploadResult:
        """
        上传文件对象到 S3

        Args:
            file_obj: 文件对象
            s3_key: S3 对象键
            bucket: 存储桶名称
            extra_args: 额外参数

        Returns:
            S3UploadResult: 上传结果，包含成功状态和直链 URL
        """
        bucket_name = bucket or self._bucket_name

        try:
            async with self.get_client() as s3:
                logger.info(f"开始上传文件对象到 S3: {s3_key}")
                await s3.upload_fileobj(
                    file_obj, bucket_name, s3_key, ExtraArgs=extra_args
                )
                logger.info(f"文件对象上传成功: {s3_key}")
                obj_url = self._get_object_url(s3_key, bucket_name)
                return S3UploadResult(
                    success=True,
                    url=obj_url,
                    key=s3_key,
                )
        except Exception as e:
            logger.error(f"文件对象上传失败 -> {s3_key}: {e}")
            return S3UploadResult(
                success=False,
                key=s3_key,
                error=str(e),
            )

    async def delete_object(self, s3_key: str, bucket: Optional[str] = None) -> bool:
        """
        删除单个 S3 对象

        Args:
            s3_key: S3 对象键
            bucket: 存储桶名称

        Returns:
            bool: 删除成功返回 True
        """
        bucket_name = bucket or self._bucket_name

        try:
            async with self.get_client() as s3:
                await s3.delete_object(Bucket=bucket_name, Key=s3_key)
                logger.info(f"对象删除成功: {s3_key}")
                return True
        except Exception as e:
            logger.error(f"对象删除失败 {s3_key}: {e}")
            return False

    async def list_objects(
        self,
        prefix: str = "",
        bucket: Optional[str] = None,
        max_keys: int = 1000,
        continuation_token: Optional[str] = None,
    ) -> S3ListResult:
        """
        列出 S3 对象

        Args:
            prefix: 对象键前缀
            bucket: 存储桶名称
            max_keys: 最大返回数量
            continuation_token: 继续令牌，用于分页

        Returns:
            S3ListResult: 对象列表结果
        """
        bucket_name = bucket or self._bucket_name

        try:
            async with self.get_client() as s3:
                params: Dict[str, Any] = {
                    "Bucket": bucket_name,
                    "Prefix": prefix,
                    "MaxKeys": max_keys,
                }

                if continuation_token:
                    params["ContinuationToken"] = continuation_token

                response = await s3.list_objects_v2(**params)

                objects = []
                if contents := response.get("Contents"):
                    for item in contents:
                        if key := item.get("Key"):
                            size = item.get("Size", 0)
                            last_mod = item.get("LastModified")
                            last_modified_str = last_mod.isoformat() if last_mod else ""
                            objects.append(
                                S3Object(
                                    key=key,
                                    size=size or 0,
                                    last_modified=last_modified_str,
                                )
                            )

                return S3ListResult(
                    success=True,
                    objects=objects,
                    prefix=prefix,
                    is_truncated=response.get("IsTruncated", False),
                    continuation_token=response.get("NextContinuationToken"),
                )

        except Exception as e:
            logger.error(f"列出对象失败，前缀: {prefix}: {e}")
            return S3ListResult(
                success=False,
                prefix=prefix,
                error=str(e),
            )

    async def generate_presigned_url(
        self,
        s3_key: str,
        bucket: Optional[str] = None,
        expiration: int = 3600,
        method: str = "get_object",
    ) -> Optional[str]:
        """
        生成预签名 URL

        Args:
            s3_key: S3 对象键
            bucket: 存储桶名称
            expiration: URL 有效期（秒）
            method: HTTP 方法（get_object, put_object 等）

        Returns:
            Optional[str]: 预签名 URL，生成失败返回 None
        """
        bucket_name = bucket or self._bucket_name

        try:
            async with self.get_client() as s3:
                url = await s3.generate_presigned_url(
                    ClientMethod=method,
                    Params={"Bucket": bucket_name, "Key": s3_key},
                    ExpiresIn=expiration,
                )
                logger.info(f"预签名 URL 生成成功: {s3_key}")
                return url
        except Exception as e:
            logger.error(f"生成预签名 URL 失败 {s3_key}: {e}")
            return None

    async def generate_presigned_url_from_direct_url(
        self,
        direct_url: str,
        expiration: int = 3600,
    ) -> Optional[str]:
        """
        从直链 URL 生成预签名 URL

        Args:
            direct_url: 直链 URL
            expiration: URL 有效期（秒）

        Returns:
            Optional[str]: 预签名 URL，生成失败返回 None
        """
        try:
            # 解析出 bucket 和 key
            if s3_config.addressing_style == "virtual":
                # 虚拟主机风格：https://bucket-name.endpoint/key
                url_without_protocol = direct_url.replace("https://", "").replace(
                    "http://", ""
                )
                first_slash = url_without_protocol.find("/")
                bucket_name = self._bucket_name
                s3_key = url_without_protocol[first_slash + 1 :]
            else:
                # 路径风格：https://endpoint/bucket-name/key
                url_without_protocol = direct_url.replace("https://", "").replace(
                    "http://", ""
                )
                path_parts = url_without_protocol.split("/")
                bucket_name = self._bucket_name
                s3_key = "/".join(path_parts[2:])

            return await self.generate_presigned_url(
                s3_key=s3_key,
                bucket=bucket_name,
                expiration=expiration,
                method="get_object",
            )
        except Exception as e:
            logger.error(f"从直链 URL 生成预签名 URL 失败 {direct_url}: {e}")
            return None

    async def object_exists(self, s3_key: str, bucket: Optional[str] = None) -> bool:
        """
        检查 S3 对象是否存在

        Args:
            s3_key: S3 对象键
            bucket: 存储桶名称

        Returns:
            bool: 存在返回 True
        """
        bucket_name = bucket or self._bucket_name

        try:
            async with self.get_client() as s3:
                await s3.head_object(Bucket=bucket_name, Key=s3_key)
                return True
        except Exception:
            return False

    async def copy_object(
        self,
        source_key: str,
        dest_key: str,
        source_bucket: Optional[str] = None,
        dest_bucket: Optional[str] = None,
    ) -> S3CopyResult:
        """
        复制 S3 对象

        Args:
            source_key: 源对象键
            dest_key: 目标对象键
            source_bucket: 源存储桶名称
            dest_bucket: 目标存储桶名称

        Returns:
            S3CopyResult: 复制结果，包含成功状态和目标直链 URL
        """
        src_bucket_name = source_bucket or self._bucket_name
        dst_bucket_name = dest_bucket or self._bucket_name

        copy_source = {"Bucket": src_bucket_name, "Key": source_key}

        try:
            async with self.get_client() as s3:
                await s3.copy_object(
                    CopySource=copy_source,  # type: ignore
                    Bucket=dst_bucket_name,
                    Key=dest_key,  # type: ignore
                )
                logger.info(f"对象复制成功: {source_key} -> {dest_key}")
                return S3CopyResult(
                    success=True,
                    source_key=source_key,
                    dest_key=dest_key,
                    dest_url=self._get_object_url(dest_key, dst_bucket_name),
                )
        except Exception as e:
            logger.error(f"对象复制失败 {source_key} -> {dest_key}: {e}")
            return S3CopyResult(
                success=False,
                source_key=source_key,
                dest_key=dest_key,
                error=str(e),
            )

    async def initialize(self):
        """初始化 S3 服务"""
        logger.info("S3 服务初始化完成")

    async def shutdown(self):
        """关闭 S3 服务"""
        logger.info("S3 服务已关闭")
