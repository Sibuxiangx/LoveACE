"""
定义请求和响应的基础模型，以及错误处理模型
"""

from typing import Annotated, Any, Dict

from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field

from loveace.router.schemas.exception import UniResponseHTTPException
from loveace.router.schemas.model import (
    ErrorModel,
    ValidationErrorDetail,
    ValidationErrorModel,
)
from loveace.router.schemas.uniresponse import UniResponseModel


class ErrorToCodeNode(BaseModel):
    message: str = Field(..., description="错误信息")
    error_code: int = Field(..., description="错误代码")
    code: str = Field(..., description="错误短ID")

    def to_http_exception(
        self, trace_id: str, message: str | None = None
    ) -> UniResponseHTTPException:
        """
        将错误信息转换为HTTPException，次方法使用于 依赖注入 | 中间件 | 抛出异常 的情况，请 raise 此异常。
        """
        return UniResponseHTTPException(
            status_code=self.error_code,
            uni_response=UniResponseModel(
                success=False,
                data=None,
                error=ErrorModel(
                    message=message if message else self.message,
                    code=self.code,
                    trace_id=trace_id,
                ),
                message=None,
            ),
        )

    def to_json_response(
        self, trace_id: str, message: str | None = None
    ) -> JSONResponse:
        """
        将错误信息转换为JSONResponse，适用于一个标准 Router 的返回。
        """
        return JSONResponse(
            status_code=self.error_code,
            content=UniResponseModel(
                success=False,
                data=None,
                error=ErrorModel(
                    message=message if message else self.message,
                    code=self.code,
                    trace_id=trace_id,
                ),
                message=None,
            ).model_dump(),
        )


class ErrorToCode(BaseModel):

    VALIDATION_ERROR: ErrorToCodeNode = ErrorToCodeNode(
        message="请求参数验证错误",
        error_code=422,
        code="VALIDATION_ERROR",
    )

    @classmethod
    def gen_code_table(cls) -> Dict[str | int, Dict[str, Any]]:
        """
        生成FastAPI兼容的响应文档格式
        支持同一状态码下的多个模型示例
        对 422 状态码进行特殊处理，使用 ValidationErrorDetail
        """
        data = cls().model_dump()
        status_info = {}

        # 按状态码分组错误信息
        for k, v in data.items():
            status_code = str(v["error_code"])
            if status_code not in status_info:
                status_info[status_code] = {"descriptions": [], "examples": []}

            # 添加描述
            status_info[status_code]["descriptions"].append(v["message"])

            # 对 422 状态码进行特殊处理
            if v["error_code"] == 422:
                # 使用 ValidationErrorDetail 作为示例
                example_detail = ValidationErrorModel(
                    message="请求参数验证失败",
                    code=v["code"],
                    trace_id="",
                    details=[
                        ValidationErrorDetail(
                            loc=["body", "field_name"],
                            msg="field required",
                            type="value_error.missing",
                        )
                    ],
                )
            else:
                # 其他状态码使用 ErrorModel
                example_detail = ErrorModel(
                    message=v["message"],
                    code=v["code"],
                    trace_id="",
                )

            status_info[status_code]["examples"].append(
                {
                    "summary": f"{v['code']} 错误",
                    "description": v["message"],
                    "value": UniResponseModel(
                        success=False,
                        message=None,
                        data=None,
                        error=example_detail,
                    ).model_dump(),
                }
            )

        # 构建FastAPI响应格式
        responses = {}
        for status_code, info in status_info.items():
            descriptions = info["descriptions"]
            examples = info["examples"]

            # 合并描述
            if len(descriptions) == 1:
                combined_description = descriptions[0]
            else:
                combined_description = "; ".join(descriptions)

            # 对 422 状态码进行特殊处理
            if status_code == "422":
                # 为 422 创建专门的响应模型
                response_def = {
                    "model": Annotated[
                        UniResponseModel,
                        Field(
                            description=combined_description,
                            examples=[example["value"] for example in examples],
                        ),
                    ],
                    "description": combined_description,
                }
            else:
                # 其他状态码使用通用模型
                response_def = {
                    "model": UniResponseModel,
                    "description": combined_description,
                }

            # 如果有示例，添加content字段
            if examples:
                # 创建examples字典
                examples_dict = {}
                for i, example in enumerate(examples):
                    key = f"example_{i + 1}_{example['summary'].lower().replace(' ', '_').replace('错误', 'error')}"
                    examples_dict[key] = {
                        "summary": example["summary"],
                        "description": example["description"],
                        "value": example["value"],
                    }

                response_def["content"] = {
                    "application/json": {"examples": examples_dict}
                }

            responses[status_code] = response_def

        return responses
