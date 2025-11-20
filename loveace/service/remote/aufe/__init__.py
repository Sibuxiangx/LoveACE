import asyncio
import binascii
import logging
import re
import uuid
from asyncio import Task
from base64 import b64encode
from datetime import datetime
from typing import Dict, Type, TypeVar

from cryptography.hazmat.backends import default_backend
from cryptography.hazmat.primitives import padding as symmetric_padding
from cryptography.hazmat.primitives.asymmetric import padding, rsa
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
from httpx import AsyncClient, RequestError
from httpx._types import HeaderTypes

from loveace.config.logger import LoggerMixin
from loveace.config.manager import config_manager
from loveace.service.model.service import Service
from loveace.service.remote.aufe.model.status import (
    ECCheckStatus,
    ECLoginStatus,
    UAAPLoginStatus,
)

# 设置 HTTPX 日志级别为 CRITICAL
if not config_manager.get_settings().app.debug:
    logging.getLogger("httpx").setLevel(logging.CRITICAL)


class SubClient:

    async def aclose(self): ...


T_SubClient = TypeVar("T_SubClient", bound=SubClient)


class AUFEConnection:
    userid: str
    ec_password: str
    password: str
    _client: AsyncClient
    twf_id: str
    last_check: datetime
    ec_logged: bool = False
    uaap_logged: bool = False
    trace_id: str
    timeout: int = 30
    _sub_clients: Dict[str, SubClient] = {}

    def __init__(self, userid: str, ec_password: str, password: str):
        self.userid = userid
        self.ec_password = ec_password
        self.password = password
        self.last_check = datetime.now()
        self.trace_id = str(uuid.uuid4().hex)
        self.timeout = config_manager.get_settings().aufe.default_timeout
        self.logger.info(
            f"创建AUFE连接，用户ID: {self.userid}, Trace ID: {self.trace_id}，超时: {self.timeout}s"
        )

    @property
    def logger(self) -> LoggerMixin:
        return LoggerMixin(user_id=self.userid, trace_id=self.trace_id)

    def start_client(self):
        self._client = AsyncClient()

    def health_checkpoint(self):
        self.last_check = datetime.now()

    async def health_check(self) -> bool:
        delta = datetime.now() - self.last_check
        self.logger.info(
            f"AUFE连接健康检查，距离上次检查时间: {delta.total_seconds()}秒"
        )
        if delta.total_seconds() > 300:  # 5分钟未检查则视为不健康
            self.logger.warning("AUFE连接不健康，已超过5分钟未检查，将自动关闭")
            return False
        if self._client.is_closed:
            self.logger.warning("AUFE连接已关闭")
            return False
        check_uaap = await self.check_uaap_login_status()
        if not check_uaap.logged_in:
            self.logger.warning("UAAP登录状态无效，可能需要重新登录")
            return False
        check_ec = await self.check_ec_login_status()
        if not check_ec.logged_in:
            self.logger.warning("EC登录状态无效，可能需要重新登录")
            return False
        return True

    def inject_subclient(self, name: str, sub_client: SubClient):
        """
        注入子客户端
        该方法用于将子客户端的关闭方法绑定到主客户端上
        以便在关闭主客户端时也能关闭子客户端
        Args:
            sub_client (SubClient): 子客户端实例，必须实现 aclose 方法
        """
        self.logger.info(f"注入子客户端 {name}，类型: {type(sub_client).__name__}")
        self._sub_clients[name] = sub_client

    def get_subclient(
        self, name: str, type_sub_client: Type[T_SubClient]
    ) -> T_SubClient | None:
        """
        获取已注入的子客户端
        Args:
            name (str): 子客户端名称
            type_sub_client (Type[T_SubClient]): 子客户端类型，用于类型检查
        Returns:
            T_SubClient: 子客户端实例
        Raises:
            ValueError: 如果子客户端不存在或类型不匹配
        """
        if name not in self._sub_clients:
            return None
        sub_client = self._sub_clients[name]
        if not isinstance(sub_client, type_sub_client):
            return None
        return sub_client

    async def close_client(self):
        await self._client.aclose()
        for sub_client in self._sub_clients.values():
            self.logger.info(f"正在关闭子客户端 {type(sub_client).__name__}")
            await sub_client.aclose()
        self._sub_clients.clear()

    async def ec_login(self) -> ECLoginStatus:
        """
        使用用户名和密码登录AUFE
        """
        try:
            # 初始请求获取认证参数
            response = await self._client.get(
                f"{config_manager.get_settings().aufe.server_url}/por/login_auth.csp?apiversion=1"
            )
            if twfid_g := re.search(r"<TwfID>(.*)</TwfID>", response.text):
                self.twf_id = twfid_g.group(1)
            else:
                self.logger.error("错误: 响应中未找到TwfID。")
                return ECLoginStatus(fail_not_found_twfid=True)
            self.logger.info(f"Twf Id: {self.twf_id[:5]}******")
            if rsa_key_g := re.search(
                r"<RSA_ENCRYPT_KEY>(.*)</RSA_ENCRYPT_KEY>", response.text
            ):
                rsa_key = rsa_key_g.group(1)
            else:
                self.logger.error("错误: 响应中未找到RSA_ENCRYPT_KEY。")
                return ECLoginStatus(fail_not_found_rsa_key=True)
            self.logger.info(f"RSA密钥: {rsa_key[:5]}******")
            if rsa_exp_match := re.search(
                r"<RSA_ENCRYPT_EXP>(.*)</RSA_ENCRYPT_EXP>", response.text
            ):
                rsa_exp = rsa_exp_match.group(1)
            else:
                self.logger.error("错误: 响应中未找到RSA_ENCRYPT_EXP。")
                return ECLoginStatus(fail_not_found_rsa_exp=True)
            self.logger.info(f"RSA指数: {rsa_exp[:5]}******")
            if csrf_match := re.search(
                r"<CSRF_RAND_CODE>(.*)</CSRF_RAND_CODE>", response.text
            ):
                csrf_code = csrf_match.group(1)
                password_to_encrypt = self.password + "_" + csrf_code
            else:
                self.logger.error("错误: 响应中未找到CSRF_RAND_CODE。")
                return ECLoginStatus(fail_not_found_csrf_code=True)
            self.logger.info(f"CSRF代码: {csrf_code[:5]}******")
            # 创建RSA密钥并加密密码
            rsa_exp_int = int(rsa_exp)
            rsa_modulus = int(rsa_key, 16)
            public_numbers = rsa.RSAPublicNumbers(e=rsa_exp_int, n=rsa_modulus)
            public_key = public_numbers.public_key(default_backend())
            encrypted_password = public_key.encrypt(
                password_to_encrypt.encode("utf-8"), padding.PKCS1v15()
            )
            encrypted_password_hex = binascii.hexlify(encrypted_password).decode(
                "ascii"
            )
            self.logger.info(f"加密后密码: {encrypted_password_hex[:5]}******")
            self.logger.info("开始执行登录请求")
            login_response = await self._client.post(
                f"{config_manager.get_settings().aufe.server_url}/por/login_psw.csp?anti_replay=1&encrypt=1&type=cs",
                data={
                    "svpn_rand_code": "",
                    "mitm": "",
                    "svpn_req_randcode": csrf_code,
                    "svpn_name": self.userid,
                    "svpn_password": encrypted_password_hex,
                },
                cookies={"TWFID": self.twf_id},
                timeout=10000,
            )
            self.logger.info(f"登录响应: {login_response.text[:10]}******")
            # 检查登录结果
            if "<Result>1</Result>" in login_response.text:
                self.logger.info("登录成功")
                self._client.cookies.set("TWFID", self.twf_id)
                self.ec_logged = True
                return ECLoginStatus(success=True)
            elif "Invalid username or password!" in login_response.text:
                self.logger.error("登录失败: 用户名或密码错误")
                return ECLoginStatus(fail_invalid_credentials=True)
            elif "[CDATA[maybe attacked]]" in login_response.text or  "CAPTCHA required" in login_response.text:
                self.logger.error("登录失败: 可能受到攻击或需要验证码")
                return ECLoginStatus(fail_maybe_attacked=True)
            else:
                self.logger.error(f"登录失败: {login_response.text}")
                return ECLoginStatus(fail_unknown_error=True)

        except RequestError as e:
            self.logger.error(f"登录连接错误: {str(e)}")
            return ECLoginStatus(fail_network_error=True)
        except Exception as e:
            self.logger.error(f"登录失败: {e}")
            return ECLoginStatus(fail_unknown_error=True)

    async def check_ec_login_status(self) -> ECCheckStatus:
        """
        检查当前登录状态
        """
        if not self.ec_logged:
            return ECCheckStatus(logged_in=False)
        try:
            response = await self._client.get(
                config_manager.get_settings().aufe.ec_check_url,
            )
            if response.status_code == 200:
                self.logger.info("登录状态有效")
                return ECCheckStatus(logged_in=True)
            else:
                self.logger.warning("登录状态无效，可能需要重新登录")
                return ECCheckStatus(logged_in=False)
        except RequestError as e:
            self.logger.error(f"检查登录状态连接错误: {str(e)}")
            return ECCheckStatus(fail_network_error=True)
        except Exception as e:
            self.logger.error(f"检查登录状态失败: {e}")
            return ECCheckStatus(fail_unknown_error=True)

    async def uaap_login(self) -> UAAPLoginStatus:
        """
        使用用户名和密码登录UAAP
        """
        try:
            # 初始请求获取登录页面
            response = await self._client.get(
                config_manager.get_settings().aufe.uaap_login_url
            )
            if lt_match := re.search(r'name="lt" value="(.*?)"', response.text):
                lt_value = lt_match.group(1)
            else:
                self.logger.error("错误: 登录页面中未找到lt参数。")
                return UAAPLoginStatus(fail_not_found_lt=True)
            self.logger.info(f"lt参数: {lt_value[:5]}******")
            if execution_match := re.search(
                r'name="execution" value="(.*?)"', response.text
            ):
                execution_value = execution_match.group(1)
            else:
                self.logger.error("错误: 登录页面中未找到execution参数。")
                return UAAPLoginStatus(fail_not_found_execution=True)
            self.logger.info(f"execution参数: {execution_value[:5]}******")
            # 处理密钥 - CryptoJS使用的是8字节密钥
            key_bytes = lt_value.encode("utf-8")[:8]
            # 如果密钥不足8字节，则用0填充
            if len(key_bytes) < 8:
                key_bytes = key_bytes + b"\0" * (8 - len(key_bytes))

            # 处理明文数据 - 确保是字节类型
            password_bytes = self.password.encode("utf-8")

            # 使用PKCS7填充
            padder = symmetric_padding.PKCS7(64).padder()
            padded_data = padder.update(password_bytes) + padder.finalize()

            # 创建DES加密器 - ECB模式
            cipher = Cipher(
                algorithms.TripleDES(key_bytes), modes.ECB(), backend=default_backend()
            )
            encryptor = cipher.encryptor()

            # 加密数据
            encrypted = encryptor.update(padded_data) + encryptor.finalize()

            # 提交登录表单
            login_response = await self._client.post(
                config_manager.get_settings().aufe.uaap_login_url,
                data={
                    "username": self.userid,
                    "password": b64encode(encrypted).decode("utf-8"),
                    "lt": lt_value,
                    "execution": execution_value,
                    "_eventId": "submit",
                    "submit": "LOGIN",
                },
                timeout=10000,
            )
            # 检查登录结果
            if (
                login_response.status_code == 302
                and "Location" in login_response.headers
            ):
                redirect_url = login_response.headers["Location"]
                if redirect_url.startswith(
                    config_manager.get_settings().aufe.uaap_check_url
                ):
                    self.logger.info("UAAP登录成功")
                    self.uaap_logged = True
                    return UAAPLoginStatus(success=True)
            elif "Invalid username or password" in login_response.text:
                self.logger.error("UAAP登录失败: 用户名或密码错误")
                return UAAPLoginStatus(fail_invalid_credentials=True)
            else:
                self.logger.error(f"UAAP登录失败: {login_response.text}")
                return UAAPLoginStatus(fail_unknown_error=True)
            return UAAPLoginStatus(fail_unknown_error=True)

        except RequestError as e:
            self.logger.error(f"UAAP登录连接错误: {str(e)}")
            return UAAPLoginStatus(fail_network_error=True)
        except Exception as e:
            self.logger.error(f"UAAP登录失败: {e}")
            return UAAPLoginStatus(fail_unknown_error=True)

    async def check_uaap_login_status(self) -> ECCheckStatus:
        """
        检查当前UAAP登录状态
        """
        return ECCheckStatus(logged_in=self.uaap_logged)

    @property
    def client(self) -> AsyncClient:
        """
        获取HTTP客户端实例
        注意: 此客户端只适用于教务系统，其他系统请查看具体 Service 实现
        """
        self.health_checkpoint()
        return self._client

    @property
    def empty_client(self, headers: HeaderTypes | None = None) -> AsyncClient:
        """
        获取一个新的空白HTTP客户端实例，用于子系统构建请求
        """
        self.health_checkpoint()
        return AsyncClient(headers=headers)


