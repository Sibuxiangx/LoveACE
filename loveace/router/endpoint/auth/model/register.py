from fastapi import status
from pydantic import BaseModel, Field

from loveace.router.schemas import (
    ErrorToCode,
    ErrorToCodeNode,
)

##############################################################
# *                    用户注册相关模型-邀请码                    *#


class InviteCodeRequest(BaseModel):
    invite_code: str = Field(..., description="邀请码")


class InviteCodeResponse(BaseModel):
    token: str = Field(..., description="邀请码验证成功后返回的Token")


class InviteErrorToCode(ErrorToCode):
    invalid_invite_code: ErrorToCodeNode = ErrorToCodeNode(
        error_code=status.HTTP_403_FORBIDDEN,
        code="INVITE_CODE_INVALID",
        message="邀请码错误",
    )
    server_error: ErrorToCodeNode = ErrorToCodeNode(
        error_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
        code="SERVER_ERROR",
        message="服务器错误",
    )


##############################################################

##############################################################
# *                     用户注册相关模型-注册                     *#


class RegisterRequest(BaseModel):
    userid: str = Field(..., description="用户ID")
    ec_password: str = Field(..., description="用户EC密码，rsa encrypt加密后的密文")
    password: str = Field(..., description="用户登录密码，rsa encrypt加密后的密文")
    token: str = Field(..., description="邀请码验证成功后返回的Token")


class RegisterResponse(BaseModel):
    token: str = Field(..., description="用户登录成功后返回的Authme Token")


class RegisterErrorToCode(ErrorToCode):
    invalid_token: ErrorToCodeNode = ErrorToCodeNode(
        error_code=status.HTTP_403_FORBIDDEN,
        code="TOKEN_INVALID",
        message="Token无效",
    )
    userid_exists: ErrorToCodeNode = ErrorToCodeNode(
        error_code=status.HTTP_409_CONFLICT,
        code="USERID_EXISTS",
        message="用户ID已存在",
    )
    decrypt_error: ErrorToCodeNode = ErrorToCodeNode(
        error_code=status.HTTP_400_BAD_REQUEST,
        code="DECRYPT_ERROR",
        message="密码解密失败",
    )
    ec_server_error: ErrorToCodeNode = ErrorToCodeNode(
        error_code=status.HTTP_400_BAD_REQUEST,
        code="EC_SERVER_ERROR",
        message="EC服务错误",
    )
    ec_password_error: ErrorToCodeNode = ErrorToCodeNode(
        error_code=status.HTTP_400_BAD_REQUEST,
        code="EC_PASSWORD_ERROR",
        message="EC密码错误",
    )
    uaap_server_error: ErrorToCodeNode = ErrorToCodeNode(
        error_code=status.HTTP_400_BAD_REQUEST,
        code="UAAP_SERVER_ERROR",
        message="UAAP服务错误",
    )
    uaap_password_error: ErrorToCodeNode = ErrorToCodeNode(
        error_code=status.HTTP_400_BAD_REQUEST,
        code="UAAP_PASSWORD_ERROR",
        message="UAAP密码错误",
    )
    register_in_cooldown: ErrorToCodeNode = ErrorToCodeNode(
        error_code=status.HTTP_429_TOO_MANY_REQUESTS,
        code="REGISTER_IN_COOLDOWN",
        message="注册请求过于频繁，请稍后再试",
    )
    server_error: ErrorToCodeNode = ErrorToCodeNode(
        error_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
        code="SERVER_ERROR",
        message="服务器错误",
    )


##############################################################
