from fastapi import APIRouter, Depends
from fastapi.responses import JSONResponse

from loveace.database.isim.room import RoomBind
from loveace.router.endpoint.isim.model.isim import (
    UniISIMInfoResponse,
)
from loveace.router.endpoint.isim.model.protect_router import ISIMRouterErrorToCode
from loveace.router.endpoint.isim.utils.isim import ISIMClient, get_isim_client
from loveace.router.endpoint.isim.utils.room import get_bound_room
from loveace.router.schemas.uniresponse import UniResponseModel

isim_elec_router = APIRouter(
    prefix="/elec",
    responses=ISIMRouterErrorToCode().gen_code_table(),
)


@isim_elec_router.get(
    "/info",
    summary="获取寝室电费信息",
    response_model=UniResponseModel[UniISIMInfoResponse],
)
async def get_isim_info(
    isim: ISIMClient = Depends(get_isim_client),
    room: RoomBind = Depends(get_bound_room),
) -> UniResponseModel[UniISIMInfoResponse] | JSONResponse:
    """
    获取用户绑定宿舍的电费信息

    ✅ 功能特性：
       - 获取当前电费余额
       - 获取用电记录历史
       - 获取缴费记录

    💡 使用场景：
       - 个人中心查看宿舍电费
       - 监测用电情况
       - 查看缴费历史

    Returns:
        UniISIMInfoResponse: 包含房间信息、电费余额、用电记录、缴费记录
    """
    try:
        # 使用 ISIMClient 的集成方法获取电费信息
        result = await isim.get_electricity_info(room.roomid)

        if result is None:
            isim.client.logger.error(f"获取寝室 {room.roomid} 电费信息失败")
            return ISIMRouterErrorToCode().remote_service_error.to_json_response(
                isim.client.logger.trace_id
            )

        room_display = await isim.get_room_display_text(room.roomid)
        room_display = "" if room_display is None else room_display
        return UniResponseModel[UniISIMInfoResponse](
            success=True,
            data=UniISIMInfoResponse(
                room_code=room.roomid,
                room_display=room_display,
                room_text=room.roomtext,
                balance=result["balance"],
                usage_records=result["usage_records"],
                payments=result["payments"],
            ),
            message="获取寝室电费信息成功",
            error=None,
        )
    except Exception as e:
        isim.client.logger.error("获取寝室电费信息异常")
        isim.client.logger.exception(e)
        return ISIMRouterErrorToCode().server_error.to_json_response(
            isim.client.logger.trace_id
        )
