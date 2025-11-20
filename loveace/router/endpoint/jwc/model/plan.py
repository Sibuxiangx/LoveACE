import re
from typing import List, Optional

from pydantic import BaseModel, Field


class PlanCompletionCourse(BaseModel):
    """培养方案课程完成情况"""

    flag_id: str = Field("", description="课程标识ID")
    flag_type: str = Field("", description="节点类型：001=分类, 002=子分类, kch=课程")
    course_code: str = Field("", description="课程代码，如 PDA2121005")
    course_name: str = Field("", description="课程名称")
    is_passed: bool = Field(False, description="是否通过（基于CSS图标解析）")
    status_description: str = Field("", description="状态描述：未修读/已通过/未通过")
    credits: Optional[float] = Field(None, description="学分")
    score: Optional[str] = Field(None, description="成绩")
    exam_date: Optional[str] = Field(None, description="考试日期")
    course_type: str = Field("", description="课程类型：必修/任选等")
    parent_id: str = Field("", description="父节点ID")
    level: int = Field(0, description="层级：0=根分类，1=子分类，2=课程")

    @classmethod
    def from_ztree_node(cls, node: dict) -> "PlanCompletionCourse":
        """从 zTree 节点数据创建课程对象"""
        # 解析name字段中的信息
        name = node.get("name", "")
        flag_id = node.get("flagId", "")
        flag_type = node.get("flagType", "")
        parent_id = node.get("pId", "")

        # 根据CSS图标判断通过状态
        is_passed = False
        status_description = "未修读"

        if "fa-smile-o fa-1x green" in name:
            is_passed = True
            status_description = "已通过"
        elif "fa-meh-o fa-1x light-grey" in name:
            is_passed = False
            status_description = "未修读"
        elif "fa-frown-o fa-1x red" in name:
            is_passed = False
            status_description = "未通过"

        # 从name中提取纯文本内容
        # 移除HTML标签和图标
        clean_name = re.sub(r"<[^>]*>", "", name)
        clean_name = re.sub(r"&nbsp;", " ", clean_name).strip()

        # 解析课程信息
        course_code = ""
        course_name = ""
        credits = None
        score = None
        exam_date = None
        course_type = ""

        if flag_type == "kch":  # 课程节点
            # 解析课程代码：[PDA2121005]形势与政策
            code_match = re.search(r"\[([^\]]+)\]", clean_name)
            if code_match:
                course_code = code_match.group(1)
                remaining_text = clean_name.split("]", 1)[1].strip()

                # 解析学分信息：[0.3学分]
                credit_match = re.search(r"\[([0-9.]+)学分\]", remaining_text)
                if credit_match:
                    credits = float(credit_match.group(1))
                    remaining_text = re.sub(
                        r"\[[0-9.]+学分\]", "", remaining_text
                    ).strip()

                # 处理复杂的括号内容
                # 例如：85.0(20250626 成绩，都没把日期解析上，中国近现代史纲要)
                # 或者：(任选,87.0(20250119))

                # 找到最外层的括号
                paren_match = re.search(
                    r"\(([^)]+(?:\([^)]*\)[^)]*)*)\)$", remaining_text
                )
                if paren_match:
                    paren_content = paren_match.group(1)
                    course_name_candidate = re.sub(
                        r"\([^)]+(?:\([^)]*\)[^)]*)*\)$", "", remaining_text
                    ).strip()

                    # 检查括号内容的格式
                    if "，" in paren_content:
                        # 处理包含中文逗号的复杂格式
                        parts = paren_content.split("，")

                        # 最后一部分可能是课程名
                        last_part = parts[-1].strip()
                        if (
                            re.search(r"[\u4e00-\u9fff]", last_part)
                            and len(last_part) > 1
                        ):
                            # 最后一部分包含中文，很可能是真正的课程名
                            course_name = last_part

                            # 从前面的部分提取成绩和其他信息
                            remaining_parts = "，".join(parts[:-1])

                            # 提取成绩
                            score_match = re.search(r"([0-9.]+)", remaining_parts)
                            if score_match:
                                score = score_match.group(1)

                            # 提取日期
                            date_match = re.search(r"(\d{8})", remaining_parts)
                            if date_match:
                                exam_date = date_match.group(1)

                            # 提取课程类型（如果有的话）
                            if len(parts) > 2:
                                potential_type = parts[0].strip()
                                if not re.search(r"[0-9.]", potential_type):
                                    course_type = potential_type
                        else:
                            # 最后一部分不是课程名，使用括号外的内容
                            course_name = (
                                course_name_candidate
                                if course_name_candidate
                                else "未知课程"
                            )

                            # 从整个括号内容提取信息
                            score_match = re.search(r"([0-9.]+)", paren_content)
                            if score_match:
                                score = score_match.group(1)

                            date_match = re.search(r"(\d{8})", paren_content)
                            if date_match:
                                exam_date = date_match.group(1)

                    elif "," in paren_content:
                        # 处理标准格式：(任选,87.0(20250119))
                        type_score_parts = paren_content.split(",", 1)
                        if len(type_score_parts) == 2:
                            course_type = type_score_parts[0].strip()
                            score_info = type_score_parts[1].strip()

                            # 解析成绩和日期
                            score_date_match = re.search(
                                r"([0-9.]+)\((\d{8})\)", score_info
                            )
                            if score_date_match:
                                score = score_date_match.group(1)
                                exam_date = score_date_match.group(2)
                            else:
                                score_match = re.search(r"([0-9.]+)", score_info)
                                if score_match:
                                    score = score_match.group(1)

                            # 使用括号外的内容作为课程名
                            course_name = (
                                course_name_candidate
                                if course_name_candidate
                                else "未知课程"
                            )

                    else:
                        # 括号内只有简单内容
                        course_name = (
                            course_name_candidate
                            if course_name_candidate
                            else "未知课程"
                        )

                        # 尝试从括号内容提取成绩
                        score_match = re.search(r"([0-9.]+)", paren_content)
                        if score_match:
                            score = score_match.group(1)

                        # 尝试提取日期
                        date_match = re.search(r"(\d{8})", paren_content)
                        if date_match:
                            exam_date = date_match.group(1)
                else:
                    # 没有括号，直接使用剩余文本作为课程名
                    course_name = remaining_text

                # 清理课程名
                course_name = re.sub(r"\s+", " ", course_name).strip()
                course_name = course_name.strip("，,。.")

                # 如果课程名为空或太短，尝试从原始名称提取
                if not course_name or len(course_name) < 2:
                    chinese_match = re.search(
                        r"[\u4e00-\u9fff]+(?:[\u4e00-\u9fff\s]*[\u4e00-\u9fff]+)*",
                        clean_name,
                    )
                    if chinese_match:
                        course_name = chinese_match.group(0).strip()
                    else:
                        course_name = clean_name
        else:
            # 分类节点
            course_name = clean_name

            # 清理分类名称中的多余括号，但保留重要信息
            # 如果是包含学分信息的分类名，保留学分信息
            if not re.search(r"学分", course_name):
                # 删除分类名称中的统计信息括号，如 "通识通修(已完成20.0/需要20.0)"
                course_name = re.sub(r"\([^)]*完成[^)]*\)", "", course_name).strip()
                # 删除其他可能的统计括号
                course_name = re.sub(
                    r"\([^)]*\d+\.\d+/[^)]*\)", "", course_name
                ).strip()

            # 清理多余的空格和空括号
            course_name = re.sub(r"\(\s*\)", "", course_name).strip()
            course_name = re.sub(r"\s+", " ", course_name).strip()

        # 确定层级
        level = 0
        if flag_type == "002":
            level = 1
        elif flag_type == "kch":
            level = 2

        return cls(
            flag_id=flag_id,
            flag_type=flag_type,
            course_code=course_code,
            course_name=course_name,
            is_passed=is_passed,
            status_description=status_description,
            credits=credits,
            score=score,
            exam_date=exam_date,
            course_type=course_type,
            parent_id=parent_id,
            level=level,
        )


