from fastapi import APIRouter, Depends
from fastapi.responses import JSONResponse
from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncSession

from loveace.database.auth.user import ACEUser
from loveace.database.creator import get_db_session
from loveace.database.isim.room import RoomBind
from loveace.router.dependencies.auth import get_user_by_token
from loveace.router.endpoint.isim.model.protect_router import ISIMRouterErrorToCode
from loveace.router.endpoint.isim.model.room import (
    BindRoomRequest,
    BindRoomResponse,
    BuildingInfo,
    BuildingListResponse,
    CacheRoomsData,
    CurrentRoomResponse,
    FloorRoomsResponse,
    ForceRefreshResponse,
    RoomDetailResponse,
)
from loveace.router.endpoint.isim.utils.isim import ISIMClient, get_isim_client
from loveace.router.endpoint.isim.utils.lock_manager import get_refresh_lock_manager
from loveace.router.schemas.uniresponse import UniResponseModel

isim_room_router = APIRouter(
    prefix="/room",
    responses=ISIMRouterErrorToCode.gen_code_table(),
)


@isim_room_router.get(
    "/list",
    summary="[完整数据] 获取所有楼栋、楼层、房间的完整树形结构",
    response_model=UniResponseModel[CacheRoomsData],
)
async def get_rooms(
    isim_conn: ISIMClient = Depends(get_isim_client),
) -> UniResponseModel[CacheRoomsData] | JSONResponse:
    """
    获取完整的寝室列表（所有楼栋、楼层、房间的树形结构）

    ⚠️ 数据量大：包含所有楼栋的完整数据，适合需要完整数据的场景
    💡 建议：移动端或需要部分数据的场景，请使用其他精细化查询接口
    """
    try:
        rooms = await isim_conn.get_cached_rooms()
        if not rooms:
            return ISIMRouterErrorToCode().null_response.to_json_response(
                isim_conn.client.logger.trace_id
            )
        return UniResponseModel[CacheRoomsData](
            success=True,
            data=rooms,
            message="获取寝室列表成功",
            error=None,
        )
    except Exception as e:
        isim_conn.client.logger.error(f"获取寝室列表异常: {str(e)}")
        return ISIMRouterErrorToCode().server_error.to_json_response(
            isim_conn.client.logger.trace_id
        )


@isim_room_router.get(
    "/list/buildings",
    summary="[轻量级] 获取所有楼栋列表（仅楼栋信息，不含楼层和房间）",
    response_model=UniResponseModel[BuildingListResponse],
)
async def get_all_buildings(
    isim_conn: ISIMClient = Depends(get_isim_client),
) -> UniResponseModel[BuildingListResponse] | JSONResponse:
    """
    获取所有楼栋列表（仅楼栋的代码和名称）

    ✅ 数据量小：只返回楼栋列表，不包含楼层和房间
    💡 使用场景：
       - 楼栋选择器
       - 第一级导航菜单
       - 需要快速获取楼栋列表的场景
    """
    logger = isim_conn.client.logger
    try:
        # 从Hash缓存获取完整数据
        full_data = await isim_conn.get_cached_rooms()

        if not full_data or not full_data.data:
            logger.warning("楼栋数据不存在")
            return ISIMRouterErrorToCode().null_response.to_json_response(
                logger.trace_id
            )

        # 提取楼栋信息
        buildings = [
            {"code": building.code, "name": building.name}
            for building in full_data.data
        ]

        result = BuildingListResponse(
            buildings=[BuildingInfo(**b) for b in buildings],
            building_count=len(buildings),
            datetime=full_data.datetime,
        )

        logger.info(f"成功获取楼栋列表，共 {len(buildings)} 个楼栋")
        return UniResponseModel[BuildingListResponse](
            success=True,
            data=result,
            message=f"获取楼栋列表成功，共 {len(buildings)} 个楼栋",
            error=None,
        )

    except Exception as e:
        logger.error(f"获取楼栋列表异常: {str(e)}")
        return ISIMRouterErrorToCode().server_error.to_json_response(logger.trace_id)


