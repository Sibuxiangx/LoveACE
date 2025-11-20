import secrets
from datetime import datetime, timedelta
from uuid import uuid4

from fastapi import APIRouter, Depends
from fastapi.responses import JSONResponse
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from loveace.config.logger import LoggerMixin
from loveace.database.auth.register import InviteCode as InviteCodeDB
from loveace.database.auth.register import RegisterCoolDown
from loveace.database.auth.token import AuthMEToken
from loveace.database.auth.user import ACEUser
from loveace.database.creator import get_db_session
from loveace.router.dependencies.logger import no_user_logger_mixin
from loveace.router.endpoint.auth.model.register import (
    InviteCodeRequest,
    InviteCodeResponse,
    InviteErrorToCode,
    RegisterErrorToCode,
    RegisterRequest,
    RegisterResponse,
)
from loveace.router.schemas.uniresponse import UniResponseModel
from loveace.service.remote.aufe import AUFEService
from loveace.service.remote.aufe.depends import get_aufe_service
from loveace.utils.rsa import RSAUtils

register_router = APIRouter(prefix="/register")


temp_tokens = []

rsa_util = RSAUtils.get_or_create_rsa_utils()


@register_router.post(
    "/invite",
    response_model=UniResponseModel[InviteCodeResponse],
    responses=InviteErrorToCode.gen_code_table(),
    summary="邀请码验证",
)
async def register(
    invite_code: InviteCodeRequest,
    db: AsyncSession = Depends(get_db_session),
    logger: LoggerMixin = Depends(no_user_logger_mixin),
) -> UniResponseModel[InviteCodeResponse] | JSONResponse:
    """
    验证邀请码并返回临时 Token

    ✅ 功能特性：
       - 验证邀请码的有效性
       - 生成临时 Token 用于后续注册步骤
       - 邀请码一次性使用

    💡 使用场景：
       - 用户注册流程的第一步
       - 邀请制系统的验证

    Args:
        invite_code: 邀请码请求对象
        db: 数据库会话
        logger: 日志记录器

    Returns:
        InviteCodeResponse: 包含临时 Token
    """
    try:
        async with db as session:
            logger.info(f"邀请码: {invite_code.invite_code}")
            invite = select(InviteCodeDB).where(
                InviteCodeDB.code == invite_code.invite_code
            )
            result = await session.execute(invite)
            invite_data = result.scalars().first()
            if invite_data is None:
                logger.info(f"邀请码不存在: {invite_code.invite_code}")
                return InviteErrorToCode().invalid_invite_code.to_json_response(
                    logger.trace_id
                )
            token = secrets.token_urlsafe(128)
            temp_tokens.append(token)
            return UniResponseModel[InviteCodeResponse](
                success=True,
                data=InviteCodeResponse(token=token),
                message="邀请码验证成功",
                error=None,
            )
    except Exception as e:
        logger.error("邀请码验证失败:")
        logger.exception(e)
        return InviteErrorToCode().server_error.to_json_response(logger.trace_id)


