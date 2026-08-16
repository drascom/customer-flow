from __future__ import annotations

import importlib
import json
import os
import sys
from pathlib import Path
from typing import Any

from .config import Settings
from .api_client import CustomerFlowAPIClient
from .gateway import AgencyGateway, GatewayError


INSTRUCTIONS = """
Customer Flow agency connector. Every request must carry the agency's MCP bearer
token. The token resolves one agency and every tool is evaluated inside that
tenant boundary. Admin, doctor-assignment, delete and cross-agency discovery
operations are deliberately absent. Use a unique idempotency key for each
intended write and reuse it only when retrying the same write.
""".strip()


def _load_database(settings: Settings) -> Any:
    configured = os.getenv("CF_API_MODULE_PATH", "").strip()
    candidates = [Path(configured)] if configured else [
        Path.cwd() / "api",
        Path.cwd().parent / "api",
        Path(__file__).resolve().parents[2] / "api",
    ]
    module_path = next((path.resolve() for path in candidates if (path / "app.py").is_file()), None)
    if module_path is None:
        raise RuntimeError("Customer Flow API module not found; set CF_API_MODULE_PATH to the api directory.")
    if str(module_path) not in sys.path:
        sys.path.insert(0, str(module_path))
    app = importlib.import_module("app")
    database = app.Database(settings.database_path, settings.media_root)
    database.initialize(seed=False)
    return database


class AgencyTokenVerifier:
    """Official MCP SDK token verifier backed by one-way agency token hashes."""

    def __init__(self, database: Any, resource_url: str):
        self.database = database
        self.resource_url = resource_url

    async def verify_token(self, token: str) -> Any | None:
        from mcp.server.auth.provider import AccessToken

        try:
            principal = self.database.authenticate_mcp_token(token)
        except Exception:
            return None
        return AccessToken(
            token=token,
            client_id=f"agency:{principal['agencyID']}",
            scopes=["customer-flow:agency"],
            resource=self.resource_url,
            subject=principal["serviceUserID"],
            claims={
                "agency_id": principal["agencyID"],
                "agency_name": principal["agencyName"],
                "service_user_id": principal["serviceUserID"],
                "rotated_at": principal["rotatedAt"],
            },
        )


def build_server(settings: Settings | None = None, database: Any | None = None) -> Any:
    try:
        from mcp.server.auth.middleware.auth_context import get_access_token
        from mcp.server.auth.settings import AuthSettings
        from mcp.server.fastmcp import FastMCP
    except ModuleNotFoundError as exc:  # pragma: no cover - deployment configuration
        raise RuntimeError("Install the MCP server dependencies before starting the gateway.") from exc

    settings = settings or Settings.from_env()
    database = database or _load_database(settings)
    verifier = AgencyTokenVerifier(database, settings.public_mcp_url)
    mcp = FastMCP(
        "Customer Flow Agency",
        instructions=INSTRUCTIONS,
        host=settings.host,
        port=settings.port,
        streamable_http_path=settings.streamable_http_path,
        json_response=True,
        stateless_http=True,
        token_verifier=verifier,
        auth=AuthSettings(
            issuer_url=settings.public_base_url,
            resource_server_url=settings.public_mcp_url,
            required_scopes=["customer-flow:agency"],
        ),
        max_request_body_size=(
            max(1024 * 1024, ((settings.max_photo_bytes + 2) // 3) * 4 + 256 * 1024)
            if settings.enable_photo_uploads else 1024 * 1024
        ),
    )

    def gateway() -> AgencyGateway:
        access = get_access_token()
        if access is None or not access.subject:
            raise GatewayError("An authenticated agency bearer token is required.")
        claims = access.claims or {}
        agency_id = str(claims.get("agency_id", ""))
        service_user_id = str(claims.get("service_user_id", ""))
        if not agency_id or access.subject != service_user_id:
            raise GatewayError("The authenticated agency principal is invalid.")
        return AgencyGateway(
            settings,
            CustomerFlowAPIClient(settings, access.token),
        )

    @mcp.resource("customer-flow://policy", mime_type="application/json")
    def policy_resource() -> str:
        """Security and data-handling policy for the authenticated agency."""
        return json.dumps(gateway().policy(), ensure_ascii=False)

    @mcp.resource("customer-flow://me", mime_type="application/json")
    def identity_resource() -> str:
        """The non-secret agency identity resolved from this request's token."""
        return json.dumps(gateway().who_am_i(), ensure_ascii=False)

    @mcp.tool(name="who_am_i")
    def who_am_i() -> dict[str, Any]:
        """Confirm the agency service account and capabilities; returns no secret."""
        return gateway().who_am_i()

    @mcp.tool(name="list_cases")
    def list_cases(
        status: str = "all", search: str = "", updated_after: str | None = None, limit: int = 50,
    ) -> dict[str, Any]:
        """List confidential case summaries belonging only to the authenticated agency."""
        return gateway().list_cases(status, search, updated_after, limit)

    @mcp.tool(name="get_case")
    def get_case(case_reference: str) -> dict[str, Any]:
        """Get one confidential agency case by public HT reference; internal IDs are omitted."""
        return gateway().get_case(case_reference)

    if settings.enable_writes:
        @mcp.tool(name="create_case")
        def create_case(
            patient_name: str, estimated_grafts: str, estimated_price_gbp: str,
            consultation_note: str, idempotency_key: str,
            previous_case_reference: str | None = None,
            duplicate_confirmed_different: bool = False,
            date_of_birth: str | None = None, age: int | None = None,
            gender: str | None = None, phone: str | None = None,
            email: str | None = None, address: str | None = None,
            occupation: str | None = None, patient_note: str | None = None,
        ) -> dict[str, Any]:
            """Create a case owned by this agency's managed MCP account; safely retryable."""
            return gateway().create_case(
                patient_name, estimated_grafts, estimated_price_gbp, consultation_note,
                idempotency_key, previous_case_reference, duplicate_confirmed_different,
                date_of_birth, age, gender, phone, email, address, occupation, patient_note,
            )

        @mcp.tool(name="add_case_message")
        def add_case_message(case_reference: str, text: str, idempotency_key: str) -> dict[str, Any]:
            """Add a message to an MCP-owned agency case, safely retryable with the same key."""
            return gateway().add_case_message(case_reference, text, idempotency_key)

    if settings.enable_photo_uploads:
        @mcp.tool(name="upload_case_photo")
        def upload_case_photo(
            case_reference: str, media_type: str, photo_base64: str, idempotency_key: str,
        ) -> dict[str, Any]:
            """Upload one validated photo to an MCP-owned agency case; disabled by default."""
            return gateway().upload_case_photo(case_reference, media_type, photo_base64, idempotency_key)

    return mcp


def main() -> None:
    server = build_server()
    server.run(transport="streamable-http")


if __name__ == "__main__":
    main()
