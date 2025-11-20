from fastapi import APIRouter, Depends
from fastapi.responses import JSONResponse
from httpx import Headers, HTTPError
from pydantic import ValidationError

from loveace.router.endpoint.ldjlb.model.base import LDJLBConfig
from loveace.router.endpoint.ldjlb.model.ldjlb import (
    ActivityDetailResponse,
    LDJLBActivityListResponse,
    LDJLBApplyResponse,
    LDJLBClubListResponse,
    LDJLBProgressInfo,
    ScanSignRequest,
    ScanSignResponse,
    SignListResponse,
)
from loveace.router.endpoint.ldjlb.utils.ldjlb_ticket import get_ldjlb_header
from loveace.router.schemas.error import ProtectRouterErrorToCode
from loveace.router.schemas.uniresponse import UniResponseModel
from loveace.service.remote.aufe import AUFEConnection
from loveace.service.remote.aufe.depends import get_aufe_conn

ldjlb_labor_router = APIRouter(
    prefix="/labor",
    responses=ProtectRouterErrorToCode().gen_code_table(),
)

ENDPOINT = {
    "progress": "/User/Activity/GetMyFinishCount?sf_request_type=ajax",
    "joined_activities": "/User/Activity/DoGetJoinPageList?sf_request_type=ajax",
    "joined_clubs": "/User/Club/DoGetJoinList?sf_request_type=ajax",
    "club_activities": "/User/Activity/DoGetPageList?sf_request_type=ajax",
    "apply_join": "/User/Activity/DoApplyJoin?sf_request_type=ajax",
    "scan_sign": "/User/Center/DoScanSignQRImage",
    "sign_list": "/User/Activity/DoGetSignList",
    "activity_detail": "/User/Activity/DoGetDetail",
}


@ldjlb_labor_router.get(
    "/progress",
    response_model=UniResponseModel[LDJLBProgressInfo],
    summary="获取劳动俱乐部修课进度",
)
async def get_labor_progress(
    conn: AUFEConnection = Depends(get_aufe_conn),
    headers: Headers = Depends(get_ldjlb_header),
) -> UniResponseModel[LDJLBProgressInfo] | JSONResponse:
    """
    获取用户的劳动俱乐部修课进度

    ✅ 功能特性：
       - 获取已完成的劳动活动数量
       - 计算修课进度百分比（满分10次）
       - 实时从劳动俱乐部服务获取最新数据

    💡 使用场景：
       - 个人中心显示劳动修课进度
       - 检查是否满足劳动教育要求
       - 了解还需完成的活动次数

    Returns:
        LDJLBProgressInfo: 包含已完成次数和进度百分比
    """
    try:
        conn.logger.info("开始获取劳动俱乐部修课进度")
        response = await conn.client.post(
            url=LDJLBConfig().to_full_url(ENDPOINT["progress"]),
            data={},
            headers=headers,
            timeout=6000,
        )
        if response.status_code != 200:
            conn.logger.error(
                f"获取劳动俱乐部修课进度失败，HTTP状态码: {response.status_code}"
            )
            return ProtectRouterErrorToCode().remote_service_error.to_json_response(
                conn.logger.trace_id, "获取劳动俱乐部修课进度失败，请稍后重试"
            )
        data = response.json()
        if data.get("code") != 0:
            conn.logger.error(
                f"获取劳动俱乐部修课进度失败，响应代码: {data.get('code')}"
            )
            return ProtectRouterErrorToCode().remote_service_error.to_json_response(
                conn.logger.trace_id, "获取劳动俱乐部修课进度失败，请稍后重试"
            )
        try:
            progress_info = LDJLBProgressInfo.model_validate(data)
            conn.logger.info(
                f"成功获取劳动俱乐部修课进度: 已完成 {progress_info.finish_count}/10 次"
            )
            return UniResponseModel[LDJLBProgressInfo](
                success=True,
                data=progress_info,
                message="获取劳动俱乐部修课进度成功",
                error=None,
            )
        except ValidationError as ve:
            conn.logger.error(f"解析劳动俱乐部修课进度失败: {str(ve)}")
            return ProtectRouterErrorToCode().validation_error.to_json_response(
                conn.logger.trace_id, "解析劳动俱乐部修课进度失败，请稍后重试"
            )

    except HTTPError as he:
        conn.logger.error(f"获取劳动俱乐部修课进度异常: {str(he)}")
        return ProtectRouterErrorToCode().remote_service_error.to_json_response(
            conn.logger.trace_id, "获取劳动俱乐部修课进度异常，请稍后重试"
        )
    except Exception as e:
        conn.logger.error(f"获取劳动俱乐部修课进度未知异常: {str(e)}")
        return ProtectRouterErrorToCode().unknown_error.to_json_response(
            conn.logger.trace_id, "获取劳动俱乐部修课进度未知异常，请稍后重试"
        )


