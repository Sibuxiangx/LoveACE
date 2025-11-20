from typing import Optional

from pydantic import BaseModel, Field


class UserProfileUpdateRequest(BaseModel):
    nickname: Optional[str] = Field(..., description="用户昵称")
    slogan: Optional[str] = Field(..., description="用户个性签名")
    avatar_uuid: Optional[str] = Field(..., description="用户头像UUID")


class UserProfileResponse(BaseModel):
    nickname: str = Field(..., description="用户昵称")
    slogan: str = Field(..., description="用户个性签名")
    avatar_url: str = Field(..., description="用户头像URL")


class AvatarUpdateResponse(BaseModel):
    uuid: str = Field(..., description="新的头像UUID")
    md5: str = Field(..., description="头像文件的MD5值")


class AvatarMD5Response(BaseModel):
    md5: str = Field(..., description="用户头像的MD5值")