class PlanCompletionCategory(BaseModel):
    """培养方案分类完成情况"""

    category_id: str = Field("", description="分类ID")
    category_name: str = Field("", description="分类名称")
    min_credits: float = Field(0.0, description="最低修读学分")
    completed_credits: float = Field(0.0, description="通过学分")
    total_courses: int = Field(0, description="已修课程门数")
    passed_courses: int = Field(0, description="已及格课程门数")
    failed_courses: int = Field(0, description="未及格课程门数")
    missing_required_courses: int = Field(0, description="必修课缺修门数")
    subcategories: List["PlanCompletionCategory"] = Field(
        default_factory=list, description="子分类"
    )
    courses: List[PlanCompletionCourse] = Field(
        default_factory=list, description="课程列表"
    )

    @classmethod
    def from_ztree_node(cls, node: dict) -> "PlanCompletionCategory":
        """从 zTree 节点创建分类对象"""
        name = node.get("name", "")
        flag_id = node.get("flagId", "")

        # 移除HTML标签获取纯文本
        clean_name = re.sub(r"<[^>]*>", "", name)
        clean_name = re.sub(r"&nbsp;", " ", clean_name).strip()

        # 解析分类统计信息
        # 格式：通识通修(最低修读学分:68,通过学分:34.4,已修课程门数:26,已及格课程门数:26,未及格课程门数:0,必修课缺修门数:12)
        stats_match = re.search(
            r"([^(]+)\(最低修读学分:([0-9.]+),通过学分:([0-9.]+),已修课程门数:(\d+),已及格课程门数:(\d+),未及格课程门数:(\d+),必修课缺修门数:(\d+)\)",
            clean_name,
        )

        if stats_match:
            category_name = stats_match.group(1)
            min_credits = float(stats_match.group(2))
            completed_credits = float(stats_match.group(3))
            total_courses = int(stats_match.group(4))
            passed_courses = int(stats_match.group(5))
            failed_courses = int(stats_match.group(6))
            missing_required_courses = int(stats_match.group(7))
        else:
            # 子分类可能没有完整的统计信息
            category_name = clean_name
            min_credits = 0.0
            completed_credits = 0.0
            total_courses = 0
            passed_courses = 0
            failed_courses = 0
            missing_required_courses = 0

        return cls(
            category_id=flag_id,
            category_name=category_name,
            min_credits=min_credits,
            completed_credits=completed_credits,
            total_courses=total_courses,
            passed_courses=passed_courses,
            failed_courses=failed_courses,
            missing_required_courses=missing_required_courses,
        )


