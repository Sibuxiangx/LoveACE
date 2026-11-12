"""iOS TestFlight 更新提示的独立 manifest。

与 manifest_v2.json 完全分开：旧版客户端不读取它，因此新字段不会影响 manifest_v2 的解码。
发布内容来自检入仓库的 ios_testflight.json，内容不变时不写入。
"""

from __future__ import annotations

import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path

from pydantic import BaseModel, Field, field_validator

from s3_client import S3Client

IOS_TESTFLIGHT_KEY = "loveace/manifest_v2_ios_testflight.json"
SOURCE_FILE = Path(__file__).parent / "ios_testflight.json"
SCHEMA_VERSION = 1
TESTFLIGHT_PREFIX = "https://testflight.apple.com/join/"


class IosTestFlightSource(BaseModel):
    """检入仓库的更新提示配置，是唯一的编辑入口"""

    enabled: bool
    version: str = Field(min_length=1)
    build: int = Field(ge=1)
    testflight_url: str
    title: str = Field(min_length=1, max_length=60)
    changelog: str = Field(min_length=1, max_length=1000)

    @field_validator("testflight_url")
    @classmethod
    def _check_testflight_url(cls, value: str) -> str:
        if not value.startswith(TESTFLIGHT_PREFIX) or len(value) == len(TESTFLIGHT_PREFIX):
            raise ValueError(f"testflight_url must be {TESTFLIGHT_PREFIX}<code>")
        return value


def _utc_now() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def load_source(path: Path = SOURCE_FILE) -> IosTestFlightSource:
    return IosTestFlightSource.model_validate_json(path.read_text("utf-8"))


def build_document(source: IosTestFlightSource, *, updated_at: str) -> dict:
    body = {
        "schema_version": SCHEMA_VERSION,
        "enabled": source.enabled,
        "version": source.version,
        "build": source.build,
        "testflight_url": source.testflight_url,
        "title": source.title,
        "changelog": source.changelog,
    }
    # revision 只由内容决定，updated_at 不参与，内容不变时重复发布结果一致
    canonical = json.dumps(body, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    revision = hashlib.sha256(canonical.encode("utf-8")).hexdigest()
    return {**body, "revision": revision, "updated_at": updated_at}


def publish(client: S3Client, path: Path = SOURCE_FILE, *, dry_run: bool = False) -> tuple[str, dict]:
    """发布更新提示。返回 (状态, 文档)，状态为 unchanged / published / dry-run。"""
    source = load_source(path)
    candidate = build_document(source, updated_at="")

    existing = client.get_json(IOS_TESTFLIGHT_KEY, missing_ok=True)
    if existing is not None and existing.get("revision") == candidate["revision"]:
        return "unchanged", existing

    document = build_document(source, updated_at=_utc_now())
    if dry_run:
        return "dry-run", document

    client.upload_content(json.dumps(document, ensure_ascii=False, indent=2), IOS_TESTFLIGHT_KEY)
    return "published", document
