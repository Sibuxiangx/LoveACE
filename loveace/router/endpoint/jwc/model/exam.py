from typing import Dict, List, Optional

from pydantic import BaseModel, Field


class ExamScheduleItem(BaseModel):
    """考试安排项目 - 校统考格式"""

    title: str = ""  # 考试标题，包含课程名、时间、地点等信息
    start: str = ""  # 考试日期 (YYYY-MM-DD)
    color: str = ""  # 显示颜色


class OtherExamRecord(BaseModel):
    """其他考试记录"""

    term_code: str = Field("", alias="ZXJXJHH")  # 学期代码
    term_name: str = Field("", alias="ZXJXJHM")  # 学期名称
    exam_name: str = Field("", alias="KSMC")  # 考试名称
    course_code: str = Field("", alias="KCH")  # 课程代码
    course_name: str = Field("", alias="KCM")  # 课程名称
    class_number: str = Field("", alias="KXH")  # 课序号
    student_id: str = Field("", alias="XH")  # 学号
    student_name: str = Field("", alias="XM")  # 姓名
    exam_location: str = Field("", alias="KSDD")  # 考试地点
    exam_date: str = Field("", alias="KSRQ")  # 考试日期
    exam_time: str = Field("", alias="KSSJ")  # 考试时间
    note: str = Field("", alias="BZ")  # 备注
    row_number: str = Field("", alias="RN")  # 行号


class OtherExamResponse(BaseModel):
    """其他考试查询响应"""

    page_size: int = Field(0, alias="pageSize")
    page_num: int = Field(0, alias="pageNum")
    page_context: Dict[str, int] = Field(default_factory=dict, alias="pageContext")
    records: Optional[List[OtherExamRecord]] = Field(alias="records")


class UnifiedExamInfo(BaseModel):
    """统一考试信息模型 - 对外提供的统一格式"""

    course_name: str = Field("", description="课程名称")
    exam_date: str = Field("", description="考试日期")
    exam_time: str = Field("", description="考试时间")
    exam_location: str = Field("", description="考试地点")
    exam_type: str = Field("", description="考试类型")
    note: str = Field("", description="备注")


class ExamInfoResponse(BaseModel):
    """考试信息统一响应模型"""

    exams: List[UnifiedExamInfo] = Field(
        default_factory=list, description="考试信息列表"
    )
    total_count: int = Field(0, description="考试总数")


class SeatInfo(BaseModel):
    """座位信息模型"""

    course_name: str = Field("", description="课程名称")
    seat_number: str = Field("", description="座位号")
