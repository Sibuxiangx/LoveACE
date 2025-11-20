import time
from typing import Generic, TypeVar, Union

from pydantic import BaseModel, Field

from loveace.router.schemas.model import ErrorModel, ValidationErrorModel

T = TypeVar("T")


class UniResponseModel(BaseModel, Generic[T]):
    """
    统一响应模型，适用于所有API响应。
    Attributes:
        success (bool): 操作是否成功。
        message (str | None): 操作的详细信息。
        data (ResponseModel | None): 操作返回的数据。
        error (DetailModel | None): 操作错误信息，支持 ErrorModel 或 ValidationErrorDetail。
        timestamp (str): 响应生成的时间戳，格式为 "YYYY-MM-DD HH:MM:SS"。
    """

    success: bool = Field(..., description="操作是否成功")
    message: str | None = Field(..., description="操作的详细信息")
    data: T | None = Field(..., description="操作返回的数据")
    error: Union[ErrorModel, ValidationErrorModel] | None = Field(
        None, description="操作错误信息"
    )
    timestamp: str = Field(
        default_factory=lambda: time.strftime("%Y-%m-%d %H:%M:%S", time.localtime()),
        description="响应生成的时间戳",
    )

    @classmethod
    def from_response(
        cls,
        success: bool,
        message: str,
        data: T | None = None,
    ) -> "UniResponseModel":
        return cls(
            success=success,
            message=message,
            data=data,
            error=None,
        )
