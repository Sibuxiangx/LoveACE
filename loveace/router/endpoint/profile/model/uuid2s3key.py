from pydantic import BaseModel, Field


class Uuid2S3KeyCache(BaseModel):
    """UUID 到 S3 Key 的缓存模型"""

    s3_key: str = Field(..., description="S3对象的key")
    md5: str = Field(..., description="文件的MD5值")