@ldjlb_labor_router.get(
    "/joined/activities",
    response_model=UniResponseModel[LDJLBActivityListResponse],
    summary="获取已加入的劳动活动列表",
)
async def get_joined_activities(
    conn: AUFEConnection = Depends(get_aufe_conn),
    headers: Headers = Depends(get_ldjlb_header),
) -> UniResponseModel[LDJLBActivityListResponse] | JSONResponse:
    """
    获取用户已加入的劳动活动列表

    ✅ 功能特性：
       - 获取用户已报名的所有劳动活动
       - 包含活动状态、时间、负责人等详细信息
       - 支持分页查询

    💡 使用场景：
       - 查看我的劳动活动页面
       - 了解已报名活动的详细信息
       - 查看活动进度和状态

    Returns:
        LDJLBActivityListResponse: 包含活动列表和分页信息
    """
    try:
        conn.logger.info("开始获取已加入的劳动活动列表")
        response = await conn.client.post(
            url=LDJLBConfig().to_full_url(ENDPOINT["joined_activities"]),
            data={},
            headers=headers,
            timeout=6000,
        )
        if response.status_code != 200:
            conn.logger.error(
                f"获取已加入的劳动活动列表失败，HTTP状态码: {response.status_code}"
            )
            return ProtectRouterErrorToCode().remote_service_error.to_json_response(
                conn.logger.trace_id, "获取已加入的劳动活动列表失败，请稍后重试"
            )
        data = response.json()
        if data.get("code") != 0:
            conn.logger.error(
                f"获取已加入的劳动活动列表失败，响应代码: {data.get('code')}"
            )
            return ProtectRouterErrorToCode().remote_service_error.to_json_response(
                conn.logger.trace_id, "获取已加入的劳动活动列表失败，请稍后重试"
            )
        try:
            activity_list = LDJLBActivityListResponse.model_validate(data)
            conn.logger.info(
                f"成功获取已加入的劳动活动列表，共 {len(activity_list.activities)} 个活动"
            )
            return UniResponseModel[LDJLBActivityListResponse](
                success=True,
                data=activity_list,
                message="获取已加入的劳动活动列表成功",
                error=None,
            )
        except ValidationError as ve:
            conn.logger.error(f"解析已加入的劳动活动列表失败: {str(ve)}")
            return ProtectRouterErrorToCode().validation_error.to_json_response(
                conn.logger.trace_id, "解析已加入的劳动活动列表失败，请稍后重试"
            )

    except HTTPError as he:
        conn.logger.error(f"获取已加入的劳动活动列表异常: {str(he)}")
        return ProtectRouterErrorToCode().remote_service_error.to_json_response(
            conn.logger.trace_id, "获取已加入的劳动活动列表异常，请稍后重试"
        )
    except Exception as e:
        conn.logger.error(f"获取已加入的劳动活动列表未知异常: {str(e)}")
        return ProtectRouterErrorToCode().unknown_error.to_json_response(
            conn.logger.trace_id, "获取已加入的劳动活动列表未知异常，请稍后重试"
        )