@isim_room_router.get(
    "/list/building/{building_code}",
    summary="[按楼栋查询] 获取指定楼栋的所有楼层和房间",
    response_model=UniResponseModel[CacheRoomsData],
)
async def get_building_rooms(
    building_code: str, isim_conn: ISIMClient = Depends(get_isim_client)
) -> UniResponseModel[CacheRoomsData] | JSONResponse:
    """
    获取指定楼栋及其所有楼层和房间的完整数据

    ✅ 数据量适中：只返回单个楼栋的数据，比完整列表小90%+
    💡 使用场景：
       - 用户选择楼栋后，展示该楼栋的所有楼层和房间
       - 楼栋详情页
       - 减少移动端流量消耗

    Args:
        building_code: 楼栋代码（如：01, 02, 11等）
    """
    logger = isim_conn.client.logger
    try:
        # 使用Hash精细化查询，只获取指定楼栋
        building_data = await isim_conn.get_building_with_floors(building_code)

        if not building_data:
            logger.warning(f"楼栋 {building_code} 不存在或无数据")
            return ISIMRouterErrorToCode().null_response.to_json_response(
                logger.trace_id
            )

        # 构造响应数据
        import datetime

        result = CacheRoomsData(
            datetime=datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
            data=[building_data],
        )

        logger.info(
            f"成功获取楼栋 {building_code} 信息，"
            f"楼层数: {len(building_data.floors)}, "
            f"房间数: {sum(len(f.rooms) for f in building_data.floors)}"
        )
        return UniResponseModel[CacheRoomsData](
            success=True,
            data=result,
            message=f"获取楼栋 {building_code} 信息成功",
            error=None,
        )

    except Exception as e:
        logger.error(f"获取楼栋 {building_code} 信息异常: {str(e)}")
        return ISIMRouterErrorToCode().server_error.to_json_response(logger.trace_id)


@isim_room_router.get(
    "/list/floor/{floor_code}",
    summary="[按楼层查询] 获取指定楼层的所有房间列表",
    response_model=UniResponseModel[FloorRoomsResponse],
)
async def get_floor_rooms(
    floor_code: str, isim_conn: ISIMClient = Depends(get_isim_client)
) -> UniResponseModel[FloorRoomsResponse] | JSONResponse:
    """
    获取指定楼层的所有房间信息

    ✅ 数据量最小：只返回单个楼层的房间列表，极小数据量
    💡 使用场景：
       - 用户选择楼层后，展示该楼层的所有房间
       - 房间选择器的第三级
       - 移动端分页加载
       - 需要最快响应速度的场景

    Args:
        floor_code: 楼层代码（如：0101, 0102, 1101等）
    """
    logger = isim_conn.client.logger
    try:
        # 获取楼层信息
        floor_info = await isim_conn.get_floor_info(floor_code)

        if not floor_info:
            logger.warning(f"楼层 {floor_code} 不存在")
            return ISIMRouterErrorToCode().null_response.to_json_response(
                logger.trace_id
            )

        # 获取房间列表（从Hash直接查询，非常快速）
        rooms = await isim_conn.get_rooms_by_floor(floor_code)

        # 从楼层代码提取楼栋代码（前2位）
        building_code = floor_code[:2] if len(floor_code) >= 2 else ""

        result = FloorRoomsResponse(
            floor_code=floor_info.code,
            floor_name=floor_info.name,
            building_code=building_code,
            rooms=rooms,
            room_count=len(rooms),
        )

        logger.info(
            f"成功获取楼层 {floor_code} ({floor_info.name}) 的房间信息，共 {len(rooms)} 个房间"
        )
        return UniResponseModel[FloorRoomsResponse](
            success=True,
            data=result,
            message=f"获取楼层 {floor_code} 的房间信息成功，共 {len(rooms)} 个房间",
            error=None,
        )

    except Exception as e:
        logger.error(f"获取楼层 {floor_code} 房间信息异常: {str(e)}")
        return ISIMRouterErrorToCode().server_error.to_json_response(logger.trace_id)


