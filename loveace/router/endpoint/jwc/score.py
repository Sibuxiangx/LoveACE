import re

from bs4 import BeautifulSoup
from fastapi import APIRouter, Depends
from fastapi.responses import JSONResponse
from httpx import HTTPError
from pydantic import ValidationError

from loveace.router.endpoint.jwc.model.base import JWCConfig
from loveace.router.endpoint.jwc.model.score import ScoreRecord, TermScoreResponse
from loveace.router.schemas.error import ProtectRouterErrorToCode
from loveace.router.schemas.uniresponse import UniResponseModel
from loveace.service.remote.aufe import AUFEConnection
from loveace.service.remote.aufe.depends import get_aufe_conn

jwc_score_router = APIRouter(
    prefix="/score",
    responses=ProtectRouterErrorToCode().gen_code_table(),
)

ENDPOINT = {
    "term_score_pre": "/student/integratedQuery/scoreQuery/allTermScores/index",
    "term_score": "/student/integratedQuery/scoreQuery/{dynamic_path}/allTermScores/data",
}


@jwc_score_router.get(
    "/{term_code}/list",
    summary="获取给定学期成绩列表",
    response_model=UniResponseModel[TermScoreResponse],
)
async def get_term_score(
    term_code: str,
    conn: AUFEConnection = Depends(get_aufe_conn),
) -> UniResponseModel[TermScoreResponse] | JSONResponse:
    """
    获取指定学期的详细成绩单

    ✅ 功能特性：
       - 获取指定学期所有课程成绩
       - 包含补考和重修成绩
       - 显示学分、绩点等详细信息

    💡 使用场景：
       - 查看历史学期的成绩
       - 导出成绩单
       - 分析学业成绩趋势

    Args:
        term_code: 学期代码（如：2023-2024-1）

    Returns:
        TermScoreResponse: 包含该学期所有成绩记录和总数
    """
    try:
        response = await conn.client.get(
            JWCConfig().to_full_url(ENDPOINT["term_score_pre"]),
            follow_redirects=True,
            timeout=conn.timeout,
        )
        if response.status_code != 200:
            conn.logger.error(f"访问成绩查询页面失败，状态码: {response.status_code}")
            return ProtectRouterErrorToCode().remote_service_error.to_json_response(
                conn.logger.trace_id
            )

        # 从页面中提取动态路径参数
        soup = BeautifulSoup(response.text, "html.parser")

        # 查找表单或Ajax请求的URL
        # 通常在JavaScript代码中或表单action中
        dynamic_path = "M1uwxk14o6"  # 默认值，如果无法提取则使用

        # 尝试从页面中提取动态路径
        scripts = soup.find_all("script")
        for script in scripts:
            try:
                script_text = script.string  # type: ignore
                if script_text and "allTermScores/data" in script_text:
                    # 使用正则表达式提取路径
                    match = re.search(
                        r"/([A-Za-z0-9]+)/allTermScores/data", script_text
                    )
                    if match:
                        dynamic_path = match.group(1)
                        break
            except AttributeError:
                continue

        data_url = JWCConfig().to_full_url(
            ENDPOINT["term_score"].format(dynamic_path=dynamic_path)
        )
        data_params = {
            "zxjxjhh": term_code,
            "kch": "",
            "kcm": "",
            "pageNum": "1",
            "pageSize": "50",
            "sf_request_type": "ajax",
        }
        data_response = await conn.client.post(
            data_url,
            data=data_params,
            follow_redirects=True,
            timeout=conn.timeout,
        )
        if data_response.status_code != 200:
            conn.logger.error(f"获取成绩数据失败，状态码: {data_response.status_code}")
            return ProtectRouterErrorToCode().remote_service_error.to_json_response(
                conn.logger.trace_id
            )
        data_json = data_response.json()
        data_list = data_json.get("list", {})
        if not data_list:
            result = TermScoreResponse(records=[], total_count=0)
            return UniResponseModel[TermScoreResponse](
                success=True,
                data=result,
                message="获取成绩单成功",
                error=None,
            )
        records = data_list.get("records", [])
        r_total_count = data_list.get("pageContext", {}).get("totalCount", 0)
        term_scores = []
        for record in records:
            term_scores.append(
                ScoreRecord(
                    sequence=record[0],
                    term_id=record[1],
                    course_code=record[2],
                    course_class=record[3],
                    course_name_cn=record[4],
                    course_name_en=record[5],
                    credits=record[6],
                    hours=record[7],
                    course_type=record[8],
                    exam_type=record[9],
                    score=record[10],
                    retake_score=record[11] if record[11] else None,
                    makeup_score=record[12] if record[12] else None,
                )
            )
        l_total_count = len(term_scores)
        assert r_total_count == l_total_count
        result = TermScoreResponse(records=term_scores, total_count=r_total_count)
        return UniResponseModel[TermScoreResponse](
            success=True,
            data=result,
            message="获取成绩单成功",
            error=None,
        )
    except AssertionError as ae:
        conn.logger.error(f"数据属性错误: {ae}")
        return ProtectRouterErrorToCode().validation_error.to_json_response(
            conn.logger.trace_id
        )
    except IndexError as ie:
        conn.logger.error(f"数据解析错误: {ie}")
        return ProtectRouterErrorToCode().validation_error.to_json_response(
            conn.logger.trace_id
        )
    except ValidationError as ve:
        conn.logger.error(f"数据验证错误: {ve}")
        return ProtectRouterErrorToCode().validation_error.to_json_response(
            conn.logger.trace_id
        )
    except HTTPError as he:
        conn.logger.error(f"HTTP请求错误: {he}")
        return ProtectRouterErrorToCode().remote_service_error.to_json_response(
            conn.logger.trace_id
        )
    except Exception as e:
        conn.logger.exception(e)
        return ProtectRouterErrorToCode().server_error.to_json_response(
            conn.logger.trace_id
        )
