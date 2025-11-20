from fastapi import APIRouter

from loveace.router.endpoint.isim.elec import isim_elec_router
from loveace.router.endpoint.isim.room import isim_room_router

isim_base_router = APIRouter(
    prefix="/isim",
    tags=["电费"],
)

isim_base_router.include_router(isim_room_router)
isim_base_router.include_router(isim_elec_router)