@isim_room_router.get(
    "/info/{room_code}",
    summary="[房间详情] 获取单个房间的完整层级信息",
    response_model=UniResponseModel[RoomDetailResponse],
)
async def get_room_info(
    room_code: str, isim_conn: ISIMClient = Depends(get_isim_client)
) -> UniResponseModel[RoomDetailResponse] | JSONResponse:
    """
    获取指定房间的完整信息（包括楼栋、楼层、房间的完整层级结构）

    ✅ 功能强大：一次性返回房间的完整上下文信息
    💡 使用场景：
       - 房间详情页展示
       - 显示完整的 "楼栋/楼层/房间" 路径
       - 房间搜索结果展示
       - 需要房间完整信息的场景

    Args:
        room_code: 房间代码（如：010101, 110627等）
    """
    logger = isim_conn.client.logger
    try:
        # 提取层级代码
        if len(room_code) < 4:
            logger.warning(f"房间代码 {room_code} 格式错误")
            return ISIMRouterErrorToCode().null_response.to_json_response(
                logger.trace_id
            )

        building_code = room_code[:2]
        floor_code = room_code[:4]

        # 并发获取所有需要的信息
        import asyncio

        building_info, floor_info, room_info = await asyncio.gather(
            isim_conn.get_building_info(building_code),
            isim_conn.get_floor_info(floor_code),
            isim_conn.query_room_info_fast(room_code),
        )

        if not room_info:
            logger.warning(f"房间 {room_code} 不存在")
            return ISIMRouterErrorToCode().null_response.to_json_response(
                logger.trace_id
            )

        # 构造显示文本
        building_name = building_info.name if building_info else "未知楼栋"
        floor_name = floor_info.name if floor_info else "未知楼层"
        display_text = f"{building_name}/{floor_name}/{room_info.name}"

        result = RoomDetailResponse(
            room_code=room_info.code,
            room_name=room_info.name,
            floor_code=floor_code,
            floor_name=floor_name,
            building_code=building_code,
            building_name=building_name,
            display_text=display_text,
        )

        logger.info(f"成功获取房间 {room_code} 的详细信息: {display_text}")
        return UniResponseModel[RoomDetailResponse](
            success=True,
            data=result,
            message=f"获取房间 {room_code} 的详细信息成功",
            error=None,
        )

    except Exception as e:
        logger.error(f"获取房间 {room_code} 详细信息异常: {str(e)}")
        return ISIMRouterErrorToCode().server_error.to_json_response(logger.trace_id)


@isim_room_router.post(
    "/bind",
    summary="[用户操作] 绑定寝室到当前用户",
    response_model=UniResponseModel[BindRoomResponse],
)
async def bind_room(
    bind_request: BindRoomRequest,
    isim_conn: ISIMClient = Depends(get_isim_client),
    db: AsyncSession = Depends(get_db_session),
) -> UniResponseModel[BindRoomResponse] | JSONResponse:
    """
    绑定寝室到当前用户（存在即更新）

    💡 使用场景：
       - 用户首次绑定寝室
       - 用户更换寝室
       - 修改绑定信息
    """
    logger = isim_conn.client.logger
    try:
        exist = await db.execute(
            select(RoomBind).where(RoomBind.user_id == isim_conn.client.userid)
        )
        exist = exist.scalars().first()
        if exist:
            if exist.roomid == bind_request.room_id:
                return UniResponseModel[BindRoomResponse](
                    success=True,
                    data=BindRoomResponse(success=True),
                    message="宿舍绑定成功",
                    error=None,
                )
            else:
                # 使用快速查询方法（从Hash直接获取，无需遍历完整树）
                room_info = await isim_conn.query_room_info_fast(bind_request.room_id)
                roomtext = room_info.name if room_info else None

                # 如果Hash中没有，回退到完整查询
                if not roomtext:
                    roomtext = await isim_conn.query_room_name(bind_request.room_id)

                await db.execute(
                    update(RoomBind)
                    .where(RoomBind.user_id == isim_conn.client.userid)
                    .values(roomid=bind_request.room_id, roomtext=roomtext)
                )
                await db.commit()
                logger.info(f"更新寝室绑定成功: {roomtext}({bind_request.room_id})")
                return UniResponseModel[BindRoomResponse](
                    success=True,
                    data=BindRoomResponse(success=True),
                    message="宿舍绑定成功",
                    error=None,
                )
        else:
            # 使用快速查询方法（从Hash直接获取，无需遍历完整树）
            room_info = await isim_conn.query_room_info_fast(bind_request.room_id)
            roomtext = room_info.name if room_info else None

            # 如果Hash中没有，回退到完整查询
            if not roomtext:
                roomtext = await isim_conn.query_room_name(bind_request.room_id)

            new_bind = RoomBind(
                user_id=isim_conn.client.userid,
                roomid=bind_request.room_id,
                roomtext=roomtext,
            )
            db.add(new_bind)
            await db.commit()
            logger.info(f"新增寝室绑定成功: {roomtext}({bind_request.room_id})")
            return UniResponseModel[BindRoomResponse](
                success=True,
                data=BindRoomResponse(success=True),
                message="宿舍绑定成功",
                error=None,
            )
    except Exception as e:
        logger.error(f"绑定寝室异常: {str(e)}")
        return ISIMRouterErrorToCode().server_error.to_json_response(
            isim_conn.client.logger.trace_id
        )


