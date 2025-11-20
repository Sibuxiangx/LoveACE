from loveace.service.remote.s3 import S3Service

s3 = S3Service()


async def get_s3_service() -> S3Service:
    """获取S3服务实例"""
    return s3
