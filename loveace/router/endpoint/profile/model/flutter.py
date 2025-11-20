from enum import Enum
from typing import Optional

from pydantic import BaseModel, Field


class FlutterImageUploadResponse(BaseModel):
    uuid: str = Field(..., description="图片的UUID")
    md5: str = Field(..., description="图片的MD5值")


class FlutterProfileResponse(BaseModel):
    dark_mode: bool = Field(..., description="是否启用暗黑模式")
    light_mode_opacity: float = Field(..., description="浅色模式下的透明度")
    light_mode_brightness: float = Field(..., description="浅色模式下的亮度")
    light_mode_background_url: Optional[str] = Field(
        None, description="浅色模式下的背景图片 URL"
    )
    light_mode_blur: float = Field(..., description="浅色模式下的背景模糊程度")
    dark_mode_opacity: float = Field(..., description="深色模式下的透明度")
    dark_mode_brightness: float = Field(..., description="深色模式下的亮度")
    dark_mode_background_url: Optional[str] = Field(
        None, description="深色模式下的背景图片 URL"
    )
    dark_mode_background_blur: float = Field(
        ..., description="深色模式下的背景模糊程度"
    )


class FlutterProfileUpdateRequest(BaseModel):
    dark_mode: Optional[bool] = Field(None, description="是否启用暗黑模式")
    light_mode_opacity: Optional[float] = Field(None, description="浅色模式下的透明度")
    light_mode_brightness: Optional[float] = Field(None, description="浅色模式下的亮度")
    light_mode_background_uuid: Optional[str] = Field(
        None, description="浅色模式下的背景图片 UUID"
    )
    light_mode_blur: Optional[float] = Field(
        None, description="浅色模式下的背景模糊程度"
    )
    dark_mode_opacity: Optional[float] = Field(None, description="深色模式下的透明度")
    dark_mode_brightness: Optional[float] = Field(None, description="深色模式下的亮度")
    dark_mode_background_uuid: Optional[str] = Field(
        None, description="深色模式下的背景图片 UUID"
    )
    dark_mode_background_blur: Optional[float] = Field(
        None, description="深色模式下的背景模糊程度"
    )


class FlutterImageMD5Response(BaseModel):
    md5: str = Field(..., description="图片的MD5值")


class FlutterImageMode(Enum):
    LIGHT = "light"
    DARK = "dark"
