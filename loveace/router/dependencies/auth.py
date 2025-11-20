from typing import Annotated

from fastapi import Depends, HTTPException
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from loveace.database.auth.token import AuthMEToken
from loveace.database.auth.user import ACEUser
from loveace.database.creator import get_db_session
from loveace.router.dependencies.logger import LoggerMixin, no_user_logger_mixin
from loveace.router.schemas.error import ProtectRouterErrorToCode
from loveace.router.schemas.exception import UniResponseHTTPException

auth_scheme = HTTPBearer(auto_error=False)


async def get_user_by_token(
    authorization: Annotated[
        HTTPAuthorizationCredentials | None, Depends(auth_scheme)
    ] = None,
    db_session: AsyncSession = Depends(get_db_session),
    logger: LoggerMixin = Depends(no_user_logger_mixin),
) -> ACEUser:
    """通过Token获取用户"""
    if not authorization:
        logger.error("缺少认证令牌")
        raise ProtectRouterErrorToCode().invalid_authentication.to_http_exception(
            logger.trace_id
        )
    token = authorization.credentials
    try:
        async with db_session as session:
            query = select(AuthMEToken).where(AuthMEToken.token == token)
            result = await session.execute(query)
            user_token = result.scalars().first()
            if user_token is None:
                logger.error("无效的认证令牌")
                raise ProtectRouterErrorToCode().invalid_authentication.to_http_exception(
                    logger.trace_id
                )
            query = select(ACEUser).where(ACEUser.userid == user_token.user_id)
            result = await session.execute(query)
            user = result.scalars().first()
            if user is None:
                logger.error("用户不存在")
                raise ProtectRouterErrorToCode().invalid_authentication.to_http_exception(
                    logger.trace_id
                )
            return user
    except (HTTPException, UniResponseHTTPException):
        raise
    except Exception as e:
        logger.exception(e)
        raise ProtectRouterErrorToCode().server_error.to_http_exception(logger.trace_id)
