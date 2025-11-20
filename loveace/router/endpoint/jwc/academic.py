import re

from fastapi import APIRouter, Depends
from fastapi.responses import JSONResponse
from pydantic import ValidationError

from loveace.router.endpoint.jwc.model.academic import (
    AcademicInfo,
    AcademicInfoTransformer,
    CourseSelectionStatus,
    CourseSelectionStatusTransformer,
    TrainingPlanInfo,
    TrainingPlanInfoTransformer,
)
from loveace.router.endpoint.jwc.model.base import JWCConfig
from loveace.router.schemas.error import ProtectRouterErrorToCode
from loveace.router.schemas.uniresponse import UniResponseModel
from loveace.service.remote.aufe import AUFEConnection
from loveace.service.remote.aufe.depends import get_aufe_conn

jwc_academic_router = APIRouter(
    prefix="/academic",
    responses=ProtectRouterErrorToCode.gen_code_table(),
)


ENDPOINTS = {
    "academic_info": "/main/academicInfo?sf_request_type=ajax",
    "training_plan": "/main/showPyfaInfo?sf_request_type=ajax",
    "course_selection_status": "/main/checkSelectCourseStatus?sf_request_type=ajax",
}


@jwc_academic_router.get(
    "/info", response_model=UniResponseModel[AcademicInfo], summary="获取学业信息"
)
async def get_academic_info(
    conn: AUFEConnection = Depends(get_aufe_conn),
) -> UniResponseModel[AcademicInfo] | JSONResponse:
    """
    获取用户的学业信息（GPA、学分等）

    ✅ 功能特性：
       - 获取当前学期学业情况
       - 获取平均学分绩点（GPA）
       - 实时从教务系统查询

    💡 使用场景：
       - 个人中心查看学业成绩概览
       - 了解学业进展情况
       - 毕业时验证学业要求

    Returns:
        AcademicInfo: 包含 GPA、学分、学业状态等信息
    """
    try:
        conn.logger.info(f"获取用户 {conn.userid} 的学业信息")
        academic_info = await conn.client.post(
            JWCConfig().to_full_url(ENDPOINTS["academic_info"]),
            data={"flag": ""},
            follow_redirects=True,
            timeout=conn.timeout,
        )
        if not academic_info.status_code == 200:
            conn.logger.error(
                f"获取用户 {conn.userid} 的学业信息失败，状态码: {academic_info.status_code}"
            )
            return ProtectRouterErrorToCode().remote_service_error.to_json_response(
                conn.logger.trace_id
            )
        try:
            data = academic_info.json()
            # 数组格式特殊处理
            data_to_validate = data[0]
            result = AcademicInfoTransformer.model_validate(
                data_to_validate
            ).to_academic_info()
            return UniResponseModel[AcademicInfo](
                success=True,
                data=result,
                message="获取学业信息成功",
                error=None,
            )
        except ValidationError as ve:
            conn.logger.error("数据验证失败")
            conn.logger.debug(f"数据验证失败详情: {ve}")
            return ProtectRouterErrorToCode().validation_error.to_json_response(
                conn.logger.trace_id
            )
    except Exception as e:
        conn.logger.exception(e)
        return ProtectRouterErrorToCode().server_error.to_json_response(
            conn.logger.trace_id
        )


