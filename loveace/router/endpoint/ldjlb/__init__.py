from fastapi import APIRouter

from loveace.router.endpoint.ldjlb.labor import ldjlb_labor_router

ldjlb_base_router = APIRouter(
    prefix="/ldjlb",
    tags=["劳动俱乐部"],
)

ldjlb_base_router.include_router(ldjlb_labor_router)
