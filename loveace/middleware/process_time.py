import time

from fastapi import Request
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.responses import Response

from loveace.config.logger import logger


class ProcessTimeMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next):
        start_time = time.time()
        logger.info(
            f"{request.method} {request.url.path} START",
            f"[Bold White][{request.method}][/Bold White] {request.url.path} [Bold Green]START[/Bold Green]",
        )
        response: Response = await call_next(request)
        process_time = time.time() - start_time
        response.headers["X-Process-Time"] = str(process_time)
        logger.info(
            f"{request.method} {request.url.path} END ({process_time:.4f}s)",
            f"[Bold White][{request.method}][/Bold White] {request.url.path} [Bold Green]END[/Bold Green] [Dim]({process_time:.4f}s)[/Dim]",
        )
        return response
