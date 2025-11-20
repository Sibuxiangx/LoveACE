from hashlib import md5
from typing import Literal


from fastapi import APIRouter, Depends, File, UploadFile
from fastapi.responses import JSONResponse
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from loveace.database.auth.user import ACEUser
from loveace.database.creator import get_db_session
from loveace.database.profile.flutter_profile import FlutterThemeProfile
from loveace.router.dependencies.auth import get_user_by_token
from loveace.router.dependencies.logger import logger_mixin_with_user
from loveace.router.endpoint.profile.model.error import ProfileErrorToCode
from loveace.router.endpoint.profile.model.flutter import (
    FlutterImageMD5Response,
    FlutterImageMode,
    FlutterImageUploadResponse,
    FlutterProfileResponse,
    FlutterProfileUpdateRequest,
)
from loveace.router.endpoint.profile.model.uuid2s3key import Uuid2S3KeyCache
from loveace.router.schemas.uniresponse import UniResponseModel
from loveace.service.remote.s3 import S3Service
from loveace.service.remote.s3.depends import get_s3_service
from loveace.utils.redis_client import RedisClient, get_redis_client

profile_flutter_router = APIRouter(
    prefix="/flutter",
    tags=["Flutter 资料"],
)


@profile_flutter_router.get(
    "/get",
    response_model=UniResponseModel[FlutterProfileResponse],
    summary="获取 Flutter 用户资料",
)
async def profile_flutter_get(
    session: AsyncSession = Depends(get_db_session),
    user: ACEUser = Depends(get_user_by_token),
    s3_service: S3Service = Depends(get_s3_service),
) -> UniResponseModel[FlutterProfileResponse] | JSONResponse:
    """
    获取用户的 Flutter 应用主题配置

    ✅ 功能特性：
       - 获取深色和浅色模式配置
       - 获取背景图片、透明度、亮度设置
       - 获取模糊效果参数

    💡 使用场景：
       - Flutter 客户端启动时加载主题
       - 显示用户自定义主题设置

    Returns:
        FlutterProfileResponse: 包含深色/浅色模式的完整主题配置
    """
    logger = logger_mixin_with_user(user.userid)
    try:
        result = await session.execute(
            select(FlutterThemeProfile).where(
                FlutterThemeProfile.user_id == user.userid
            )
        )
        flutter_profile: FlutterThemeProfile | None = result.scalars().first()
        if not flutter_profile:
            return ProfileErrorToCode().profile_not_found.to_json_response(
                logger.trace_id, "您还未设置用户资料，请先设置用户资料。"
            )
        if flutter_profile.light_mode_background_url:
            if light_bg_url := await s3_service.generate_presigned_url_from_direct_url(
                flutter_profile.light_mode_background_url
            ):
                flutter_profile.light_mode_background_url = light_bg_url
            else:
                logger.warning("生成用户浅色模式背景预签名 URL 失败，可能图片已被删除")
                flutter_profile.light_mode_background_url = ""
        else:
            flutter_profile.light_mode_background_url = ""
        if flutter_profile.dark_mode_background_url:
            if dark_bg_url := await s3_service.generate_presigned_url_from_direct_url(
                flutter_profile.dark_mode_background_url
            ):
                flutter_profile.dark_mode_background_url = dark_bg_url
            else:
                logger.warning("生成用户深色模式背景预签名 URL 失败，可能图片已被删除")
                flutter_profile.dark_mode_background_url = ""
        else:
            flutter_profile.dark_mode_background_url = ""

        flutter_response = FlutterProfileResponse(
            dark_mode=flutter_profile.dark_mode,
            light_mode_opacity=flutter_profile.light_mode_opacity,
            light_mode_brightness=flutter_profile.light_mode_brightness,
            light_mode_background_url=flutter_profile.light_mode_background_url,
            light_mode_blur=flutter_profile.light_mode_blur,
            dark_mode_opacity=flutter_profile.dark_mode_opacity,
            dark_mode_brightness=flutter_profile.dark_mode_brightness,
            dark_mode_background_url=flutter_profile.dark_mode_background_url,
            dark_mode_background_blur=flutter_profile.dark_mode_background_blur,
        )
        return UniResponseModel[FlutterProfileResponse](
            success=True,
            data=flutter_response,
            message="获取 Flutter 用户资料成功",
            error=None,
        )
    except Exception as e:
        logger.error("获取 Flutter 用户资料时发生错误")
        logger.exception(e)
        return ProfileErrorToCode().server_error.to_json_response(logger.trace_id)