class PlanCompletionInfo(BaseModel):
    """培养方案完成情况总信息"""

    plan_name: str = Field("", description="培养方案名称")
    major: str = Field("", description="专业名称")
    grade: str = Field("", description="年级")
    categories: List[PlanCompletionCategory] = Field(
        default_factory=list, description="分类列表"
    )
    total_categories: int = Field(0, description="总分类数")
    total_courses: int = Field(0, description="总课程数")
    passed_courses: int = Field(0, description="已通过课程数")
    failed_courses: int = Field(0, description="未通过课程数")
    unread_courses: int = Field(0, description="未修读课程数")

    def calculate_statistics(self):
        """计算统计信息"""
        total_courses = 0
        passed_courses = 0
        failed_courses = 0
        unread_courses = 0

        def count_courses(categories: List[PlanCompletionCategory]):
            nonlocal total_courses, passed_courses, failed_courses, unread_courses

            for category in categories:
                for course in category.courses:
                    total_courses += 1
                    if course.is_passed:
                        passed_courses += 1
                    elif course.status_description == "未通过":
                        failed_courses += 1
                    else:
                        unread_courses += 1

                # 递归处理子分类
                count_courses(category.subcategories)

        count_courses(self.categories)

        self.total_categories = len(self.categories)
        self.total_courses = total_courses
        self.passed_courses = passed_courses
        self.failed_courses = failed_courses
        self.unread_courses = unread_courses
