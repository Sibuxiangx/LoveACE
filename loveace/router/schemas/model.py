from typing import Any, List

from pydantic import BaseModel, Field


class ErrorModel(BaseModel):
    message: str = Field(..., description="详细信息")
    code: str = Field(..., description="错误短ID")
    trace_id: str = Field(..., description="trace_id")


class ValidationErrorDetail(BaseModel):
    loc: List[Any] = Field(..., description="错误位置")
    msg: str = Field(..., description="错误信息")
    type: str = Field(..., description="错误类型")


class ValidationErrorModel(ErrorModel):
    details: List[ValidationErrorDetail] = Field(..., description="验证错误详情")