@profile_flutter_router.put(
    "/image/upload",
    response_model=UniResponseModel[FlutterImageUploadResponse],
    summary="上传 Flutter 背景图片",
)
async def profile_flutter_image_upload(
    background_image_upload: UploadFile = File(
        ..., description="背景图片文件，限制大小小于 5MB"
    ),
    user: ACEUser = Depends(get_user_by_token),
    s3_service: S3Service = Depends(get_s3_service),
    redis_client: RedisClient = Depends(get_redis_client),
) -> UniResponseModel[FlutterImageUploadResponse] | JSONResponse:
    """
    上传 Flutter 主题的背景图片

    ✅ 功能特性：
       - 支持 JPEG 和 PNG 格式
       - 限制文件大小为 5MB 以内
       - 上传后返回临时 UUID，需要通过 /update 接口确认才会保存

    ⚠️ 限制条件：
       - 仅支持 JPEG 和 PNG 格式
       - 文件大小不能超过 5MB
       - 上传的临时文件有效期为 1 小时

    💡 使用场景：
       - 用户上传深色模式背景图片
       - 用户上传浅色模式背景图片

    Args:
        background_image_upload: 背景图片文件

    Returns:
        FlutterImageUploadResponse: 包含临时图片 UUID
    """
    logger = logger_mixin_with_user(user.userid)
    print(background_image_upload.content_type)
    if not background_image_upload.content_type and not background_image_upload.size:
        logger.warning("上传的背景图片文件缺少必要的内容类型或大小信息")
        return ProfileErrorToCode().mimetype_not_allowed.to_json_response(
            logger.trace_id, "上传的背景图片文件缺少必要的内容类型或大小信息"
        )
    if background_image_upload.size and background_image_upload.size > 5 * 1024 * 1024:
        logger.warning("上传的背景图片文件过大")
        return ProfileErrorToCode().too_large_image.to_json_response(
            logger.trace_id, "上传的背景图片文件过大，最大允许5MB"
        )
    if background_image_upload.content_type not in ["image/jpeg", "image/png"]:
        logger.warning("上传的背景图片文件格式不支持")
        return ProfileErrorToCode().mimetype_not_allowed.to_json_response(
            logger.trace_id, "上传的背景图片文件格式不支持，仅支持 JPEG、PNG"
        )
    md5_hash = md5(background_image_upload.file.read()).hexdigest()
    background_image_upload.file.seek(0)
    s3_key = f"backgrounds/{user.userid}/never_use/{user.userid}-{md5_hash}.jpg"
    back_upload = await s3_service.upload_obj(
        file_obj=background_image_upload.file,
        s3_key=s3_key,
        extra_args={"ContentType": background_image_upload.content_type},
    )
    if not back_upload.success or not back_upload.url:
        logger.error("上传用户背景图片到 S3 失败")
        return ProfileErrorToCode().remote_service_error.to_json_response(
            logger.trace_id, "上传用户背景图片失败，请稍后重试"
        )

    cache_data = Uuid2S3KeyCache(s3_key=s3_key, md5=md5_hash)
    await redis_client.set_object(
        key=f"flutter:background:{user.userid}-{md5_hash}",
        value=cache_data,
        model_class=Uuid2S3KeyCache,
        expire=3600,
    )
    upload_response = FlutterImageUploadResponse(uuid=f"{user.userid}-{md5_hash}", md5=md5_hash)
    return UniResponseModel[FlutterImageUploadResponse](
        success=True,
        data=upload_response,
        message="上传背景图片成功",
        error=None,
    )


