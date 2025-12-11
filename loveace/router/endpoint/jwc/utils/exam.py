import time
from json import JSONDecodeError
from typing import List, Optional

from bs4 import BeautifulSoup

from loveace.router.endpoint.jwc.model.base import JWCConfig
from loveace.router.endpoint.jwc.model.exam import (
    ExamInfoResponse,
    ExamScheduleItem,
    OtherExamRecord,
    OtherExamResponse,
    SeatInfo,
    UnifiedExamInfo,
)
from loveace.service.remote.aufe import AUFEConnection

ENDPOINTS = {
    "school_exam_pre_request": "/student/examinationManagement/examPlan/index",
    "school_exam_request": "/student/examinationManagement/examPlan/detail",
    "seat_info": "/student/examinationManagement/examPlan/index",
    "other_exam_record": "/student/examinationManagement/othersExamPlan/queryScores?sf_request_type=ajax",
}


# +++++===== 考试信息前置方法 =====+++++ #
async def fetch_school_exam_schedule(
    start_date: str, end_date: str, conn: AUFEConnection
) -> List[ExamScheduleItem]:
    """
    获取校统考考试安排

    Args:
        start_date: 开始日期 (YYYY-MM-DD)
        end_date: 结束日期 (YYYY-MM-DD)

    Returns:
        List[ExamScheduleItem]: 校统考列表
    """
    try:
        timestamp = int(time.time() * 1000)

        headers = {
            # **conn.client.headers,
            "Accept": "application/json, text/javascript, */*; q=0.01",
            "X-Requested-With": "XMLHttpRequest",
        }

        params = {
            "start": start_date,
            "end": end_date,
            "_": str(timestamp),
            "sf_request_type": "ajax",
        }
        await conn.client.get(
            url=JWCConfig().to_full_url(ENDPOINTS["school_exam_pre_request"]),
            follow_redirects=True,
            headers=headers,
            timeout=conn.timeout,
        )
        response = await conn.client.get(
            url=JWCConfig().to_full_url(ENDPOINTS["school_exam_request"]),
            headers=headers,
            params=params,
            follow_redirects=True,
            timeout=conn.timeout,
        )

        if response.status_code != 200:
            conn.logger.error(f"获取校统考信息失败: HTTP状态码 {response.status_code}")
            return []
        if "]" == response.text:
            conn.logger.warning("获取校统考信息成功，但无数据")
            return []
        try:
            json_data = response.json()
        except JSONDecodeError as e:
            conn.logger.error(f"解析校统考信息JSON失败: {str(e)}")
            return []

        # 解析为ExamScheduleItem列表
        school_exams = []
        if isinstance(json_data, list):
            for item in json_data:
                exam_item = ExamScheduleItem.model_validate(item)
                school_exams.append(exam_item)

        conn.logger.info(f"获取校统考信息成功，共 {len(school_exams)} 场考试")
        return school_exams

    except Exception as e:
        conn.logger.error(f"获取校统考信息出现如下异常: {str(e)}")
        return []


async def fetch_exam_seat_info(conn: AUFEConnection) -> List[SeatInfo]:
    """
    获取考试座位号信息
    conn: AUFEConnection

    Returns:
        List[SeatInfo]: 座位信息列表
    """
    try:
        headers = {
            # **conn.client.headers,
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7",
        }

        response = await conn.client.get(
            url=JWCConfig().to_full_url(ENDPOINTS["seat_info"]),
            headers=headers,
            follow_redirects=True,
            timeout=conn.timeout,
        )

        if response.status_code != 200:
            conn.logger.error(
                f"获取考试座位号信息失败: HTTP状态码 {response.status_code}"
            )
            return []
        soup = BeautifulSoup(response.text, "lxml")
        seat_infos = []

        # 查找所有考试信息区块
        exam_blocks = soup.find_all("div", {"class": "widget-box"})
        for block in exam_blocks:
            course_name = ""
            seat_number = ""

            # 获取课程名
            title = block.find("h5", {"class": "widget-title"})  # type: ignore
            if title:
                course_text = title.get_text(strip=True)  # type: ignore
                # 提取课程名，格式可能是: "（课程代码-班号）课程名"
                if "）" in course_text:
                    course_name = course_text.split("）", 1)[1].strip()
                else:
                    course_name = course_text.strip()

            # 获取座位号
            widget_main = block.find("div", {"class": "widget-main"})  # type: ignore
            if widget_main:
                content = widget_main.get_text()  # type: ignore
                for line in content.split("\n"):
                    if "座位号" in line:
                        try:
                            seat_number = line.split("座位号:")[1].strip()
                        except Exception:
                            try:
                                seat_number = line.split("座位号：")[1].strip()
                            except Exception:
                                pass
                        break

            if course_name and seat_number:
                seat_infos.append(
                    SeatInfo(course_name=course_name, seat_number=seat_number)
                )

        conn.logger.info(f"获取考试座位号信息成功，共 {len(seat_infos)} 条记录")
        return seat_infos

    except Exception as e:
        conn.logger.error(f"获取考试座位号信息异常: {str(e)}")
        return []