@ldjlb_labor_router.get(
    "/joined/clubs",
    response_model=UniResponseModel[LDJLBClubListResponse],
    summary="获取已加入的劳动俱乐部列表",
)
async def get_joined_clubs(
    conn: AUFEConnection = Depends(get_aufe_conn),
    headers: Headers = Depends(get_ldjlb_header),
) -> UniResponseModel[LDJLBClubListResponse] | JSONResponse:
    """
    获取用户已加入的劳动俱乐部列表

    ✅ 功能特性：
       - 获取用户已加入的所有劳动俱乐部
       - 包含俱乐部详细信息、负责人、成员数等
       - 用于后续查询俱乐部活动

    💡 使用场景：
       - 查看我的俱乐部页面
       - 获取俱乐部ID用于查询活动
       - 了解俱乐部详细信息

    Returns:
        LDJLBClubListResponse: 包含俱乐部列表
    """
    try:
        conn.logger.info("开始获取已加入的劳动俱乐部列表")
        response = await conn.client.post(
            url=LDJLBConfig().to_full_url(ENDPOINT["joined_clubs"]),
            data={},
            headers=headers,
            timeout=6000,
        )
        if response.status_code != 200:
            conn.logger.error(
                f"获取已加入的劳动俱乐部列表失败，HTTP状态码: {response.status_code}"
            )
            return ProtectRouterErrorToCode().remote_service_error.to_json_response(
                conn.logger.trace_id, "获取已加入的劳动俱乐部列表失败，请稍后重试"
            )
        data = response.json()
        if data.get("code") != 0:
            conn.logger.error(
                f"获取已加入的劳动俱乐部列表失败，响应代码: {data.get('code')}"
            )
            return ProtectRouterErrorToCode().remote_service_error.to_json_response(
                conn.logger.trace_id, "获取已加入的劳动俱乐部列表失败，请稍后重试"
            )
        try:
            club_list = LDJLBClubListResponse.model_validate(data)
            conn.logger.info(
                f"成功获取已加入的劳动俱乐部列表，共 {len(club_list.clubs)} 个俱乐部"
            )
            return UniResponseModel[LDJLBClubListResponse](
                success=True,
                data=club_list,
                message="获取已加入的劳动俱乐部列表成功",
                error=None,
            )
        except ValidationError as ve:
            conn.logger.error(f"解析已加入的劳动俱乐部列表失败: {str(ve)}")
            return ProtectRouterErrorToCode().validation_error.to_json_response(
                conn.logger.trace_id, "解析已加入的劳动俱乐部列表失败，请稍后重试"
            )

    except HTTPError as he:
        conn.logger.error(f"获取已加入的劳动俱乐部列表异常: {str(he)}")
        return ProtectRouterErrorToCode().remote_service_error.to_json_response(
            conn.logger.trace_id, "获取已加入的劳动俱乐部列表异常，请稍后重试"
        )
    except Exception as e:
        conn.logger.error(f"获取已加入的劳动俱乐部列表未知异常: {str(e)}")
        return ProtectRouterErrorToCode().unknown_error.to_json_response(
            conn.logger.trace_id, "获取已加入的劳动俱乐部列表未知异常，请稍后重试"
        )


@ldjlb_labor_router.get(
    "/club/{club_id}/activities",
    response_model=UniResponseModel[LDJLBActivityListResponse],
    summary="获取指定俱乐部的活动列表",
)
async def get_club_activities(
    club_id: str,
    page_index: int = 1,
    page_size: int = 100,
    conn: AUFEConnection = Depends(get_aufe_conn),
    headers: Headers = Depends(get_ldjlb_header),
) -> UniResponseModel[LDJLBActivityListResponse] | JSONResponse:
    """
    获取指定俱乐部的活动列表

    ✅ 功能特性：
       - 根据俱乐部ID获取该俱乐部的所有活动
       - 支持分页查询（默认pageSize=100）
       - 包含活动的详细信息和报名状态

    💡 使用场景：
       - 浏览某个俱乐部的活动列表
       - 查找可报名的劳动活动
       - 了解活动详情准备报名

    Args:
        club_id: 俱乐部ID
        page_index: 页码，默认1
        page_size: 每页大小，默认100

    Returns:
        LDJLBActivityListResponse: 包含活动列表和分页信息
    """
    try:
        conn.logger.info(f"开始获取俱乐部 {club_id} 的活动列表")
        response = await conn.client.post(
            url=LDJLBConfig().to_full_url(ENDPOINT["club_activities"])
            + f"?pageIndex={page_index}&pageSize={page_size}&clubID={club_id}",
            data={},
            headers=headers,
            timeout=6000,
        )
        if response.status_code != 200:
            conn.logger.error(
                f"获取俱乐部活动列表失败，HTTP状态码: {response.status_code}"
            )
            return ProtectRouterErrorToCode().remote_service_error.to_json_response(
                conn.logger.trace_id, "获取俱乐部活动列表失败，请稍后重试"
            )
        data = response.json()
        if data.get("code") != 0:
            conn.logger.error(f"获取俱乐部活动列表失败，响应代码: {data.get('code')}")
            return ProtectRouterErrorToCode().remote_service_error.to_json_response(
                conn.logger.trace_id, "获取俱乐部活动列表失败，请稍后重试"
            )
        try:
            activity_list = LDJLBActivityListResponse.model_validate(data)
            conn.logger.info(
                f"成功获取俱乐部 {club_id} 的活动列表，共 {len(activity_list.activities)} 个活动"
            )
            return UniResponseModel[LDJLBActivityListResponse](
                success=True,
                data=activity_list,
                message="获取俱乐部活动列表成功",
                error=None,
            )
        except ValidationError as ve:
            conn.logger.error(f"解析俱乐部活动列表失败: {str(ve)}")
            return ProtectRouterErrorToCode().validation_error.to_json_response(
                conn.logger.trace_id, "解析俱乐部活动列表失败，请稍后重试"
            )

    except HTTPError as he:
        conn.logger.error(f"获取俱乐部活动列表异常: {str(he)}")
        return ProtectRouterErrorToCode().remote_service_error.to_json_response(
            conn.logger.trace_id, "获取俱乐部活动列表异常，请稍后重试"
        )
    except Exception as e:
        conn.logger.error(f"获取俱乐部活动列表未知异常: {str(e)}")
        return ProtectRouterErrorToCode().unknown_error.to_json_response(
            conn.logger.trace_id, "获取俱乐部活动列表未知异常，请稍后重试"
        )


