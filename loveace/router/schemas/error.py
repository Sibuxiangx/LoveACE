"""
经过一层封装的错误代码映射，专用于保护路由
"""

from fastapi import status

from loveace.router.schemas.base import ErrorToCode, ErrorToCodeNode


class ProtectRouterErrorToCode(ErrorToCode):
    invalid_authentication: ErrorToCodeNode = ErrorToCodeNode(
        message="无效的认证信息",
        error_code=status.HTTP_401_UNAUTHORIZED,
        code="INVALID_AUTHENTICATION",
    )
    forbidden: ErrorToCodeNode = ErrorToCodeNode(
        message="禁止访问",
        error_code=status.HTTP_403_FORBIDDEN,
        code="FORBIDDEN",
    )
    cooldown: ErrorToCodeNode = ErrorToCodeNode(
        message="请求过于频繁，请稍后再试",
        error_code=status.HTTP_429_TOO_MANY_REQUESTS,
        code="COOLDOWN",
    )
    user_need_reset_password: ErrorToCodeNode = ErrorToCodeNode(
        message="用户需要重置密码",
        error_code=status.HTTP_403_FORBIDDEN,
        code="USER_NEED_RESET_PASSWORD",
    )
    remote_service_error: ErrorToCodeNode = ErrorToCodeNode(
        message="远程服务错误",
        error_code=status.HTTP_502_BAD_GATEWAY,
        code="REMOTE_SERVICE_ERROR",
    )
    validation_error: ErrorToCodeNode = ErrorToCodeNode(
        message="数据验证失败",
        error_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
        code="VALIDATION_ERROR",
    )
    server_error: ErrorToCodeNode = ErrorToCodeNode(
        message="服务器错误",
        error_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
        code="SERVER_ERROR",
    )
    null_response: ErrorToCodeNode = ErrorToCodeNode(
        message="远程服务返回空响应",
        error_code=status.HTTP_502_BAD_GATEWAY,
        code="NULL_RESPONSE",
    )
    timeout: ErrorToCodeNode = ErrorToCodeNode(
        message="请求远程服务超时",
        error_code=status.HTTP_504_GATEWAY_TIMEOUT,
        code="TIMEOUT",
    )
    unknown_error: ErrorToCodeNode = ErrorToCodeNode(
        message="未知错误",
        error_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
        code="UNKNOWN",
    )
    empty_path: ErrorToCodeNode = ErrorToCodeNode(
        message="请求路径不能为空",
        error_code=status.HTTP_400_BAD_REQUEST,
        code="EMPTY_PATH",
    )
