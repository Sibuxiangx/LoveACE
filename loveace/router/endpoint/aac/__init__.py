from fastapi import APIRouter

from loveace.router.endpoint.aac.credit import aac_credit_router

aac_base_router = APIRouter(
    prefix="/aac",
    tags=["爱安财"],
)

aac_base_router.include_router(aac_credit_router)
