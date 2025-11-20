from pydantic import BaseModel, Field


class TermItem(BaseModel):
    """学期信息项"""

    term_code: str = Field(..., description="学期代码")
    term_name: str = Field(..., description="学期名称")
    is_current: bool = Field(..., description="是否为当前学期")


class CurrentTermInfo(BaseModel):
    """学期周数信息"""

    academic_year: str = Field("", description="学年，如 2025-2026")
    current_term_name: str = Field("", description="学期，如 秋、春")
    week_number: int = Field(0, description="当前周数")
    start_at: str = Field("", description="学期开始时间,格式 YYYY-MM-DD")
    is_end: bool = Field(False, description="是否为学期结束")
    weekday: int = Field(0, description="星期几")