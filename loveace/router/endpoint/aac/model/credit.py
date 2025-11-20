from typing import List

from pydantic import BaseModel, Field


class LoveACCreditInfo(BaseModel):
    """爱安财总分信息"""

    total_score: float = Field(
        0.0, alias="TotalScore", description="总分，爱安财服务端已四舍五入"
    )
    is_type_adopt: bool = Field(
        False, alias="IsTypeAdopt", description="是否达到毕业要求"
    )
    type_adopt_result: str = Field(
        "", alias="TypeAdoptResult", description="未达到毕业要求的原因"
    )


class LoveACCreditItem(BaseModel):
    """爱安财分数明细条目"""

    id: str = Field("", alias="ID", description="条目ID")
    title: str = Field("", alias="Title", description="条目标题")
    type_name: str = Field("", alias="TypeName", description="条目类别名称")
    user_no: str = Field("", alias="UserNo", description="用户编号，即学号")
    score: float = Field(0.0, alias="Score", description="分数")
    add_time: str = Field("", alias="AddTime", description="添加时间")


class LoveACCreditCategory(BaseModel):
    """爱安财分数类别"""

    id: str = Field("", alias="ID", description="类别ID")
    show_num: int = Field(0, alias="ShowNum", description="显示序号")
    type_name: str = Field("", alias="TypeName", description="类别名称")
    total_score: float = Field(0.0, alias="TotalScore", description="类别总分")
    children: List[LoveACCreditItem] = Field(
        [], alias="children", description="该类别下的分数明细列表"
    )
