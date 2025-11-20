import re
from datetime import datetime

from bs4 import BeautifulSoup
from fastapi import APIRouter, Depends
from fastapi.responses import JSONResponse
from httpx import HTTPError
from pydantic import ValidationError

from loveace.router.endpoint.jwc.model.base import JWCConfig
from loveace.router.endpoint.jwc.model.term import CurrentTermInfo, TermItem
from loveace.router.schemas.error import ProtectRouterErrorToCode
from loveace.router.schemas.uniresponse import UniResponseModel
from loveace.service.remote.aufe import AUFEConnection
from loveace.service.remote.aufe.depends import get_aufe_conn

jwc_term_router = APIRouter(
    prefix="/term",
    responses=ProtectRouterErrorToCode().gen_code_table(),
)

ENDPOINT = {
    "all_terms": "/student/courseSelect/calendarSemesterCurriculum/index",
    "calendar": "/indexCalendar",
}


@jwc_term_router.get(
    "/all",
    summary="获取所有学期信息",
    response_model=UniResponseModel[list[TermItem]],
)
async def get_all_terms(
    conn: AUFEConnection = Depends(get_aufe_conn),
) -> UniResponseModel[list[TermItem]] | JSONResponse:
    """
    获取用户可选的所有学期列表

    ✅ 功能特性：
       - 获取从入学至今的所有学期
       - 标记当前学期
       - 学期名称格式统一处理

    💡 使用场景：
       - 选课系统的学期选择菜单
       - 成绩查询的学期选择
       - 课程表查询的学期选择

    Returns:
        list[TermItem]: 学期列表，包含学期代码、名称、是否为当前学期
    """
    try:
        all_terms = []
        response = await conn.client.get(
            JWCConfig().to_full_url(ENDPOINT["all_terms"]),
            follow_redirects=True,
            timeout=conn.timeout,
        )
        if response.status_code != 200:
            conn.logger.error(f"获取学期信息失败，状态码: {response.status_code}")
            return ProtectRouterErrorToCode().remote_service_error.to_json_response(
                conn.logger.trace_id
            )
        # 解析HTML获取学期选项
        soup = BeautifulSoup(response.text, "lxml")

        # 查找学期选择下拉框
        select_element = soup.find("select", {"id": "planCode"})
        if not select_element:
            conn.logger.error("未找到学期选择框")
            return UniResponseModel[list[TermItem]](
                success=False,
                data=[],
                message="未找到学期选择框",
                error=None,
            )

        terms = {}
        # 使用更安全的方式处理选项
        try:
            options = select_element.find_all("option")  # type: ignore
            for option in options:
                value = option.get("value")  # type: ignore
                text = option.get_text(strip=True)  # type: ignore

                # 跳过空值选项（如"全部"）
                if value and str(value).strip() and text != "全部":
                    terms[str(value)] = text
        except AttributeError:
            conn.logger.error("解析学期选项失败")
            return UniResponseModel[list[TermItem]](
                success=False,
                data=[],
                message="解析学期选项失败",
                error=None,
            )

        conn.logger.info(f"成功获取{len(terms)}个学期信息")
        counter = 0
        # 遍历学期选项，提取学期代码和名称
        # 将学期中的 "春" 替换为 "下" ， "秋" 替换为 "上"
        for key, value in terms.items():
            counter += 1
            value = value.replace("春", "下").replace("秋", "上")
            all_terms.append(
                TermItem(term_code=key, term_name=value, is_current=counter == 1)
            )

        return UniResponseModel[list[TermItem]](
            success=True,
            data=all_terms,
            message="获取学期信息成功",
            error=None,
        )
    except ValidationError as ve:
        conn.logger.error(f"数据验证错误: {ve}")
        return ProtectRouterErrorToCode().validation_error.to_json_response(
            conn.logger.trace_id
        )
    except HTTPError as he:
        conn.logger.error(f"HTTP请求错误: {he}")
        return ProtectRouterErrorToCode().remote_service_error.to_json_response(
            conn.logger.trace_id
        )
    except Exception as e:
        conn.logger.exception(e)
        return ProtectRouterErrorToCode().server_error.to_json_response(
            conn.logger.trace_id
        )


