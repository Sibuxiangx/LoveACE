from fastapi import APIRouter, Depends
from fastapi.responses import JSONResponse
from pydantic import ValidationError

from loveace.router.endpoint.jwc.model.competition import (
    CompetitionFullResponse,
)
from loveace.router.endpoint.jwc.utils.aspnet_form_parser import ASPNETFormParser
from loveace.router.endpoint.jwc.utils.competition import CompetitionInfoParser
from loveace.router.schemas.error import ProtectRouterErrorToCode
from loveace.router.schemas.uniresponse import UniResponseModel
from loveace.service.remote.aufe import AUFEConnection
from loveace.service.remote.aufe.depends import get_aufe_conn

jwc_competition_router = APIRouter(
    prefix="/competition",
    responses=ProtectRouterErrorToCode().gen_code_table(),
)

ENDPOINT = {
    "awards_page": "http://211-86-241-245.vpn2.aufe.edu.cn:8118/xsXmMain.aspx",
}


@jwc_competition_router.get(
    "/info",
    summary="获取完整学科竞赛信息",
    response_model=UniResponseModel[CompetitionFullResponse],
)
async def get_full_competition_info(
    conn: AUFEConnection = Depends(get_aufe_conn),
) -> UniResponseModel[CompetitionFullResponse] | JSONResponse:
    """
    获取用户的完整学科竞赛信息（一次请求获取所有数据）

    ✅ 功能特性：
       - 一次请求获取获奖项目列表和学分汇总
       - 减少网络IO调用，提高性能
       - 返回完整的竞赛相关数据

    📊 返回数据：
       - 获奖项目列表（包含项目信息、学分、奖励等）
       - 学分汇总（各类学分统计）
       - 学生基本信息

    💡 使用场景：
       - 需要完整竞赛信息的仪表板
       - 移动端应用（减少请求次数）
       - 性能敏感的场景

    Returns:
        CompetitionFullResponse: 包含完整竞赛信息的响应对象
    """
    try:
        conn.logger.info(f"获取用户 {conn.userid} 的完整学科竞赛信息")

        # 第一次访问页面获取 HTML 内容和 Cookie
        conn.logger.debug("第一次访问创新创业管理平台页面获取表单数据")
        index_response = await conn.client.get(
            ENDPOINT["awards_page"],
            follow_redirects=True,
            timeout=conn.timeout,
        )

        if index_response.status_code != 200:
            conn.logger.error(f"第一次访问创新创业管理平台失败，状态码: {index_response.status_code}")
            return ProtectRouterErrorToCode().remote_service_error.to_json_response(
                conn.logger.trace_id
            )

        # 从第一次响应中提取动态表单数据
        conn.logger.debug("从页面中提取动态表单数据")
        try:
            form_data = ASPNETFormParser.get_awards_list_form_data(index_response.text)
            conn.logger.debug(f"成功提取表单数据，__VIEWSTATE 长度: {len(form_data.get('__VIEWSTATE', ''))}")
        except Exception as e:
            conn.logger.error(f"提取表单数据失败: {e}")
            return ProtectRouterErrorToCode().server_error.to_json_response(
                conn.logger.trace_id
            )

        # 第二次请求：使用动态表单数据请求已申报奖项页面
        conn.logger.debug("使用动态表单数据请求已申报奖项页面")
        result_response = await conn.client.post(
            ENDPOINT["awards_page"],
            follow_redirects=True,
            data=form_data,
            timeout=conn.timeout,
        )

        if result_response.status_code != 200:
            conn.logger.error(f"请求已申报奖项页面失败，状态码: {result_response.status_code}")
            return ProtectRouterErrorToCode().remote_service_error.to_json_response(
                conn.logger.trace_id
            )

        # 一次性解析所有数据
        parser = CompetitionInfoParser(result_response.text)
        full_response = parser.parse_full_competition_info()

        conn.logger.info(
            f"成功获取用户 {conn.userid} 的完整竞赛信息，共 {full_response.total_awards_count} 项获奖"
        )

        return UniResponseModel[CompetitionFullResponse](
            success=True,
            data=full_response,
            message="获取竞赛信息成功",
            error=None,
        )

    except ValidationError as e:
        conn.logger.error(f"用户 {conn.userid} 的竞赛信息数据验证失败: {e}")
        return ProtectRouterErrorToCode().validation_error.to_json_response(
            conn.logger.trace_id
        )
    except Exception as e:
        conn.logger.error(f"用户 {conn.userid} 的完整竞赛信息获取失败: {e}")
        return ProtectRouterErrorToCode().server_error.to_json_response(
            conn.logger.trace_id
        )
