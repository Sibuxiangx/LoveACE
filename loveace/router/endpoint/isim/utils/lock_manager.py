"""
全局锁管理器模块
用于管理需要冷却时间(CD)的操作锁
"""

import asyncio
import time
from typing import Optional


class RefreshLockManager:
    """刷新操作锁管理器，确保一次只能执行一个刷新操作，且有30分钟的冷却时间"""

    def __init__(self, cooldown_seconds: int = 1800):  # 默认30分钟 = 1800秒
        """
        初始化锁管理器

        Args:
            cooldown_seconds: 冷却时间（秒），默认为1800秒（30分钟）
        """
        self._lock = asyncio.Lock()
        self._last_refresh_time: Optional[float] = None
        self._cooldown_seconds = cooldown_seconds
        self._is_refreshing = False

    async def try_acquire(self) -> tuple[bool, Optional[float]]:
        """
        尝试获取锁并检查冷却时间

        Returns:
            tuple[bool, Optional[float]]:
                - bool: 是否成功获取锁（未在冷却期且未被占用）
                - Optional[float]: 如果在冷却期，返回剩余冷却时间（秒），否则为None
        """
        # 检查是否有其他人正在刷新
        if self._is_refreshing:
            return False, None

        # 检查冷却时间
        if self._last_refresh_time is not None:
            elapsed = time.time() - self._last_refresh_time
            if elapsed < self._cooldown_seconds:
                remaining_cooldown = self._cooldown_seconds - elapsed
                return False, remaining_cooldown

        # 尝试获取锁（非阻塞）
        acquired = not self._lock.locked()
        if acquired:
            await self._lock.acquire()
            self._is_refreshing = True

        return acquired, None

    def release(self):
        """
        释放锁并更新最后刷新时间
        """
        self._last_refresh_time = time.time()
        self._is_refreshing = False
        if self._lock.locked():
            self._lock.release()

    def get_remaining_cooldown(self) -> Optional[float]:
        """
        获取剩余冷却时间

        Returns:
            Optional[float]: 剩余冷却时间（秒），如果不在冷却期则返回None
        """
        if self._last_refresh_time is None:
            return None

        elapsed = time.time() - self._last_refresh_time
        if elapsed < self._cooldown_seconds:
            return self._cooldown_seconds - elapsed

        return None

    def is_in_cooldown(self) -> bool:
        """
        检查是否在冷却期内

        Returns:
            bool: 是否在冷却期内
        """
        return self.get_remaining_cooldown() is not None

    def is_refreshing(self) -> bool:
        """
        检查是否正在刷新

        Returns:
            bool: 是否正在刷新
        """
        return self._is_refreshing


# 全局单例实例
_refresh_lock_manager = RefreshLockManager(cooldown_seconds=1800)  # 30分钟


def get_refresh_lock_manager() -> RefreshLockManager:
    """
    获取全局刷新锁管理器实例

    Returns:
        RefreshLockManager: 全局锁管理器实例
    """
    return _refresh_lock_manager
