from pydantic import BaseModel, Field


class AuthMeResponse(BaseModel):
    success: bool = Field(..., description="是否验证成功")
    userid: str = Field(..., description="用户ID")
