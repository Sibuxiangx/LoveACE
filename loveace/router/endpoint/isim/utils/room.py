from fastapi import Depends
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from loveace.database.creator import get_db_session
from loveace.database.isim.room import RoomBind
from loveace.router.endpoint.isim.model.protect_router import ISIMRouterErrorToCode
from loveace.router.endpoint.isim.utils.isim import ISIMClient, get_isim_client


async def get_bound_room(
    isim_conn: ISIMClient = Depends(get_isim_client),
    db: AsyncSession = Depends(get_db_session),
) -> RoomBind:
    """获取已绑定的寝室"""
    result = await db.execute(
        select(RoomBind).where(RoomBind.user_id == isim_conn.client.userid)
    )
    bound_room = result.scalars().first()
    if not bound_room:
        raise ISIMRouterErrorToCode.UNBOUNDROOM.to_http_exception(
            isim_conn.client.logger.trace_id
        )
    return bound_room