@ldjlb_labor_router.post(
    "/activity/{activity_id}/apply",
    response_model=UniResponseModel[LDJLBApplyResponse],
    summary="报名参加劳动活动",
)
async def apply_activity(
    activity_id: str,
    reason: str = "加入课程",
    conn: AUFEConnection = Depends(get_aufe_conn),
    headers: Headers = Depends(get_ldjlb_header),
) -> UniResponseModel[LDJLBApplyResponse] | JSONResponse:
    """
    报名参加劳动活动

    ✅ 功能特性：
       - 报名参加指定的劳动活动
       - 自动提交报名申请
       - 返回报名结果

    💡 使用场景：
       - 用户点击报名按钮
       - 批量报名多个活动
       - 自动化报名流程

    Args:
        activity_id: 活动ID
        reason: 报名理由，默认"加入课程"

    Returns:
        LDJLBApplyResponse: 包含报名结果代码和消息
    """
    try:
        conn.logger.info(f"开始报名活动 {activity_id}")
        response = await conn.client.post(
            url=LDJLBConfig().to_full_url(ENDPOINT["apply_join"]),
            data={"activityID": activity_id, "reason": reason},
            headers=headers,
            timeout=6000,
        )
        if response.status_code != 200:
            conn.logger.error(f"报名活动失败，HTTP状态码: {response.status_code}")
            return ProtectRouterErrorToCode().remote_service_error.to_json_response(
                conn.logger.trace_id, "报名活动失败，请稍后重试"
            )
        data = response.json()
        try:
            apply_result = LDJLBApplyResponse.model_validate(data)
            if apply_result.code == 0:
                conn.logger.success(f"成功报名活动 {activity_id}: {apply_result.msg}")
            else:
                conn.logger.warning(
                    f"报名活动 {activity_id} 失败: {apply_result.msg} (code: {apply_result.code})"
                )
            return UniResponseModel[LDJLBApplyResponse](
                success=apply_result.code == 0,
                data=apply_result,
                message=apply_result.msg,
                error=None,
            )
        except ValidationError as ve:
            conn.logger.error(f"解析报名响应失败: {str(ve)}")
            return ProtectRouterErrorToCode().validation_error.to_json_response(
                conn.logger.trace_id, "解析报名响应失败，请稍后重试"
            )

    except HTTPError as he:
        conn.logger.error(f"报名活动异常: {str(he)}")
        return ProtectRouterErrorToCode().remote_service_error.to_json_response(
            conn.logger.trace_id, "报名活动异常，请稍后重试"
        )
    except Exception as e:
        conn.logger.error(f"报名活动未知异常: {str(e)}")
        return ProtectRouterErrorToCode().unknown_error.to_json_response(
            conn.logger.trace_id, "报名活动未知异常，请稍后重试"
        )


