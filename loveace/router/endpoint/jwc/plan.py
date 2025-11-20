import re

import ujson
from bs4 import BeautifulSoup
from fastapi import APIRouter, Depends
from fastapi.responses import JSONResponse
from httpx import HTTPError
from pydantic import ValidationError
from ujson import JSONDecodeError

from loveace.router.endpoint.jwc.model.base import JWCConfig
from loveace.router.endpoint.jwc.model.plan import (
    PlanCompletionCategory,
    PlanCompletionInfo,
)
from loveace.router.endpoint.jwc.utils.plan import populate_category_children
from loveace.router.schemas.error import ProtectRouterErrorToCode
from loveace.router.schemas.uniresponse import UniResponseModel
from loveace.service.remote.aufe import AUFEConnection
from loveace.service.remote.aufe.depends import get_aufe_conn

ENDPOINT = {
    "plan": "/student/integratedQuery/planCompletion/index",
}

jwc_plan_router = APIRouter(
    prefix="/plan",
    responses=ProtectRouterErrorToCode().gen_code_table(),
)


@jwc_plan_router.get(
    "/current",
    summary="获取当前培养方案完成信息",
    response_model=UniResponseModel[PlanCompletionInfo],
)
async def get_current_plan_completion(
    conn: AUFEConnection = Depends(get_aufe_conn),
) -> UniResponseModel[PlanCompletionInfo] | JSONResponse:
    """
    获取用户的培养方案完成情况

    ✅ 功能特性：
       - 获取培养方案的总体完成进度
       - 按类别显示各类课程的完成情况
       - 显示已完成、未完成、可选课程等

    💡 使用场景：
       - 查看毕业要求的完成进度
       - 了解还需要修读哪些课程
       - 规划后续选课

    Returns:
        PlanCompletionInfo: 包含方案完成情况和各类别详情
    """
    try:
        conn.logger.info("获取当前培养方案完成信息")
        response = await conn.client.get(
            JWCConfig().to_full_url(ENDPOINT["plan"]),
            follow_redirects=True,
            timeout=600,
        )
        if response.status_code != 200:
            conn.logger.error(f"获取培养方案信息失败，状态码: {response.status_code}")
            return ProtectRouterErrorToCode().remote_service_error.to_json_response(
                conn.logger.trace_id
            )

        html_content = response.text

        # 使用BeautifulSoup解析HTML
        soup = BeautifulSoup(html_content, "lxml")

        # 提取培养方案名称
        plan_name = ""

        # 查找包含"培养方案"的h4标签
        h4_elements = soup.find_all("h4")
        for h4 in h4_elements:
            text = h4.get_text(strip=True) if h4 else ""
            if "培养方案" in text:
                plan_name = text
                conn.logger.info(f"找到培养方案标题: {plan_name}")
                break

        # 解析专业和年级信息
        major = ""
        grade = ""
        if plan_name:
            grade_match = re.search(r"(\d{4})级", plan_name)
            if grade_match:
                grade = grade_match.group(1)

            major_match = re.search(r"\d{4}级(.+?)本科", plan_name)
            if major_match:
                major = major_match.group(1)

        # 查找zTree数据
        ztree_data = []

        # 在script标签中查找zTree初始化数据
        scripts = soup.find_all("script")
        for script in scripts:
            try:
                script_text = script.get_text() if script else ""
                if "$.fn.zTree.init" in script_text and "flagId" in script_text:
                    conn.logger.info("找到包含zTree初始化的script标签")

                    # 提取zTree数据
                    # 尝试多种模式匹配
                    patterns = [
                        r'\$\.fn\.zTree\.init\(\$\("#treeDemo"\),\s*setting,\s*(\[.*?\])\s*\);',
                        r"\.zTree\.init\([^,]+,\s*[^,]+,\s*(\[.*?\])\s*\);",
                        r'init\(\$\("#treeDemo"\)[^,]*,\s*[^,]*,\s*(\[.*?\])',
                    ]

                    json_part = None
                    for pattern in patterns:
                        match = re.search(pattern, script_text, re.DOTALL)
                        if match:
                            json_part = match.group(1)
                            conn.logger.info(
                                f"使用模式匹配成功提取zTree数据: {len(json_part)}字符"
                            )
                            break

                    if json_part:
                        # 清理和修复JSON格式
                        # 移除JavaScript注释和多余的逗号
                        json_part = re.sub(r"//.*?\n", "\n", json_part)
                        json_part = re.sub(r"/\*.*?\*/", "", json_part, flags=re.DOTALL)
                        json_part = re.sub(r",\s*}", "}", json_part)
                        json_part = re.sub(r",\s*]", "]", json_part)

                        try:
                            ztree_data = ujson.loads(json_part)
                            conn.logger.info(f"JSON解析成功，共{len(ztree_data)}个节点")
                            break
                        except JSONDecodeError as e:
                            conn.logger.warning(f"JSON解析失败: {str(e)}")
                            # 如果JSON解析失败，不使用手动解析，直接跳过
                            continue
                    else:
                        conn.logger.warning("未能通过模式匹配提取zTree数据")
                        continue
            except Exception:
                continue
        if not ztree_data:
            conn.logger.warning("未找到有效的zTree数据")

            # 输出调试信息
            conn.logger.info(f"HTML内容长度: {len(html_content)}")
            conn.logger.info(f"找到的script标签数量: {len(soup.find_all('script'))}")

            # 检查是否包含关键词
            contains_ztree = "zTree" in html_content
            contains_flagid = "flagId" in html_content
            contains_plan = "培养方案" in html_content
            conn.logger.info(
                f"HTML包含关键词: zTree={contains_ztree}, flagId={contains_flagid}, 培养方案={contains_plan}"
            )
            conn.logger.warning("未找到有效的zTree数据")

            if contains_plan:
                conn.logger.warning(
                    "检测到培养方案内容，但zTree数据解析失败，可能页面结构已变化"
                )
            else:
                conn.logger.warning(
                    "未检测到培养方案相关内容，可能需要重新登录或检查访问权限"
                )
            return ProtectRouterErrorToCode().remote_service_error.to_json_response(
                conn.logger.trace_id,
                message="未找到有效的培养方案数据，请检查登录状态或稍后再试",
            )
        # 解析zTree数据构建分类和课程信息
        try:
            # 按层级组织数据
            nodes_by_id = {node["id"]: node for node in ztree_data}
            root_categories = []

            # 统计根分类和所有节点信息，用于调试
            all_parent_ids = set()
            root_nodes = []

            for node in ztree_data:
                parent_id = node.get("pId", "")
                all_parent_ids.add(parent_id)

                # 根分类的判断条件：pId为"-1"（这是zTree中真正的根节点标识）
                # 从HTML示例可以看出，真正的根分类的pId是"-1"
                is_root_category = parent_id == "-1"

                if is_root_category:
                    root_nodes.append(node)

            conn.logger.info(
                f"zTree数据分析: 总节点数={len(ztree_data)}, 根节点数={len(root_nodes)}, 不同父ID数={len(all_parent_ids)}"
            )
            conn.logger.debug(f"所有父ID: {sorted(all_parent_ids)}")

            # 构建分类树
            for node in root_nodes:
                category = PlanCompletionCategory.from_ztree_node(node)
                # 填充分类的子分类和课程（支持多层嵌套）
                try:
                    populate_category_children(category, node["id"], nodes_by_id, conn)
                except Exception as e:
                    conn.logger.error(f"填充分类子项异常: {str(e)}")
                    conn.logger.error(
                        f"异常节点信息: category_id={node['id']}, 错误详情: {str(e)}"
                    )
                root_categories.append(category)
                conn.logger.info(
                    f"创建根分类: {category.category_name} (ID: {node['id']})"
                )

            # 创建完成情况信息
            completion_info = PlanCompletionInfo(
                plan_name=plan_name,
                major=major,
                grade=grade,
                categories=root_categories,
                total_categories=0,
                total_courses=0,
                passed_courses=0,
                failed_courses=0,
                unread_courses=0,
            )

            # 计算统计信息
            completion_info.calculate_statistics()
            conn.logger.info(
                f"培养方案完成信息统计: 分类数={completion_info.total_categories}, 课程数={completion_info.total_courses}, 已过课程={completion_info.passed_courses}, 未过课程={completion_info.failed_courses}, 未修读课程={completion_info.unread_courses}"
            )
            return UniResponseModel[PlanCompletionInfo](
                success=True,
                data=completion_info,
                message="获取培养方案完成信息成功",
                error=None,
            )
        except ValidationError as ve:
            conn.logger.error(f"数据验证错误: {ve}")
            return ProtectRouterErrorToCode().validation_error.to_json_response(
                conn.logger.trace_id
            )
        except Exception as e:
            conn.logger.exception(e)
            return ProtectRouterErrorToCode().server_error.to_json_response(
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
