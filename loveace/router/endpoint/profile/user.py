from hashlib import md5


from fastapi import APIRouter, Depends, File, UploadFile
from fastapi.responses import JSONResponse
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from loveace.database.auth.user import ACEUser
from loveace.database.creator import get_db_session
from loveace.database.profile.user_profile import UserProfile
from loveace.router.dependencies.auth import get_user_by_token
from loveace.router.dependencies.logger import logger_mixin_with_user
from loveace.router.endpoint.profile.model.error import ProfileErrorToCode
from loveace.router.endpoint.profile.model.user import (
    AvatarMD5Response,
    AvatarUpdateResponse,
    UserProfileResponse,
    UserProfileUpdateRequest,
)
from loveace.router.endpoint.profile.model.uuid2s3key import Uuid2S3KeyCache
from loveace.router.schemas.uniresponse import UniResponseModel
from loveace.service.remote.s3 import S3Service
from loveace.service.remote.s3.depends import get_s3_service
from loveace.utils.redis_client import RedisClient, get_redis_client

profile_user_router = APIRouter(
    prefix="/user",
    tags=["用户资料"],
)


@profile_user_router.get(
    "/get", response_model=UniResponseModel[UserProfileResponse], summary="获取用户资料"
)
async def profile_user_get(
    session: AsyncSession = Depends(get_db_session),
    user: ACEUser = Depends(get_user_by_token),
    s3_service: S3Service = Depends(get_s3_service),
) -> UniResponseModel[UserProfileResponse] | JSONResponse:
    """
    获取当前用户的资料信息

    ✅ 功能特性：
       - 获取昵称、个签、头像等用户资料
       - 实时从数据库查询最新信息

    💡 使用场景：
       - 个人中心展示用户资料
       - 编辑资料前获取当前信息
       - 其他用户查看个人资料

    Returns:
        UserProfileResponse: 包含昵称、个签、头像 URL
    """
    logger = logger_mixin_with_user(user.userid)
    try:
        result = await session.execute(
            select(UserProfile).where(UserProfile.user_id == user.userid)
        )
        user_profile: UserProfile | None = result.scalars().first()
        if not user_profile:
            return ProfileErrorToCode().profile_not_found.to_json_response(
                logger.trace_id, "您还未设置用户资料，请先设置用户资料。"
            )
        if user_profile.avatar_url:
            if avatar_url := await s3_service.generate_presigned_url_from_direct_url(
                user_profile.avatar_url
            ):
                avatar_url = avatar_url
            else:
                logger.warning("生成用户头像预签名 URL 失败，可能头像已被删除")
                avatar_url = ""
        else:
            avatar_url = ""

        user_response = UserProfileResponse(
            nickname=user_profile.nickname,
            slogan=user_profile.slogan,
            avatar_url=avatar_url,
        )
        return UniResponseModel[UserProfileResponse](
            success=True,
            data=user_response,
            message="获取用户资料成功",
            error=None,
        )
    except Exception as e:
        logger.error("获取用户资料时发生错误")
        logger.exception(e)
        return ProfileErrorToCode().server_error.to_json_response(logger.trace_id)