@register_router.post(
    "/next",
    response_model=UniResponseModel[RegisterResponse],
    responses=RegisterErrorToCode.gen_code_table(),
    summary="用户注册",
)
async def register_user(
    register_info: RegisterRequest,
    db: AsyncSession = Depends(get_db_session),
    logger: LoggerMixin = Depends(no_user_logger_mixin),
    aufe_service: AUFEService = Depends(get_aufe_service),
) -> UniResponseModel[RegisterResponse] | JSONResponse:
    """
    用户注册，验证身份并创建账户

    ✅ 功能特性：
       - 通过 AUFE 服务验证 EC 密码和登录密码
       - 验证身份信息的有效性
       - 生成 Authme Token 用于登录

    ⚠️ 限制条件：
       - EC 密码或登录密码错误会触发 5 分钟冷却时间
       - 用户 ID 不能重复
       - 必须提供有效的邀请 Token

    💡 使用场景：
       - 新用户注册
       - 创建学号对应的账户

    Args:
        register_info: 包含用户 ID、EC 密码、登录密码和邀请 Token 的注册信息
        db: 数据库会话
        logger: 日志记录器
        aufe_service: AUFE 远程认证服务

    Returns:
        RegisterResponse: 包含 Authme Token
    """
    try:
        async with db as session:
            # COOLDOWN检查
            query = select(RegisterCoolDown).where(
                RegisterCoolDown.userid == register_info.userid
            )
            result = await session.execute(query)
            cooldown = result.scalars().first()
            if cooldown:
                if cooldown.expire_date > datetime.now():
                    logger.info(f"用户ID注册冷却中: {register_info.userid}")
                    return RegisterErrorToCode().userid_exists.to_json_response(
                        logger.trace_id
                    )
                else:
                    await session.delete(cooldown)
                    await session.commit()
            if register_info.token not in temp_tokens:
                logger.info(f"无效的注册Token: {register_info.token}")
                return RegisterErrorToCode().invalid_token.to_json_response(
                    logger.trace_id
                )
            query = select(ACEUser).where(ACEUser.userid == register_info.userid)
            result = await session.execute(query)
            user = result.scalars().first()
            if user is not None:
                logger.info(f"用户ID已存在: {register_info.userid}")
                return RegisterErrorToCode().userid_exists.to_json_response(
                    logger.trace_id
                )
            # 尝试使用AUFE服务验证EC密码
            try:
                ec_password = rsa_util.decrypt(register_info.ec_password)
                password = rsa_util.decrypt(register_info.password)
            except Exception as e:
                logger.info(f"用户 {register_info.userid} 提供的密码解密失败: {e}")
                return RegisterErrorToCode().decrypt_error.to_json_response(
                    logger.trace_id
                )
            conn = await aufe_service.get_or_create_connection(
                userid=register_info.userid,
                ec_password=ec_password,
                password=password,
            )
            ec_login_status = await conn.ec_login()
            if not ec_login_status.success:
                cooldown_entry = RegisterCoolDown(
                    userid=register_info.userid,
                    expire_date=datetime.now() + timedelta(minutes=5),
                )
                session.add(cooldown_entry)
                await session.commit()
                if ec_login_status.fail_invalid_credentials:
                    logger.info(f"EC密码错误: {register_info.userid}")
                    return RegisterErrorToCode().ec_password_error.to_json_response(
                        logger.trace_id
                    )
                else:
                    logger.error(f"AUFE服务异常: {ec_login_status}")
                    return RegisterErrorToCode().ec_server_error.to_json_response(
                        logger.trace_id
                    )

            uaap_login_status = await conn.uaap_login()
            if not uaap_login_status.success:
                cooldown_entry = RegisterCoolDown(
                    userid=register_info.userid,
                    expire_date=datetime.now() + timedelta(minutes=5),
                )
                session.add(cooldown_entry)
                await session.commit()
                if uaap_login_status.fail_invalid_credentials:
                    logger.info(f"登录密码错误: {register_info.userid}")
                    return RegisterErrorToCode().uaap_password_error.to_json_response(
                        logger.trace_id
                    )
                else:
                    logger.error(f"AUFE服务异常: {uaap_login_status}")
                    return RegisterErrorToCode().ec_server_error.to_json_response(
                        logger.trace_id
                    )
            # 创建新用户
            new_user = ACEUser(
                userid=register_info.userid,
                ec_password=register_info.ec_password,
                password=register_info.password,
            )
            session.add(new_user)
            await session.commit()
            # 注册成功后删除临时Token
            temp_tokens.remove(register_info.token)
            # 生成Authme Token
            authme_token = secrets.token_urlsafe(128)
            new_token = AuthMEToken(
                user_id=new_user.userid, token=authme_token, device_id=uuid4().hex
            )
            session.add(new_token)
            await session.commit()
            return UniResponseModel[RegisterResponse](
                success=True,
                data=RegisterResponse(token=authme_token),
                message="注册成功",
                error=None,
            )
    except ValueError as ve:
        logger.error("用户注册失败: RSA解密错误")
        logger.exception(ve)
        return RegisterErrorToCode().server_error.to_json_response(
            logger.trace_id, "RSA解密错误，请检查授权密文"
        )
    except Exception as e:
        logger.error("用户注册失败:")
        logger.exception(e)
        return RegisterErrorToCode().server_error.to_json_response(logger.trace_id)
