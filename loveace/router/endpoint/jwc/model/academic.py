from typing import List

from pydantic import BaseModel, Field

from loveace.router.endpoint.jwc.utils.zxjxjhh_to_term_format import (
    convert_zxjxjhh_to_term_format,
)


class AcademicInfoTransformer(BaseModel):
    """学术信息数据项"""

    completed_courses: int = Field(0, alias="courseNum")
    failed_courses: int = Field(0, alias="coursePas")
    gpa: float = Field(0, alias="gpa")
    current_term: str = Field("", alias="zxjxjhh")
    pending_courses: int = Field(0, alias="courseNum_bxqyxd")

    def to_academic_info(self) -> "AcademicInfo":
        """转换为 AcademicInfo"""
        return AcademicInfo(
            completed_courses=self.completed_courses,
            failed_courses=self.failed_courses,
            pending_courses=self.pending_courses,
            gpa=self.gpa,
            current_term=self.current_term,
            current_term_name=convert_zxjxjhh_to_term_format(self.current_term),
        )


class AcademicInfo(BaseModel):
    """学术信息数据模型"""

    completed_courses: int = Field(0, description="已修课程数")
    failed_courses: int = Field(0, description="不及格课程数")
    pending_courses: int = Field(0, description="本学期待修课程数")
    gpa: float = Field(0, description="绩点")
    current_term: str = Field("", description="当前学期")
    current_term_name: str = Field("", description="当前学期名称")


class TrainingPlanInfoTransformer(BaseModel):
    """培养方案响应模型"""

    count: int = 0
    data: List[List[str]] = []


class TrainingPlanInfo(BaseModel):
    """培养方案信息模型"""

    plan_name: str = Field("", description="培养方案名称")
    major_name: str = Field("", description="专业名称")
    grade: str = Field("", description="年级")


class CourseSelectionStatusTransformer(BaseModel):
    """选课状态响应模型新格式"""

    term_name: str = Field("", alias="zxjxjhm")
    status_code: str = Field("", alias="retString")


class CourseSelectionStatus(BaseModel):
    """选课状态信息"""

    can_select: bool = Field(False, description="是否可以选课")