@profile_user_router.put(
    "/avatar/upload",
    response_model=UniResponseModel[AvatarUpdateResponse],
    summary="上传用户头像",
)
async def profile_user_avatar_upload(
    avatar_update_request: UploadFile = File(
        ..., description="用户头像文件，限制大小小于 5MB"
    ),
    user: ACEUser = Depends(get_user_by_token),
    s3_service: S3Service = Depends(get_s3_service),
    redis_client: RedisClient = Depends(get_redis_client),
) -> UniResponseModel[AvatarUpdateResponse] | JSONResponse:
    """
    上传用户头像到 S3 存储

    ✅ 功能特性：
       - 支持 JPEG 和 PNG 格式
       - 限制文件大小为 5MB 以内
       - 上传后返回临时 UUID，需要通过 /update 接口确认才会保存

    ⚠️ 限制条件：
       - 仅支持 JPEG 和 PNG 格式
       - 文件大小不能超过 5MB
       - 上传的临时文件有效期为 1 小时

    💡 使用场景：
       - 用户上传新头像
       - 裁剪或预览后再确认保存

    Args:
        avatar_update_request: 头像文件

    Returns:
        AvatarUpdateResponse: 包含临时头像 UUID，后续需在 /update 接口中使用
    """
    logger = logger_mixin_with_user(user.userid)
    if not avatar_update_request.content_type and not avatar_update_request.size:
        logger.warning("上传的头像文件缺少必要的内容类型或大小信息")
        return ProfileErrorToCode().mimetype_not_allowed.to_json_response(
            logger.trace_id, "上传的头像文件缺少必要的内容类型或大小信息"
        )
    if avatar_update_request.size and avatar_update_request.size > 5 * 1024 * 1024:
        logger.warning("上传的头像文件过大")
        return ProfileErrorToCode().too_large_image.to_json_response(
            logger.trace_id, "上传的头像文件过大，最大允许5MB"
        )
    if avatar_update_request.content_type not in ["image/jpeg", "image/png"]:
        logger.warning("上传的头像文件格式不支持")
        return ProfileErrorToCode().mimetype_not_allowed.to_json_response(
            logger.trace_id, "上传的头像文件格式不支持，仅支持 JPEG、PNG"
        )
    s3_key = f"avatars/{user.userid}/never_use/{user.userid}.jpg"
    avatar_upload = await s3_service.upload_obj(
        file_obj=avatar_update_request.file,
        s3_key=s3_key,
        extra_args={"ContentType": avatar_update_request.content_type},
    )
    if not avatar_upload.success or not avatar_upload.url:
        logger.error("上传用户头像到 S3 失败")
        return ProfileErrorToCode().remote_service_error.to_json_response(
            logger.trace_id, "上传用户头像失败，请稍后重试"
        )
    avatar_update_request.file.seek(0)
    md5_hash = md5(avatar_update_request.file.read()).hexdigest()
    logger.info(f"计算上传头像的 MD5 值: {md5_hash}")

    cache_data = Uuid2S3KeyCache(s3_key=s3_key, md5=md5_hash)
    await redis_client.set_object(
        key=f"user:avatar:{user.userid}",
        value=cache_data,
        model_class=Uuid2S3KeyCache,
        expire=3600,
    )
    avatar_response = AvatarUpdateResponse(uuid=user.userid, md5=md5_hash)
    return UniResponseModel[AvatarUpdateResponse](
        success=True,
        data=avatar_response,
        message="上传头像成功",
        error=None,
    )