@ldjlb_labor_router.post(
    "/scan_sign",
    response_model=UniResponseModel[ScanSignResponse],
    summary="扫码签到",
)
async def scan_sign_in(
    request: ScanSignRequest,
    conn: AUFEConnection = Depends(get_aufe_conn),
    headers: Headers = Depends(get_ldjlb_header),
) -> UniResponseModel[ScanSignResponse] | JSONResponse:
    """
    扫码签到功能

    ✅ 功能特性：
       - 通过扫描二维码进行活动签到
       - 支持位置信息验证
       - 实时反馈签到结果

    Args:
        request: 扫码签到请求，包含:
            - content: 扫描的二维码内容
            - location: 位置信息，格式为"经度,纬度"

    Returns:
        UniResponseModel[ScanSignResponse]: 包含签到结果
    """
    try:
        conn.logger.info(f"开始扫码签到，位置: {request.location}")

        # 发送POST请求到劳动俱乐部签到接口
        response = await conn.client.post(
            url=LDJLBConfig().to_full_url(ENDPOINT["scan_sign"]),
            json={
                "content": request.content,
                "location": request.location,
            },
            headers=headers,
            timeout=6000,
        )

        if response.status_code != 200:
            conn.logger.error(f"扫码签到失败，HTTP状态码: {response.status_code}")
            return ProtectRouterErrorToCode().remote_service_error.to_json_response(
                conn.logger.trace_id, "扫码签到失败，请稍后重试"
            )

        data = response.json()

        try:
            sign_result = ScanSignResponse.model_validate(data)

            if sign_result.code == 0:
                conn.logger.success(f"扫码签到成功: {sign_result.msg}")
            else:
                conn.logger.warning(
                    f"扫码签到失败: {sign_result.msg} (code: {sign_result.code})"
                )

            return UniResponseModel[ScanSignResponse](
                success=sign_result.code == 0,
                data=sign_result,
                message=sign_result.msg or "签到完成",
                error=None,
            )

        except ValidationError as ve:
            conn.logger.error(f"解析签到响应失败: {str(ve)}")
            return ProtectRouterErrorToCode().validation_error.to_json_response(
                conn.logger.trace_id, "解析签到响应失败，请稍后重试"
            )

    except HTTPError as he:
        conn.logger.error(f"扫码签到异常: {str(he)}")
        return ProtectRouterErrorToCode().remote_service_error.to_json_response(
            conn.logger.trace_id, "扫码签到异常，请稍后重试"
        )
    except Exception as e:
        conn.logger.error(f"扫码签到未知异常: {str(e)}")
        return ProtectRouterErrorToCode().unknown_error.to_json_response(
            conn.logger.trace_id, "扫码签到未知异常，请稍后重试"
        )


@ldjlb_labor_router.get(
    "/{activity_id}/sign_list",
    response_model=UniResponseModel[SignListResponse],
    summary="获取活动签到列表",
)
async def get_sign_list(
    activity_id: str,
    conn: AUFEConnection = Depends(get_aufe_conn),
    headers: Headers = Depends(get_ldjlb_header),
) -> UniResponseModel[SignListResponse] | JSONResponse:
    """
    获取指定活动的签到列表

    ✅ 功能特性：
       - 获取活动的所有签到项
       - 支持分页查询
       - 查看签到状态和时间
       - 辅助扫码签到功能

    Args:
        activity_id: 活动ID
        sign_type: 签到类型，默认1（签到）
        page_index: 页码，从1开始
        page_size: 每页大小，默认10

    Returns:
        UniResponseModel[SignListResponse]: 包含签到列表数据
    """
    sign_type: int = 1
    page_index: int = 1
    page_size: int = 10
    try:
        conn.logger.info(f"开始获取活动 {activity_id} 的签到列表")

        # 发送POST请求到劳动俱乐部签到列表接口
        response = await conn.client.post(
            url=LDJLBConfig().to_full_url(ENDPOINT["sign_list"]),
            data={
                "activityID": activity_id,
                "type": sign_type,
                "pageIndex": page_index,
                "pageSize": page_size,
            },
            headers=headers,
            timeout=6000,
        )

        if response.status_code != 200:
            conn.logger.error(f"获取签到列表失败，HTTP状态码: {response.status_code}")
            return ProtectRouterErrorToCode().remote_service_error.to_json_response(
                conn.logger.trace_id, "获取签到列表失败，请稍后重试"
            )

        data = response.json()

        try:
            sign_list_result = SignListResponse.model_validate(data)

            if sign_list_result.code == 0:
                sign_count = len(sign_list_result.data)
                signed_count = sum(1 for item in sign_list_result.data if item.is_sign)
                conn.logger.success(
                    f"成功获取签到列表，共 {sign_count} 项，已签到 {signed_count} 项"
                )
            else:
                conn.logger.warning(f"获取签到列表失败 (code: {sign_list_result.code})")

            return UniResponseModel[SignListResponse](
                success=sign_list_result.code == 0,
                data=sign_list_result,
                message="获取签到列表成功"
                if sign_list_result.code == 0
                else "获取签到列表失败",
                error=None,
            )

        except ValidationError as ve:
            conn.logger.error(f"解析签到列表响应失败: {str(ve)}")
            return ProtectRouterErrorToCode().validation_error.to_json_response(
                conn.logger.trace_id, "解析签到列表响应失败，请稍后重试"
            )

    except HTTPError as he:
        conn.logger.error(f"获取签到列表异常: {str(he)}")
        return ProtectRouterErrorToCode().remote_service_error.to_json_response(
            conn.logger.trace_id, "获取签到列表异常，请稍后重试"
        )
    except Exception as e:
        conn.logger.error(f"获取签到列表未知异常: {str(e)}")
        return ProtectRouterErrorToCode().unknown_error.to_json_response(
            conn.logger.trace_id, "获取签到列表未知异常，请稍后重试"
        )


