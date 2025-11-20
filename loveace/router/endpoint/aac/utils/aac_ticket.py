from urllib.parse import unquote

from fastapi import Depends
from httpx import Headers
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from loveace.config.manager import config_manager
from loveace.database.aac.ticket import AACTicket
from loveace.database.creator import get_db_session
from loveace.router.dependencies.auth import ProtectRouterErrorToCode
from loveace.router.endpoint.aac.model.base import AACConfig
from loveace.service.remote.aufe import AUFEConnection
from loveace.service.remote.aufe.depends import get_aufe_conn
from loveace.utils.rsa import RSAUtils

rsa = RSAUtils.get_or_create_rsa_utils(AACConfig.RSA_PRIVATE_KEY_PATH)


def _extract_and_encrypt_token(location: str, logger) -> str | None:
    """从重定向URL中提取并加密系统令牌"""
    try:
        sys_token = location.split("ticket=")[-1]
        # URL编码转为正常字符串
        sys_token = unquote(sys_token)
        if not sys_token:
            logger.error("系统令牌为空")
            return None

        logger.info(f"获取到系统令牌: {sys_token[:10]}...")
        # 加密系统令牌
        encrypted_token = rsa.encrypt(sys_token)
        return encrypted_token
    except Exception as e:
        logger.error(f"解析/加密系统令牌失败: {str(e)}")
        return None


async def get_system_token(conn: AUFEConnection) -> str:
    next_location = AACConfig.LOGIN_SERVICE_URL
    max_redirects = 10  # 防止无限重定向
    redirect_count = 0
    try:
        while redirect_count < max_redirects:
            response = await conn.client.get(
                next_location, follow_redirects=False, timeout=conn.timeout
            )

            # 如果是重定向，继续跟踪
            if response.status_code in (301, 302, 303, 307, 308):
                next_location = response.headers.get("Location")
                if not next_location:
                    conn.logger.error("重定向响应中缺少 Location 头")
                    return ""

                conn.logger.debug(f"重定向到: {next_location}")
                redirect_count += 1

                if "register?ticket=" in next_location:
                    conn.logger.info(f"重定向到爱安财注册页面: {next_location}")
                    encrypted_token = _extract_and_encrypt_token(
                        next_location, conn.logger
                    )
                    return encrypted_token if encrypted_token else ""
            else:
                break

        if redirect_count >= max_redirects:
            conn.logger.error(f"重定向次数过多 ({max_redirects})")
            return ""

        conn.logger.error("未能获取系统令牌")
        return ""

    except Exception as e:
        conn.logger.error(f"获取系统令牌异常: {str(e)}")
        return ""


async def get_aac_header(
    conn: AUFEConnection = Depends(get_aufe_conn),
    db: AsyncSession = Depends(get_db_session),
) -> Headers:
    """
    获取AAC Ticket的依赖项。
    如果用户没有登录AUFE或UAAP，或者AAC Ticket不存在且无法获取新的Ticket，则会抛出HTTP异常。
    否则，返回有效的AAC Ticket字符串。
    """
    # 检查AAC Ticket是否存在
    async with db as session:
        result = await session.execute(
            select(AACTicket).where(AACTicket.userid == conn.userid)
        )
        aac_ticket = result.scalars().first()

    if not aac_ticket:
        aac_ticket = await _get_or_fetch_ticket(conn, db, is_new=True)
    else:
        aac_ticket_token = aac_ticket.aac_token
        try:
            # 解密以验证Ticket有效性
            decrypted_ticket = rsa.decrypt(aac_ticket_token)
            if not decrypted_ticket:
                raise ValueError("解密后的Ticket为空")
            aac_ticket = decrypted_ticket
        except Exception as e:
            conn.logger.error(
                f"用户 {conn.userid} 的 AAC Ticket 无效，正在获取新的 Ticket: {str(e)}"
            )
            aac_ticket = await _get_or_fetch_ticket(conn, db, is_new=False)
        else:
            conn.logger.info(f"用户 {conn.userid} 使用现有的 AAC Ticket")

    return Headers(
        {
            **config_manager.get_settings().aufe.default_headers,
            "ticket": aac_ticket,
            "sdp-app-session": conn.twf_id,
        }
    )


async def _get_or_fetch_ticket(
    conn: AUFEConnection, db: AsyncSession, is_new: bool
) -> str:
    """获取或重新获取AAC Ticket并保存到数据库（返回解密后的ticket）"""
    action_type = "获取" if is_new else "重新获取"
    conn.logger.info(
        f"用户 {conn.userid} 的 AAC Ticket {'不存在' if is_new else '无效'}，正在{action_type}新的 Ticket"
    )

    encrypted_token = await get_system_token(conn)
    if not encrypted_token:
        conn.logger.error(f"用户 {conn.userid} {action_type} AAC Ticket 失败")
        raise ProtectRouterErrorToCode().remote_service_error.to_http_exception(
            conn.logger.trace_id,
            message="获取 AAC Ticket 失败，请检查 AUFE/UAAP 登录状态",
        )

    # 解密token
    try:
        decrypted_token = rsa.decrypt(encrypted_token)
        if not decrypted_token:
            raise ValueError("解密后的Ticket为空")
    except Exception as e:
        conn.logger.error(f"用户 {conn.userid} 解密 AAC Ticket 失败: {str(e)}")
        raise ProtectRouterErrorToCode().remote_service_error.to_http_exception(
            conn.logger.trace_id,
            message="解密 AAC Ticket 失败",
        )

    # 保存加密后的token到数据库
    async with db as session:
        if is_new:
            session.add(AACTicket(userid=conn.userid, aac_token=encrypted_token))
        else:
            result = await session.execute(
                select(AACTicket).where(AACTicket.userid == conn.userid)
            )
            existing_ticket = result.scalars().first()
            if existing_ticket:
                existing_ticket.aac_token = encrypted_token
        await session.commit()

    conn.logger.success(f"用户 {conn.userid} 成功{action_type}并保存新的 AAC Ticket")
    # 返回解密后的token
    return decrypted_token
