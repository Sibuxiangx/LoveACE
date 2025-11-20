from fastapi import APIRouter

from loveace.router.endpoint.jwc.academic import jwc_academic_router
from loveace.router.endpoint.jwc.competition import jwc_competition_router
from loveace.router.endpoint.jwc.exam import jwc_exam_router
from loveace.router.endpoint.jwc.plan import jwc_plan_router
from loveace.router.endpoint.jwc.schedule import jwc_schedules_router
from loveace.router.endpoint.jwc.score import jwc_score_router
from loveace.router.endpoint.jwc.term import jwc_term_router

jwc_base_router = APIRouter(prefix="/jwc", tags=["教务处"])
jwc_base_router.include_router(jwc_exam_router)
jwc_base_router.include_router(jwc_academic_router)
jwc_base_router.include_router(jwc_term_router)
jwc_base_router.include_router(jwc_score_router)
jwc_base_router.include_router(jwc_plan_router)
jwc_base_router.include_router(jwc_schedules_router)
jwc_base_router.include_router(jwc_competition_router)
