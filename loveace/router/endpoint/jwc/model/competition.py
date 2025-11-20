from typing import List, Optional

from pydantic import BaseModel, Field


class AwardProject(BaseModel):
    """
    获奖项目信息模型

    表示用户通过创新创业管理平台申报的单个获奖项目
    """

    project_id: str = Field("", description="申报ID，唯一标识符")
    project_name: str = Field("", description="项目名称/赛事名称")
    level: str = Field("", description="级别（校级/省部级/国家级等）")
    grade: str = Field("", description="等级/奖项等级（一等奖/二等奖等）")
    award_date: str = Field("", description="获奖日期，格式为 YYYY/M/D")
    applicant_id: str = Field("", description="主持人姓名")
    applicant_name: str = Field("", description="参与人姓名（作为用户）")
    order: int = Field(0, description="顺序号（多人项目的排序）")
    credits: float = Field(0.0, description="获奖学分")
    bonus: float = Field(0.0, description="奖励金额")
    status: str = Field("", description="申报状态（提交/审核中/已审核等）")
    verification_status: str = Field(
        "", description="学校审核状态（通过/未通过/待审核等）"
    )


class CreditsSummary(BaseModel):
    """
    学分汇总信息模型

    存储用户在创新创业管理平台的各类学分统计
    """

    discipline_competition_credits: Optional[float] = Field(
        None, description="学科竞赛学分"
    )
    scientific_research_credits: Optional[float] = Field(
        None, description="科研项目学分"
    )
    transferable_competition_credits: Optional[float] = Field(
        None, description="可转竞赛类学分"
    )
    innovation_practice_credits: Optional[float] = Field(
        None, description="创新创业实践学分"
    )
    ability_certification_credits: Optional[float] = Field(
        None, description="能力资格认证学分"
    )
    other_project_credits: Optional[float] = Field(None, description="其他项目学分")


class CompetitionAwardsResponse(BaseModel):
    """
    获奖项目列表响应模型
    """

    student_id: str = Field("", description="学生ID/工号")
    total_count: int = Field(0, description="获奖项目总数")
    awards: List[AwardProject] = Field(default_factory=list, description="获奖项目列表")


class CompetitionCreditsSummaryResponse(BaseModel):
    """
    学分汇总响应模型
    """

    student_id: str = Field("", description="学生ID/工号")
    credits_summary: Optional[CreditsSummary] = Field(None, description="学分汇总详情")


class CompetitionFullResponse(BaseModel):
    """
    学科竞赛完整信息响应模型

    整合了获奖项目列表和学分汇总信息，减少网络IO调用
    在单次请求中返回所有竞赛相关数据
    """

    student_id: str = Field("", description="学生ID/工号")
    total_awards_count: int = Field(0, description="获奖项目总数")
    awards: List[AwardProject] = Field(default_factory=list, description="获奖项目列表")
    credits_summary: Optional[CreditsSummary] = Field(None, description="学分汇总详情")
