from pathlib import Path

from loveace.config.manager import config_manager

settings = config_manager.get_settings()


class LDJLBConfig:
    """劳动俱乐部模块配置常量"""

    BASE_URL = "http://api-ldjlb-ac-acxk-net.vpn2.aufe.edu.cn:8118"
    WEB_URL = "http://ldjlb-ac-acxk-net.vpn2.aufe.edu.cn:8118"
    LOGIN_SERVICE_URL = "http://uaap-aufe-edu-cn.vpn2.aufe.edu.cn:8118/cas/login?service=http%3a%2f%2fapi.ldjlb.ac.acxk.net%2fUser%2fIndex%2fCoreLoginCallback%3fisCASGateway%3dtrue"
    RSA_PRIVATE_KEY_PATH = str(
        Path(settings.app.rsa_protect_key_path).joinpath("aac_private_key.pem")
    )

    def to_full_url(self, path: str) -> str:
        """将路径转换为完整URL"""
        if path.startswith("http://") or path.startswith("https://"):
            return path
        return self.BASE_URL.rstrip("/") + "/" + path.lstrip("/")