@jwc_term_router.get(
    "/current",
    summary="获取当前学期信息",
    response_model=UniResponseModel[CurrentTermInfo],
)
async def get_current_term(
    conn: AUFEConnection = Depends(get_aufe_conn),
) -> UniResponseModel[CurrentTermInfo] | JSONResponse:
    """
    获取当前学期的详细信息

    ✅ 功能特性：
       - 获取当前学期的开始和结束日期
       - 获取学期周数信息
       - 实时从教务系统获取

    💡 使用场景：
       - 显示当前学期进度
       - 课程表的周次显示参考
       - 学期时间提醒

    Returns:
        CurrentTermInfo: 包含学期代码、名称、开始日期、结束日期等
    """
    try:
        info_response = await conn.client.get(
            JWCConfig().DEFAULT_BASE_URL, follow_redirects=True, timeout=conn.timeout
        )
        if info_response.status_code != 200:
            conn.logger.error(
                f"获取学期信息页面失败，状态码: {info_response.status_code}"
            )
            return ProtectRouterErrorToCode().remote_service_error.to_json_response(
                conn.logger.trace_id
            )

        start_response = await conn.client.get(
            JWCConfig().to_full_url(ENDPOINT["calendar"]),
            follow_redirects=True,
            timeout=conn.timeout,
        )
        if start_response.status_code != 200:
            conn.logger.error(
                f"获取学期开始时间失败，状态码: {start_response.status_code}"
            )
            return ProtectRouterErrorToCode().remote_service_error.to_json_response(
                conn.logger.trace_id
            )
        # 提取学期开始时间
        flexible_pattern = r'var\s+rq\s*=\s*"(\d{8})";\s*//.*'
        match = re.findall(flexible_pattern, start_response.text)
        if not match:
            conn.logger.error("未找到学期开始时间")
            return ProtectRouterErrorToCode().remote_service_error.to_json_response(
                conn.logger.trace_id
            )
        start_date_str = match[0]
        try:
            start_date = datetime.strptime(start_date_str, "%Y%m%d").date()
        except ValueError:
            conn.logger.error(f"学期开始时间格式错误: {start_date_str}")
            return ProtectRouterErrorToCode().remote_service_error.to_json_response(
                conn.logger.trace_id
            )
        start_date = datetime.strptime(start_date_str, "%Y%m%d").date()

        html_content = info_response.text

        # 使用BeautifulSoup解析HTML
        soup = BeautifulSoup(html_content, "html.parser")

        # 查找包含学期周数信息的元素
        # 使用CSS选择器查找
        calendar_element = soup.select_one(
            "#navbar-container > div.navbar-buttons.navbar-header.pull-right > ul > li.light-red > a"
        )

        if not calendar_element:
            # 如果CSS选择器失败，尝试其他方法
            # 查找包含"第X周"的元素
            potential_elements = soup.find_all("a", class_="dropdown-toggle")
            calendar_element = None

            for element in potential_elements:
                text = element.get_text(strip=True) if element else ""
                if "第" in text and "周" in text:
                    calendar_element = element
                    break

            # 如果还是找不到，尝试查找任何包含学期信息的元素
            if not calendar_element:
                all_elements = soup.find_all(text=re.compile(r"\d{4}-\d{4}.*第\d+周"))
                if all_elements:
                    # 找到包含学期信息的文本，查找其父元素
                    for text_node in all_elements:
                        parent = text_node.parent
                        if parent:
                            calendar_element = parent
                            break

        if not calendar_element:
            conn.logger.warning("未找到学期周数信息元素")

            # 尝试在整个页面中搜索学期信息模式
            semester_pattern = re.search(
                r"(\d{4}-\d{4})\s*(春|秋|夏)?\s*第(\d+)周\s*(星期[一二三四五六日天])?",
                html_content,
            )
            if semester_pattern:
                calendar_text = semester_pattern.group(0)
                conn.logger.info(f"通过正则表达式找到学期信息: {calendar_text}")
            else:
                conn.logger.debug(f"HTML内容长度: {len(html_content)}")
                conn.logger.debug(
                    "未检测到学期周数相关内容，可能需要重新登录或检查访问权限"
                )
                return ProtectRouterErrorToCode().remote_service_error.to_json_response(
                    conn.logger.trace_id
                )
        else:
            # 提取文本内容
            calendar_text = calendar_element.get_text(strip=True)
            conn.logger.info(f"找到学期周数信息: {calendar_text}")
            clean_text = re.sub(r"\s+", " ", calendar_text.strip())

            # 初始化默认值
            academic_year = ""
            term = ""
            week_number = 0
            is_end = False

            try:
                # 解析学年：2025-2026
                year_match = re.search(r"(\d{4}-\d{4})", clean_text)
                if year_match:
                    academic_year = year_match.group(1)

                # 解析学期：秋、春
                semester_match = re.search(r"(春|秋)", clean_text)
                if semester_match:
                    term = semester_match.group(1)

                # 解析周数：第1周、第15周等
                week_match = re.search(r"第(\d+)周", clean_text)
                if week_match:
                    week_number = int(week_match.group(1))

                # 判断是否为学期结束（通常第16周以后或包含"结束"等关键词）
                if week_number >= 16 or "结束" in clean_text or "考试" in clean_text:
                    is_end = True

            except Exception as e:
                conn.logger.warning(f"解析学期周数信息时出错: {str(e)}")
                return ProtectRouterErrorToCode().server_error.to_json_response(
                    conn.logger.trace_id
                )
            result = CurrentTermInfo(
                academic_year=academic_year,
                current_term_name=term,
                week_number=week_number,
                start_at=start_date.strftime("%Y-%m-%d"),
                is_end=is_end,
                weekday=datetime.now().weekday(),
            )
            return UniResponseModel[CurrentTermInfo](
                success=True,
                data=result,
                message="获取当前学期信息成功",
                error=None,
            )
    except Exception as e:
        conn.logger.exception(e)
        return ProtectRouterErrorToCode().server_error.to_json_response(
            conn.logger.trace_id
        )
