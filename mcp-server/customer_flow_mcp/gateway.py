from __future__ import annotations

import base64
import binascii
import re
from datetime import datetime
from typing import Any

from .config import Settings
from .api_client import CustomerFlowAPIError


CASE_REFERENCE = re.compile(r"^HT-[0-9]{4,12}$", re.IGNORECASE)
IDEMPOTENCY_KEY = re.compile(r"^[A-Za-z0-9._:-]{8,128}$")
STATUSES = {"waiting", "answered", "closed"}
GENDERS = {"male", "female", "non_binary", "other", "prefer_not_to_say"}
MEDIA_TYPES = {"image/jpeg", "image/png", "image/heic"}


class GatewayError(RuntimeError):
    pass


class AgencyGateway:
    """Policy boundary between an MCP client and the Customer Flow API."""

    def __init__(
        self,
        settings: Settings,
        client: Any | None = None,
        principal: dict[str, Any] | None = None,
    ):
        self.settings = settings
        if client is None:
            raise GatewayError("An authenticated agency data client is required.")
        self.client = client
        self.principal = principal

    def _principal(self) -> dict[str, Any]:
        if self.principal is not None:
            user = self.principal
        else:
            try:
                user = self.client.me()
            except CustomerFlowAPIError as exc:
                raise GatewayError(str(exc)) from None
        if user.get("role") != "agent" or not user.get("agencyID"):
            raise GatewayError(
                "MCP credentials must belong to an active agent account assigned to exactly one agency."
            )
        return user

    @staticmethod
    def _idempotency_key(value: str) -> str:
        key = value.strip()
        if not IDEMPOTENCY_KEY.fullmatch(key):
            raise GatewayError(
                "idempotency_key must be 8-128 characters using letters, numbers, '.', '_', ':' or '-'."
            )
        return key

    @staticmethod
    def _reference(value: str) -> str:
        reference = value.strip().upper()
        if not CASE_REFERENCE.fullmatch(reference):
            raise GatewayError("case_reference must look like HT-240910.")
        return reference

    def who_am_i(self) -> dict[str, Any]:
        user = self._principal()
        return {
            "account": user.get("displayName"),
            "username": user.get("username"),
            "agency_id": user.get("agencyID"),
            "role": "agent",
            "writes_enabled": self.settings.enable_writes,
            "photo_uploads_enabled": self.settings.enable_photo_uploads,
        }

    def _cases(self) -> list[dict[str, Any]]:
        self._principal()
        try:
            return self.client.list_cases()
        except CustomerFlowAPIError as exc:
            raise GatewayError(str(exc)) from None

    def _resolve(self, case_reference: str) -> dict[str, Any]:
        reference = self._reference(case_reference)
        item = next((case for case in self._cases() if case.get("reference") == reference), None)
        if item is None:
            raise GatewayError("The case was not found in this agency.")
        case_id = str(item.get("id", ""))
        if not case_id:
            raise GatewayError("Customer Flow returned an invalid case record.")
        try:
            detail = self.client.get_case(case_id)
        except CustomerFlowAPIError as exc:
            raise GatewayError(str(exc)) from None
        if detail.get("reference") != reference:
            raise GatewayError("Customer Flow returned an inconsistent case record.")
        return detail

    @staticmethod
    def _message_summary(message: dict[str, Any]) -> dict[str, Any]:
        return {
            "author": message.get("author"),
            "role": message.get("role"),
            "created_at": message.get("createdAt"),
            "text": message.get("text"),
            "has_photo": bool(message.get("attachmentPhotoID")),
            "approximate_grafts": message.get("approximateGrafts"),
            "recommended_price": message.get("recommendedPrice"),
        }

    @classmethod
    def _case_summary(cls, case: dict[str, Any]) -> dict[str, Any]:
        messages = case.get("messages") if isinstance(case.get("messages"), list) else []
        latest = messages[-1] if messages and isinstance(messages[-1], dict) else None
        patient = case.get("patient") if isinstance(case.get("patient"), dict) else {}
        return {
            "case_reference": case.get("reference"),
            "patient_name": patient.get("name"),
            "status": case.get("status"),
            "submitted_by": case.get("agentName"),
            "uploaded_at": case.get("uploadedAt"),
            "photo_count": case.get("photoCount"),
            "estimated_grafts": case.get("agentGrafts"),
            "estimated_price": case.get("agentPrice"),
            "currency": case.get("currency"),
            "latest_message": cls._message_summary(latest) if latest else None,
        }

    @classmethod
    def _case_detail(cls, case: dict[str, Any]) -> dict[str, Any]:
        summary = cls._case_summary(case)
        patient = case.get("patient") if isinstance(case.get("patient"), dict) else {}
        messages = case.get("messages") if isinstance(case.get("messages"), list) else []
        summary.update({
            "data_classification": "confidential_patient_data",
            "patient": {
                "name": patient.get("name"),
                "date_of_birth": patient.get("dateOfBirth"),
                "stated_age": patient.get("statedAge"),
                "age": patient.get("age"),
                "gender": patient.get("gender"),
                "phone": patient.get("phone"),
                "email": patient.get("email"),
                "address": patient.get("address"),
                "occupation": patient.get("occupation"),
                "profile_note": patient.get("profileNote"),
            },
            "consultation_note": case.get("agentNote"),
            "final_grafts": case.get("finalGrafts"),
            "final_price": case.get("finalPrice"),
            "finalized_at": case.get("finalizedAt"),
            "messages": [
                cls._message_summary(message)
                for message in messages
                if isinstance(message, dict)
            ],
        })
        return summary

    def list_cases(
        self,
        status: str = "all",
        search: str = "",
        updated_after: str | None = None,
        limit: int = 50,
    ) -> dict[str, Any]:
        normalized_status = status.strip().casefold()
        if normalized_status != "all" and normalized_status not in STATUSES:
            raise GatewayError("status must be all, waiting, answered or closed.")
        if not 1 <= limit <= 100:
            raise GatewayError("limit must be between 1 and 100.")
        after = None
        if updated_after:
            try:
                after = datetime.fromisoformat(updated_after.replace("Z", "+00:00"))
            except ValueError as exc:
                raise GatewayError("updated_after must be an ISO 8601 timestamp.") from exc
            if after.tzinfo is None or after.utcoffset() is None:
                raise GatewayError("updated_after must include a timezone, such as Z or +00:00.")
        needle = search.strip().casefold()
        matches = []
        for case in reversed(self._cases()):
            if normalized_status != "all" and case.get("status") != normalized_status:
                continue
            patient = case.get("patient") if isinstance(case.get("patient"), dict) else {}
            if needle and needle not in f"{case.get('reference', '')} {patient.get('name', '')}".casefold():
                continue
            if after:
                raw_timestamp = str(patient.get("lastUpdated") or case.get("uploadedAt") or "")
                try:
                    timestamp = datetime.fromisoformat(raw_timestamp.replace("Z", "+00:00"))
                except ValueError:
                    continue
                if timestamp.tzinfo is None or timestamp.utcoffset() is None:
                    continue
                if timestamp <= after:
                    continue
            matches.append(self._case_summary(case))
        total = len(matches)
        return {
            "data_classification": "confidential_patient_data",
            "count": min(total, limit),
            "truncated": total > limit,
            "cases": matches[:limit],
        }

    def get_case(self, case_reference: str) -> dict[str, Any]:
        return self._case_detail(self._resolve(case_reference))

    def _require_writes(self) -> None:
        if not self.settings.enable_writes:
            raise GatewayError("Write tools are disabled for this MCP deployment.")

    @staticmethod
    def _bounded(value: str | None, name: str, limit: int, required: bool = False) -> str | None:
        result = value.strip() if value is not None else ""
        if required and not result:
            raise GatewayError(f"{name} is required.")
        if len(result) > limit:
            raise GatewayError(f"{name} must be at most {limit} characters.")
        return result or None

    def create_case(
        self,
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
        self._require_writes()
        self._principal()
        key = self._idempotency_key(idempotency_key)
        name = self._bounded(patient_name, "patient_name", 160, required=True)
        if name is None or len(name.split()) < 2:
            raise GatewayError("patient_name must include at least a first name and surname.")
        grafts = self._bounded(estimated_grafts, "estimated_grafts", 32, required=True)
        price = self._bounded(estimated_price_gbp.lstrip("£"), "estimated_price_gbp", 32, required=True)
        note = self._bounded(consultation_note, "consultation_note", 4000, required=True)
        if age is not None and not 0 <= age <= 130:
            raise GatewayError("age must be between 0 and 130.")
        normalized_gender = gender.strip().casefold() if gender else None
        if normalized_gender and normalized_gender not in GENDERS:
            raise GatewayError("gender is not a supported value.")
        profile = {
            "dateOfBirth": self._bounded(date_of_birth, "date_of_birth", 10),
            "age": age,
            "gender": normalized_gender,
            "phone": self._bounded(phone, "phone", 40),
            "email": self._bounded(email, "email", 254),
            "address": self._bounded(address, "address", 500),
            "occupation": self._bounded(occupation, "occupation", 120),
            "profileNote": self._bounded(patient_note, "patient_note", 1000),
        }
        payload: dict[str, Any] = {
            "patientName": name,
            "grafts": grafts,
            "currency": "GBP",
            "price": price,
            "note": note,
            "photoCount": 0,
            "patientProfile": profile,
            "duplicateConfirmedDifferent": duplicate_confirmed_different,
        }
        if previous_case_reference:
            previous = self._resolve(previous_case_reference)
            patient = previous.get("patient") if isinstance(previous.get("patient"), dict) else {}
            patient_id = patient.get("id")
            if not patient_id:
                raise GatewayError("The previous case does not contain a reusable patient record.")
            payload["existingPatientID"] = patient_id
        try:
            created = self.client.create_case(payload, key)
        except CustomerFlowAPIError as exc:
            raise GatewayError(str(exc)) from None
        return self._case_detail(created)

    def add_case_message(
        self, case_reference: str, text: str, idempotency_key: str
    ) -> dict[str, Any]:
        self._require_writes()
        key = self._idempotency_key(idempotency_key)
        message = self._bounded(text, "text", 4000, required=True)
        case = self._resolve(case_reference)
        try:
            updated = self.client.add_agent_update(str(case["id"]), str(message), key)
        except CustomerFlowAPIError as exc:
            raise GatewayError(str(exc)) from None
        return self._case_detail(updated)

    @staticmethod
    def _valid_image_signature(body: bytes, media_type: str) -> bool:
        if media_type == "image/jpeg":
            return body.startswith(b"\xff\xd8\xff")
        if media_type == "image/png":
            return body.startswith(b"\x89PNG\r\n\x1a\n")
        return len(body) >= 12 and body[4:12] in {
            b"ftypheic", b"ftypheix", b"ftyphevc", b"ftyphevx", b"ftypmif1"
        }

    def upload_case_photo(
        self,
        case_reference: str,
        media_type: str,
        photo_base64: str,
        idempotency_key: str,
    ) -> dict[str, Any]:
        self._require_writes()
        if not self.settings.enable_photo_uploads:
            raise GatewayError("Photo upload is disabled for this MCP deployment.")
        key = self._idempotency_key(idempotency_key)
        normalized_type = media_type.strip().casefold()
        if normalized_type not in MEDIA_TYPES:
            raise GatewayError("media_type must be image/jpeg, image/png or image/heic.")
        if len(photo_base64) > ((self.settings.max_photo_bytes + 2) // 3) * 4 + 4:
            raise GatewayError("The encoded photo exceeds this deployment's size limit.")
        try:
            body = base64.b64decode(photo_base64, validate=True)
        except (binascii.Error, ValueError) as exc:
            raise GatewayError("photo_base64 must contain valid base64 without a data-URL prefix.") from exc
        if not body or len(body) > self.settings.max_photo_bytes:
            raise GatewayError("The decoded photo exceeds this deployment's size limit.")
        if not self._valid_image_signature(body, normalized_type):
            raise GatewayError("The photo bytes do not match media_type.")
        case = self._resolve(case_reference)
        try:
            updated = self.client.upload_case_photo(
                str(case["id"]), body, normalized_type, key
            )
        except CustomerFlowAPIError as exc:
            raise GatewayError(str(exc)) from None
        return self._case_detail(updated)

    def policy(self) -> dict[str, Any]:
        return {
            "scope": "the agency resolved from the current bearer token",
            "data_classification": "confidential_patient_data",
            "read_tools": ["who_am_i", "list_cases", "get_case"],
            "write_tools_enabled": self.settings.enable_writes,
            "photo_uploads_enabled": self.settings.enable_photo_uploads,
            "not_exposed": [
                "admin operations",
                "doctor assignment",
                "user or agency management",
                "patient matching",
                "delete operations",
                "case closing",
            ],
            "handling": "Do not copy patient data outside the agency's approved systems.",
        }
