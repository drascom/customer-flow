from __future__ import annotations

import json
from dataclasses import dataclass
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.parse import quote
from urllib.request import Request, urlopen

from .config import Settings


@dataclass(frozen=True)
class CustomerFlowAPIError(RuntimeError):
    status: int
    code: str
    message: str

    def __str__(self) -> str:
        return f"{self.code}: {self.message}"


class CustomerFlowAPIClient:
    """Narrow API adapter authenticated by one request's agency MCP token."""

    def __init__(self, settings: Settings, token: str):
        if not token.startswith("cfmcp_"):
            raise CustomerFlowAPIError(401, "invalid_mcp_token", "An agency MCP token is required.")
        self.settings = settings
        self._token = token

    def _request(
        self,
        method: str,
        path: str,
        *,
        payload: dict[str, Any] | None = None,
        body: bytes | None = None,
        content_type: str = "application/json",
        idempotency_key: str | None = None,
    ) -> dict[str, Any]:
        if payload is not None and body is not None:
            raise ValueError("Use payload or body, not both.")
        request_body = body
        if payload is not None:
            request_body = json.dumps(payload, separators=(",", ":"), ensure_ascii=False).encode()
        headers = {
            "Accept": "application/json",
            "Authorization": f"Bearer {self._token}",
        }
        if request_body is not None:
            headers["Content-Type"] = content_type
        if idempotency_key:
            headers["Idempotency-Key"] = idempotency_key
        request = Request(
            self.settings.api_base_url + path,
            data=request_body,
            headers=headers,
            method=method,
        )
        try:
            with urlopen(request, timeout=self.settings.request_timeout_seconds) as response:
                value = json.load(response)
                if not isinstance(value, dict):
                    raise CustomerFlowAPIError(
                        502, "invalid_api_response", "Customer Flow returned invalid JSON."
                    )
                return value
        except HTTPError as exc:
            try:
                error_body = json.load(exc)
            except (json.JSONDecodeError, UnicodeDecodeError):
                error_body = {}
            error = error_body.get("error", {}) if isinstance(error_body, dict) else {}
            raise CustomerFlowAPIError(
                exc.code,
                str(error.get("code") or "api_error"),
                str(error.get("message") or "Customer Flow rejected the request."),
            ) from None
        except URLError as exc:
            raise CustomerFlowAPIError(
                503, "api_unavailable", "Customer Flow API is unavailable."
            ) from exc

    def me(self) -> dict[str, Any]:
        return self._request("GET", "/auth/me").get("user", {})

    def list_cases(self) -> list[dict[str, Any]]:
        cases = self._request("GET", "/cases").get("cases", [])
        if not isinstance(cases, list):
            raise CustomerFlowAPIError(
                502, "invalid_api_response", "Customer Flow returned an invalid case list."
            )
        return [item for item in cases if isinstance(item, dict)]

    def get_case(self, case_id: str) -> dict[str, Any]:
        return self._request("GET", f"/cases/{quote(case_id, safe='')}").get("case", {})

    def create_case(self, payload: dict[str, Any], idempotency_key: str) -> dict[str, Any]:
        return self._request(
            "POST", "/cases", payload=payload, idempotency_key=idempotency_key
        ).get("case", {})

    def add_agent_update(
        self, case_id: str, text: str, idempotency_key: str
    ) -> dict[str, Any]:
        return self._request(
            "POST",
            f"/cases/{quote(case_id, safe='')}/agent-updates",
            payload={"text": text},
            idempotency_key=idempotency_key,
        ).get("case", {})

    def upload_case_photo(
        self,
        case_id: str,
        body: bytes,
        media_type: str,
        idempotency_key: str,
    ) -> dict[str, Any]:
        return self._request(
            "POST",
            f"/cases/{quote(case_id, safe='')}/photos",
            body=body,
            content_type=media_type,
            idempotency_key=idempotency_key,
        ).get("case", {})
