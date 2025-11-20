import asyncio
from contextlib import asynccontextmanager

import uvicorn
from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from starlette.exceptions import HTTPException

from loveace.config.logger import logger
from loveace.config.manager import config_manager
from loveace.database.creator import db_manager
from loveace.middleware.process_time import ProcessTimeMiddleware
from loveace.router.endpoint.aac import aac_base_router
from loveace.router.endpoint.ldjlb import ldjlb_base_router
from loveace.router.endpoint.apifox import apifox_router
from loveace.router.endpoint.auth import auth_router
from loveace.router.endpoint.isim import isim_base_router
from loveace.router.endpoint.jwc import jwc_base_router
from loveace.router.endpoint.profile import profile_router
from loveace.router.endpoint.utils.alive import alive_router
from loveace.router.schemas.exception import UniResponseHTTPException
from loveace.router.schemas.model import ValidationErrorDetail, ValidationErrorModel
from loveace.router.schemas.uniresponse import UniResponseModel
from loveace.service.remote.aufe.depends import service as aufe_service


@asynccontextmanager
async def lifespan(app: FastAPI):
    # 验证配置文件完整性
    if not config_manager.validate_config():
        logger.error("配置文件验证失败，请检查配置")
        raise RuntimeError("配置文件验证失败")

    logger.info("应用程序启动中...")

    # 启动时连接数据库
    if await db_manager.init_db():
        logger.info("数据库连接成功")
    else:
        logger.error("数据库连接失败，应用程序无法启动")
        await asyncio.sleep(5)
        raise RuntimeError("数据库初始化失败")

    # 启动时连接Redis
    try:
        await db_manager.get_redis_client()
        logger.info("Redis连接成功")
    except Exception as e:
        logger.error(f"Redis连接失败: {e}")
        await db_manager.close_db()
        raise RuntimeError("Redis初始化失败")

    # 启动时执行 AUFE 服务初始化
    try:
        await aufe_service.initialize()
        logger.info("AUFE服务初始化成功")
    except Exception as e:
        logger.error(f"AUFE服务初始化失败: {e}")
        raise

    yield

    # 关闭时断开Redis连接
    await db_manager.close_redis()
    logger.info("Redis连接已关闭")

    # 关闭时断开数据库连接
    await db_manager.close_db()
    logger.info("应用程序已关闭")

    # 关闭时清理 AUFE 服务
    try:
        await aufe_service.shutdown()
    except Exception as e:
        logger.warning(f"AUFE服务关闭异常: {e}")


# 获取应用配置
app_config = config_manager.get_settings().app

# 创建FastAPI应用
app = FastAPI(
    lifespan=lifespan,
    title=app_config.title,
    description=app_config.description,
    version=app_config.version,
    debug=app_config.debug,
    docs_url="/docs" if app_config.debug else None,
    redoc_url="/redoc" if app_config.debug else None,
    openapi_url="/openapi.json" if app_config.debug else None,
)

# CORS配置
app.add_middleware(
    CORSMiddleware,
    allow_origins=app_config.cors_allow_origins,
    allow_credentials=app_config.cors_allow_credentials,
    allow_methods=app_config.cors_allow_methods,
    allow_headers=app_config.cors_allow_headers,
)

# 处理时间中间件
app.add_middleware(ProcessTimeMiddleware)

# 注册路由
app.include_router(apifox_router)
app.include_router(profile_router)
app.include_router(alive_router)
app.include_router(auth_router)
app.include_router(jwc_base_router)
app.include_router(aac_base_router)
app.include_router(ldjlb_base_router)
app.include_router(isim_base_router)


async def uniresponse_http_exception_handler(
    request: Request, exc: UniResponseHTTPException
):
    return JSONResponse(
        status_code=exc.status_code,
        content=exc.uni_response.model_dump(),
    )


async def validation_exception_handler(request: Request, exc: RequestValidationError):
    return JSONResponse(
        status_code=422,
        content=UniResponseModel(
            success=False,
            data=None,
            message=None,
            error=ValidationErrorModel(
                message="请求参数验证错误",
                code="VALIDATION_ERROR",
                trace_id="",
                details=[
                    ValidationErrorDetail(
                        loc=err["loc"],
                        msg=err["msg"],
                        type=err["type"],
                    )
                    for err in exc.errors()
                ],
            ),
        ).model_dump(),
    )


app.exception_handlers[UniResponseHTTPException] = uniresponse_http_exception_handler
app.exception_handlers[RequestValidationError] = validation_exception_handler


if __name__ == "__main__":
    if app_config.debug:
        uvicorn.run(
            app,
            host=app_config.host,
            port=app_config.port,
            workers=app_config.workers,
        )
    else:
        logger.info(
            f"请手动输入如下指令启动服务:\ngranian --interface asgi main:app --host {app_config.host} --port {app_config.port} --workers {app_config.workers} --process-name LoveACE-V2"
        )
