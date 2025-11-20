from loveace.router.endpoint.jwc.model.plan import (
    PlanCompletionCategory,
    PlanCompletionCourse,
)
from loveace.service.remote.aufe import AUFEConnection


def populate_category_children(
    category: PlanCompletionCategory,
    category_id: str,
    nodes_by_id: dict,
    conn: AUFEConnection,
):
    """填充分类的子分类和课程（支持多层嵌套）"""
    try:
        children_count = 0
        subcategory_count = 0
        course_count = 0

        for node in nodes_by_id.values():
            if node.get("pId") == category_id:
                children_count += 1
                flag_type = node.get("flagType", "")

                if flag_type in ["001", "002"]:  # 分类或子分类
                    subcategory = PlanCompletionCategory.from_ztree_node(node)
                    # 递归处理子项，支持多层嵌套
                    populate_category_children(
                        subcategory, node["id"], nodes_by_id, conn
                    )
                    category.subcategories.append(subcategory)
                    subcategory_count += 1
                elif flag_type == "kch":  # 课程
                    course = PlanCompletionCourse.from_ztree_node(node)
                    category.courses.append(course)
                    course_count += 1
                else:
                    # 处理其他类型的节点，也可能是分类
                    # 根据是否有子节点来判断是分类还是课程
                    has_children = any(
                        n.get("pId") == node["id"] for n in nodes_by_id.values()
                    )
                    if has_children:
                        # 有子节点，当作分类处理
                        subcategory = PlanCompletionCategory.from_ztree_node(node)
                        populate_category_children(
                            subcategory, node["id"], nodes_by_id, conn
                        )
                        category.subcategories.append(subcategory)
                        subcategory_count += 1
                    else:
                        # 无子节点，当作课程处理
                        course = PlanCompletionCourse.from_ztree_node(node)
                        category.courses.append(course)
                        course_count += 1

        if children_count > 0:
            conn.logger.info(
                f"分类 '{category.category_name}' (ID: {category_id}) 的子项: 总数={children_count}, 子分类={subcategory_count}, 课程={course_count}"
            )

    except Exception as e:
        conn.logger.error(f"填充分类子项异常: {str(e)}")
        conn.logger.error(
            f"异常节点信息: category_id={category_id}, 错误详情: {str(e)}"
        )
        raise
