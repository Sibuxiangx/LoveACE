from fastapi import status

from loveace.router.schemas import ErrorToCode, ErrorToCodeNode


class ProfileErrorToCode(ErrorToCode):
    profile_not_found: ErrorToCodeNode = ErrorToCodeNode(
        error_code=status.HTTP_404_NOT_FOUND,
        code="PROFILE_NOT_FOUND",
        message="用户资料未找到",
    )
    unauthorized_access: ErrorToCodeNode = ErrorToCodeNode(
        error_code=status.HTTP_401_UNAUTHORIZED,
        code="UNAUTHORIZED_ACCESS",
        message="未授权的访问",
    )
    need_one_more_field: ErrorToCodeNode = ErrorToCodeNode(
        error_code=status.HTTP_400_BAD_REQUEST,
        code="NEED_ONE_MORE_FIELD",
        message="需要至少提供一个字段进行更新",
    )
    too_large_image: ErrorToCodeNode = ErrorToCodeNode(
        error_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
        code="TOO_LARGE_IMAGE",
        message="上传的图片过大",
    )
    mimetype_not_allowed: ErrorToCodeNode = ErrorToCodeNode(
        error_code=status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
        code="MIMETYPE_NOT_ALLOWED",
        message="不支持的图片格式",
    )
    resource_expired: ErrorToCodeNode = ErrorToCodeNode(
        error_code=status.HTTP_410_GONE,
        code="RESOURCE_EXPIRED",
        message="资源已过期",
    )
    remote_service_error: ErrorToCodeNode = ErrorToCodeNode(
        error_code=status.HTTP_502_BAD_GATEWAY,
        code="REMOTE_SERVICE_ERROR",
        message="远程服务错误",
    )
    server_error: ErrorToCodeNode = ErrorToCodeNode(
        error_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
        code="SERVER_ERROR",
        message="服务器错误",
    )
