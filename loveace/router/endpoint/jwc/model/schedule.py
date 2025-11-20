from typing import List

from pydantic import BaseModel, Field


class TimeSlot(BaseModel):
    """时间段模型"""

    session: int = Field(..., description="节次")
    session_name: str = Field(..., description="节次名称")
    start_time: str = Field(..., description="开始时间，格式：HHMM")
    end_time: str = Field(..., description="结束时间，格式：HHMM")
    time_length: str = Field(..., description="时长（分钟）")
    djjc: int = Field(..., description="大节节次")


class CourseTimeLocation(BaseModel):
    """课程时间地点模型"""

    class_day: int = Field(..., description="上课星期几（1-7）")
    class_sessions: int = Field(..., description="上课节次")
    continuing_session: int = Field(..., description="持续节次数")
    class_week: str = Field(..., description="上课周次（24位二进制字符串）")
    week_description: str = Field(..., description="上课周次描述")
    campus_name: str = Field(..., description="校区名称")
    teaching_building_name: str = Field(..., description="教学楼名称")
    classroom_name: str = Field(..., description="教室名称")


class ScheduleCourse(BaseModel):
    """课表课程模型"""

    course_name: str = Field(..., description="课程名称")
    course_code: str = Field(..., description="课程代码")
    course_sequence: str = Field(..., description="课程序号")
    teacher_name: str = Field(..., description="授课教师")
    course_properties: str = Field(..., description="课程性质")
    exam_type: str = Field(..., description="考试类型")
    unit: float = Field(..., description="学分")
    time_locations: List[CourseTimeLocation] = Field(..., description="时间地点列表")
    is_no_schedule: bool = Field(False, description="是否无具体时间安排")


class ScheduleData(BaseModel):
    """课表数据模型"""

    total_units: float = Field(..., description="总学分")
    time_slots: List[TimeSlot] = Field(..., description="时间段列表")
    courses: List[ScheduleCourse] = Field(..., description="课程列表")
