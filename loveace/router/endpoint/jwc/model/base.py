class JWCConfig:
    """教务系统配置常量"""

    DEFAULT_BASE_URL = "http://jwcxk2-aufe-edu-cn.vpn2.aufe.edu.cn:8118/"

    def to_full_url(self, path: str) -> str:
        """将路径转换为完整URL"""
        if path.startswith("http://") or path.startswith("https://"):
            return path
        return self.DEFAULT_BASE_URL.rstrip("/") + "/" + path.lstrip("/")
