import secrets
from datetime import datetime, timedelta
from uuid import uuid4

from fastapi import APIRouter, Depends
from fastapi.responses import JSONResponse
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from loveace.config.logger import LoggerMixin
from loveace.database.auth.login import LoginCoolDown
from loveace.database.auth.token import AuthMEToken
from loveace.database.auth.user import ACEUser
from loveace.database.creator import get_db_session
from loveace.router.dependencies.logger import no_user_logger_mixin
from loveace.router.endpoint.auth.model.login import (
    LoginErrorToCode,
    LoginRequest,
    LoginResponse,
)
from loveace.router.schemas.uniresponse import UniResponseModel
from loveace.service.remote.aufe import AUFEService
from loveace.service.remote.aufe.depends import get_aufe_service
from loveace.utils.rsa import RSAUtils

login_router = APIRouter(prefix="/login", responses=LoginErrorToCode.gen_code_table())
rsa_util = RSAUtils.get_or_create_rsa_utils()


@login_router.post(
    "/next",
    response_model=UniResponseModel[LoginResponse],
    summary="用户登录",
)
async def login(
    login_request: LoginRequest,
    db: AsyncSession = Depends(get_db_session),
    aufe_service: AUFEService = Depends(get_aufe_service),
    logger: LoggerMixin = Depends(no_user_logger_mixin),
) -> UniResponseModel[LoginResponse] | JSONResponse:
    """
    用户登录，返回 Authme Token

    ✅ 功能特性：
       - 通过 AUFE 服务验证 EC 密码和登录密码
       - 限制用户总 Token 数为 5 个
       - 登录失败后设置 1 分钟冷却时间

    ⚠️ 限制条件：
       - 连续登录失败会触发冷却机制
       - 冷却期间内拒绝该用户的登录请求

    💡 使用场景：
       - 用户首次登录
       - 用户重新登录（更换设备）
       - 用户忘记密码后重新设置并登录

    Args:
        login_request: 包含用户 ID、EC 密码、登录密码的登录请求
        db: 数据库会话
        aufe_service: AUFE 远程认证服务
        logger: 日志记录器

    Returns:
        LoginResponse: 包含新生成的 Authme Token
    """
    try:
        async with db as session:
            logger.info(f"用户登录: {login_request.userid}")
            # 检查用户是否存在
            query = select(ACEUser).where(ACEUser.userid == login_request.userid)
            result = await session.execute(query)
            user = result.scalars().first()
            if user is None:
                logger.info(f"用户不存在: {login_request.userid}")
                return LoginErrorToCode().invalid_credentials.to_json_response(
                    logger.trace_id
                )
            # 检查是否在冷却时间内
            query = select(LoginCoolDown).where(LoginCoolDown.userid == user.userid)
            result = await session.execute(query)
            cooldown = result.scalars().first()
            if cooldown and cooldown.expire_date > datetime.now():
                logger.info(f"用户 {login_request.userid} 在冷却时间内，拒绝登录")
                return LoginErrorToCode().cooldown.to_json_response(logger.trace_id)
            # 解密数据库中的 EC密码 登录密码 和 请求体中的 EC密码 登录密码
            try:
                db_ec_password = rsa_util.decrypt(user.ec_password)
                db_password = rsa_util.decrypt(user.password)
                ec_password = rsa_util.decrypt(login_request.ec_password)
                password = rsa_util.decrypt(login_request.password)
            except Exception as e:
                logger.info(f"用户 {login_request.userid} 提供的密码解密失败: {e}")
                return LoginErrorToCode().invalid_credentials.to_json_response(
                    logger.trace_id
                )
            # 尝试使用AUFE服务验证EC密码和登录密码
            conn = await aufe_service.get_or_create_connection(
                userid=login_request.userid,
                ec_password=ec_password,
                password=password,
            )
            if not await conn.health_check():
                logger.info(f"用户 {login_request.userid} 的AUFE连接不可用")

                # EC密码登录重试机制 (最多3次)
                ec_login_status = None
                for ec_retry in range(3):
                    ec_login_status = await conn.ec_login()
                    if ec_login_status.success:
                        break

                    # 如果是攻击防范或密码错误，直接退出重试
                    if (
                        ec_login_status.fail_maybe_attacked
                        or ec_login_status.fail_invalid_credentials
                    ):
                        logger.info(
                            f"用户 {login_request.userid} EC登录失败 (攻击防范或密码错误)，停止重试"
                        )
                        break

                    logger.info(
                        f"用户 {login_request.userid} EC登录重试第 {ec_retry + 1} 次"
                    )

                if not ec_login_status or not ec_login_status.success:
                    logger.info(f"用户 {login_request.userid} 的EC密码错误")
                    # 设置冷却时间
                    cooldown_time = timedelta(minutes=1)
                    if cooldown:
                        cooldown.expire_date = datetime.now() + cooldown_time
                    else:
                        cooldown = LoginCoolDown(
                            userid=user.userid,
                            expire_date=datetime.now() + cooldown_time,
                        )
                        session.add(cooldown)
                    await session.commit()
                    return (
                        LoginErrorToCode().remote_invalid_credentials.to_json_response(
                            logger.trace_id
                        )
                    )

                # UAAP密码登录重试机制 (最多3次)
                uaap_login_status = None
                for uaap_retry in range(3):
                    uaap_login_status = await conn.uaap_login()
                    if uaap_login_status.success:
                        break

                    # 如果是密码错误，直接退出重试
                    if uaap_login_status.fail_invalid_credentials:
                        logger.info(
                            f"用户 {login_request.userid} UAAP登录失败 (密码错误)，停止重试"
                        )
                        break

                    logger.info(
                        f"用户 {login_request.userid} UAAP登录重试第 {uaap_retry + 1} 次"
                    )

                if not uaap_login_status or not uaap_login_status.success:
                    logger.info(f"用户 {login_request.userid} 的登录密码错误")
                    # 设置冷却时间
                    cooldown_time = timedelta(minutes=1)
                    if cooldown:
                        cooldown.expire_date = datetime.now() + cooldown_time
                    else:
                        cooldown = LoginCoolDown(
                            userid=user.userid,
                            expire_date=datetime.now() + cooldown_time,
                        )
                        session.add(cooldown)
                    await session.commit()
                    return (
                        LoginErrorToCode().remote_invalid_credentials.to_json_response(
                            logger.trace_id
                        )
                    )
            # 删除冷却时间
            if cooldown:
                await session.delete(cooldown)
                await session.commit()
            # 比对密码，如果新的密码与数据库中的密码不一致，则更新数据库中的密码
            if db_ec_password != ec_password or db_password != password:
                user.ec_password = rsa_util.encrypt(ec_password)
                user.password = rsa_util.encrypt(password)
                session.add(user)
                await session.commit()
                logger.info(f"用户 {login_request.userid} 的密码已更新")
            # 创建新的Authme Token
            new_token = AuthMEToken(
                user_id=user.userid,
                token=secrets.token_urlsafe(32),
                device_id=uuid4().hex,
            )
            session.add(new_token)
            await session.commit()
            # 限制用户总 Token 数为5个，删除最早的 Token
            query = (
                select(AuthMEToken)
                .where(AuthMEToken.user_id == user.userid)
                .order_by(AuthMEToken.create_date.asc())
            )
            result = await session.execute(query)
            tokens = result.scalars().all()
            if len(tokens) > 5:
                for token in tokens[:-5]:
                    await session.delete(token)
                await session.commit()
            logger.info(f"用户 {login_request.userid} 登录成功，返回Token")
            return UniResponseModel[LoginResponse](
                success=True,
                data=LoginResponse(token=new_token.token),
                message="登录成功",
                error=None,
            )
    except Exception as e:
        logger.error(f"用户 {login_request.userid} 登录时发生错误: {e}")
        return LoginErrorToCode().server_error.to_json_response(logger.trace_id)