@ldjlb_labor_router.get(
    "/{activity_id}/detail",
    response_model=UniResponseModel[ActivityDetailResponse],
    summary="获取活动详情",
)
async def get_activity_detail(
    activity_id: str,
    conn: AUFEConnection = Depends(get_aufe_conn),
    headers: Headers = Depends(get_ldjlb_header),
) -> UniResponseModel[ActivityDetailResponse] | JSONResponse:
    """
    获取活动详细信息

    ✅ 功能特性：
       - 获取活动完整信息（标题、时间、地点等）
       - 查看活动地址和教室信息
       - 查看报名人数和限制
       - 查看审批流程和教师列表
       - 支持扫码签到功能的前置查询

    Args:
        activity_id: 活动ID

    Returns:
        UniResponseModel[ActivityDetailResponse]: 包含活动详细信息

    说明：
        - formData 中包含"活动地址"等关键信息（如教室位置）
        - flowData 包含审批流程记录
        - teacherList 包含活动相关教师信息
    """
    try:
        conn.logger.info(f"开始获取活动详情: {activity_id}")

        # 发送POST请求到劳动俱乐部活动详情接口
        response = await conn.client.post(
            url=LDJLBConfig().to_full_url(ENDPOINT["activity_detail"]),
            data={"id": activity_id},
            headers=headers,
            timeout=6000,
        )

        if response.status_code != 200:
            conn.logger.error(f"获取活动详情失败，HTTP状态码: {response.status_code}")
            return ProtectRouterErrorToCode().remote_service_error.to_json_response(
                conn.logger.trace_id, "获取活动详情失败，请稍后重试"
            )

        data = response.json()

        try:
            detail_result = ActivityDetailResponse.model_validate(data)

            if detail_result.code == 0 and detail_result.data:
                # 提取关键信息用于日志
                activity_title = detail_result.data.title
                activity_location = "未知"

                # 从 formData 中提取活动地址
                for field in detail_result.form_data:
                    if field.name == "活动地址" and field.value:
                        activity_location = field.value
                        break

                conn.logger.success(
                    f"成功获取活动详情 - 标题: {activity_title}, 地点: {activity_location}"
                )
            else:
                conn.logger.warning(f"获取活动详情失败 (code: {detail_result.code})")

            return UniResponseModel[ActivityDetailResponse](
                success=detail_result.code == 0,
                data=detail_result,
                message="获取活动详情成功"
                if detail_result.code == 0
                else "获取活动详情失败",
                error=None,
            )

        except ValidationError as ve:
            conn.logger.error(f"解析活动详情响应失败: {str(ve)}")
            return ProtectRouterErrorToCode().validation_error.to_json_response(
                conn.logger.trace_id, "解析活动详情响应失败，请稍后重试"
            )

    except HTTPError as he:
        conn.logger.error(f"获取活动详情异常: {str(he)}")
        return ProtectRouterErrorToCode().remote_service_error.to_json_response(
            conn.logger.trace_id, "获取活动详情异常，请稍后重试"
        )
    except Exception as e:
        conn.logger.error(f"获取活动详情未知异常: {str(e)}")
        return ProtectRouterErrorToCode().unknown_error.to_json_response(
            conn.logger.trace_id, "获取活动详情未知异常，请稍后重试"
        )