def convert_school_exam_to_unified(
    exam: ExamScheduleItem, seat_infos: List[SeatInfo], conn: AUFEConnection
) -> Optional[UnifiedExamInfo]:
    """
    将校统考数据转换为统一格式

    Args:
        exam: 校统考项目
        seat_info: 座位号信息映射

    Returns:
        Optional[UnifiedExamInfo]: 统一格式的考试信息
    """
    try:
        # 解析title信息，格式如: "新媒体导论\n08:30-10:30\n西校\n西校通慧楼\n通慧楼-308\n"
        title_parts = exam.title.strip().split("\n")
        if len(title_parts) < 2:
            return None

        course_name = title_parts[0]
        exam_time = title_parts[1] if len(title_parts) > 1 else ""

        # 拼接地点信息
        location_parts = title_parts[2:] if len(title_parts) > 2 else []
        exam_location = " ".join([part for part in location_parts if part.strip()])

        # 添加座位号到备注
        note = ""
        for seat in seat_infos:
            if seat.course_name == course_name:
                note = f"座位号: {seat.seat_number}"
                note = note.removesuffix("准考证号：")
                break

        return UnifiedExamInfo(
            course_name=course_name,
            exam_date=exam.start,
            exam_time=exam_time,
            exam_location=exam_location,
            exam_type="校统考",
            note=note,
        )

    except Exception as e:
        conn.logger.error(f"转换校统考数据异常: {str(e)}")
        return None


async def fetch_other_exam_records(
    term_code: str, conn: AUFEConnection
) -> List[OtherExamRecord]:
    """
    获取其他考试记录

    Args:
        term_code: 学期代码
        conn: AUFEConnection

    Returns:
        List: 其他考试记录列表
    """
    try:
        headers = {
            # **conn.client.headers,
            "Accept": "application/json, text/javascript, */*; q=0.01",
            "Content-Type": "application/x-www-form-urlencoded; charset=UTF-8",
            "X-Requested-With": "XMLHttpRequest",
        }

        data = {"zxjxjhh": term_code, "tab": "0", "pageNum": "1", "pageSize": "30"}

        response = await conn.client.post(
            url=JWCConfig().to_full_url(ENDPOINTS["other_exam_record"]),
            headers=headers,
            data=data,
            follow_redirects=True,
            timeout=conn.timeout,
        )
        valid = OtherExamResponse.model_validate_json(response.text)
        if valid.records:
            conn.logger.info(f"获取其他考试信息成功，共 {len(valid.records)} 条记录")
            return valid.records
        else:
            conn.logger.warning("获取其他考试信息成功，但无记录")
            return []

    except Exception as e:
        conn.logger.error(f"获取其他考试信息出现如下异常: {str(e)}")
        return []


def convert_other_exam_to_unified(
    record: OtherExamRecord, conn: AUFEConnection
) -> Optional[UnifiedExamInfo]:
    """
    将其他考试记录转换为统一格式

    Args:
        record: 其他考试记录

    Returns:
        Optional[UnifiedExamInfo]: 统一格式的考试信息
    """
    try:
        return UnifiedExamInfo(
            course_name=record.course_name,
            exam_date=record.exam_date,
            exam_time=record.exam_time,
            exam_location=record.exam_location,
            exam_type="其他考试",
            note=record.note,
        )

    except Exception as e:
        conn.logger.error(f"转换其他考试数据异常: {str(e)}")
        return None


async def fetch_unified_exam_info(
    conn: AUFEConnection,
    start_date: str,
    end_date: str,
    term_code: str = "2024-2025-2-1",
) -> ExamInfoResponse:
    """
    获取统一的考试信息，包括校统考和其他考试

    Args:
        start_date: 开始日期 (YYYY-MM-DD)
        end_date: 结束日期 (YYYY-MM-DD)
        term_code: 学期代码，默认为当前学期

    Returns:
        ExamInfoResponse: 统一的考试信息响应
    """
    try:
        # 合并并转换为统一格式
        unified_exams = []
        # 获取校统考信息
        if school_exams := await fetch_school_exam_schedule(start_date, end_date, conn):
            # 获取座位号信息
            seat_info = await fetch_exam_seat_info(conn)
            # 处理校统考数据
            for exam in school_exams:
                unified_exam = convert_school_exam_to_unified(exam, seat_info, conn)
                if unified_exam:
                    unified_exams.append(unified_exam)

        # 获取其他考试信息
        other_exams = await fetch_other_exam_records(term_code, conn)
        # 处理其他考试数据
        for record in other_exams:
            unified_exam = convert_other_exam_to_unified(record, conn)
            if unified_exam:
                unified_exams.append(unified_exam)

        # 按考试日期排序
        def _sort_key(exam: UnifiedExamInfo) -> str:
            return exam.exam_date + " " + exam.exam_time

        unified_exams.sort(key=_sort_key)

        return ExamInfoResponse(
            exams=unified_exams,
            total_count=len(unified_exams),
        )

    except Exception:
        raise
