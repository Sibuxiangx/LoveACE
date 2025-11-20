from typing import List

from pydantic import BaseModel, Field

##############################################################
# *                     寝室绑定请求模型                       *#
##############################################################


class BindRoomRequest(BaseModel):
    """绑定寝室请求模型"""

    room_id: str = Field(..., description="寝室ID")


##############################################################
# *                     寝室绑定响应模型                       *#
##############################################################


class BindRoomResponse(BaseModel):
    """绑定寝室响应模型"""

    success: bool = Field(..., description="是否绑定成功")


##############################################################
# *                     楼栋信息模型                          *#
##############################################################


class BuildingInfo(BaseModel):
    """楼栋信息"""

    code: str = Field(..., description="楼栋代码")
    name: str = Field(..., description="楼栋名称")


##############################################################
# *                     楼层信息模型                          *#
##############################################################


class FloorInfo(BaseModel):
    """楼层信息"""

    code: str = Field(..., description="楼层代码")
    name: str = Field(..., description="楼层名称")


##############################################################
# *                     房间信息模型                          *#
##############################################################


class RoomInfo(BaseModel):
    """房间信息"""

    code: str = Field(..., description="房间代码")
    name: str = Field(..., description="房间名称")


###############################################################
# *                  楼栋-楼层-房间信息模型                     *#
###############################################################
class CacheFloorData(BaseModel):
    """缓存的楼层信息"""

    code: str = Field(..., description="楼层代码")
    name: str = Field(..., description="楼层名称")
    rooms: List[RoomInfo] = Field(..., description="房间列表")


class CacheBuildingData(BaseModel):
    """缓存的楼栋信息"""

    code: str = Field(..., description="楼栋代码")
    name: str = Field(..., description="楼栋名称")
    floors: List[CacheFloorData] = Field(..., description="楼层列表")


class CacheRoomsData(BaseModel):
    """缓存的寝室信息"""

    datetime: str = Field(..., description="数据更新时间，格式：YYYY-MM-DD HH:MM:SS")
    data: List[CacheBuildingData] = Field(..., description="楼栋列表")


class RoomBindingInfo(BaseModel):
    """房间绑定信息"""

    building: BuildingInfo
    floor: FloorInfo
    room: RoomInfo
    room_id: str = Field(..., description="完整房间ID")
    display_text: str = Field(
        ..., description="显示文本，如：北苑11号学生公寓/11-6层/11-627"
    )


##############################################################
# *                 获取当前宿舍响应模型                        *#
##############################################################


class CurrentRoomResponse(BaseModel):
    """获取当前宿舍响应模型"""

    room_code: str = Field(..., description="房间代码")
    display_text: str = Field(
        ..., description="显示文本，如：北苑11号学生公寓/11-6层/11-627"
    )


##############################################################
# *                 强制刷新响应模型                           *#
##############################################################


class ForceRefreshResponse(BaseModel):
    """强制刷新响应模型"""

    success: bool = Field(..., description="是否刷新成功")
    message: str = Field(..., description="响应消息")
    remaining_cooldown: float = Field(
        default=0.0, description="剩余冷却时间（秒），0表示无冷却"
    )


##############################################################
# *                 楼层房间查询响应模型                        *#
##############################################################


class FloorRoomsResponse(BaseModel):
    """楼层房间查询响应模型"""

    floor_code: str = Field(..., description="楼层代码")
    floor_name: str = Field(..., description="楼层名称")
    building_code: str = Field(..., description="所属楼栋代码")
    rooms: List[RoomInfo] = Field(..., description="房间列表")
    room_count: int = Field(..., description="房间数量")


##############################################################
# *                 房间详情查询响应模型                        *#
##############################################################


class RoomDetailResponse(BaseModel):
    """房间详情查询响应模型"""

    room_code: str = Field(..., description="房间代码")
    room_name: str = Field(..., description="房间名称")
    floor_code: str = Field(..., description="所属楼层代码")
    floor_name: str = Field(..., description="所属楼层名称")
    building_code: str = Field(..., description="所属楼栋代码")
    building_name: str = Field(..., description="所属楼栋名称")
    display_text: str = Field(..., description="完整显示文本")


##############################################################
# *                 楼栋列表响应模型                           *#
##############################################################


class BuildingListResponse(BaseModel):
    """楼栋列表响应模型"""

    buildings: List[BuildingInfo] = Field(..., description="楼栋列表")
    building_count: int = Field(..., description="楼栋数量")
    datetime: str = Field(..., description="数据更新时间")
