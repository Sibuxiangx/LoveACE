from fastapi import APIRouter, Depends
from fastapi.responses import JSONResponse

from loveace.router.endpoint.auth.model.authme import AuthMeResponse
from loveace.router.schemas.error import ProtectRouterErrorToCode
from loveace.router.schemas.uniresponse import UniResponseModel
from loveace.service.remote.aufe import AUFEConnection
from loveace.service.remote.aufe.depends import get_aufe_conn

authme_router = APIRouter(
    prefix="/authme", responses=ProtectRouterErrorToCode.gen_code_table()
)


@authme_router.get(
    "/token",
    response_model=UniResponseModel[AuthMeResponse],
    summary="Token 有效性验证",
)
async def auth_me(
    conn: AUFEConnection = Depends(get_aufe_conn),
) -> UniResponseModel[AuthMeResponse] | JSONResponse:
    """
    验证 Token 有效性并获取用户信息

    ✅ 功能特性：
       - 验证 Authme Token 是否有效
       - 返回当前认证用户的 ID
       - 用于前端权限验证

    💡 使用场景：
       - 前端页面加载时验证登录状态
       - Token 过期检测
       - 获取当前登录用户信息

    Returns:
        AuthMeResponse: 包含验证结果和用户 ID
    """
    user_id = conn.userid
    return UniResponseModel[AuthMeResponse](
        success=True,
        data=AuthMeResponse(success=True, userid=user_id),
        message="Token 验证成功",
        error=None,
    )
