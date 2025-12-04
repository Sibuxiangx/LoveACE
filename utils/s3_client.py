import json
import mimetypes
import opendal
from config import get_settings


# 添加 APK 的 MIME 类型
mimetypes.add_type("application/vnd.android.package-archive", ".apk")


class S3Client:
    """S3 客户端封装 (基于 OpenDAL)"""

    def __init__(self):
        settings = get_settings()
        self.cdn_base_url = settings.cdn_base_url
        self.bucket = settings.s3_bucket

        self.op = opendal.Operator(
            "s3",
            endpoint=settings.s3_endpoint,
            access_key_id=settings.s3_access_key,
            secret_access_key=settings.s3_secret_key,
            bucket=settings.s3_bucket,
            region=settings.s3_region,
        )

    def _get_url(self, s3_key: str) -> str:
        """获取文件 URL"""
        if self.cdn_base_url:
            return f"{self.cdn_base_url.rstrip('/')}/{s3_key}"
        return f"{self.op.info().full_capability()}/{self.bucket}/{s3_key}"

    def _get_content_type(self, filename: str) -> str:
        """根据文件名获取 Content-Type"""
        content_type, _ = mimetypes.guess_type(filename)
        return content_type or "application/octet-stream"

    def upload_file(self, local_path: str, s3_key: str) -> str:
        """上传文件到 S3"""
        content_type = self._get_content_type(local_path)
        with open(local_path, "rb") as f:
            self.op.write(s3_key, f.read(),content_type=content_type)
        return self._get_url(s3_key)

    def upload_content(self, content: str | bytes, s3_key: str) -> str:
        """上传内容到 S3"""
        if isinstance(content, str):
            content = content.encode("utf-8")
        content_type = self._get_content_type(s3_key)
        self.op.write(s3_key, content,content_type=content_type)
        return self._get_url(s3_key)

    def get_json(self, s3_key: str) -> dict | None:
        """获取 JSON 文件"""
        try:
            data = self.op.read(s3_key)
            return json.loads(data.decode("utf-8"))
        except Exception:
            return None

    def exists(self, s3_key: str) -> bool:
        """检查文件是否存在"""
        try:
            self.op.stat(s3_key)
            return True
        except Exception:
            return False
