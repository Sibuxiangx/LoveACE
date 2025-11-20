import uuid

from loveace.config.logger import LoggerMixin


def no_user_logger_mixin() -> LoggerMixin:
    return LoggerMixin(trace_id=str(uuid.uuid4().hex))


def logger_mixin_with_user(userid: str) -> LoggerMixin:
    return LoggerMixin(trace_id=str(uuid.uuid4().hex), user_id=userid)
