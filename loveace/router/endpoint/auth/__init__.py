from fastapi import APIRouter

from loveace.router.endpoint.auth.authme import authme_router
from loveace.router.endpoint.auth.login import login_router
from loveace.router.endpoint.auth.register import register_router

auth_router = APIRouter(prefix="/auth", tags=["用户验证"])
auth_router.include_router(login_router)
auth_router.include_router(register_router)
auth_router.include_router(authme_router)
