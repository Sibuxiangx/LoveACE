from fastapi import Depends, HTTPException

from loveace.database.auth.user import ACEUser
from loveace.router.dependencies.auth import get_user_by_token
from loveace.router.schemas.error import ProtectRouterErrorToCode
from loveace.router.schemas.exception import UniResponseHTTPException
from loveace.service.remote.aufe import AUFEConnection, AUFEService
from loveace.utils.rsa import RSAUtils

service = AUFEService()
rsa = RSAUtils.get_or_create_rsa_utils()


async def get_aufe_service() -> AUFEService:
    """获取AUFE服务实例"""
    return service


async def get_aufe_conn(
    user: ACEUser = Depends(get_user_by_token),
) -> AUFEConnection:
    """获取用户的AUFE连接"""
    service = await get_aufe_service()
    conn = await service.get_or_create_connection(
        user.userid,
        ec_password=rsa.decrypt(user.ec_password),
        password=rsa.decrypt(user.password),
    )
    logger = conn.logger
    # 同步当前请求的 trace_id 到连接的 logger
    conn.logger.trace_id = logger.trace_id
    if conn.ec_logged and conn.uaap_logged:
        logger.info(f"用户 {user.userid} 的AUFE连接已登录且可用")
        return conn
    try:
        # 测试连接是否可用
        if (await conn.check_ec_login_status()).logged_in:
            logger.info(f"用户 {user.userid} 的AUFE连接仍然可用")
            if (await conn.check_uaap_login_status()).logged_in:
                logger.info(f"用户 {user.userid} 的UAAP连接仍然可用")
                return conn
            else:
                logger.info(f"用户 {user.userid} 的UAAP连接不可用，尝试重新登录")
                
                # UAAP登录重试机制 (最多3次)
                uaap_login_status = None
                for uaap_retry in range(3):
                    uaap_login_status = await conn.uaap_login()
                    if uaap_login_status.success:
                        break

                    # 如果是密码错误，直接退出重试
                    if uaap_login_status.fail_invalid_credentials:
                        logger.error(
                            f"用户 {user.userid} UAAP登录失败 (密码错误)，停止重试"
                        )
                        break

                    logger.info(
                        f"用户 {user.userid} UAAP登录重试第 {uaap_retry + 1} 次"
                    )

                if not uaap_login_status or not uaap_login_status.success:
                    if uaap_login_status and uaap_login_status.fail_invalid_credentials:
                        logger.error(
                            f"用户 {user.userid} 的UAAP连接重新登录失败，可能是密码错误"
                        )
                        raise ProtectRouterErrorToCode().user_need_reset_password.to_http_exception(
                            logger.trace_id
                        )
                    else:
                        logger.error(f"用户 {user.userid} 的UAAP连接重新登录失败")
                        raise ProtectRouterErrorToCode().invalid_authentication.to_http_exception(
                            logger.trace_id
                        )

                if (await conn.check_uaap_login_status()).logged_in:
                    logger.info(f"用户 {user.userid} 的UAAP连接重新登录成功")
                    return conn
                else:
                    logger.error(f"用户 {user.userid} 的UAAP连接重新登录失败")
                    raise ProtectRouterErrorToCode().invalid_authentication.to_http_exception(
                        logger.trace_id
                    )
        else:
            logger.info(f"用户 {user.userid} 的AUFE连接不可用，尝试重新登录")
            
            # EC登录重试机制 (最多3次)
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
                    logger.error(
                        f"用户 {user.userid} EC登录失败 (攻击防范或密码错误)，停止重试"
                    )
                    break

                logger.info(
                    f"用户 {user.userid} EC登录重试第 {ec_retry + 1} 次"
                )

            if not ec_login_status or not ec_login_status.success:
                if ec_login_status and ec_login_status.fail_invalid_credentials:
                    logger.error(
                        f"用户 {user.userid} 的AUFE连接重新登录失败，可能是密码错误"
                    )
                    raise ProtectRouterErrorToCode().user_need_reset_password.to_http_exception(
                        logger.trace_id
                    )
                else:
                    logger.error(f"用户 {user.userid} 的AUFE连接重新登录失败")
                    raise ProtectRouterErrorToCode().invalid_authentication.to_http_exception(
                        logger.trace_id
                    )

            if (await conn.check_ec_login_status()).logged_in:
                logger.info(f"用户 {user.userid} 的AUFE连接重新登录成功")
                
                # UAAP登录重试机制 (最多3次)
                uaap_login_status = None
                for uaap_retry in range(3):
                    uaap_login_status = await conn.uaap_login()
                    if uaap_login_status.success:
                        break

                    # 如果是密码错误，直接退出重试
                    if uaap_login_status.fail_invalid_credentials:
                        logger.error(
                            f"用户 {user.userid} UAAP登录失败 (密码错误)，停止重试"
                        )
                        break

                    logger.info(
                        f"用户 {user.userid} UAAP登录重试第 {uaap_retry + 1} 次"
                    )

                if not uaap_login_status or not uaap_login_status.success:
                    if uaap_login_status and uaap_login_status.fail_invalid_credentials:
                        logger.error(
                            f"用户 {user.userid} 的UAAP连接重新登录失败，可能是密码错误"
                        )
                        raise ProtectRouterErrorToCode().user_need_reset_password.to_http_exception(
                            logger.trace_id
                        )
                    else:
                        logger.error(f"用户 {user.userid} 的UAAP连接重新登录失败")
                        raise ProtectRouterErrorToCode().invalid_authentication.to_http_exception(
                            logger.trace_id
                        )

                if (await conn.check_uaap_login_status()).logged_in:
                    logger.info(f"用户 {user.userid} 的UAAP连接重新登录成功")
                    return conn
                else:
                    logger.error(f"用户 {user.userid} 的UAAP连接重新登录失败")
                    raise ProtectRouterErrorToCode().invalid_authentication.to_http_exception(
                        logger.trace_id
                    )
            else:
                logger.error(f"用户 {user.userid} 的AUFE连接重新登录失败")
                raise ProtectRouterErrorToCode().invalid_authentication.to_http_exception(
                    logger.trace_id
                )

    except (HTTPException, UniResponseHTTPException):
        raise
    except Exception as e:
        logger.exception(e)
        raise ProtectRouterErrorToCode().remote_service_error.to_http_exception(
            logger.trace_id
        )
