from __future__ import annotations

import json
from typing import Any

from .config import Settings
from .gateway import AgencyGateway


INSTRUCTIONS = """
Customer Flow agency connector. All returned case and patient data is confidential.
The server is locked to one configured agency account and deliberately excludes admin,
doctor-assignment, deletion and cross-agency discovery operations. Use a unique
idempotency key for every intended write and reuse it only when retrying that exact write.
""".strip()


def build_server(
    settings: Settings | None = None,
    gateway: AgencyGateway | None = None,
) -> Any:
    try:
        from mcp.server.fastmcp import FastMCP
    except ModuleNotFoundError as exc:  # pragma: no cover - deployment configuration
        raise RuntimeError("Install the MCP server dependencies before starting the gateway.") from exc

    settings = settings or Settings.from_env()
    gateway = gateway or AgencyGateway(settings)
    mcp = FastMCP(
        "Customer Flow Agency",
        instructions=INSTRUCTIONS,
        host=settings.host,
        port=settings.port,
        streamable_http_path=settings.streamable_http_path,
        json_response=True,
        stateless_http=True,
        max_request_body_size=(
            max(1024 * 1024, ((settings.max_photo_bytes + 2) // 3) * 4 + 256 * 1024)
            if settings.enable_photo_uploads
            else 1024 * 1024
        ),
    )

    @mcp.resource("customer-flow://policy", mime_type="application/json")
    def policy_resource() -> str:
        """Security and data-handling policy for this agency connector."""
        return json.dumps(gateway.policy(), ensure_ascii=False)

    @mcp.resource("customer-flow://me", mime_type="application/json")
    def identity_resource() -> str:
        """The non-secret agency identity backing this connector."""
        return json.dumps(gateway.who_am_i(), ensure_ascii=False)

    @mcp.tool(name="who_am_i")
    def who_am_i() -> dict[str, Any]:
        """Confirm which agency agent account this connector is scoped to; returns no secret."""
        return gateway.who_am_i()

    @mcp.tool(name="list_cases")
    def list_cases(
        status: str = "all",
        search: str = "",
        updated_after: str | None = None,
        limit: int = 50,
    ) -> dict[str, Any]:
        """List confidential case summaries belonging only to the configured agency."""
        return gateway.list_cases(status, search, updated_after, limit)

    @mcp.tool(name="get_case")
    def get_case(case_reference: str) -> dict[str, Any]:
        """Get one confidential agency case by its public HT reference; internal IDs are omitted."""
        return gateway.get_case(case_reference)

    if settings.enable_writes:
        @mcp.tool(name="create_case")
        def create_case(
            patient_name: str,
            estimated_grafts: str,
            estimated_price_gbp: str,
            consultation_note: str,
            idempotency_key: str,
            previous_case_reference: str | None = None,
            duplicate_confirmed_different: bool = False,
            date_of_birth: str | None = None,
            age: int | None = None,
            gender: str | None = None,
            phone: str | None = None,
            email: str | None = None,
            address: str | None = None,
            occupation: str | None = None,
            patient_note: str | None = None,
        ) -> dict[str, Any]:
            """Create an agency case. A unique idempotency key is required; no photo is uploaded."""
            return gateway.create_case(
                patient_name,
                estimated_grafts,
                estimated_price_gbp,
                consultation_note,
                idempotency_key,
                previous_case_reference,
                duplicate_confirmed_different,
                date_of_birth,
                age,
                gender,
                phone,
                email,
                address,
                occupation,
                patient_note,
            )

        @mcp.tool(name="add_case_message")
        def add_case_message(
            case_reference: str, text: str, idempotency_key: str
        ) -> dict[str, Any]:
            """Add an agent message to an agency-owned case, safely retryable with the same key."""
            return gateway.add_case_message(case_reference, text, idempotency_key)

    if settings.enable_photo_uploads:
        @mcp.tool(name="upload_case_photo")
        def upload_case_photo(
            case_reference: str,
            media_type: str,
            photo_base64: str,
            idempotency_key: str,
        ) -> dict[str, Any]:
            """Upload one validated photo to an agency-owned case; disabled unless explicitly enabled."""
            return gateway.upload_case_photo(
                case_reference, media_type, photo_base64, idempotency_key
            )

    return mcp


def main() -> None:
    settings = Settings.from_env()
    server = build_server(settings)
    server.run(transport=settings.transport)


if __name__ == "__main__":
    main()