@jwc_academic_router.get(
    "/training_plan",
    response_model=UniResponseModel[TrainingPlanInfo],
    summary="获取培养方案信息",
)
async def get_training_plan_info(
    conn: AUFEConnection = Depends(get_aufe_conn),
) -> UniResponseModel[TrainingPlanInfo] | JSONResponse:
    """
    获取用户的培养方案信息

    ✅ 功能特性：
       - 获取所属专业的培养方案
       - 获取年级和专业名称
       - 提取关键信息（年级、专业）

    💡 使用场景：
       - 了解培养方案要求
       - 查看所属年级和专业
       - 课程规划参考

    Returns:
        TrainingPlanInfo: 包含方案名称、专业名称、年级信息
    """
    try:
        conn.logger.info(f"获取用户 {conn.userid} 的培养方案信息")
        training_plan_info = await conn.client.get(
            JWCConfig().to_full_url(ENDPOINTS["training_plan"]),
            follow_redirects=True,
            timeout=conn.timeout,
        )
        if not training_plan_info.status_code == 200:
            conn.logger.error(
                f"获取用户 {conn.userid} 的培养方案信息失败，状态码: {training_plan_info.status_code}"
            )
            return ProtectRouterErrorToCode().remote_service_error.to_json_response(
                conn.logger.trace_id
            )
        try:
            data = training_plan_info.json()
            transformer = TrainingPlanInfoTransformer.model_validate(data)
            if transformer.count > 0 and len(transformer.data) > 0:
                first_plan = transformer.data[0]
                if len(first_plan) >= 2:
                    plan_name = first_plan[0]
                    # 提取年级信息 - 假设格式为"20XX级..."
                    grade_match = re.search(r"(\d{4})级", plan_name)
                    grade = grade_match.group(1) if grade_match else ""

                    # 提取专业名称 - 假设格式为"20XX级XXX本科培养方案"
                    major_match = re.search(r"\d{4}级(.+?)本科", plan_name)
                    major_name = major_match.group(1) if major_match else ""
                    result = TrainingPlanInfo(
                        plan_name=plan_name, major_name=major_name, grade=grade
                    )
                    return UniResponseModel[TrainingPlanInfo](
                        success=True,
                        data=result,
                        message="获取培养方案信息成功",
                        error=None,
                    )
                else:
                    conn.logger.error("培养方案数据格式不正确，字段数量不足")
                    return ProtectRouterErrorToCode().validation_error.to_json_response(
                        conn.logger.trace_id
                    )
            else:
                conn.logger.error("培养方案数据为空")
                return ProtectRouterErrorToCode().validation_error.to_json_response(
                    conn.logger.trace_id
                )
        except ValidationError as ve:
            conn.logger.error("数据验证失败")
            conn.logger.debug(f"数据验证失败详情: {ve}")
            return ProtectRouterErrorToCode().validation_error.to_json_response(
                conn.logger.trace_id
            )
    except Exception as e:
        conn.logger.exception(e)
        return ProtectRouterErrorToCode().server_error.to_json_response(
            conn.logger.trace_id
        )


@jwc_academic_router.get(
    "/course_selection_status",
    response_model=UniResponseModel[CourseSelectionStatus],
    summary="获取选课状态信息",
)
async def get_course_selection_status(
    conn: AUFEConnection = Depends(get_aufe_conn),
) -> UniResponseModel[CourseSelectionStatus] | JSONResponse:
    """
    获取用户的选课状态

    ✅ 功能特性：
       - 获取当前选课时间窗口
       - 获取选课开放状态
       - 显示选课时间提醒

    💡 使用场景：
       - 查看当前是否在选课时间内
       - 获取选课开始和结束时间
       - 选课前的状态检查

    Returns:
        CourseSelectionStatus: 包含选课状态、开始时间、结束时间等
    """
    try:
        conn.logger.info(f"获取用户 {conn.userid} 的选课状态信息")
        course_selection_status = await conn.client.get(
            JWCConfig().to_full_url(ENDPOINTS["course_selection_status"]),
            follow_redirects=True,
            timeout=conn.timeout,
        )
        if not course_selection_status.status_code == 200:
            conn.logger.error(
                f"获取用户 {conn.userid} 的选课状态信息失败，状态码: {course_selection_status.status_code}"
            )
            return ProtectRouterErrorToCode().remote_service_error.to_json_response(
                conn.logger.trace_id
            )
        try:
            data = course_selection_status.json()
            result = CourseSelectionStatus(
                can_select=(
                    True
                    if CourseSelectionStatusTransformer.model_validate(data).status_code
                    == "1"
                    else False
                )
            )
            return UniResponseModel[CourseSelectionStatus](
                success=True,
                data=result,
                message="获取选课状态成功",
                error=None,
            )
        except ValidationError as ve:
            conn.logger.error("数据验证失败")
            conn.logger.debug(f"数据验证失败详情: {ve}")
            return ProtectRouterErrorToCode().validation_error.to_json_response(
                conn.logger.trace_id
            )
    except Exception as e:
        conn.logger.exception(e)
        return ProtectRouterErrorToCode().server_error.to_json_response(
            conn.logger.trace_id
        )