@profile_flutter_router.put(
    "/update",
    response_model=UniResponseModel[FlutterProfileResponse],
    summary="更新 Flutter 用户资料",
)
async def profile_flutter_update(
    profile_update_request: FlutterProfileUpdateRequest,
    session: AsyncSession = Depends(get_db_session),
    user: ACEUser = Depends(get_user_by_token),
    s3_service: S3Service = Depends(get_s3_service),
    redis_client: RedisClient = Depends(get_redis_client),
) -> UniResponseModel[FlutterProfileResponse] | JSONResponse:
    """
    更新用户的 Flutter 主题配置

    ✅ 功能特性：
       - 支持更新深色和浅色模式配置
       - 支持更新背景图片、透明度、亮度、模糊效果
       - 可同时更新或选择性更新

    💡 使用场景：
       - 用户自定义 Flutter 客户端主题
       - 修改深色模式或浅色模式设置
       - 更新背景图片

    Args:
        profile_update_request: 包含要更新的主题配置字段
        session: 数据库会话
        user: 当前用户
        s3_service: S3 服务
        redis_client: Redis 客户端

    Returns:
        FlutterProfileResponse: 更新后的主题配置
    """
    logger = logger_mixin_with_user(user.userid)
    try:
        if not any(
            [
                profile_update_request.dark_mode,
                profile_update_request.light_mode_opacity,
                profile_update_request.light_mode_brightness,
                profile_update_request.light_mode_background_uuid,
                profile_update_request.light_mode_blur,
                profile_update_request.dark_mode_opacity,
                profile_update_request.dark_mode_brightness,
                profile_update_request.dark_mode_background_uuid,
                profile_update_request.dark_mode_background_blur,
            ]
        ):
            logger.warning("未提供任何更新的资料字段")
            return ProfileErrorToCode().need_one_more_field.to_json_response(
                logger.trace_id, "未提供任何更新的资料字段"
            )

        result = await session.execute(
            select(FlutterThemeProfile).where(
                FlutterThemeProfile.user_id == user.userid
            )
        )
        flutter_profile: FlutterThemeProfile | None = result.scalars().first()

        if not flutter_profile:
            flutter_profile = FlutterThemeProfile(user_id=user.userid)

        if profile_update_request.dark_mode is not None:
            flutter_profile.dark_mode = profile_update_request.dark_mode
        if profile_update_request.light_mode_opacity is not None:
            flutter_profile.light_mode_opacity = (
                profile_update_request.light_mode_opacity
            )
        if profile_update_request.light_mode_brightness is not None:
            flutter_profile.light_mode_brightness = (
                profile_update_request.light_mode_brightness
            )
        if profile_update_request.light_mode_background_uuid is not None:
            light_bg_cache = await redis_client.get_object(
                key=f"flutter:background:{profile_update_request.light_mode_background_uuid}",
                model_class=Uuid2S3KeyCache,
            )
            if light_bg_cache:
                copy = await s3_service.copy_object(
                    source_key=light_bg_cache.s3_key,
                    dest_key=f"backgrounds/{user.userid}/{user.userid}-light.jpg",
                )
                if copy.success and copy.dest_url:
                    flutter_profile.light_mode_background_url = copy.dest_url
                    flutter_profile.light_mode_background_md5 = (
                        light_bg_cache.md5 if light_bg_cache else ""
                    )
                    await redis_client.delete(
                        key=f"flutter:background:{profile_update_request.light_mode_background_uuid}"
                    )
            else:
                logger.warning("提供的浅色模式背景图片 UUID 无效或已过期")
                return ProfileErrorToCode().resource_expired.to_json_response(
                    logger.trace_id, "提供的浅色模式背景图片 UUID 无效或已过期"
                )
        if profile_update_request.light_mode_blur is not None:
            flutter_profile.light_mode_blur = profile_update_request.light_mode_blur
        if profile_update_request.dark_mode_opacity is not None:
            flutter_profile.dark_mode_opacity = profile_update_request.dark_mode_opacity
        if profile_update_request.dark_mode_brightness is not None:
            flutter_profile.dark_mode_brightness = (
                profile_update_request.dark_mode_brightness
            )
        if profile_update_request.dark_mode_background_uuid is not None:
            dark_bg_cache = await redis_client.get_object(
                key=f"flutter:background:{profile_update_request.dark_mode_background_uuid}",
                model_class=Uuid2S3KeyCache,
            )
            if dark_bg_cache:
                copy = await s3_service.copy_object(
                    source_key=dark_bg_cache.s3_key,
                    dest_key=f"backgrounds/{user.userid}/{user.userid}-dark.jpg",
                )
                if copy.success and copy.dest_url:
                    flutter_profile.dark_mode_background_url = copy.dest_url
                    flutter_profile.dark_mode_background_md5 = (
                        dark_bg_cache.md5 if dark_bg_cache else ""
                    )
                    await redis_client.delete(
                        key=f"flutter:background:{profile_update_request.dark_mode_background_uuid}"
                    )
            else:
                logger.warning("提供的深色模式背景图片 UUID 无效或已过期")
                return ProfileErrorToCode().resource_expired.to_json_response(
                    logger.trace_id, "提供的深色模式背景图片 UUID 无效或已过期"
                )
        if profile_update_request.dark_mode_background_blur is not None:
            flutter_profile.dark_mode_background_blur = (
                profile_update_request.dark_mode_background_blur
            )
        session.add(flutter_profile)
        await session.commit()

        flutter_response = FlutterProfileResponse(
            dark_mode=flutter_profile.dark_mode,
            light_mode_opacity=flutter_profile.light_mode_opacity,
            light_mode_brightness=flutter_profile.light_mode_brightness,
            light_mode_background_url=(
                await s3_service.generate_presigned_url_from_direct_url(
                    flutter_profile.light_mode_background_url
                )
                if flutter_profile.light_mode_background_url
                else ""
            ),
            light_mode_blur=flutter_profile.light_mode_blur,
            dark_mode_opacity=flutter_profile.dark_mode_opacity,
            dark_mode_brightness=flutter_profile.dark_mode_brightness,
            dark_mode_background_url=(
                await s3_service.generate_presigned_url_from_direct_url(
                    flutter_profile.dark_mode_background_url
                )
                if flutter_profile.dark_mode_background_url
                else ""
            ),
            dark_mode_background_blur=flutter_profile.dark_mode_background_blur,
        )
        return UniResponseModel[FlutterProfileResponse](
            success=True,
            data=flutter_response,
            message="更新 Flutter 用户资料成功",
            error=None,
        )
    except Exception as e:
        logger.error("更新 Flutter 用户资料时发生错误")
        logger.exception(e)
        return ProfileErrorToCode().server_error.to_json_response(logger.trace_id)