@profile_user_router.put(
    "/update",
    response_model=UniResponseModel[UserProfileResponse],
    summary="更新用户资料",
)
async def profile_user_update(
    profile_update_request: UserProfileUpdateRequest,
    session: AsyncSession = Depends(get_db_session),
    user: ACEUser = Depends(get_user_by_token),
    s3_service: S3Service = Depends(get_s3_service),
    redis_client: RedisClient = Depends(get_redis_client),
) -> UniResponseModel[UserProfileResponse] | JSONResponse:
    """
    更新用户资料（昵称、个签、头像）

    ✅ 功能特性：
       - 支持更新昵称、个签、头像
       - 可同时更新或选择性更新
       - 头像通过 /avatar/upload 上传后，需传入 avatar_uuid 进行确认

    💡 使用场景：
       - 用户编辑个人资料
       - 修改昵称或个签
       - 确认并保存头像

    Args:
        profile_update_request: 包含要更新的资料字段（至少一个）
        session: 数据库会话
        user: 当前用户
        s3_service: S3 服务
        redis_client: Redis 客户端

    Returns:
        UserProfileResponse: 更新后的用户资料
    """
    logger = logger_mixin_with_user(user.userid)
    try:
        if not any(
            [
                profile_update_request.nickname,
                profile_update_request.slogan,
                profile_update_request.avatar_uuid,
            ]
        ):
            logger.warning("用户资料更新请求中未包含任何可更新的字段")
            return ProfileErrorToCode().need_one_more_field.to_json_response(
                logger.trace_id, "请至少提供一个需要更新的字段"
            )
        result = await session.execute(
            select(UserProfile).where(UserProfile.user_id == user.userid)
        )
        user_profile: UserProfile | None = result.scalars().first()
        avatar_url = ""
        preset_avatar_cache = None
        if profile_update_request.avatar_uuid:
            preset_avatar_cache = await redis_client.get_object(
                key=f"user:avatar:{profile_update_request.avatar_uuid}",
                model_class=Uuid2S3KeyCache,
            )

        if preset_avatar_cache:
            copy = await s3_service.copy_object(
                source_key=preset_avatar_cache.s3_key,
                dest_key=f"avatars/{user.userid}/{user.userid}.jpg",
            )
            if copy.success:
                avatar_url = copy.dest_url
            else:
                logger.error("复制用户头像到正式存储位置失败")
                return ProfileErrorToCode().remote_service_error.to_json_response(
                    logger.trace_id, "设置用户头像失败，请稍后重试"
                )
        if not user_profile:
            user_profile = UserProfile(
                user_id=user.userid,
                nickname=profile_update_request.nickname,
                slogan=profile_update_request.slogan,
                avatar_url=avatar_url if preset_avatar_cache else "",
                avatar_md5=preset_avatar_cache.md5 if preset_avatar_cache else "",
            )
            session.add(user_profile)
        else:
            if profile_update_request.nickname:
                user_profile.nickname = profile_update_request.nickname
            if profile_update_request.slogan:
                user_profile.slogan = profile_update_request.slogan
            if profile_update_request.avatar_uuid:
                if avatar_url:
                    user_profile.avatar_url = avatar_url
                    user_profile.avatar_md5 = (
                        preset_avatar_cache.md5 if preset_avatar_cache else ""
                    )
                    await redis_client.delete(
                        key=f"user:avatar:{profile_update_request.avatar_uuid}"
                    )
                else:
                    logger.warning("提供的头像 UUID 无效或已过期")
                    return ProfileErrorToCode().resource_expired.to_json_response(
                        logger.trace_id, "提供的头像 UUID 无效或已过期"
                    )
        await session.commit()
        if user_profile.avatar_url:
            avatar_url = await s3_service.generate_presigned_url_from_direct_url(
                user_profile.avatar_url
            )
            if not avatar_url:
                logger.warning("生成用户头像预签名 URL 失败，可能头像已被删除")
                avatar_url = ""
        else:
            avatar_url = ""

        user_response = UserProfileResponse(
            nickname=user_profile.nickname,
            slogan=user_profile.slogan if user_profile.slogan else "",
            avatar_url=avatar_url,
        )
        return UniResponseModel[UserProfileResponse](
            success=True,
            data=user_response,
            message="更新用户资料成功",
            error=None,
        )
    except Exception as e:
        logger.error("更新用户资料时发生错误")
        logger.exception(e)
        return ProfileErrorToCode().server_error.to_json_response(logger.trace_id)


@profile_user_router.get(
    "/avatar/md5",
    summary="获取用户头像的MD5值",
    response_model=UniResponseModel[AvatarMD5Response],
)
async def profile_user_avatar_md5(
    session: AsyncSession = Depends(get_db_session),
    user: ACEUser = Depends(get_user_by_token),
) -> UniResponseModel[AvatarMD5Response] | JSONResponse:
    """
    获取当前用户头像的 MD5 值

    ✅ 功能特性：
       - 从数据库中获取用户头像的 MD5 值
       - 用于验证头像文件完整性或进行缓存控制
    💡 使用场景：
       - 在头像上传后，验证文件的完整性
       - 缓存头像文件的 MD5 值，以便后续快速验证
    """
    logger = logger_mixin_with_user(user.userid)
    result = await session.execute(
        select(UserProfile.avatar_md5).where(UserProfile.user_id == user.userid)
    )
    avatar_md5: str | None = result.scalar()
    if not avatar_md5:
        logger.warning("用户头像的 MD5 值未找到")
        return ProfileErrorToCode().profile_not_found.to_json_response(
            logger.trace_id, "用户头像的 MD5 值未找到"
        )
    return UniResponseModel[AvatarMD5Response](
        success=True,
        data=AvatarMD5Response(md5=avatar_md5),
        message="获取用户头像的 MD5 值成功",
        error=None,
    )
