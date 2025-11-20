from fastapi import status
from pydantic import BaseModel, Field

from loveace.router.schemas.base import ErrorToCode, ErrorToCodeNode


class LoginRequest(BaseModel):
    userid: str = Field(..., description="用户ID")
    ec_password: str = Field(..., description="用户EC密码，rsa encrypt加密后的密文")
    password: str = Field(..., description="用户登录密码，rsa encrypt加密后的密文")


class LoginResponse(BaseModel):
    token: str = Field(..., description="用户登录成功后返回的Authme Token")


class LoginErrorToCode(ErrorToCode):
    invalid_credentials: ErrorToCodeNode = ErrorToCodeNode(
        error_code=status.HTTP_403_FORBIDDEN,
        code="CREDENTIALS_INVALID",
        message="凭证无效",
    )
    remote_invalid_credentials: ErrorToCodeNode = ErrorToCodeNode(
        error_code=status.HTTP_403_FORBIDDEN,
        code="REMOTE_CREDENTIALS_INVALID",
        message="远程凭证无效，EC密码或登录密码错误，需要进行密码重置",
    )
    cooldown: ErrorToCodeNode = ErrorToCodeNode(
        error_code=status.HTTP_429_TOO_MANY_REQUESTS,
        code="COOLDOWN",
        message="操作过于频繁，请稍后再试",
    )
    server_error: ErrorToCodeNode = ErrorToCodeNode(
        error_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
        code="SERVER_ERROR",
        message="服务器错误",
    )