class AUFEService(Service):
    """
    AUFE服务类
    该类用于管理多个AUFE连接实例，提供获取或创建连接的功能
    并定期清理不健康的连接
    """

    sessions: dict[str, AUFEConnection] = {}
    logger: LoggerMixin
    task: Task

    def __init__(self):
        # AUFEService 的 logger 不需要 trace_id，因为它是服务级别的日志
        self.logger = LoggerMixin(user_id="AUFEService", trace_id="")

    async def get_or_create_connection(
        self, userid: str, ec_password: str, password: str
    ) -> AUFEConnection:
        """
        获取或创建AUFE连接
        该方法会检查现有连接的健康状态，如果不健康则重新创建连接
        注意，获取实例后请尽快操作登录，否则可能因为连接不健康而需要重新创建
        Args:
            userid (str): 用户ID
            ec_password (str): EC系统密码
            password (str): UAAP密码
        Returns:
            AUFEConnection: AUFE连接实例
        """
        if userid not in self.sessions:
            self.sessions[userid] = AUFEConnection(
                userid=userid, ec_password=ec_password, password=password
            )
            self.sessions[userid].start_client()
            return self.sessions[userid]
        return self.sessions[userid]

    async def _loop_cleanup(self):
        """
        清理不健康的AUFE连接
        """
        to_remove = []
        for userid, connection in self.sessions.items():
            if not await connection.health_check():
                self.logger.info(f"用户 {userid} 的AUFE连接不健康，正在关闭连接")
                await connection.close_client()
                self.logger.info(f"用户 {userid} 的AUFE连接已关闭，正在移除连接")
                to_remove.append(userid)
                self.logger.info(f"用户 {userid} 的AUFE连接已移除")
        for userid in to_remove:
            del self.sessions[userid]

    async def loop_cleanup_task(self):
        """
        定期清理不健康的AUFE连接 ASYNC TASK
        该任务每5分钟运行一次，检查所有连接的健康状态，并清理不健康的连接
        该任务应在应用启动时运行，并在应用关闭时取消
        """
        while True:
            await asyncio.sleep(60)  # 每分钟检查一次
            await self._loop_cleanup()

    async def initialize(self):
        """
        初始化AUFE服务
        该方法在应用启动时调用，用于启动清理任务
        """
        self.logger.info("初始化AUFE服务")
        self.task = asyncio.create_task(self.loop_cleanup_task())
        self.logger.info("AUFE服务初始化完成")

    async def shutdown(self):
        """
        关闭AUFE服务
        该方法在应用关闭时调用，用于关闭所有连接
        """
        self.logger.info("关闭AUFE服务")
        for userid, connection in self.sessions.items():
            self.logger.info(f"正在关闭用户 {userid} 的AUFE连接")
            await connection.close_client()
            self.logger.info(f"用户 {userid} 的AUFE连接已关闭")
        self.sessions.clear()
        self.task.cancel()
        try:
            await self.task
        except asyncio.CancelledError:
            self.logger.info("AUFE服务已关闭")
            pass
