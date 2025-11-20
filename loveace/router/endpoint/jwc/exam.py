from datetime import datetime

from fastapi import APIRouter, Depends
from fastapi.responses import JSONResponse
from pydantic import ValidationError

from loveace.router.endpoint.jwc.academic import get_academic_info
from loveace.router.endpoint.jwc.model.academic import AcademicInfo
from loveace.router.endpoint.jwc.model.exam import ExamInfoResponse
from loveace.router.endpoint.jwc.utils.exam import fetch_unified_exam_info
from loveace.router.schemas.error import ProtectRouterErrorToCode
from loveace.router.schemas.uniresponse import UniResponseModel
from loveace.service.remote.aufe import AUFEConnection
from loveace.service.remote.aufe.depends import get_aufe_conn

jwc_exam_router = APIRouter(
    prefix="/exam",
    responses=ProtectRouterErrorToCode().gen_code_table(),
)


@jwc_exam_router.get(
    "/info", response_model=UniResponseModel[ExamInfoResponse], summary="获取考试信息"
)
async def get_exam_info(
    conn: AUFEConnection = Depends(get_aufe_conn),
) -> UniResponseModel[ExamInfoResponse] | JSONResponse:
    """
    获取用户的考试信息

    ✅ 功能特性：
       - 获取当前学期的考试安排
       - 自动确定考试时间范围
       - 显示考试时间、地点、课程等信息

    💡 使用场景：
       - 查看即将进行的考试
       - 了解考试安排和地点
       - 提前规划复习计划

    Returns:
        ExamInfoResponse: 包含考试列表和总数
    """
    try:
        academic_info = await get_academic_info(conn)
        if isinstance(academic_info, UniResponseModel):
            if academic_info.data and isinstance(academic_info.data, AcademicInfo):
                term_code = academic_info.data.current_term
            else:
                result = ExamInfoResponse(exams=[], total_count=0)
                return UniResponseModel[ExamInfoResponse](
                    success=False,
                    data=result,
                    message="无法获取学期信息",
                    error=None,
                )
        elif isinstance(academic_info, AcademicInfo):
            term_code = academic_info.current_term
        else:
            result = ExamInfoResponse(exams=[], total_count=0)
            return UniResponseModel[ExamInfoResponse](
                success=False,
                data=result,
                message="无法获取学期信息",
                error=None,
            )
        conn.logger.info(f"获取用户 {conn.userid} 的考试信息")

        start_date = datetime.now()
        # termcode 结尾为 1 为秋季学期，考试应在3月之前，2为春季学期，考试应在9月之前
        end_date = datetime(
            year=start_date.year + (1 if term_code.endswith("1") else 0),
            month=3 if term_code.endswith("1") else 9,
            day=30,
        )
        exam_info = await fetch_unified_exam_info(
            conn,
            start_date=start_date.strftime("%Y-%m-%d"),
            end_date=end_date.strftime("%Y-%m-%d"),
            term_code=term_code,
        )
        return UniResponseModel[ExamInfoResponse](
            success=True,
            data=exam_info,
            message="获取考试信息成功",
            error=None,
        )
    except ValidationError as e:
        conn.logger.error(f"用户 {conn.userid} 的考试信息数据验证失败: {e}")
        return ProtectRouterErrorToCode().validation_error.to_json_response(
            conn.logger.trace_id
        )
    except Exception as e:
        conn.logger.error(f"用户 {conn.userid} 的考试信息获取失败: {e}")
        return ProtectRouterErrorToCode().server_error.to_json_response(
            conn.logger.trace_id
        )