@isim_room_router.get(
    "/current",
    summary="[用户查询] 获取当前用户绑定的宿舍信息",
    response_model=UniResponseModel[CurrentRoomResponse],
)
async def get_current_room(
    user: ACEUser = Depends(get_user_by_token),
    isim_conn: ISIMClient = Depends(get_isim_client),
    db: AsyncSession = Depends(get_db_session),
) -> UniResponseModel[CurrentRoomResponse] | JSONResponse:
    """
    获取当前用户绑定的宿舍信息，返回 room_code 和 display_text

    💡 使用场景：
       - 个人中心显示已绑定宿舍
       - 查询当前用户的寝室信息
       - 验证用户是否已绑定寝室
    """
    logger = isim_conn.client.logger
    try:
        # 查询用户绑定的房间
        result = await db.execute(
            select(RoomBind).where(RoomBind.user_id == user.userid)
        )
        room_bind = result.scalars().first()

        if not room_bind:
            logger.warning(f"用户 {user.userid} 未绑定宿舍")
            return UniResponseModel[CurrentRoomResponse](
                success=True,
                data=CurrentRoomResponse(
                    room_code="",
                    display_text="",
                ),
                message="获取宿舍信息成功，用户未绑定宿舍",
                error=None,
            )

        # 优先从Hash缓存快速获取房间显示文本
        display_text = await isim_conn.get_room_display_text(room_bind.roomid)
        if not display_text:
            # 如果缓存中没有，使用数据库中存储的文本
            display_text = room_bind.roomtext
            logger.debug(
                f"Hash缓存中未找到房间 {room_bind.roomid}，使用数据库存储的文本"
            )

        logger.info(f"成功获取用户 {user.userid} 的宿舍信息: {display_text}")
        return UniResponseModel[CurrentRoomResponse](
            success=True,
            data=CurrentRoomResponse(
                room_code=room_bind.roomid,
                display_text=display_text,
            ),
            message="获取宿舍信息成功",
            error=None,
        )

    except Exception as e:
        logger.error(f"获取当前宿舍异常: {str(e)}")
        return ISIMRouterErrorToCode().server_error.to_json_response(logger.trace_id)


@isim_room_router.post(
    "/refresh",
    summary="[管理操作] 强制刷新房间列表缓存",
    response_model=UniResponseModel[ForceRefreshResponse],
)
async def force_refresh_rooms(
    isim_conn: ISIMClient = Depends(get_isim_client),
) -> UniResponseModel[ForceRefreshResponse] | JSONResponse:
    """
    强制刷新房间列表缓存（从ISIM系统重新获取数据）

    ⚠️ 限制：
       - 使用全局锁确保同一时间只有一个请求在执行刷新操作
       - 刷新完成后有30分钟的冷却时间

    💡 使用场景：
       - 发现数据不准确时手动刷新
       - 管理员更新缓存数据
       - 调试和测试
    """
    logger = isim_conn.client.logger
    lock_manager = get_refresh_lock_manager()

    try:
        # 尝试获取锁
        acquired, remaining_cooldown = await lock_manager.try_acquire()

        if not acquired:
            if remaining_cooldown is not None:
                # 在冷却期内
                minutes = int(remaining_cooldown // 60)
                seconds = int(remaining_cooldown % 60)
                message = f"刷新操作冷却中，请在 {minutes} 分 {seconds} 秒后重试"
                logger.warning(f"刷新请求被拒绝: {message}")
                return UniResponseModel[ForceRefreshResponse](
                    success=False,
                    data=ForceRefreshResponse(
                        success=False,
                        message=message,
                        remaining_cooldown=remaining_cooldown,
                    ),
                    message=message,
                    error=None,
                )
            else:
                # 有其他人正在刷新
                message = "其他用户正在刷新房间列表，请稍后再试"
                logger.warning(message)
                return UniResponseModel[ForceRefreshResponse](
                    success=False,
                    data=ForceRefreshResponse(
                        success=False,
                        message=message,
                        remaining_cooldown=0.0,
                    ),
                    message=message,
                    error=None,
                )

        # 成功获取锁，执行刷新操作
        try:
            logger.info("开始强制刷新房间列表缓存")
            await isim_conn.force_refresh_room_cache()
            logger.info("房间列表缓存刷新完成")

            return UniResponseModel[ForceRefreshResponse](
                success=True,
                data=ForceRefreshResponse(
                    success=True,
                    message="房间列表刷新成功",
                    remaining_cooldown=0.0,
                ),
                message="房间列表刷新成功",
                error=None,
            )

        finally:
            # 释放锁并设置冷却时间
            lock_manager.release()
            logger.info("刷新锁已释放，冷却时间已设置")

    except Exception as e:
        logger.error(f"强制刷新房间列表异常: {str(e)}")
        # 确保异常时也释放锁
        if lock_manager.is_refreshing():
            lock_manager.release()
        return ISIMRouterErrorToCode().server_error.to_json_response(logger.trace_id)
