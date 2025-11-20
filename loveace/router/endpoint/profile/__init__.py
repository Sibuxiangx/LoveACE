from fastapi import APIRouter

from loveace.router.endpoint.profile.flutter import profile_flutter_router
from loveace.router.endpoint.profile.model.error import ProfileErrorToCode
from loveace.router.endpoint.profile.user import profile_user_router

profile_router = APIRouter(
    prefix="/profile",
    responses=ProfileErrorToCode.gen_code_table(),
)

profile_router.include_router(profile_user_router)
profile_router.include_router(profile_flutter_router)
