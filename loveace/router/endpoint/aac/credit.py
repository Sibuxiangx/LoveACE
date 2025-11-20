from typing import List

from fastapi import APIRouter, Depends
from fastapi.responses import JSONResponse
from httpx import Headers, HTTPError
from pydantic import ValidationError

from loveace.router.endpoint.aac.model.base import AACConfig
from loveace.router.endpoint.aac.model.credit import (
    LoveACCreditCategory,
    LoveACCreditInfo,
)
from loveace.router.endpoint.aac.utils.aac_ticket import get_aac_header
from loveace.router.schemas.error import ProtectRouterErrorToCode
from loveace.router.schemas.uniresponse import UniResponseModel
from loveace.service.remote.aufe import AUFEConnection
from loveace.service.remote.aufe.depends import get_aufe_conn

aac_credit_router = APIRouter(
    prefix="/credit",
    responses=ProtectRouterErrorToCode().gen_code_table(),
)

ENDPOINT = {
    "total_score": "/User/Center/DoGetScoreInfo?sf_request_type=ajax",
    "score_list": "/User/Center/DoGetScoreList?sf_request_type=ajax",
}


@aac_credit_router.get(
    "/info",
    response_model=UniResponseModel[LoveACCreditInfo],
    summary="获取爱安财总分信息",
)
async def get_credit_info(
    conn: AUFEConnection = Depends(get_aufe_conn),
    headers: Headers = Depends(get_aac_header),
) -> UniResponseModel[LoveACCreditInfo] | JSONResponse:
    """
    获取用户的爱安财总分信息

    ✅ 功能特性：
       - 获取爱安财总分和毕业要求状态
       - 获取未达标的原因说明
       - 实时从 AUFE 服务获取最新数据

    💡 使用场景：
       - 个人中心显示爱安财总分
       - 检查是否满足毕业要求
       - 了解分数不足的原因

    Returns:
        LoveACCreditInfo: 包含总分、达成状态和详细信息
    """
    try:
        conn.logger.info("开始获取爱安财总分信息")
        response = await conn.client.post(
            url=AACConfig().to_full_url(ENDPOINT["total_score"]),
            data={},
            headers=headers,
            timeout=6000,
        )
        if response.status_code != 200:
            conn.logger.error(
                f"获取爱安财总分信息失败，HTTP状态码: {response.status_code}"
            )
            return ProtectRouterErrorToCode().remote_service_error.to_json_response(
                conn.logger.trace_id, "获取爱安财总分信息失败，请稍后重试"
            )
        data = response.json()
        if data.get("code") != 0:
            conn.logger.error(f"获取爱安财总分信息失败，响应代码: {data.get('code')}")
            return ProtectRouterErrorToCode().remote_service_error.to_json_response(
                conn.logger.trace_id, "获取爱安财总分信息失败，请稍后重试"
            )
        data = data.get("data", {})
        if not data:
            conn.logger.error("获取爱安财总分信息失败，响应数据为空")
            return ProtectRouterErrorToCode().null_response.to_json_response(
                conn.logger.trace_id, "获取爱安财总分信息失败，请稍后重试"
            )
        try:
            credit_info = LoveACCreditInfo.model_validate(data)
            conn.logger.info("成功获取爱安财总分信息")
            return UniResponseModel[LoveACCreditInfo](
                success=True,
                data=credit_info,
                message="获取爱安财总分信息成功",
                error=None,
            )
        except ValidationError as ve:
            conn.logger.error(f"解析爱安财总分信息失败: {str(ve)}")
            return ProtectRouterErrorToCode().validation_error.to_json_response(
                conn.logger.trace_id, "解析爱安财总分信息失败，请稍后重试"
            )

    except HTTPError as he:
        conn.logger.error(f"获取爱安财总分信息异常: {str(he)}")
        return ProtectRouterErrorToCode().remote_service_error.to_json_response(
            conn.logger.trace_id, "获取爱安财总分信息异常，请稍后重试"
        )
    except Exception as e:
        conn.logger.error(f"获取爱安财总分信息未知异常: {str(e)}")
        return ProtectRouterErrorToCode().unknown_error.to_json_response(
            conn.logger.trace_id, "获取爱安财总分信息未知异常，请稍后重试"
        )


@aac_credit_router.get(
    "/list",
    response_model=UniResponseModel[List[LoveACCreditCategory]],
    summary="获取爱安财分数明细",
)
async def get_credit_list(
    conn: AUFEConnection = Depends(get_aufe_conn),
    headers: Headers = Depends(get_aac_header),
) -> UniResponseModel[List[LoveACCreditCategory]] | JSONResponse:
    """
    获取用户的爱安财分数明细列表

    ✅ 功能特性：
       - 获取分数的详细分类信息
       - 显示每个分数项的具体内容
       - 支持分页查询

    💡 使用场景：
       - 查看分数明细页面
       - 了解各类别分数构成
       - 分析分数不足的原因

    Returns:
        list[LoveACCreditCategory]: 分数分类列表，每个分类包含多个分数项
    """
    try:
        conn.logger.info("开始获取爱安财分数明细")
        response = await conn.client.post(
            url=AACConfig().to_full_url(ENDPOINT["score_list"]),
            data={"pageIndex": "1", "pageSize": "10"},
            headers=headers,
            timeout=6000,
        )
        if response.status_code != 200:
            conn.logger.error(
                f"获取爱安财分数明细失败，HTTP状态码: {response.status_code}"
            )
            return ProtectRouterErrorToCode().remote_service_error.to_json_response(
                conn.logger.trace_id, "获取爱安财分数明细失败，请稍后重试"
            )
        data = response.json()
        if data.get("code") != 0:
            conn.logger.error(f"获取爱安财分数明细失败，响应代码: {data.get('code')}")
            return ProtectRouterErrorToCode().remote_service_error.to_json_response(
                conn.logger.trace_id, "获取爱安财分数明细失败，请稍后重试"
            )
        data = data.get("data", [])
        if not data:
            conn.logger.error("获取爱安财分数明细失败，响应数据为空")
            return ProtectRouterErrorToCode().null_response.to_json_response(
                conn.logger.trace_id, "获取爱安财分数明细失败，请稍后重试"
            )
        try:
            credit_list = [LoveACCreditCategory.model_validate(item) for item in data]
            conn.logger.info("成功获取爱安财分数明细")
            return UniResponseModel[List[LoveACCreditCategory]](
                success=True,
                data=credit_list,
                message="获取爱安财分数明细成功",
                error=None,
            )
        except ValidationError as ve:
            conn.logger.error(f"解析爱安财分数明细失败: {str(ve)}")
            return ProtectRouterErrorToCode().validation_error.to_json_response(
                conn.logger.trace_id, "解析爱安财分数明细失败，请稍后重试"
            )

    except HTTPError as he:
        conn.logger.error(f"获取爱安财分数明细异常: {str(he)}")
        return ProtectRouterErrorToCode().remote_service_error.to_json_response(
            conn.logger.trace_id, "获取爱安财分数明细异常，请稍后重试"
        )
    except Exception as e:
        conn.logger.error(f"获取爱安财分数明细未知异常: {str(e)}")
        return ProtectRouterErrorToCode().unknown_error.to_json_response(
            conn.logger.trace_id, "获取爱安财分数明细未知异常，请稍后重试"
        )
