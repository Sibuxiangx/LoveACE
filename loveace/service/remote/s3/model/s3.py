from typing import Optional

from pydantic import BaseModel


class S3UploadResult(BaseModel):
    """S3 上传结果"""

    success: bool
    """上传是否成功"""
    url: Optional[str] = None
    """直链 URL，仅在上传成功时返回"""
    key: Optional[str] = None
    """S3 对象键"""
    error: Optional[str] = None
    """错误信息，仅在上传失败时返回"""


class S3CopyResult(BaseModel):
    """S3 复制结果"""

    success: bool
    """复制是否成功"""
    source_key: Optional[str] = None
    """源 S3 对象键"""
    dest_key: Optional[str] = None
    """目标 S3 对象键"""
    dest_url: Optional[str] = None
    """目标直链 URL，仅在复制成功时返回"""
    error: Optional[str] = None
    """错误信息，仅在复制失败时返回"""


class S3Object(BaseModel):
    """S3 对象基本信息"""

    key: str
    """对象键"""
    size: int
    """对象大小（字节）"""
    last_modified: str
    """最后修改时间"""


class S3ListResult(BaseModel):
    """S3 列表操作结果"""

    success: bool
    """操作是否成功"""
    objects: list[S3Object] = []
    """对象列表"""
    prefix: str = ""
    """前缀"""
    is_truncated: bool = False
    """是否存在更多对象"""
    continuation_token: Optional[str] = None
    """继续令牌，用于分页"""
    error: Optional[str] = None
    """错误信息"""
