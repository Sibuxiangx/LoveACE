import asyncio
import re

from bs4 import BeautifulSoup
from fastapi import APIRouter, Depends
from fastapi.responses import JSONResponse
from pydantic import ValidationError

from loveace.router.endpoint.jwc.model.base import JWCConfig
from loveace.router.endpoint.jwc.model.schedule import ScheduleData
from loveace.router.schemas.error import ProtectRouterErrorToCode
from loveace.router.schemas.uniresponse import UniResponseModel
from loveace.service.remote.aufe import AUFEConnection
from loveace.service.remote.aufe.depends import get_aufe_conn

jwc_schedules_router = APIRouter(
    prefix="/schedule",
    responses=ProtectRouterErrorToCode.gen_code_table(),
)


ENDPOINTS = {
    "student_schedule_pre": "/student/courseSelect/calendarSemesterCurriculum/index",
    "student_schedule": "/student/courseSelect/thisSemesterCurriculum/{dynamic_path}/ajaxStudentSchedule/past/callback",
    "section_and_time": "/ajax/getSectionAndTime",
}


@jwc_schedules_router.get(
    "/{term_code}/table",
    summary="获取课表信息",
    response_model=UniResponseModel[ScheduleData],
)
async def get_schedule_table(
    term_code: str, conn: AUFEConnection = Depends(get_aufe_conn)
) -> UniResponseModel[ScheduleData] | JSONResponse:
    """
    获取指定学期的课程表

    ✅ 功能特性：
       - 获取指定学期的完整课程表
       - 显示课程名称、教室、时间、教师等信息
       - 支持按周查询

    💡 使用场景：
       - 查看本周课程安排
       - 了解完整学期课程表
       - 课表分享和导出

    Args:
        term_code: 学期代码（如：2023-2024-1）

    Returns:
        ScheduleData: 包含课程表数据和课程详情
    """
    try:
        conn.logger.info(f"开始获取学期 {term_code} 的课表信息")
        # 第一步：访问课表预备页面，获取动态路径

        dynamic_page = JWCConfig().to_full_url(ENDPOINTS["student_schedule_pre"])
        dynamic_page_response = await conn.client.get(
            dynamic_page, follow_redirects=True, timeout=conn.timeout
        )
        if dynamic_page_response.status_code != 200:
            conn.logger.error(
                f"获取课表预备页面失败，状态码: {dynamic_page_response.status_code}"
            )
            return ProtectRouterErrorToCode.remote_service_error.to_json_response(
                conn.logger.trace_id
            )

        soup = BeautifulSoup(dynamic_page_response.text, "lxml")

        # 尝试从页面中提取动态路径
        scripts = soup.find_all("script")
        dynamic_path = "B2RMNJkT95"  # 默认值
        for script in scripts:
            try:
                script_text = script.string  # type: ignore
                if script_text and "ajaxStudentSchedule" in script_text:
                    # 使用正则表达式提取路径
                    match = re.search(
                        r"/([A-Za-z0-9]+)/ajaxStudentSchedule", script_text
                    )
                    if match:
                        dynamic_path = match.group(1)
                        break
            except AttributeError:
                continue
        section_and_time_headers = {
            **conn.client.headers,
            "Referer": JWCConfig().to_full_url(ENDPOINTS["student_schedule"]),
        }
        select_and_time_url = JWCConfig().to_full_url(ENDPOINTS["section_and_time"])
        select_and_time_data = {
            "planNumber": "",
            "ff": "f",
            "sf_request_type": "ajax",
        }
        section_and_time_response_coro = conn.client.post(
            select_and_time_url,
            data=select_and_time_data,
            headers=section_and_time_headers,
            follow_redirects=True,
            timeout=conn.timeout,
        )
        student_schedule_url = JWCConfig().to_full_url(
            ENDPOINTS["student_schedule"].format(dynamic_path=dynamic_path)
        )

        schedule_params = {
            "planCode": term_code,
            "sf_request_type": "ajax",
        }
        student_schedule_response_coro = conn.client.get(
            student_schedule_url,
            params=schedule_params,
            follow_redirects=True,
            timeout=conn.timeout,
        )
        section_and_time_response, student_schedule_response = await asyncio.gather(
            section_and_time_response_coro, student_schedule_response_coro
        )
        if section_and_time_response.status_code != 200:
            conn.logger.error(
                f"获取节次时间信息失败，状态码: {section_and_time_response.status_code}"
            )
            return ProtectRouterErrorToCode.remote_service_error.to_json_response(
                conn.logger.trace_id, message="无法获取节次时间信息，请稍后再试"
            )
        if student_schedule_response.status_code != 200:
            conn.logger.error(
                f"获取课表信息失败，状态码: {student_schedule_response.status_code}"
            )
            return ProtectRouterErrorToCode.remote_service_error.to_json_response(
                conn.logger.trace_id, message="无法获取课表信息，请稍后再试"
            )
        time_data = section_and_time_response.json()
        schedule_data = student_schedule_response.json()

        # 处理时间段信息
        time_slots = []
        section_time = time_data.get("sectionTime", [])
        for time_slot in section_time:
            time_slots.append(
                {
                    "session": time_slot.get("id", {}).get("session", 0),
                    "session_name": time_slot.get("sessionName", ""),
                    "start_time": time_slot.get("startTime", ""),
                    "end_time": time_slot.get("endTime", ""),
                    "time_length": time_slot.get("timeLength", ""),
                    "djjc": time_slot.get("djjc", 0),
                }
            )

        # 处理课程信息
        courses = []
        xkxx_list = schedule_data.get("xkxx", [])

        for xkxx_item in xkxx_list:
            if isinstance(xkxx_item, dict):
                for course_key, course_data in xkxx_item.items():
                    if isinstance(course_data, dict):
                        # 提取基本课程信息
                        course_name = course_data.get("courseName", "")
                        course_code = course_data.get("id", {}).get("coureNumber", "")
                        course_sequence = course_data.get("id", {}).get(
                            "coureSequenceNumber", ""
                        )
                        teacher_name = (
                            course_data.get("attendClassTeacher", "")
                            .replace("* ", "")
                            .strip()
                        )
                        course_properties = course_data.get("coursePropertiesName", "")
                        exam_type = course_data.get("examTypeName", "")
                        unit = float(course_data.get("unit", 0))

                        # 处理时间地点列表
                        time_locations = []
                        time_place_list = course_data.get("timeAndPlaceList", [])

                        # 检查是否有具体时间安排
                        is_no_schedule = len(time_place_list) == 0

                        for time_place in time_place_list:
                            # 过滤掉无用的字段，只保留关键信息
                            time_location = {
                                "class_day": time_place.get("classDay", 0),
                                "class_sessions": time_place.get("classSessions", 0),
                                "continuing_session": time_place.get(
                                    "continuingSession", 0
                                ),
                                "class_week": time_place.get("classWeek", ""),
                                "week_description": time_place.get(
                                    "weekDescription", ""
                                ),
                                "campus_name": time_place.get("campusName", ""),
                                "teaching_building_name": time_place.get(
                                    "teachingBuildingName", ""
                                ),
                                "classroom_name": time_place.get("classroomName", ""),
                            }
                            time_locations.append(time_location)

                        # 只保留有效的课程（有课程名称的）
                        if course_name:
                            course = {
                                "course_name": course_name,
                                "course_code": course_code,
                                "course_sequence": course_sequence,
                                "teacher_name": teacher_name,
                                "course_properties": course_properties,
                                "exam_type": exam_type,
                                "unit": unit,
                                "time_locations": time_locations,
                                "is_no_schedule": is_no_schedule,
                            }
                            courses.append(course)
        # 构建最终数据
        processed_data = {
            "total_units": float(schedule_data.get("allUnits", 0)),
            "time_slots": time_slots,
            "courses": courses,
        }

        conn.logger.info(
            f"成功处理课表数据：共{len(courses)}门课程，{len(time_slots)}个时间段"
        )
        result = ScheduleData.model_validate(processed_data)
        return UniResponseModel[ScheduleData](
            success=True,
            data=result,
            message="获取课表信息成功",
            error=None,
        )
    except ValidationError as ve:
        conn.logger.error(f"数据验证错误: {ve}")
        return ProtectRouterErrorToCode().validation_error.to_json_response(
            conn.logger.trace_id, "数据验证错误"
        )
    except Exception as e:
        conn.logger.exception(e)
        return ProtectRouterErrorToCode().server_error.to_json_response(
            conn.logger.trace_id,
        )
