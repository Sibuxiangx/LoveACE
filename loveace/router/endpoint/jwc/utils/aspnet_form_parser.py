"""
ASP.NET 表单解析器
用于从 ASP.NET 页面中提取动态表单数据
"""

import re
from typing import Dict, Optional, Any

from bs4 import BeautifulSoup


class ASPNETFormParser:
    """ASP.NET 表单解析器"""

    @staticmethod
    def extract_form_data(html_content: str) -> Dict[str, str]:
        """
        从 ASP.NET 页面 HTML 中提取表单数据

        Args:
            html_content: HTML 页面内容

        Returns:
            包含表单字段的字典
        """

        return ASPNETFormParser._extract_with_beautifulsoup(html_content)

    @staticmethod
    def _extract_with_beautifulsoup(html_content: str) -> Dict[str, str]:
        """
        使用 BeautifulSoup 提取表单数据

        Args:
            html_content: HTML 页面内容

        Returns:
            包含表单字段的字典
        """
        form_data = {}

        # 使用 BeautifulSoup 解析 HTML
        soup = BeautifulSoup(html_content, "lxml")

        # 查找表单
        form = soup.find("form", {"method": "post"})
        if not form:
            raise ValueError("未找到 POST 表单")

        # 提取隐藏字段
        hidden_fields = [
            "__EVENTTARGET",
            "__EVENTARGUMENT",
            "__LASTFOCUS",
            "__VIEWSTATE",
            "__VIEWSTATEGENERATOR",
            "__EVENTVALIDATION",
        ]

        for field_name in hidden_fields:
            input_element = form.find("input", {"name": field_name})
            if input_element and input_element.get("value"):
                form_data[field_name] = input_element.get("value")
            else:
                form_data[field_name] = ""

        # 添加其他表单字段的默认值
        form_data.update(
            {
                "ctl00$ContentPlaceHolder1$ContentPlaceHolder2$ddlSslb": "%",
                "ctl00$ContentPlaceHolder1$ContentPlaceHolder2$txtSsmc": "",
                "ctl00$ContentPlaceHolder1$ContentPlaceHolder2$gvSb$ctl28$txtNewPageIndex": "1",
            }
        )

        return form_data

    @staticmethod
    def get_awards_list_form_data(html_content: str) -> Dict[str, str]:
        """
        获取已申报奖项列表页面的表单数据

        Args:
            html_content: HTML 页面内容

        Returns:
            用于请求已申报奖项的表单数据
        """
        base_form_data = ASPNETFormParser.extract_form_data(html_content)

        # 设置 EVENTTARGET 为"已申报奖项"选项卡
        base_form_data["__EVENTTARGET"] = (
            "ctl00$ContentPlaceHolder1$ContentPlaceHolder2$DataList1$ctl01$LinkButton1"
        )

        return base_form_data
