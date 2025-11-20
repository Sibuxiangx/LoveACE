from typing import List, Optional

from pydantic import BaseModel, Field


class ScoreRecord(BaseModel):
    """成绩记录模型"""

    sequence: int = Field(0, description="序号")
    term_id: str = Field("", description="学期ID")
    course_code: str = Field("", description="课程代码")
    course_class: str = Field("", description="课程班级")
    course_name_cn: str = Field("", description="课程名称（中文）")
    course_name_en: str = Field("", description="课程名称（英文）")
    credits: str = Field("", description="学分")
    hours: int = Field(0, description="学时")
    course_type: Optional[str] = Field(None, description="课程性质")
    exam_type: Optional[str] = Field(None, description="考试性质")
    score: str = Field("", description="成绩")
    retake_score: Optional[str] = Field(None, description="重修成绩")
    makeup_score: Optional[str] = Field(None, description="补考成绩")


class TermScoreResponse(BaseModel):
    """学期成绩响应模型"""

    total_count: int = Field(0, description="总记录数")
    records: List[ScoreRecord] = Field(default_factory=list, description="成绩记录列表")
