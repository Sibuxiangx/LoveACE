from fastapi import status

from loveace.router.schemas.error import ErrorToCodeNode, ProtectRouterErrorToCode


class ISIMRouterErrorToCode(ProtectRouterErrorToCode):
    """ISIM 统一错误码"""

    UNBOUNDROOM: ErrorToCodeNode = ErrorToCodeNode(
        error_code=status.HTTP_400_BAD_REQUEST,
        code="UNBOUND_ROOM",
        message="房间未绑定",
    )
    CACHEDROOMSEXPIRED: ErrorToCodeNode = ErrorToCodeNode(
        error_code=status.HTTP_400_BAD_REQUEST,
        code="CACHED_ROOMS_EXPIRED",
        message="房间缓存已过期，请稍后重新获取房间列表",
    )
