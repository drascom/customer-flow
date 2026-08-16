from __future__ import annotations

import ipaddress
import os
from dataclasses import dataclass
from urllib.parse import urlsplit, urlunsplit


class ConfigurationError(ValueError):
    """Raised when the gateway would start with an unsafe configuration."""


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


def _api_base_url(value: str, allow_insecure_http: bool) -> str:
    parsed = urlsplit(value.strip().rstrip("/"))
    if parsed.scheme not in {"http", "https"} or not parsed.hostname:
        raise ConfigurationError("CF_MCP_API_BASE_URL must be an absolute HTTP(S) URL.")
    if parsed.username or parsed.password or parsed.query or parsed.fragment:
        raise ConfigurationError("CF_MCP_API_BASE_URL cannot contain credentials, a query or a fragment.")
    if parsed.scheme != "https" and not (_is_loopback(parsed.hostname) and allow_insecure_http):
        raise ConfigurationError(
            "Customer Flow API must use HTTPS. Set CF_MCP_ALLOW_INSECURE_HTTP=true only for a loopback test API."
        )
    path = parsed.path.rstrip("/")
    if not path.endswith("/api/v1"):
        path += "/api/v1"
    return urlunsplit((parsed.scheme, parsed.netloc, path, "", ""))


@dataclass(frozen=True)
class Settings:
    api_base_url: str
    api_token: str | None
    api_username: str | None
    api_password: str | None
    enable_writes: bool = False
    enable_photo_uploads: bool = False
    max_photo_bytes: int = 8 * 1024 * 1024
    request_timeout_seconds: float = 20.0
    transport: str = "stdio"
    host: str = "127.0.0.1"
    port: int = 8091
    streamable_http_path: str = "/mcp"

    @classmethod
    def from_env(cls) -> "Settings":
        allow_insecure = _boolean("CF_MCP_ALLOW_INSECURE_HTTP")
        api_base_url = _api_base_url(
            os.getenv("CF_MCP_API_BASE_URL", "https://flow.drascom.uk"), allow_insecure
        )
        api_token = os.getenv("CF_MCP_API_TOKEN", "").strip() or None
        api_username = os.getenv("CF_MCP_API_USERNAME", "").strip() or None
        api_password = os.getenv("CF_MCP_API_PASSWORD", "") or None
        if not api_token and not (api_username and api_password):
            raise ConfigurationError(
                "Set CF_MCP_API_TOKEN or both CF_MCP_API_USERNAME and CF_MCP_API_PASSWORD."
            )

        enable_writes = _boolean("CF_MCP_ENABLE_WRITES")
        enable_photo_uploads = _boolean("CF_MCP_ENABLE_PHOTO_UPLOADS")
        if enable_photo_uploads and not enable_writes:
            raise ConfigurationError("Photo uploads require CF_MCP_ENABLE_WRITES=true.")

        transport = os.getenv("CF_MCP_TRANSPORT", "stdio").strip().casefold()
        if transport not in {"stdio", "streamable-http"}:
            raise ConfigurationError("CF_MCP_TRANSPORT must be stdio or streamable-http.")
        host = os.getenv("CF_MCP_HOST", "127.0.0.1").strip()
        if transport == "streamable-http" and not _is_loopback(host):
            if not _boolean("CF_MCP_PUBLIC_BIND_ACKNOWLEDGED"):
                raise ConfigurationError(
                    "Public MCP binding is disabled. Bind to loopback behind an authenticated reverse proxy, "
                    "or explicitly set CF_MCP_PUBLIC_BIND_ACKNOWLEDGED=true."
                )

        try:
            port = int(os.getenv("CF_MCP_PORT", "8091"))
            max_photo_bytes = int(os.getenv("CF_MCP_MAX_PHOTO_BYTES", str(8 * 1024 * 1024)))
            timeout = float(os.getenv("CF_MCP_REQUEST_TIMEOUT_SECONDS", "20"))
        except ValueError as exc:
            raise ConfigurationError("MCP port, size and timeout settings must be numeric.") from exc
        if not 1 <= port <= 65535:
            raise ConfigurationError("CF_MCP_PORT must be between 1 and 65535.")
        if not 1 <= max_photo_bytes <= 20 * 1024 * 1024:
            raise ConfigurationError("CF_MCP_MAX_PHOTO_BYTES must be between 1 byte and 20 MB.")
        if not 1 <= timeout <= 120:
            raise ConfigurationError("CF_MCP_REQUEST_TIMEOUT_SECONDS must be between 1 and 120.")

        path = os.getenv("CF_MCP_PATH", "/mcp").strip()
        if not path.startswith("/") or "?" in path or "#" in path:
            raise ConfigurationError("CF_MCP_PATH must be an absolute URL path.")
        return cls(
            api_base_url=api_base_url,
            api_token=api_token,
            api_username=api_username,
            api_password=api_password,
            enable_writes=enable_writes,
            enable_photo_uploads=enable_photo_uploads,
            max_photo_bytes=max_photo_bytes,
            request_timeout_seconds=timeout,
            transport=transport,
            host=host,
            port=port,
            streamable_http_path=path,
        )
