from loveace.router.schemas.uniresponse import UniResponseModel


class UniResponseHTTPException(Exception):
    """
    统一响应格式的 HTTP 异常，用于在路由中直接抛出异常时使用。
    """

    def __init__(self, status_code: int, uni_response: UniResponseModel):
        self.status_code = status_code
        self.uni_response = uni_response