@profile_flutter_router.get(
    "/image/{mode}/md5",
    summary="获取 Flutter 背景图片的 MD5 值",
    response_model=UniResponseModel[FlutterImageMD5Response],
)
async def profile_flutter_image_md5(
    mode: FlutterImageMode,
    user: ACEUser = Depends(get_user_by_token),
    session: AsyncSession = Depends(get_db_session),
) -> UniResponseModel[FlutterImageMD5Response] | JSONResponse:
    """
    获取 Flutter 主题背景图片的 MD5 值
    ✅ 功能特性：
       - 支持获取深色模式或浅色模式背景图片的 MD5 值
       - 通过用户 ID 定位对应的背景图片
    💡 使用场景：
       - 验证当前背景图片是否被篡改
       - 用于缓存或同步背景图片时的完整性校验
    Args:
        black_or_white: 指定获取深色模式（black）或浅色模式（white）的背景图片 MD5 值
        user: 当前用户
        redis_client: Redis 客户端
    Returns:
        FlutterImageMD5Response: 包含背景图片的 MD5 值
    """
    logger = logger_mixin_with_user(user.userid)
    try:
        if mode == FlutterImageMode.DARK:
            md5_value = await session.execute(
                select(FlutterThemeProfile.dark_mode_background_md5).where(
                    FlutterThemeProfile.user_id == user.userid
                )
            )
            result_md5 = md5_value.scalars().first()
        else:
            md5_value = await session.execute(
                select(FlutterThemeProfile.light_mode_background_md5).where(
                    FlutterThemeProfile.user_id == user.userid
                )
            )
            result_md5 = md5_value.scalars().first()
        if result_md5:
            result = FlutterImageMD5Response(md5=result_md5)
            return UniResponseModel[FlutterImageMD5Response](
                success=True,
                data=result,
                message="获取 Flutter 背景图片 MD5 值成功",
                error=None,
            )
        else:
            logger.warning("用户背景图片的 MD5 值未找到")
            return ProfileErrorToCode().profile_not_found.to_json_response(
                logger.trace_id, "用户背景图片的 MD5 值未找到"
            )
    except Exception as e:
        logger.error("获取 Flutter 背景图片 MD5 值时发生错误")
        logger.exception(e)
        return ProfileErrorToCode().server_error.to_json_response(logger.trace_id)
