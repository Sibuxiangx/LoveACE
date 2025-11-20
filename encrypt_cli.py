#!/usr/bin/env python3
"""
RSA 密钥文件管理工具
支持：
1. 将 .pem 格式的密钥文件加密为 .hex 格式（使用 AES-GCM-SIV 加密）
2. 修改已加密密钥的密码
"""

import os
import shutil
from pathlib import Path

from cryptography.hazmat.backends import default_backend
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.ciphers.aead import AESGCMSIV
from cryptography.hazmat.primitives.kdf.pbkdf2 import PBKDF2HMAC
from rich.console import Console
from rich.panel import Panel
from rich.prompt import Prompt
from rich.table import Table

console = Console()


def derive_key_from_password(
    password: str, salt: bytes | None = None
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

    kdf = PBKDF2HMAC(
        algorithm=hashes.SHA256(),
        length=16,  # AES-128 需要 16 字节密钥
        salt=salt,
        iterations=100000,
    )
    key = kdf.derive(password.encode("utf-8"))
    return key, salt


def encrypt_pem_file(pem_file_path: str, password: str) -> str:
    """加密 PEM 文件并保存为 .hex 格式

    Args:
        pem_file_path (str): PEM 文件路径
        password (str): 密码

    Returns:
        str: 保存的 .hex 文件路径
    """
    pem_path = Path(pem_file_path)

    # 读取 PEM 文件
    if not pem_path.exists():
        console.print(f"[red]✗ 文件不存在: {pem_file_path}[/red]")
        return ""

    with open(pem_path, "rb") as f:
        plaintext = f.read()

    # 派生密钥并加密
    key, salt = derive_key_from_password(password)
    aesgcmsiv = AESGCMSIV(key)
    nonce = os.urandom(12)
    ciphertext = aesgcmsiv.encrypt(nonce, plaintext, None)

    # 生成 .hex 文件路径
    hex_path = str(pem_path).replace(".pem", ".hex")

    # 保存加密数据：salt + nonce + ciphertext
    with open(hex_path, "wb") as f:
        f.write(salt + nonce + ciphertext)

    return hex_path


def find_all_key_files(search_dir: str = ".") -> tuple[list[Path], list[Path]]:
    """检索项目中的所有密钥文件

    Args:
        search_dir (str): 搜索目录，默认为当前目录

    Returns:
        tuple[list[Path], list[Path]]: (.pem 文件列表, .hex 文件列表)
    """
    search_path = Path(search_dir)
    pem_files = []
    hex_files = []

    for pem_file in search_path.rglob("*.pem"):
        # 排除备份文件
        if not pem_file.name.endswith(".backup"):
            pem_files.append(pem_file)

    for hex_file in search_path.rglob("*.hex"):
        hex_files.append(hex_file)

    return pem_files, hex_files


def change_key_password(hex_file_path: str):
    """修改已加密密钥的密码

    Args:
        hex_file_path (str): .hex 密钥文件路径
    """
    hex_path = Path(hex_file_path)

    if not hex_path.exists():
        console.print(
            Panel(
                f"[bold red]✗ 文件不存在: {hex_file_path}[/bold red]",
                title="[bold red]错误[/bold red]",
                expand=False,
            )
        )
        return

    # 读取加密的文件
    with open(hex_path, "rb") as f:
        encrypted_data = f.read()

    # 解析加密数据：salt(16) + nonce(12) + ciphertext
    salt = encrypted_data[:16]
    nonce = encrypted_data[16:28]
    ciphertext = encrypted_data[28:]

    # 请求旧密码
    console.print(
        Panel(
            "[bold cyan]请输入当前密码以验证[/bold cyan]",
            title="[bold blue]验证密钥[/bold blue]",
            expand=False,
        )
    )
    old_password = Prompt.ask(
        "[bold]请输入当前密码[/bold]", password=True, console=console
    )

    # 验证旧密码
    try:
        old_key, _ = derive_key_from_password(old_password, salt)
        aesgcmsiv = AESGCMSIV(old_key)
        plaintext = aesgcmsiv.decrypt(nonce, ciphertext, None)
        console.print("[bold green]✓ 密码验证成功[/bold green]")
    except Exception:
        console.print(
            Panel(
                "[bold red]✗ 密码错误或密钥文件已损坏[/bold red]",
                title="[bold red]错误[/bold red]",
                expand=False,
            )
        )
        return

    # 设置新密码
    console.print(
        Panel(
            "[bold cyan]请设置新密码[/bold cyan]",
            title="[bold blue]设置新密码[/bold blue]",
            expand=False,
        )
    )

    new_password = Prompt.ask(
        "[bold]请输入新密码[/bold]", password=True, console=console
    )
    new_password_confirm = Prompt.ask(
        "[bold]请确认新密码[/bold]", password=True, console=console
    )

    if new_password != new_password_confirm:
        console.print(
            Panel(
                "[bold red]✗ 两次输入的密码不一致[/bold red]",
                title="[bold red]错误[/bold red]",
                expand=False,
            )
        )
        return

    if new_password == old_password:
        console.print(
            Panel(
                "[bold yellow]⚠ 新密码与旧密码相同，无需修改[/bold yellow]",
                expand=False,
            )
        )
        return

    # 使用新密码重新加密
    console.print("[bold cyan]正在重新加密文件...[/bold cyan]")
    new_key, new_salt = derive_key_from_password(new_password)
    new_aesgcmsiv = AESGCMSIV(new_key)
    new_nonce = os.urandom(12)
    new_ciphertext = new_aesgcmsiv.encrypt(new_nonce, plaintext, None)

    # 保存新的加密数据
    with open(hex_path, "wb") as f:
        f.write(new_salt + new_nonce + new_ciphertext)

    console.print(
        Panel(
            "[bold green]✓ 密钥密码修改成功[/bold green]",
            title="[bold blue]完成[/bold blue]",
            expand=False,
        )
    )


def main_menu():
    """主菜单"""
    while True:
        console.clear()
        console.print(
            Panel(
                "[bold cyan]RSA 密钥文件管理工具[/bold cyan]",
                title="[bold blue]主菜单[/bold blue]",
                expand=False,
            )
        )

        console.print()
        menu_options = [
            "1. 加密 PEM 密钥文件",
            "2. 修改密钥密码",
            "3. 退出",
        ]

        for option in menu_options:
            console.print(f"  {option}")

        console.print()
        choice = Prompt.ask(
            "[bold]请选择操作[/bold]",
            choices=["1", "2", "3"],
            console=console,
        )

        if choice == "1":
            encrypt_key_operation()
        elif choice == "2":
            change_password_operation()
        elif choice == "3":
            console.print("[bold cyan]再见！[/bold cyan]")
            break


def encrypt_key_operation():
    """加密密钥文件的交互操作"""
    console.clear()
    console.print(
        Panel(
            "[bold cyan]加密 PEM 密钥文件[/bold cyan]",
            title="[bold blue]加密操作[/bold blue]",
            expand=False,
        )
    )

    # 获取密钥文件路径
    default_path = "data/keys/private_key.pem"
    private_key_path = Prompt.ask(
        "[bold]请输入 RSA 私钥文件路径[/bold]",
        default=default_path,
        console=console,
    )

    console.print(
        Panel(
            f"[bold cyan]正在操作密钥文件[/bold cyan]\n"
            f"[cyan]文件路径：{private_key_path}[/cyan]",
            expand=False,
        )
    )

    pem_path = Path(private_key_path)
    if not pem_path.exists():
        console.print(
            Panel(
                f"[bold red]✗ 文件不存在: {private_key_path}[/bold red]",
                title="[bold red]错误[/bold red]",
                expand=False,
            )
        )
        Prompt.ask(
            "\n[bold]按 Enter 返回主菜单[/bold]", console=console, show_default=False
        )
        return

    # 验证是否是有效的 RSA 私钥
    try:
        with open(pem_path, "rb") as f:
            serialization.load_pem_private_key(
                f.read(), password=None, backend=default_backend()
            )
        console.print("[bold green]✓ RSA 私钥验证成功[/bold green]")
    except Exception as e:
        console.print(
            Panel(
                f"[bold red]✗ 无效的 RSA 私钥文件: {str(e)}[/bold red]",
                title="[bold red]错误[/bold red]",
                expand=False,
            )
        )
        Prompt.ask(
            "\n[bold]按 Enter 返回主菜单[/bold]", console=console, show_default=False
        )
        return

    # 设置密码
    console.print(
        Panel(
            "[bold cyan]请为该密钥文件设置密码[/bold cyan]",
            title="[bold blue]设置密码[/bold blue]",
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
        Prompt.ask(
            "\n[bold]按 Enter 返回主菜单[/bold]", console=console, show_default=False
        )
        return

    # 加密文件
    console.print("[bold cyan]正在加密文件...[/bold cyan]")
    hex_path = encrypt_pem_file(private_key_path, password)

    if not hex_path:
        Prompt.ask(
            "\n[bold]按 Enter 返回主菜单[/bold]", console=console, show_default=False
        )
        return

    # 备份原文件
    backup_path = str(pem_path) + ".backup"
    shutil.copy(pem_path, backup_path)

    # 删除原文件
    pem_path.unlink()

    # 如果存在公钥文件，也转换为 .hex
    public_key_path = str(pem_path).replace("private_key.pem", "public_key.pem")
    if Path(public_key_path).exists():
        public_hex_path = public_key_path.replace(".pem", ".hex")
        shutil.copy(public_key_path, public_hex_path)
        Path(public_key_path).unlink()
        console.print(f"[cyan]公钥文件已转换: {public_hex_path}[/cyan]")

    # 显示结果
    console.print(
        Panel(
            "[bold green]✓ 密钥文件加密成功[/bold green]",
            title="[bold blue]完成[/bold blue]",
            expand=False,
        )
    )

    table = Table(title="加密结果")
    table.add_column("项目", style="cyan")
    table.add_column("路径", style="green")

    table.add_row("原文件备份", backup_path)
    table.add_row("加密后的文件", hex_path)

    console.print(table)

    console.print(
        Panel(
            "[bold yellow]提示：原 .pem 文件已删除，请妥善保管上述路径中的文件[/bold yellow]",
            expand=False,
        )
    )

    Prompt.ask(
        "\n[bold]按 Enter 返回主菜单[/bold]", console=console, show_default=False
    )


def change_password_operation():
    """修改密码的交互操作"""
    console.clear()
    console.print(
        Panel(
            "[bold cyan]修改密钥密码[/bold cyan]",
            title="[bold blue]密码修改[/bold blue]",
            expand=False,
        )
    )

    # 扫描所有 .hex 文件
    console.print("[bold cyan]扫描密钥文件中...[/bold cyan]")
    _, hex_files = find_all_key_files()

    if not hex_files:
        console.print(
            Panel(
                "[bold yellow]未找到任何 .hex 密钥文件[/bold yellow]",
                expand=False,
            )
        )
        Prompt.ask(
            "\n[bold]按 Enter 返回主菜单[/bold]", console=console, show_default=False
        )
        return

    # 显示所有可用的 .hex 文件
    console.print()
    console.print("[bold cyan]可用的密钥文件：[/bold cyan]")
    table = Table()
    table.add_column("序号", style="yellow")
    table.add_column("文件路径", style="green")
    table.add_column("大小", style="cyan")

    for idx, file_path in enumerate(hex_files, 1):
        file_size = file_path.stat().st_size
        table.add_row(str(idx), str(file_path), f"{file_size} bytes")

    console.print(table)

    # 让用户选择要修改的文件
    console.print()
    valid_choices = [str(i) for i in range(1, len(hex_files) + 1)]
    choice = Prompt.ask(
        "[bold]请选择要修改的密钥文件序号[/bold]",
        choices=valid_choices,
        console=console,
    )

    selected_hex_file = hex_files[int(choice) - 1]

    console.print()
    console.print(
        Panel(
            f"[bold cyan]正在操作密钥文件[/bold cyan]\n"
            f"[cyan]文件路径：{selected_hex_file}[/cyan]",
            expand=False,
        )
    )

    change_key_password(str(selected_hex_file))
    Prompt.ask(
        "\n[bold]按 Enter 返回主菜单[/bold]", console=console, show_default=False
    )


def main():
    """主函数"""
    main_menu()


if __name__ == "__main__":
    main()
