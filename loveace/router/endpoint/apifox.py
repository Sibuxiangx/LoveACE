from fastapi import APIRouter
from fastapi.responses import RedirectResponse

apifox_router = APIRouter()


@apifox_router.get(
    "/",
    tags=["首页"],
    summary="首页 - 请求后跳转到 Apifox 文档页面",
    response_model=None,
    responses={"307": {"description": "重定向到 Apifox 文档页面"}},
)
async def redirect_to_apifox():
    """
    重定向到 API 文档页面

    ✅ 功能特性：
       - 自动重定向到 Apifox 文档
       - 提供 API 接口的完整文档
       - 包含参数说明和示例

    💡 使用场景：
       - 访问 API 根路径时自动跳转
       - 获取 API 文档

    Returns:
        RedirectResponse: 重定向到 Apifox 文档页面
    """
    return RedirectResponse(url="https://docs.loveace.linota.cn/")
