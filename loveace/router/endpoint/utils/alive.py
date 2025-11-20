from fastapi import APIRouter
from pydantic import BaseModel, Field


class AliveResponse(BaseModel):
    message: str = Field(
        default="LoveACE is alive and running!", description="服务状态消息"
    )


alive_router = APIRouter()


@alive_router.get(
    "/alive",
    response_model=AliveResponse,
    tags=["服务健康检查"],
    summary="服务健康检查接口",
)
async def alive_check():
    """
    服务健康检查接口

    ✅ 功能特性：
       - 返回服务运行状态
       - 提供简单的健康检查响应

    💡 使用场景：
       - 监控服务状态
       - 负载均衡器健康检查

    Returns:
        AliveResponse: 包含服务状态消息的响应模型
    """
    return AliveResponse()
