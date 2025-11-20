import base64
import os
from contextvars import ContextVar
from pathlib import Path
from typing import Dict

from cryptography.hazmat.backends import default_backend
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding, rsa
from cryptography.hazmat.primitives.asymmetric.rsa import RSAPrivateKey, RSAPublicKey
from cryptography.hazmat.primitives.ciphers.aead import AESGCMSIV
from cryptography.hazmat.primitives.kdf.pbkdf2 import PBKDF2HMAC
from rich.console import Console
from rich.panel import Panel
from rich.prompt import Prompt

from loveace.config.manager import config_manager

console = Console()

rsa_context: ContextVar[Dict[str, "RSAUtils"]] = ContextVar("rsa_context")


class RSAUtils:
    """RSA 工具类，支持 AES-GCM-SIV 加密的密钥保护"""

    private_key_path: str
    private_key: RSAPrivateKey
    public_key: RSAPublicKey

    def __init__(self, private_key_path: str | None = None):
        """初始化 RSAUtils 类

        Args:
            private_key_path (str): 私钥文件路径
        """
        settings = config_manager.get_settings()
        self.private_key_path = str(
            Path(settings.app.rsa_protect_key_path).joinpath(
                Path(
                    private_key_path
                    or config_manager.get_settings().app.rsa_private_key_path
                ).name
            )
        )
        # 转换路径扩展名为 .hex
        self.private_key_path = str(self.private_key_path).replace(".pem", ".hex")
        self.load_keys()

    def _derive_key_from_password(
        self, password: str, salt: bytes | None = None
    ) -> tuple[bytes, bytes]:
        """从密码派生 AES 密钥

        Args:
            password (str): 用户输入的密码
            salt (bytes): 盐值，如果为 None 则生成新的

        Returns:
            tuple[bytes, bytes]: (派生密钥, 盐值)
        """
        if salt is None:
            salt = os.urandom(16)

        kdf_obj = PBKDF2HMAC(
            algorithm=hashes.SHA256(),
            length=16,  # AES-128 需要 16 字节密钥
            salt=salt,
            iterations=100000,
        )
        key = kdf_obj.derive(password.encode("utf-8"))
        return key, salt

    def load_keys(self):
        """加载密钥对（从加密的 AES 文件中）"""
        path = Path(self.private_key_path)
        console.print(
            Panel(
                f"[bold cyan]正在操作密钥文件[/bold cyan]\n"
                f"[cyan]文件路径：{self.private_key_path}[/cyan]",
                expand=False,
            )
        )
        if not path.exists():
            console.print(
                Panel(
                    "[bold yellow]RSA 密钥对不存在，将为您生成新的密钥对[/bold yellow]",
                    title="[bold blue]密钥生成[/bold blue]",
                    expand=False,
                )
            )
            self.generate_keys()
        else:
            self._load_encrypted_key()

    def _load_encrypted_key(self):
        """从加密的 .hex 文件加载密钥"""
        console.print(
            Panel(
                f"[bold cyan]检测到本地 RSA 私钥文件[/bold cyan]\n"
                f"[cyan]文件路径：{self.private_key_path}[/cyan]",
                title="[bold blue]密钥加载[/bold blue]",
                expand=False,
            )
        )

        console.print(
            "[bold yellow]该密钥文件受密码保护，需要您输入密码来解密[/bold yellow]"
        )
        password = Prompt.ask(
            "[bold]请输入 RSA 私钥密码[/bold]", password=True, console=console
        )

        with open(self.private_key_path, "rb") as key_file:
            encrypted_data = key_file.read()

        # 解析加密数据：salt(16) + nonce(12) + ciphertext
        salt = encrypted_data[:16]
        nonce = encrypted_data[16:28]
        ciphertext = encrypted_data[28:]

        # 派生密钥
        key, _ = self._derive_key_from_password(password, salt)

        # 使用 AES-GCM-SIV 解密
        try:
            aesgcmsiv = AESGCMSIV(key)
            plaintext = aesgcmsiv.decrypt(nonce, ciphertext, None)
            console.print("[bold green]✓ 私钥密码验证成功[/bold green]")
        except Exception as e:
            console.print(
                Panel(
                    "[bold red]✗ 私钥密码错误或密钥文件已损坏[/bold red]",
                    title="[bold red]错误[/bold red]",
                    expand=False,
                )
            )
            raise ValueError("Invalid password or corrupted key file") from e

        # 加载 PEM 格式的私钥
        try:
            pk = serialization.load_pem_private_key(
                plaintext, password=None, backend=default_backend()
            )
            if isinstance(pk, RSAPrivateKey):
                self.private_key = pk
            else:
                raise ValueError("Loaded key is not an RSA private key")
        except Exception:
            console.print(
                Panel(
                    "[bold red]✗ 密钥格式错误[/bold red]",
                    title="[bold red]错误[/bold red]",
                    expand=False,
                )
            )
            raise

        self.public_key = self.private_key.public_key()

    def generate_keys(self, key_size: int = 2048):
        """生成 RSA 密钥对并使用 AES 加密保存到文件

        Args:
            key_size (int): 密钥大小，默认2048位
        """
        path = Path(self.private_key_path)
        path.parent.mkdir(parents=True, exist_ok=True)

        # 提示用户设置密码
        console.print(
            Panel(
                "[bold cyan]请设置 RSA 私钥密码（用于保护密钥文件）[/bold cyan]",
                title="[bold blue]密钥保护[/bold blue]",
                expand=False,
            )
        )
        password = Prompt.ask("[bold]请输入密码[/bold]", password=True, console=console)
        password_confirm = Prompt.ask(
            "[bold]请确认密码[/bold]", password=True, console=console
        )

        if password != password_confirm:
            console.print(
                Panel(
                    "[bold red]✗ 两次输入的密码不一致[/bold red]",
                    title="[bold red]错误[/bold red]",
                    expand=False,
                )
            )
            raise ValueError("Passwords do not match")

        # 生成 RSA 密钥对
        console.print("[bold cyan]正在生成 RSA 密钥对...[/bold cyan]")
        private_key = rsa.generate_private_key(
            public_exponent=65537, key_size=key_size, backend=default_backend()
        )
        public_key = private_key.public_key()

        # 将私钥序列化为 PEM 格式
        pem_private = private_key.private_bytes(
            encoding=serialization.Encoding.PEM,
            format=serialization.PrivateFormat.TraditionalOpenSSL,
            encryption_algorithm=serialization.NoEncryption(),
        )

        pem_public = public_key.public_bytes(
            encoding=serialization.Encoding.PEM,
            format=serialization.PublicFormat.SubjectPublicKeyInfo,
        )

        # 使用 AES-GCM-SIV 加密私钥
        key, salt = self._derive_key_from_password(password)
        aesgcmsiv = AESGCMSIV(key)
        nonce = os.urandom(12)
        ciphertext = aesgcmsiv.encrypt(nonce, pem_private, None)

        # 保存加密的私钥：salt + nonce + ciphertext
        with open(self.private_key_path, "wb") as private_file:
            private_file.write(salt + nonce + ciphertext)

        # 保存公钥（不加密）
        public_key_path = self.private_key_path.replace(".hex", "_public.pem")
        with open(public_key_path, "wb") as public_file:
            public_file.write(pem_public)

        self.private_key = private_key
        self.public_key = public_key

        console.print(
            Panel(
                f"[bold green]✓ RSA 密钥对生成成功[/bold green]\n"
                f"[cyan]私钥路径：[/cyan]{self.private_key_path}\n"
                f"[cyan]公钥路径：[/cyan]{public_key_path}",
                title="[bold blue]完成[/bold blue]",
                expand=False,
            )
        )

    def encrypt(self, plaintext: str) -> str:
        """使用公钥加密数据

        Args:
            plaintext (str): 明文字符串

        Returns:
            str: Base64 编码的密文字符串
        """
        ciphertext = self.public_key.encrypt(
            plaintext.encode("utf-8"),
            padding.PKCS1v15(),
        )
        return base64.b64encode(ciphertext).decode("utf-8")

    def decrypt(self, b64_ciphertext: str) -> str:
        """使用私钥解密数据

        Args:
            b64_ciphertext (str): Base64 编码的密文字符串

        Returns:
            str: 解密后的明文字符串
        """
        ciphertext = base64.b64decode(b64_ciphertext)
        plaintext = self.private_key.decrypt(
            ciphertext,
            padding.PKCS1v15(),
        )
        return plaintext.decode("utf-8")

    @staticmethod
    def encrypt_file_with_aes(
        plaintext: bytes, password: str | None = None
    ) -> tuple[bytes, str]:
        """使用 AES-GCM-SIV 和密码加密数据

        Args:
            plaintext (bytes): 明文数据
            password (str): 密码，如果为 None 则生成随机密钥

        Returns:
            tuple[bytes, str]: (加密数据, 密钥的十六进制字符串)
        """
        if password is None:
            # 生成随机密钥
            key = AESGCMSIV.generate_key(bit_length=128)
            aesgcmsiv = AESGCMSIV(key)
            nonce = os.urandom(12)
            ciphertext = aesgcmsiv.encrypt(nonce, plaintext, None)
            encrypted_data = key + nonce + ciphertext
        else:
            # 从密码派生密钥
            salt = os.urandom(16)
            kdf_obj = PBKDF2HMAC(
                algorithm=hashes.SHA256(),
                length=16,
                salt=salt,
                iterations=100000,
            )
            key = kdf_obj.derive(password.encode("utf-8"))
            aesgcmsiv = AESGCMSIV(key)
            nonce = os.urandom(12)
            ciphertext = aesgcmsiv.encrypt(nonce, plaintext, None)
            encrypted_data = salt + nonce + ciphertext

        key_hex = key.hex()
        return encrypted_data, key_hex

    @staticmethod
    def get_or_create_rsa_utils(private_key_path: str | None = None) -> "RSAUtils":
        """
        获取或创建 RSAUtils 实例
        Args:
            private_key_path (str | None): 私钥文件路径，如果为 None 则使用配置中的默认路径
        """
        private_key_path = (
            private_key_path or config_manager.get_settings().app.rsa_private_key_path
        )
        try:
            rsa_utils_dict = rsa_context.get()
            if private_key_path in rsa_utils_dict:
                return rsa_utils_dict[private_key_path]
            else:
                rsa_utils = RSAUtils(private_key_path)
                rsa_utils_dict[private_key_path] = rsa_utils
                rsa_context.set(rsa_utils_dict)
                return rsa_utils
        except LookupError:
            rsa_utils = RSAUtils(private_key_path)
            rsa_utils_dict = {private_key_path: rsa_utils}
            rsa_context.set(rsa_utils_dict)
            return rsa_utils
