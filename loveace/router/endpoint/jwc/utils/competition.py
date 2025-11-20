from typing import Optional

from bs4 import BeautifulSoup

from loveace.router.endpoint.jwc.model.competition import (
    AwardProject,
    CompetitionAwardsResponse,
    CompetitionCreditsSummaryResponse,
    CompetitionFullResponse,
    CreditsSummary,
)


class CompetitionInfoParser:
    """
    创新创业管理平台信息解析器

    功能：
        - 解析获奖项目列表（表格数据）
        - 解析学分汇总信息
        - 提取学生基本信息
    """

    def __init__(self, html_content: str):
        """
        初始化解析器

        参数:
            html_content: HTML页面内容字符串
        """
        self.soup = BeautifulSoup(html_content, "html.parser")

    def parse_awards(self) -> CompetitionAwardsResponse:
        """
        解析获奖项目列表

        返回:
            CompetitionAwardsResponse: 包含获奖项目列表的响应对象
        """
        # 解析学生ID
        student_id = self._parse_student_id()

        # 解析项目列表
        projects = self._parse_projects()

        response = CompetitionAwardsResponse(
            student_id=student_id,
            total_count=len(projects),
            awards=projects,
        )

        return response

    def parse_credits_summary(self) -> CompetitionCreditsSummaryResponse:
        """
        解析学分汇总信息

        返回:
            CompetitionCreditsSummaryResponse: 包含学分汇总信息的响应对象
        """
        # 解析学生ID
        student_id = self._parse_student_id()

        # 解析学分汇总
        credits_summary = self._parse_credits_summary()

        response = CompetitionCreditsSummaryResponse(
            student_id=student_id,
            credits_summary=credits_summary,
        )

        return response

    def parse_full_competition_info(self) -> CompetitionFullResponse:
        """
        解析完整的学科竞赛信息（获奖项目 + 学分汇总）

        一次性解析HTML，同时提取获奖项目列表和学分汇总信息，
        减少网络IO和数据库查询次数

        返回:
            CompetitionFullResponse: 包含完整竞赛信息的响应对象
        """
        # 解析学生ID
        student_id = self._parse_student_id()

        # 解析项目列表
        projects = self._parse_projects()

        # 解析学分汇总
        credits_summary = self._parse_credits_summary()

        response = CompetitionFullResponse(
            student_id=student_id,
            total_awards_count=len(projects),
            awards=projects,
            credits_summary=credits_summary,
        )

        return response

    def _parse_student_id(self) -> str:
        """
        解析学生基本信息 - 学生ID/工号

        返回:
            str: 学生ID，如果未找到返回空字符串
        """
        student_span = self.soup.find("span", id="ContentPlaceHolder1_lblXM")
        if student_span:
            text = student_span.get_text(strip=True)
            # 格式: "欢迎您：20244787"
            if "：" in text:
                return text.split("：")[1].strip()
        return ""

    def _parse_projects(self) -> list:
        """
        解析获奖项目列表

        数据来源: 页面中ID为 ContentPlaceHolder1_ContentPlaceHolder2_gvHj 的表格

        表格结构:
            - 第一行为表头
            - 后续行为项目数据
            - 包含15列数据

        返回:
            list[AwardProject]: 获奖项目列表
        """
        projects = []

        # 查找项目列表表格
        table = self.soup.find(
            "table", id="ContentPlaceHolder1_ContentPlaceHolder2_gvHj"
        )
        if not table:
            return projects

        rows = table.find_all("tr")
        # 跳过表头行（第一行）
        for row in rows[1:]:
            cells = row.find_all("td")
            if len(cells) < 9:  # 至少需要9列数据
                continue

            try:
                project = AwardProject(
                    project_id=cells[0].get_text(strip=True),
                    project_name=cells[1].get_text(strip=True),
                    level=cells[2].get_text(strip=True),
                    grade=cells[3].get_text(strip=True),
                    award_date=cells[4].get_text(strip=True),
                    applicant_id=cells[5].get_text(strip=True),
                    applicant_name=cells[6].get_text(strip=True),
                    order=int(cells[7].get_text(strip=True)),
                    credits=float(cells[8].get_text(strip=True)),
                    bonus=float(cells[9].get_text(strip=True)),
                    status=cells[10].get_text(strip=True),
                    verification_status=cells[11].get_text(strip=True),
                )
                projects.append(project)
            except (ValueError, IndexError):
                # 数据格式异常，记录但继续处理
                continue

        return projects

    def _parse_credits_summary(self) -> Optional[CreditsSummary]:
        """
        解析学分汇总信息

        数据来源: 页面中的学分汇总表中的各类学分 span 元素

        提取内容:
            - 学科竞赛学分
            - 科研项目学分
            - 可转竞赛类学分
            - 创新创业实践学分
            - 能力资格认证学分
            - 其他项目学分

        返回:
            CreditsSummary: 学分汇总对象，如果无法解析则返回 None
        """
        discipline_competition_credits = None
        scientific_research_credits = None
        transferable_competition_credits = None
        innovation_practice_credits = None
        ability_certification_credits = None
        other_project_credits = None

        # 查找学科竞赛学分
        xkjs_span = self.soup.find(
            "span", id="ContentPlaceHolder1_ContentPlaceHolder2_lblXkjsxf"
        )
        if xkjs_span:
            text = xkjs_span.get_text(strip=True)
            discipline_competition_credits = self._parse_credit_value(text)

        # 查找科研项目学分
        ky_span = self.soup.find(
            "span", id="ContentPlaceHolder1_ContentPlaceHolder2_lblKyxf"
        )
        if ky_span:
            text = ky_span.get_text(strip=True)
            scientific_research_credits = self._parse_credit_value(text)

        # 查找可转竞赛类学分
        kzjsl_span = self.soup.find(
            "span", id="ContentPlaceHolder1_ContentPlaceHolder2_lblKzjslxf"
        )
        if kzjsl_span:
            text = kzjsl_span.get_text(strip=True)
            transferable_competition_credits = self._parse_credit_value(text)

        # 查找创新创业实践学分
        cxcy_span = self.soup.find(
            "span", id="ContentPlaceHolder1_ContentPlaceHolder2_lblCxcyxf"
        )
        if cxcy_span:
            text = cxcy_span.get_text(strip=True)
            innovation_practice_credits = self._parse_credit_value(text)

        # 查找能力资格认证学分
        nlzg_span = self.soup.find(
            "span", id="ContentPlaceHolder1_ContentPlaceHolder2_lblNlzgxf"
        )
        if nlzg_span:
            text = nlzg_span.get_text(strip=True)
            ability_certification_credits = self._parse_credit_value(text)

        # 查找其他项目学分
        qt_span = self.soup.find(
            "span", id="ContentPlaceHolder1_ContentPlaceHolder2_lblQtxf"
        )
        if qt_span:
            text = qt_span.get_text(strip=True)
            other_project_credits = self._parse_credit_value(text)

        return CreditsSummary(
            discipline_competition_credits=discipline_competition_credits,
            scientific_research_credits=scientific_research_credits,
            transferable_competition_credits=transferable_competition_credits,
            innovation_practice_credits=innovation_practice_credits,
            ability_certification_credits=ability_certification_credits,
            other_project_credits=other_project_credits,
        )

    @staticmethod
    def _parse_credit_value(text: str) -> Optional[float]:
        """
        解析学分值

        参数:
            text: 文本值，可能为"0", "16.60", "无"等

        返回:
            float: 学分值，如果为"无"或无法解析则返回 None
        """
        text = text.strip()
        if text == "无" or text == "":
            return None
        try:
            return float(text)
        except ValueError:
            return None
