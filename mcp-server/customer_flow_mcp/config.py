from __future__ import annotations

import ipaddress
import os
from dataclasses import dataclass
from pathlib import Path
from urllib.parse import urlsplit, urlunsplit


class ConfigurationError(ValueError):
    """Raised when the shared MCP endpoint would start unsafely."""


def _boolean(name: str, default: bool = False) -> bool:
    raw = os.getenv(name)
    if raw is None:
        return default
    value = raw.strip().casefold()
    if value in {"1", "true", "yes", "on"}:
        return True
    if value in {"0", "false", "no", "off"}:
        return False
    raise ConfigurationError(f"{name} must be true or false.")


def _is_loopback(host: str) -> bool:
    if host.casefold() == "localhost":
        return True
    try:
        return ipaddress.ip_address(host).is_loopback
    except ValueError:
        return False


def _public_base_url(value: str, allow_insecure_http: bool) -> str:
    parsed = urlsplit(value.strip().rstrip("/"))
    if parsed.scheme not in {"http", "https"} or not parsed.hostname:
        raise ConfigurationError("CF_PUBLIC_BASE_URL must be an absolute HTTP(S) URL.")
    if parsed.username or parsed.password or parsed.query or parsed.fragment:
        raise ConfigurationError("CF_PUBLIC_BASE_URL cannot contain credentials, a query or a fragment.")
    if parsed.scheme != "https" and not (_is_loopback(parsed.hostname) and allow_insecure_http):
        raise ConfigurationError(
            "The public MCP URL must use HTTPS; insecure HTTP is permitted only for loopback tests."
        )
    return urlunsplit((parsed.scheme, parsed.netloc, parsed.path.rstrip("/"), "", ""))


def _api_base_url(value: str) -> str:
    parsed = urlsplit(value.strip().rstrip("/"))
    if parsed.scheme not in {"http", "https"} or not parsed.hostname:
        raise ConfigurationError("CF_API_BASE_URL must be an absolute HTTP(S) URL.")
    if parsed.username or parsed.password or parsed.query or parsed.fragment:
        raise ConfigurationError("CF_API_BASE_URL cannot contain credentials, a query or a fragment.")
    if parsed.scheme != "https" and not _is_loopback(parsed.hostname):
        raise ConfigurationError("CF_API_BASE_URL must use HTTPS unless it targets loopback.")
    path = parsed.path.rstrip("/")
    if not path.endswith("/api/v1"):
        raise ConfigurationError("CF_API_BASE_URL must end with /api/v1.")
    return urlunsplit((parsed.scheme, parsed.netloc, path, "", ""))


@dataclass(frozen=True)
class Settings:
    database_path: Path
    media_root: Path
    public_base_url: str
    api_base_url: str = "http://127.0.0.1:8080/api/v1"
    request_timeout_seconds: float = 15.0
    enable_writes: bool = False
    enable_photo_uploads: bool = False
    max_photo_bytes: int = 8 * 1024 * 1024
    host: str = "127.0.0.1"
    port: int = 8091
    streamable_http_path: str = "/mcp"

    @property
    def public_mcp_url(self) -> str:
        return f"{self.public_base_url}{self.streamable_http_path}"

    @classmethod
    def from_env(cls) -> "Settings":
        allow_insecure = _boolean("CF_MCP_ALLOW_INSECURE_HTTP")
        public_base_url = _public_base_url(
            os.getenv("CF_PUBLIC_BASE_URL", "https://flow.drascom.uk"), allow_insecure
        )
        enable_writes = _boolean("CF_MCP_ENABLE_WRITES")
        enable_photo_uploads = _boolean("CF_MCP_ENABLE_PHOTO_UPLOADS")
        if enable_photo_uploads and not enable_writes:
            raise ConfigurationError("Photo uploads require CF_MCP_ENABLE_WRITES=true.")

        host = os.getenv("CF_MCP_HOST", "127.0.0.1").strip()
        if not _is_loopback(host) and not _boolean("CF_MCP_PUBLIC_BIND_ACKNOWLEDGED"):
            raise ConfigurationError(
                "Bind the MCP service to loopback behind the HTTPS reverse proxy, or explicitly acknowledge a public bind."
            )
        try:
            port = int(os.getenv("CF_MCP_PORT", "8091"))
            max_photo_bytes = int(os.getenv("CF_MCP_MAX_PHOTO_BYTES", str(8 * 1024 * 1024)))
            request_timeout_seconds = float(os.getenv("CF_MCP_API_TIMEOUT_SECONDS", "15"))
        except ValueError as exc:
            raise ConfigurationError("MCP port, size and timeout settings must be numeric.") from exc
        if not 1 <= port <= 65535:
            raise ConfigurationError("CF_MCP_PORT must be between 1 and 65535.")
        if not 1 <= max_photo_bytes <= 20 * 1024 * 1024:
            raise ConfigurationError("CF_MCP_MAX_PHOTO_BYTES must be between 1 byte and 20 MB.")
        if not 1 <= request_timeout_seconds <= 60:
            raise ConfigurationError("CF_MCP_API_TIMEOUT_SECONDS must be between 1 and 60 seconds.")
        path = os.getenv("CF_MCP_PATH", "/mcp").strip()
        if not path.startswith("/") or "?" in path or "#" in path or path == "/":
            raise ConfigurationError("CF_MCP_PATH must be a non-root absolute URL path.")

        database_path = Path(os.getenv("CF_DB_PATH", "data/customer-flow.sqlite3")).expanduser().resolve()
        media_root = Path(os.getenv("CF_MEDIA_ROOT", "data/media")).expanduser().resolve()
        return cls(
            database_path=database_path,
            media_root=media_root,
            public_base_url=public_base_url,
            api_base_url=_api_base_url(
                os.getenv("CF_API_BASE_URL", "http://127.0.0.1:8080/api/v1")
            ),
            request_timeout_seconds=request_timeout_seconds,
            enable_writes=enable_writes,
            enable_photo_uploads=enable_photo_uploads,
            max_photo_bytes=max_photo_bytes,
            host=host,
            port=port,
            streamable_http_path=path,
        )
