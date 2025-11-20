from abc import abstractmethod


class Service:
    @abstractmethod
    async def initialize(self):
        """初始化服务"""
        pass

    @abstractmethod
    async def shutdown(self):
        """关闭服务"""
        pass
