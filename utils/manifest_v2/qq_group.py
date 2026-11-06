"""独立的 QQ 群 manifest。

与 manifest_v2 完全分离：独立对象、独立源文件、独立发布命令，不被主 manifest 引用。
只有认识该路径的客户端（新版本）会请求它，旧版本客户端不会读取。
"""

from __future__ import annotations

import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Literal
from urllib.parse import urlsplit

from pydantic import BaseModel, ConfigDict, Field, field_validator

from s3_client import CANONICAL_CDN_BASE_URL, S3Client

QQ_GROUP_KEY = "loveace/qq_group_v1.json"
QQ_GROUP_ASSET_PREFIX = "loveace/assets/qq-group"
SOURCE_DIR = Path(__file__).parent / "qq_group"
SOURCE_FILE = "group.json"
IMAGE_FILE = "qrcode.png"
IMAGE_SUFFIXES = {".png", ".jpg", ".jpeg", ".webp"}
SCHEMA_VERSION = 1
# 不参与内容指纹的字段：内容相同则 revision 相同，发布可以幂等跳过
VOLATILE_FIELDS = {"revision", "updated_at"}


class QqGroupSource(BaseModel):
    """检入仓库的群配置，是唯一的编辑入口"""

    model_config = ConfigDict(extra="forbid")

    enabled: bool = True
    title: str = Field(min_length=1, max_length=40)
    group_number: str = Field(pattern=r"^\d{5,12}$")
    share_url: str

    @field_validator("share_url")
    @classmethod
    def validate_share_url(cls, value: str) -> str:
        parsed = urlsplit(value)
        if parsed.scheme != "https" or parsed.netloc != "qm.qq.com":
            raise ValueError("share_url must be an https://qm.qq.com link")
        return value


class QqGroupDocument(BaseModel):
    """发布到 S3 的公开文档，客户端只读"""

    model_config = ConfigDict(extra="forbid")

    schema_version: Literal[1]
    revision: str
    updated_at: str
    enabled: bool
    title: str
    group_number: str
    share_url: str
    qr_image_url: str


def _utc_now() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def _canonical(data: dict) -> str:
    return json.dumps(data, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def _fingerprint(data: dict) -> str:
    body = {key: value for key, value in data.items() if key not in VOLATILE_FIELDS}
    return hashlib.sha256(_canonical(body).encode("utf-8")).hexdigest()


def load_source(directory: Path = SOURCE_DIR) -> tuple[QqGroupSource, Path]:
    source = QqGroupSource.model_validate_json((directory / SOURCE_FILE).read_text("utf-8"))
    image = directory / IMAGE_FILE
    if not image.is_file():
        raise FileNotFoundError(f"qr image not found: {image}")
    if image.suffix.lower() not in IMAGE_SUFFIXES:
        raise ValueError(f"unsupported qr image type: {image.suffix}")
    return source, image


def image_object_key(image: Path) -> str:
    """按内容寻址：图片变化才产生新 URL，旧对象不被覆盖，CDN 缓存不会串内容"""
    digest = hashlib.sha256(image.read_bytes()).hexdigest()[:12]
    return f"{QQ_GROUP_ASSET_PREFIX}-{digest}{image.suffix.lower()}"


def build_document(source: QqGroupSource, qr_image_url: str, *, updated_at: str) -> dict:
    body = {
        "schema_version": SCHEMA_VERSION,
        "enabled": source.enabled,
        "title": source.title,
        "group_number": source.group_number,
        "share_url": source.share_url,
        "qr_image_url": qr_image_url,
    }
    document = {**body, "revision": _fingerprint(body), "updated_at": updated_at}
    return QqGroupDocument.model_validate(document).model_dump()


def publish(client: S3Client, directory: Path = SOURCE_DIR, *, dry_run: bool = False) -> tuple[str, dict]:
    """发布群 manifest。内容未变时不写入，重复执行结果一致。

    返回 (状态, 文档)，状态为 unchanged / published / dry-run。
    """
    source, image = load_source(directory)
    image_key = image_object_key(image)
    qr_image_url = f"{CANONICAL_CDN_BASE_URL}/{image_key}"
    candidate = build_document(source, qr_image_url, updated_at="")

    existing = client.get_json(QQ_GROUP_KEY, missing_ok=True)
    if (
        existing is not None
        and existing.get("revision") == candidate["revision"]
        and client.exists(image_key)
    ):
        return "unchanged", existing

    if not dry_run and not client.exists(image_key):
        client.upload_file(str(image), image_key)

    document = build_document(source, qr_image_url, updated_at=_utc_now())
    if dry_run:
        return "dry-run", document

    client.upload_content(json.dumps(document, ensure_ascii=False, indent=2), QQ_GROUP_KEY)
    return "published", document
