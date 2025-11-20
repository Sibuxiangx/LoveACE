import asyncio
import datetime
import hashlib
import json
import random
import re
from functools import wraps
from typing import Any, Dict, List, Optional

from bs4 import BeautifulSoup
from fastapi import Depends

from loveace.config.manager import config_manager
from loveace.router.endpoint.isim.model.isim import (
    ElectricityBalance,
    ElectricityUsageRecord,
    PaymentRecord,
)
from loveace.router.endpoint.isim.model.room import (
    BuildingInfo,
    CacheBuildingData,
    CacheFloorData,
    CacheRoomsData,
    FloorInfo,
    RoomInfo,
)
from loveace.service.remote.aufe import AUFEConnection, SubClient
from loveace.service.remote.aufe.depends import get_aufe_conn
from loveace.utils.redis_client import get_redis_client


def ensure_session(func):
    """装饰器：确保在调用方法前已初始化会话"""

    @wraps(func)
    async def wrapper(self, *args, **kwargs):
        if isinstance(self, ISIMClient):
            await self._ensure_jsession()
            return await func(self, *args, **kwargs)

    return wrapper


class ISIMClient(SubClient):
    """ISIM系统客户端，用于获取楼栋、楼层和房间信息

    该客户端会自动管理会话初始化，无需手动调用 get_jsession()
    """

    DEFAULT_BASE_URL = config_manager.get_settings().isim.base_url.rstrip("/")

    def __init__(self, aufe_connection: AUFEConnection, auto_init: bool = True):
        """
        初始化ISIM客户端

        Args:
            aufe_connection: AUFE连接实例
            auto_init: 是否自动初始化会话（默认为True，推荐保持默认）
        """
        self.client = aufe_connection
        self.config = config_manager.get_settings()
        self._jsessionid: Optional[str] = None
        self._session_initialized = False
        self._auto_init = auto_init
        self._init_lock = asyncio.Lock()  # 防止并发初始化
        self._jsession_bound = False  # 标记是否已绑定寝室

    def _generate_session_params(self) -> Dict[str, str]:
        """生成会话参数（openid和sn）"""
        seed = self.client.userid if self.client.userid != "unknown" else "default"

        # 生成openid - 基于学号的哈希值
        openid_hash = hashlib.md5(f"{seed}_openid".encode()).hexdigest()
        openid = openid_hash[:15] + str(random.randint(100, 999))

        # 生成sn - 简单使用固定值
        sn = "sn"

        return {"openid": openid, "sn": sn}

    async def _ensure_jsession(self) -> None:
        """
        确保会话已初始化（内部方法）
        使用锁机制防止并发初始化
        """
        if self._session_initialized and self._jsessionid:
            return

        async with self._init_lock:
            # 双重检查，避免重复初始化
            if self._session_initialized and self._jsessionid:
                return

            if not self._auto_init:
                raise RuntimeError(
                    "ISIM会话未初始化。请先调用 get_jsession() 或在创建实例时设置 auto_init=True"
                )

            success = await self.get_jsession()
            if not success:
                raise RuntimeError("ISIM会话初始化失败，请检查网络连接或认证状态")

    async def get_jsession(self) -> bool:
        """
        初始化ISIM会话，获取JSESSIONID

        通常不需要手动调用此方法，客户端会在需要时自动初始化

        Returns:
            bool: 是否成功获取JSESSIONID
        """
        try:
            self.client.logger.info("开始初始化ISIM会话")

            params = self._generate_session_params()

            response = await self.client.client.get(
                f"{self.DEFAULT_BASE_URL}/go",
                params=params,
                follow_redirects=False,
                timeout=self.client.timeout,
            )

            # 检查是否收到302重定向响应
            if response.status_code == 302:
                set_cookie_header = response.headers.get("set-cookie", "")
                if "JSESSIONID=" in set_cookie_header:
                    jsessionid_match = re.search(
                        r"JSESSIONID=([^;]+)", set_cookie_header
                    )
                    if jsessionid_match:
                        self._jsessionid = jsessionid_match.group(1)
                        self._session_initialized = True  # 标记会话已初始化
                        self.client.logger.info(
                            f"成功获取JSESSIONID: {jsessionid_match.group(1)[:10]}***"
                        )

                        # 验证重定向位置
                        location = response.headers.get("location", "")
                        if "home" in location and "jsessionid" in location:
                            self.client.logger.info(
                                f"重定向位置正确: {location[:8]}****"
                            )
                        else:
                            self.client.logger.warning(f"重定向位置异常: {location}")

                        return True

                self.client.logger.error("未能从Set-Cookie头中提取JSESSIONID")
                return False
            else:
                self.client.logger.error(
                    f"期望302重定向，但收到状态码: {response.status_code}"
                )
                if response.text:
                    self.client.logger.debug(f"响应内容: {response.text[:200]}...")
                return False

        except Exception as e:
            self.client.logger.error(f"初始化ISIM会话异常: {str(e)}")
            return False

    @ensure_session
    async def get_buildings(
        self, jsessionid: Optional[str] = None
    ) -> List[BuildingInfo]:
        """
        获取楼栋列表

        Args:
            jsessionid: 会话ID，通常不需要提供（自动使用实例中的ID）

        Returns:
            List[BuildingInfo]: 楼栋信息列表
        """
        jsessionid = jsessionid or self._jsessionid

        try:
            headers = {
                **self.config.aufe.default_headers,
                "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7",
                "Accept-Language": "zh-CN,zh;q=0.9",
                "Connection": "keep-alive",
                "Upgrade-Insecure-Requests": "1",
                "Cookie": f"JSESSIONID={jsessionid}; TWFID={self.client.twf_id}",
                "Referer": f"{self.DEFAULT_BASE_URL}/home;jsessionid={jsessionid}",
            }

            response = await self.client.client.get(
                f"{self.DEFAULT_BASE_URL}/about",
                headers=headers,
                follow_redirects=True,
                timeout=self.client.timeout,
            )

            if response.status_code != 200:
                raise Exception(f"请求失败，状态码: {response.status_code}")

            # 解析HTML页面获取楼栋信息
            soup = BeautifulSoup(response.text, "html.parser")
            buildings = []
            scripts = soup.find_all("script")

            for script in scripts:
                if script.string and "pickerBuilding" in script.string:
                    values_match = re.search(r"values:\s*\[(.*?)\]", script.string)
                    display_values_match = re.search(
                        r"displayValues:\s*\[(.*?)\]", script.string
                    )

                    if values_match and display_values_match:
                        values_str = values_match.group(1)
                        display_values_str = display_values_match.group(1)

                        values = [v.strip().strip('"') for v in values_str.split(",")]
                        display_values = [
                            v.strip().strip('"') for v in display_values_str.split(",")
                        ]

                        for code, name in zip(values, display_values):
                            if code and code != '""' and name != "请选择":
                                buildings.append(BuildingInfo(code=code, name=name))
                        break

            self.client.logger.info(f"成功获取{len(buildings)}个楼栋信息")
            return buildings

        except Exception as e:
            self.client.logger.exception(e)
            self.client.logger.error(f"获取楼栋列表异常: {str(e)}")
            return []

    @ensure_session
    async def get_floors(
        self, building_code: str, jsessionid: Optional[str] = None
    ) -> List[FloorInfo]:
        """
        获取指定楼栋的楼层列表

        Args:
            building_code: 楼栋代码
            jsessionid: 会话ID，通常不需要提供（自动使用实例中的ID）

        Returns:
            List[FloorInfo]: 楼层信息列表
        """
        jsessionid = jsessionid or self._jsessionid

        try:
            self.client.logger.info(f"开始获取楼层列表，楼栋代码: {building_code}")

            headers = {
                **self.config.aufe.default_headers,
                "Accept": "application/json, text/javascript, */*; q=0.01",
                "Accept-Language": "zh-CN,zh;q=0.9",
                "Connection": "keep-alive",
                "X-Requested-With": "XMLHttpRequest",
                "Cookie": f"JSESSIONID={jsessionid}; TWFID={self.client.twf_id}",
                "Referer": f"{self.DEFAULT_BASE_URL}/about;jsessionid={jsessionid}",
            }

            response = await self.client.client.get(
                f"{self.DEFAULT_BASE_URL}/about/floors/{building_code}",
                headers=headers,
                follow_redirects=True,
                timeout=self.client.timeout,
            )

            if response.status_code != 200:
                raise Exception(f"请求失败，状态码: {response.status_code}")

            # 解析响应
            data_str = response.text.strip()
            self.client.logger.debug(f"楼层响应原始数据: {data_str[:200]}...")

            try:
                json_data = response.json()
            except Exception:
                # 手动转换JavaScript对象字面量为JSON格式
                json_str = re.sub(r"([a-zA-Z_][a-zA-Z0-9_]*)\s*:", r'"\1":', data_str)
                self.client.logger.debug(f"转换后的JSON字符串: {json_str[:200]}...")
                json_data = json.loads(json_str)

            floors = []

            if isinstance(json_data, list) and len(json_data) > 0:
                floor_data = json_data[0]
                floor_codes = floor_data.get("floordm", [])
                floor_names = floor_data.get("floorname", [])

                # 跳过第一个空值（"请选择"）
                for code, name in zip(floor_codes[1:], floor_names[1:]):
                    if code and name and name != "请选择":
                        floors.append(FloorInfo(code=code, name=name))

                self.client.logger.info(f"成功获取{len(floors)}个楼层信息")
                return floors
            else:
                self.client.logger.warning(f"楼层数据格式异常: {json_data}")
                return []

        except Exception as e:
            self.client.logger.error(f"获取楼层列表异常: {str(e)}")
            return []

    @ensure_session
    async def get_rooms(
        self, floor_code: str, jsessionid: Optional[str] = None
    ) -> List[RoomInfo]:
        """
        获取指定楼层的房间列表

        Args:
            floor_code: 楼层代码
            jsessionid: 会话ID，通常不需要提供（自动使用实例中的ID）

        Returns:
            List[RoomInfo]: 房间信息列表
        """
        jsessionid = jsessionid or self._jsessionid

        try:
            self.client.logger.info(f"开始获取房间列表，楼层代码: {floor_code}")

            headers = {
                **self.config.aufe.default_headers,
                "Accept": "application/json, text/javascript, */*; q=0.01",
                "Accept-Language": "zh-CN,zh;q=0.9",
                "Connection": "keep-alive",
                "X-Requested-With": "XMLHttpRequest",
                "Cookie": f"JSESSIONID={jsessionid}; TWFID={self.client.twf_id}",
                "Referer": f"{self.DEFAULT_BASE_URL}/about;jsessionid={jsessionid}",
            }

            response = await self.client.client.get(
                f"{self.DEFAULT_BASE_URL}/about/rooms/{floor_code}",
                headers=headers,
                follow_redirects=True,
                timeout=self.client.timeout,
            )

            if response.status_code != 200:
                raise Exception(f"请求失败，状态码: {response.status_code}")

            # 解析响应
            data_str = response.text.strip()
            self.client.logger.debug(f"房间响应原始数据: {data_str[:200]}...")

            try:
                json_data = response.json()
            except Exception:
                # 手动转换JavaScript对象字面量为JSON格式
                json_str = re.sub(r"([a-zA-Z_][a-zA-Z0-9_]*)\s*:", r'"\1":', data_str)
                self.client.logger.debug(f"转换后的JSON字符串: {json_str[:200]}...")
                json_data = json.loads(json_str)

            rooms = []

            if isinstance(json_data, list) and len(json_data) > 0:
                room_data = json_data[0]
                room_codes = room_data.get("roomdm", [])
                room_names = room_data.get("roomname", [])

                # 跳过第一个空值（"请选择"）
                for code, name in zip(room_codes[1:], room_names[1:]):
                    if code and name and name != "请选择":
                        rooms.append(RoomInfo(code=code, name=name))

                self.client.logger.info(f"成功获取{len(rooms)}个房间信息")
                return rooms
            else:
                self.client.logger.warning(f"房间数据格式异常: {json_data}")
                return []

        except Exception as e:
            self.client.logger.error(f"获取房间列表异常: {str(e)}")
            return []

    @ensure_session
    async def bind_room_to_jsession(self, room_code: str) -> bool:
        """
        绑定房间到当前会话

        Args:
            room_code: 房间代码

        Returns:
            bool: 是否绑定成功
        """
        if self._jsession_bound:
            return True  # 已绑定，直接返回成功
        params = self._generate_session_params()
        room_id = room_code
        display_text = await self.get_room_display_text(room_id)
        if not display_text:
            self.client.logger.error(f"未找到房间名称: {room_id}")
            return False

        data = {
            "sn": params["sn"],
            "openid": params["openid"],
            "roomdm": room_id,
            "room": display_text,
            "mode": "u",  # u表示更新绑定
        }
        headers = {
            **self.config.aufe.default_headers,
            "Accept": "application/json, text/javascript, */*; q=0.01",
            "Accept-Language": "zh-CN,zh;q=0.9",
            "Connection": "keep-alive",
            "X-Requested-With": "XMLHttpRequest",
            "Content-Type": "application/x-www-form-urlencoded; charset=UTF-8",
            "Cookie": f"JSESSIONID={self._jsessionid}; TWFID={self.client.twf_id}",
            "Referer": f"{self.DEFAULT_BASE_URL}/about;jsessionid={self._jsessionid}",
        }
        response = await self.client.client.post(
            f"{self.DEFAULT_BASE_URL}/about/rebinding",
            headers=headers,
            data=data,
            follow_redirects=True,
            timeout=self.client.timeout,
        )
        if response.status_code != 200:
            self.client.logger.error(
                f"绑定寝室请求失败，状态码: {response.status_code}"
            )
            return False
        self._jsession_bound = True
        return True

    @ensure_session
    async def get_all_room_data(
        self, max_retries: int = 2, retry_delay: float = 1.0
    ) -> CacheRoomsData:
        """
        获取所有楼栋、楼层和房间的完整数据结构

        支持失败节点自动重试机制：
        - 第一轮并发请求所有数据
        - 提取失败的楼层节点
        - 单独重试失败节点

        Args:
            max_retries: 失败节点最大重试次数，默认2次
            retry_delay: 重试延迟时间（秒），默认1秒

        Returns:
            CacheRoomsData: 完整的房间数据结构
        """
        jsessionid = self._jsessionid

        # 第一步：获取所有楼栋
        self.client.logger.info("开始获取所有楼栋信息")
        buildings = await self.get_buildings(jsessionid)

        if not buildings:
            self.client.logger.error("获取楼栋列表失败")
            return CacheRoomsData(
                datetime=datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
                data=[],
            )

        # 第二步：并发获取所有楼层
        self.client.logger.info(f"开始并发获取 {len(buildings)} 个楼栋的楼层信息")
        floor_tasks = [
            self.get_floors(building.code, jsessionid) for building in buildings
        ]
        all_floors = await asyncio.gather(*floor_tasks, return_exceptions=True)

        # 处理楼层获取结果，记录失败的楼栋
        failed_buildings: List[BuildingInfo] = []
        valid_floors: List[List[FloorInfo]] = []

        for i, floors_result in enumerate(all_floors):
            if isinstance(floors_result, Exception):
                self.client.logger.warning(
                    f"楼栋 {buildings[i].code} ({buildings[i].name}) "
                    f"获取楼层失败: {str(floors_result)}"
                )
                failed_buildings.append(buildings[i])
                valid_floors.append([])
            elif not floors_result or not isinstance(floors_result, list):
                self.client.logger.warning(
                    f"楼栋 {buildings[i].code} ({buildings[i].name}) 楼层数据为空"
                )
                valid_floors.append([])
            else:
                valid_floors.append(floors_result)

        # 重试失败的楼栋
        if failed_buildings and max_retries > 0:
            self.client.logger.info(
                f"开始重试 {len(failed_buildings)} 个失败的楼栋，最大重试次数: {max_retries}"
            )

            for retry_count in range(1, max_retries + 1):
                if not failed_buildings:
                    break

                self.client.logger.info(
                    f"第 {retry_count} 次重试，待重试楼栋数: {len(failed_buildings)}"
                )

                # 延迟后重试
                if retry_delay > 0:
                    await asyncio.sleep(retry_delay)

                retry_tasks = [
                    self.get_floors(building.code, jsessionid)
                    for building in failed_buildings
                ]
                retry_results = await asyncio.gather(
                    *retry_tasks, return_exceptions=True
                )

                # 更新成功的结果
                new_failed_buildings: List[BuildingInfo] = []
                for i, result in enumerate(retry_results):
                    building = failed_buildings[i]
                    building_index = next(
                        (
                            idx
                            for idx, b in enumerate(buildings)
                            if b.code == building.code
                        ),
                        None,
                    )

                    if isinstance(result, Exception):
                        self.client.logger.warning(
                            f"重试 {retry_count}: 楼栋 {building.code} 仍然失败: {str(result)}"
                        )
                        new_failed_buildings.append(building)
                    elif not result or not isinstance(result, list):
                        self.client.logger.warning(
                            f"重试 {retry_count}: 楼栋 {building.code} 数据为空"
                        )
                    else:
                        self.client.logger.info(
                            f"重试 {retry_count}: 楼栋 {building.code} 成功获取 {len(result)} 个楼层"
                        )
                        if building_index is not None:
                            valid_floors[building_index] = result

                failed_buildings = new_failed_buildings

        # 统计最终失败的楼栋
        if failed_buildings:
            self.client.logger.error(
                f"最终仍有 {len(failed_buildings)} 个楼栋获取失败: "
                f"{[f'{b.code}({b.name})' for b in failed_buildings]}"
            )

        # 第三步：并发获取所有房间
        self.client.logger.info("开始并发获取所有房间信息")

        # 收集所有楼层代码及其所属楼栋索引
        floor_info_list: List[tuple[int, int, FloorInfo]] = (
            []
        )  # (building_idx, floor_idx, floor)
        for building_idx, floors in enumerate(valid_floors):
            for floor_idx, floor in enumerate(floors):
                floor_info_list.append((building_idx, floor_idx, floor))

        # 并发获取房间
        room_tasks = [
            self.get_rooms(floor.code, jsessionid) for _, _, floor in floor_info_list
        ]
        all_rooms_results = await asyncio.gather(*room_tasks, return_exceptions=True)

        # 处理房间获取结果
        failed_floors: List[tuple[int, int, FloorInfo]] = []
        room_results_map: Dict[str, List[RoomInfo]] = {}

        for i, rooms_result in enumerate(all_rooms_results):
            building_idx, floor_idx, floor = floor_info_list[i]

            if isinstance(rooms_result, Exception):
                self.client.logger.warning(
                    f"楼层 {floor.code} ({floor.name}) 获取房间失败: {str(rooms_result)}"
                )
                failed_floors.append((building_idx, floor_idx, floor))
                room_results_map[floor.code] = []
            elif not rooms_result or not isinstance(rooms_result, list):
                self.client.logger.debug(
                    f"楼层 {floor.code} ({floor.name}) 房间数据为空"
                )
                room_results_map[floor.code] = []
            else:
                room_results_map[floor.code] = rooms_result

        # 重试失败的楼层
        if failed_floors and max_retries > 0:
            self.client.logger.info(
                f"开始重试 {len(failed_floors)} 个失败的楼层，最大重试次数: {max_retries}"
            )

            for retry_count in range(1, max_retries + 1):
                if not failed_floors:
                    break

                self.client.logger.info(
                    f"第 {retry_count} 次重试，待重试楼层数: {len(failed_floors)}"
                )

                # 延迟后重试
                if retry_delay > 0:
                    await asyncio.sleep(retry_delay)

                retry_tasks = [
                    self.get_rooms(floor.code, jsessionid)
                    for _, _, floor in failed_floors
                ]
                retry_results = await asyncio.gather(
                    *retry_tasks, return_exceptions=True
                )

                # 更新成功的结果
                new_failed_floors: List[tuple[int, int, FloorInfo]] = []
                for i, result in enumerate(retry_results):
                    building_idx, floor_idx, floor = failed_floors[i]

                    if isinstance(result, Exception):
                        self.client.logger.warning(
                            f"重试 {retry_count}: 楼层 {floor.code} 仍然失败: {str(result)}"
                        )
                        new_failed_floors.append((building_idx, floor_idx, floor))
                    elif not result or not isinstance(result, list):
                        self.client.logger.warning(
                            f"重试 {retry_count}: 楼层 {floor.code} 数据为空"
                        )
                        room_results_map[floor.code] = []
                    else:
                        self.client.logger.info(
                            f"重试 {retry_count}: 楼层 {floor.code} 成功获取 {len(result)} 个房间"
                        )
                        room_results_map[floor.code] = result

                failed_floors = new_failed_floors

        # 统计最终失败的楼层
        if failed_floors:
            self.client.logger.error(
                f"最终仍有 {len(failed_floors)} 个楼层获取失败: "
                f"{[f'{floor.code}({floor.name})' for _, _, floor in failed_floors]}"
            )

        # 第四步：构建完整数据结构
        self.client.logger.info("开始构建完整数据结构")
        buildings.sort(key=lambda b: b.code)

        data = []
        for i, building in enumerate(buildings):
            floors = valid_floors[i]
            if not floors:
                # 该楼栋没有楼层数据，跳过
                continue

            floors.sort(key=lambda f: f.code)

            floor_data_list = []
            for floor in floors:
                rooms = room_results_map.get(floor.code, [])
                floor_data_list.append(
                    CacheFloorData(
                        code=floor.code,
                        name=floor.name,
                        rooms=rooms,
                    )
                )

            data.append(
                CacheBuildingData(
                    code=building.code,
                    name=building.name,
                    floors=floor_data_list,
                )
            )

        result = CacheRoomsData(
            datetime=datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
            data=data,
        )

        # 统计信息
        total_buildings = len(result.data)
        total_floors = sum(len(b.floors) for b in result.data)
        total_rooms = sum(
            len(floor.rooms) for building in result.data for floor in building.floors
        )

        self.client.logger.info(
            f"数据获取完成 - 楼栋: {total_buildings}, 楼层: {total_floors}, 房间: {total_rooms}"
        )

        return result

    async def _cache_room_data_to_hash(self) -> None:
        """
        将房间数据平铺缓存到Redis Hash中，过期时间为一周

        Hash结构:
        - key: isim:rooms:v1:data
        - fields:
            - meta: 元数据（更新时间、版本号）
            - building:{code}: 楼栋信息 JSON
            - floor:{code}: 楼层信息 JSON
            - rooms:{floor_code}: 该楼层的所有房间列表 JSON
        """
        try:
            self.client.logger.info("开始构建Hash缓存结构")
            data = await self.get_all_room_data()
            redis_client = await get_redis_client()

            # 构建Hash映射
            hash_mapping: Dict[str, Any] = {}

            # 添加元数据
            meta = {
                "datetime": data.datetime,
                "version": "v1",
                "building_count": len(data.data),
            }
            hash_mapping["meta"] = json.dumps(meta, ensure_ascii=False)

            # 平铺楼栋、楼层、房间数据
            floor_count = 0
            room_count = 0

            for building in data.data:
                # 存储楼栋信息
                building_key = f"building:{building.code}"
                building_info = {
                    "code": building.code,
                    "name": building.name,
                }
                hash_mapping[building_key] = json.dumps(
                    building_info, ensure_ascii=False
                )

                # 存储楼层和房间信息
                for floor in building.floors:
                    floor_count += 1

                    # 存储楼层信息
                    floor_key = f"floor:{floor.code}"
                    floor_info = {
                        "code": floor.code,
                        "name": floor.name,
                        "building_code": building.code,
                    }
                    hash_mapping[floor_key] = json.dumps(floor_info, ensure_ascii=False)

                    # 存储该楼层的所有房间
                    rooms_key = f"rooms:{floor.code}"
                    rooms_list = [
                        {"code": room.code, "name": room.name} for room in floor.rooms
                    ]
                    room_count += len(rooms_list)
                    hash_mapping[rooms_key] = json.dumps(rooms_list, ensure_ascii=False)

            # 批量写入Hash
            HASH_KEY = "isim:rooms:v1:data"
            await redis_client.hash_set(HASH_KEY, hash_mapping)

            # 设置过期时间为一周
            ONE_WEEK_SECONDS = 7 * 24 * 60 * 60
            await redis_client.expire(HASH_KEY, ONE_WEEK_SECONDS)

            self.client.logger.info(
                f"房间数据已缓存到Redis Hash，"
                f"楼栋数: {len(data.data)}, "
                f"楼层数: {floor_count}, "
                f"房间数: {room_count}, "
                f"过期时间: 7天"
            )

        except Exception as e:
            self.client.logger.error(f"缓存房间数据到Redis Hash失败: {str(e)}")
            self.client.logger.exception(e)

    async def get_cached_rooms_from_hash(
        self,
        building_code: Optional[str] = None,
        floor_code: Optional[str] = None,
    ) -> Optional[CacheRoomsData]:
        """
        从Redis Hash中获取房间缓存数据

        支持全量获取或按楼栋/楼层查询

        Args:
            building_code: 楼栋代码，为None则获取全部
            floor_code: 楼层代码，为None则获取该楼栋全部楼层

        Returns:
            CacheRoomsData: 房间数据，不存在返回None
        """
        try:
            redis_client = await get_redis_client()
            HASH_KEY = "isim:rooms:v1:data"

            # 检查Hash是否存在
            if not await redis_client.exists(HASH_KEY):
                self.client.logger.info("Redis Hash缓存不存在")
                return None

            # 获取元数据
            meta_str = await redis_client.hash_get(HASH_KEY, "meta")
            if not meta_str:
                self.client.logger.warning("Hash中缺少元数据")
                return None

            meta = json.loads(meta_str)

            # 根据查询条件获取数据
            if building_code:
                # 按楼栋或楼层查询
                return await self._get_rooms_by_building(
                    redis_client, HASH_KEY, building_code, floor_code, meta
                )
            else:
                # 全量查询
                return await self._get_all_rooms_from_hash(redis_client, HASH_KEY, meta)

        except Exception as e:
            self.client.logger.error(f"从Hash获取房间缓存异常: {str(e)}")
            self.client.logger.exception(e)
            return None

    async def _get_all_rooms_from_hash(
        self,
        redis_client: Any,
        hash_key: str,
        meta: Dict[str, Any],
    ) -> CacheRoomsData:
        """从Hash中获取所有房间数据"""
        try:
            # 获取所有Hash字段
            all_data = await redis_client.hash_get_all(hash_key)

            # 提取所有楼栋代码
            building_codes = set()
            for field in all_data.keys():
                if field.startswith("building:"):
                    code = field.replace("building:", "")
                    building_codes.add(code)

            # 构建完整数据结构
            buildings = []
            for building_code in sorted(building_codes):
                building_key = f"building:{building_code}"
                building_data = json.loads(all_data.get(building_key, "{}"))

                if not building_data:
                    continue

                # 查找该楼栋的所有楼层
                floors = []
                for field, value in all_data.items():
                    if field.startswith("floor:") and field.replace(
                        "floor:", ""
                    ).startswith(building_code):
                        floor_data = json.loads(value)
                        floor_code = floor_data["code"]

                        # 获取该楼层的房间
                        rooms_key = f"rooms:{floor_code}"
                        rooms_data = json.loads(all_data.get(rooms_key, "[]"))

                        floors.append(
                            CacheFloorData(
                                code=floor_data["code"],
                                name=floor_data["name"],
                                rooms=[RoomInfo(**room) for room in rooms_data],
                            )
                        )

                # 按楼层代码排序
                floors.sort(key=lambda f: f.code)

                buildings.append(
                    CacheBuildingData(
                        code=building_data["code"],
                        name=building_data["name"],
                        floors=floors,
                    )
                )

            return CacheRoomsData(
                datetime=meta.get("datetime", ""),
                data=buildings,
            )

        except Exception as e:
            self.client.logger.error(f"从Hash构建完整数据结构失败: {str(e)}")
            raise

    async def _get_rooms_by_building(
        self,
        redis_client: Any,
        hash_key: str,
        building_code: str,
        floor_code: Optional[str],
        meta: Dict[str, Any],
    ) -> CacheRoomsData:
        """从Hash中按楼栋获取房间数据"""
        try:
            # 获取楼栋信息
            building_key = f"building:{building_code}"
            building_str = await redis_client.hash_get(hash_key, building_key)

            if not building_str:
                self.client.logger.warning(f"楼栋 {building_code} 不存在")
                return CacheRoomsData(datetime=meta.get("datetime", ""), data=[])

            building_data = json.loads(building_str)

            # 获取楼层列表
            floors = []

            if floor_code:
                # 查询特定楼层
                floor_key = f"floor:{floor_code}"
                floor_str = await redis_client.hash_get(hash_key, floor_key)

                if floor_str:
                    floor_data = json.loads(floor_str)
                    rooms_key = f"rooms:{floor_code}"
                    rooms_str = await redis_client.hash_get(hash_key, rooms_key)
                    rooms_data = json.loads(rooms_str) if rooms_str else []

                    floors.append(
                        CacheFloorData(
                            code=floor_data["code"],
                            name=floor_data["name"],
                            rooms=[RoomInfo(**room) for room in rooms_data],
                        )
                    )
            else:
                # 查询该楼栋的所有楼层
                all_data = await redis_client.hash_get_all(hash_key)

                for field, value in all_data.items():
                    if field.startswith("floor:") and field.replace(
                        "floor:", ""
                    ).startswith(building_code):
                        floor_data = json.loads(value)
                        floor_code_item = floor_data["code"]

                        # 获取该楼层的房间
                        rooms_key = f"rooms:{floor_code_item}"
                        rooms_str = await redis_client.hash_get(hash_key, rooms_key)
                        rooms_data = json.loads(rooms_str) if rooms_str else []

                        floors.append(
                            CacheFloorData(
                                code=floor_data["code"],
                                name=floor_data["name"],
                                rooms=[RoomInfo(**room) for room in rooms_data],
                            )
                        )

                # 按楼层代码排序
                floors.sort(key=lambda f: f.code)

            building = CacheBuildingData(
                code=building_data["code"],
                name=building_data["name"],
                floors=floors,
            )

            return CacheRoomsData(
                datetime=meta.get("datetime", ""),
                data=[building],
            )

        except Exception as e:
            self.client.logger.error(f"从Hash按楼栋获取数据失败: {str(e)}")
            raise

    async def query_room_name(self, room_code: str) -> Optional[str]:
        """
        根据房间代码查询房间名称

        Args:
            room_code: 房间代码

        Returns:
            Optional[str]: 房间名称，如果未找到则返回None
        """
        bulding = room_code[:2]
        floor = room_code[:4]
        room = room_code
        rooms_data = await self.get_cached_rooms()
        for building in rooms_data.data:
            if building.code == bulding:
                for fl in building.floors:
                    if fl.code == floor:
                        for rm in fl.rooms:
                            if rm.code == room:
                                return rm.name
        return None

    async def query_room_name_online(self, room_code: str) -> Optional[str]:
        """
        在线根据房间代码查询房间名称

        Args:
            room_code: 房间代码

        Returns:
            Optional[str]: 房间名称，如果未找到则返回None
        """
        await self._ensure_jsession()  # 确保会话已初始化

        bulding = room_code[:2]
        floor = room_code[:4]
        room = room_code
        jsessionid = self._jsessionid

        floors = await self.get_floors(bulding, jsessionid)
        for fl in floors:
            if fl.code == floor:
                rooms = await self.get_rooms(floor, jsessionid)
                for rm in rooms:
                    if rm.code == room:
                        return rm.name
        return None

    async def get_room_display_text(self, room_code: str) -> Optional[str]:
        """
        根据房间代码获取完整的房间显示名称

        Args:
            room_code: 房间代码

        Returns:
            Optional[str]: 完整的房间显示名称，如果未找到则返回None
        """
        bulding = room_code[:2]
        floor = room_code[:4]
        room = room_code
        rooms_data = await self.get_cached_rooms()
        for building in rooms_data.data:
            if building.code == bulding:
                for fl in building.floors:
                    if fl.code == floor:
                        for rm in fl.rooms:
                            if rm.code == room:
                                return f"{building.name}/{fl.name}/{rm.name}"
        return None

    async def get_cached_rooms(self) -> CacheRoomsData:
        """
        从Redis获取缓存的房间数据，如果缓存不存在则重新获取

        使用Hash存储方案

        Returns:
            CacheRoomsData: 房间数据
        """
        try:
            # 从Hash获取缓存数据
            cached_data = await self.get_cached_rooms_from_hash()

            if cached_data is not None and cached_data.data:
                self.client.logger.info("成功从Redis Hash获取房间缓存数据")
                return cached_data

            # 缓存不存在，重新获取数据
            self.client.logger.info("Redis中房间缓存不存在，重新获取数据")
            data = await self.get_all_room_data()

            # 使用Hash方案缓存数据
            await self._cache_room_data_to_hash()

            self.client.logger.info("房间数据已缓存到Redis Hash，过期时间：7天")
            return data

        except Exception as e:
            self.client.logger.error(f"获取房间缓存异常: {str(e)}")
            # 异常时返回空数据
            return CacheRoomsData(datetime="", data=[])

    async def refresh_expired_room_cache(self) -> None:
        """
        刷新过期的房间缓存（该方法已弃用，改用Redis自动过期机制）
        为了向后兼容，该方法仍然保留但不执行任何操作
        Redis会自动在7天后失效缓存
        """
        self.client.logger.info("房间缓存已完全迁移到Redis，使用Redis的自动过期机制")

    async def force_refresh_room_cache(self) -> None:
        """
        强制刷新房间缓存（重新从ISIM系统获取数据并缓存到Redis Hash）
        """
        try:
            self.client.logger.info("开始强制刷新房间缓存")

            # 使用Hash方案缓存
            await self._cache_room_data_to_hash()

            self.client.logger.info(
                "房间缓存已强制刷新并缓存到Redis Hash，过期时间：7天"
            )
        except Exception as e:
            self.client.logger.error(f"强制刷新房间缓存失败: {str(e)}")

    async def get_building_info(self, building_code: str) -> Optional[BuildingInfo]:
        """
        从缓存中获取指定楼栋信息

        Args:
            building_code: 楼栋代码

        Returns:
            BuildingInfo: 楼栋信息，不存在返回None
        """
        try:
            redis_client = await get_redis_client()
            HASH_KEY = "isim:rooms:v1:data"

            building_key = f"building:{building_code}"
            building_str = await redis_client.hash_get(HASH_KEY, building_key)

            if not building_str:
                return None

            building_data = json.loads(building_str)
            return BuildingInfo(**building_data)

        except Exception as e:
            self.client.logger.error(f"获取楼栋信息失败: {str(e)}")
            return None

    async def get_floor_info(self, floor_code: str) -> Optional[FloorInfo]:
        """
        从缓存中获取指定楼层信息

        Args:
            floor_code: 楼层代码

        Returns:
            FloorInfo: 楼层信息，不存在返回None
        """
        try:
            redis_client = await get_redis_client()
            HASH_KEY = "isim:rooms:v1:data"

            floor_key = f"floor:{floor_code}"
            floor_str = await redis_client.hash_get(HASH_KEY, floor_key)

            if not floor_str:
                return None

            floor_data = json.loads(floor_str)
            return FloorInfo(code=floor_data["code"], name=floor_data["name"])

        except Exception as e:
            self.client.logger.error(f"获取楼层信息失败: {str(e)}")
            return None

    async def get_rooms_by_floor(self, floor_code: str) -> List[RoomInfo]:
        """
        从缓存中获取指定楼层的所有房间

        Args:
            floor_code: 楼层代码

        Returns:
            List[RoomInfo]: 房间列表
        """
        try:
            redis_client = await get_redis_client()
            HASH_KEY = "isim:rooms:v1:data"

            rooms_key = f"rooms:{floor_code}"
            rooms_str = await redis_client.hash_get(HASH_KEY, rooms_key)

            if not rooms_str:
                return []

            rooms_data = json.loads(rooms_str)
            return [RoomInfo(**room) for room in rooms_data]

        except Exception as e:
            self.client.logger.error(f"获取楼层房间列表失败: {str(e)}")
            return []

    async def get_building_with_floors(
        self, building_code: str
    ) -> Optional[CacheBuildingData]:
        """
        从缓存中获取指定楼栋及其所有楼层和房间

        Args:
            building_code: 楼栋代码

        Returns:
            CacheBuildingData: 楼栋完整数据，不存在返回None
        """
        try:
            data = await self.get_cached_rooms_from_hash(building_code=building_code)
            if data and data.data:
                return data.data[0]
            return None

        except Exception as e:
            self.client.logger.error(f"获取楼栋完整数据失败: {str(e)}")
            return None

    async def query_room_info_fast(self, room_code: str) -> Optional[RoomInfo]:
        """
        快速查询房间信息（从Hash缓存）

        Args:
            room_code: 房间代码（如：010101）

        Returns:
            RoomInfo: 房间信息，不存在返回None
        """
        try:
            # 从房间代码提取楼层代码
            if len(room_code) < 4:
                return None

            floor_code = room_code[:4]
            rooms = await self.get_rooms_by_floor(floor_code)

            # 在房间列表中查找
            for room in rooms:
                if room.code == room_code:
                    return room

            return None

        except Exception as e:
            self.client.logger.error(f"快速查询房间信息失败: {str(e)}")
            return None

    async def get_headers(self) -> Dict[str, str]:
        """获取当前请求头信息"""
        return {
            **self.config.aufe.default_headers,
            "Accept": "application/json, text/javascript, */*; q=0.01",
            "Accept-Language": "zh-CN,zh;q=0.9",
            "Connection": "keep-alive",
            "X-Requested-With": "XMLHttpRequest",
            "Cookie": f"JSESSIONID={self._jsessionid}; TWFID={self.client.twf_id}",
            "Referer": f"{self.DEFAULT_BASE_URL}/about;jsessionid={self._jsessionid}",
        }

    @ensure_session
    async def get_electricity_info(self, room_code: str) -> Optional[Dict]:
        """
        获取寝室电费信息，包括余额、用电记录和充值记录

        Args:
            room_code: 房间代码

        Returns:
            Optional[Dict]: 包含balance、usage_records、payments的字典，失败时返回None
        """

        try:
            # 绑定寝室到当前会话
            if not await self.bind_room_to_jsession(room_code):
                self.client.logger.error(f"绑定寝室失败: {room_code}")
                return None

            header = await self.get_headers()

            # 获取用电记录和余额信息
            url_usage = f"{self.DEFAULT_BASE_URL}/use/record"
            response_usage_co = self.client.client.get(
                url_usage, headers=header, timeout=10000, follow_redirects=True
            )
            url_payment = f"{self.DEFAULT_BASE_URL}/pay/record"
            response_payment_co = self.client.client.get(
                url_payment, headers=header, timeout=10000, follow_redirects=True
            )
            response_usage, response_payment = await asyncio.gather(
                response_usage_co, response_payment_co
            )

            if response_usage.status_code != 200:
                self.client.logger.error(
                    f"获取寝室电费信息失败，状态码: {response_usage.status_code}"
                )
                return None

            soup = BeautifulSoup(response_usage.text, "lxml")

            # 提取余额信息
            balance_items = soup.find_all("li", class_="item-content")
            remaining_purchased = 0.0
            remaining_subsidy = 0.0

            for item in balance_items:
                title_div = item.find("div", class_="item-title")
                after_div = item.find("div", class_="item-after")

                if title_div and after_div:
                    title = title_div.get_text(strip=True)
                    value_text = after_div.get_text(strip=True)

                    # 提取数值
                    value_match = re.search(r"([\d.]+)", value_text)
                    if value_match:
                        value = float(value_match.group(1))

                        if "剩余购电" in title:
                            remaining_purchased = value
                        elif "剩余补助" in title:
                            remaining_subsidy = value

            # 提取用电记录
            usage_records = []
            record_items = soup.select("#divRecord ul li")

            for item in record_items:
                title_div = item.find("div", class_="item-title")
                after_div = item.find("div", class_="item-after")
                subtitle_div = item.find("div", class_="item-subtitle")

                if title_div and after_div and subtitle_div:
                    record_time = title_div.get_text(strip=True)
                    usage_text = after_div.get_text(strip=True)
                    meter_text = subtitle_div.get_text(strip=True)

                    # 提取用电量
                    usage_match = re.search(r"([\d.]+)度", usage_text)
                    if usage_match:
                        usage_amount = float(usage_match.group(1))

                        # 提取电表名称
                        meter_match = re.search(r"电表:\s*(.+)", meter_text)
                        meter_name = meter_match.group(1) if meter_match else meter_text

                        usage_records.append(
                            ElectricityUsageRecord(
                                record_time=record_time,
                                usage_amount=usage_amount,
                                meter_name=meter_name,
                            )
                        )

            balance = ElectricityBalance(
                remaining_purchased=remaining_purchased,
                remaining_subsidy=remaining_subsidy,
            )

            # 获取充值记录
            if response_payment.status_code != 200:
                self.client.logger.error(
                    f"获取寝室电费充值记录失败，状态码: {response_payment.status_code}"
                )
                return None

            soup = BeautifulSoup(response_payment.text, "lxml")
            payment_records = []
            record_items = soup.select("#divRecord ul li")

            for item in record_items:
                title_div = item.find("div", class_="item-title")
                after_div = item.find("div", class_="item-after")
                subtitle_div = item.find("div", class_="item-subtitle")

                if title_div and after_div and subtitle_div:
                    payment_time = title_div.get_text(strip=True)
                    amount_text = after_div.get_text(strip=True)
                    type_text = subtitle_div.get_text(strip=True)

                    # 提取金额
                    amount_match = re.search(r"(-?[\d.]+)元", amount_text)
                    if amount_match:
                        amount = float(amount_match.group(1))

                        # 提取充值类型
                        type_match = re.search(r"类型:\s*(.+)", type_text)
                        payment_type = type_match.group(1) if type_match else type_text

                        payment_records.append(
                            PaymentRecord(
                                payment_time=payment_time,
                                amount=amount,
                                payment_type=payment_type,
                            )
                        )

            self.client.logger.info(f"成功获取寝室 {room_code} 的电费信息")
            return {
                "balance": balance,
                "usage_records": usage_records,
                "payments": payment_records,
            }

        except Exception as e:
            self.client.logger.error(f"获取寝室电费信息异常: {str(e)}")
            self.client.logger.exception(e)
            return None

    async def aclose(self):
        """关闭客户端，释放资源"""
        self.client.logger.info("正在关闭ISIM客户端")
        # 目前没有额外资源需要释放
        pass


async def get_isim_client(conn: AUFEConnection = Depends(get_aufe_conn)) -> ISIMClient:
    """
    获取ISIM客户端实例

    客户端会自动初始化会话和刷新过期的缓存，无需手动调用初始化方法
    """
    if client := conn.get_subclient("isim", ISIMClient):
        conn.logger.info("复用已存在的ISIM客户端实例")
        return client
    isim = ISIMClient(conn)
    conn.logger.info("创建新的ISIM客户端实例")
    conn.inject_subclient("isim", isim)
    # 预先刷新过期的房间缓存（如果需要）
    await isim.refresh_expired_room_cache()
    return isim
