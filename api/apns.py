"""Optional Apple Push Notification delivery for Customer Flow.

The API and in-app notification centre do not depend on APNs credentials. When
the required environment variables are present, this module drains the durable
push outbox using Apple's token-based provider authentication.
"""

from __future__ import annotations

import base64
import json
import os
import subprocess
import threading
import time
from pathlib import Path
from typing import Protocol


class PushDatabase(Protocol):
    def pending_push_deliveries(self, limit: int = 20) -> list[dict]: ...

    def complete_push_delivery(
        self, delivery_id: str, *, delivered: bool, error: str | None = None,
        invalid_device_id: str | None = None,
    ) -> None: ...


def _base64url(value: bytes) -> str:
    return base64.urlsafe_b64encode(value).rstrip(b"=").decode("ascii")


def _read_der_length(data: bytes, offset: int) -> tuple[int, int]:
    first = data[offset]
    if first < 0x80:
        return first, offset + 1
    byte_count = first & 0x7F
    return int.from_bytes(data[offset + 1:offset + 1 + byte_count], "big"), offset + 1 + byte_count


def _ecdsa_der_to_raw(signature: bytes) -> bytes:
    if not signature or signature[0] != 0x30:
        raise RuntimeError("OpenSSL returned an invalid APNs signature.")
    _, offset = _read_der_length(signature, 1)
    values = []
    for _ in range(2):
        if offset >= len(signature) or signature[offset] != 0x02:
            raise RuntimeError("OpenSSL returned an invalid APNs signature.")
        length, offset = _read_der_length(signature, offset + 1)
        value = signature[offset:offset + length]
        offset += length
        values.append(value.lstrip(b"\0").rjust(32, b"\0"))
    if any(len(value) != 32 for value in values):
        raise RuntimeError("OpenSSL returned an invalid APNs signature.")
    return b"".join(values)


class APNSPushSender:
    """Sends APNs alerts with a short-lived ES256 provider token."""

    def __init__(self, key_id: str, team_id: str, private_key: Path, topic: str):
        self.key_id = key_id
        self.team_id = team_id
        self.private_key = private_key
        self.topic = topic
        self._token: str | None = None
        self._token_created_at = 0
        self._token_lock = threading.Lock()

    @classmethod
    def from_environment(cls) -> APNSPushSender | None:
        key_id = os.getenv("CF_APNS_KEY_ID", "").strip()
        team_id = os.getenv("CF_APNS_TEAM_ID", "").strip()
        private_key = Path(os.getenv("CF_APNS_PRIVATE_KEY", "")).expanduser()
        topic = os.getenv("CF_APNS_TOPIC", "com.customerflow.client").strip()
        if not key_id or not team_id or not str(private_key) or not private_key.is_file() or not topic:
            return None
        return cls(key_id, team_id, private_key, topic)

    def send(self, delivery: dict) -> tuple[bool, str | None, bool]:
        payload = json.dumps({
            "aps": {
                "alert": {"title": delivery["title"], "body": delivery["body"]},
                "sound": "default",
                "badge": delivery["unread_count"],
                "thread-id": delivery["case_id"] or "customer-flow",
            },
            "kind": delivery["kind"],
            "caseID": delivery["case_id"],
        }, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
        host = "api.sandbox.push.apple.com" if delivery["environment"] == "sandbox" else "api.push.apple.com"
        command = [
            "curl", "--http2", "--silent", "--show-error", "--max-time", "20",
            "--output", "-", "--write-out", "\n%{http_code}", "--request", "POST",
            "--header", f"authorization: bearer {self._provider_token()}",
            "--header", f"apns-topic: {self.topic}",
            "--header", "apns-push-type: alert",
            "--header", "apns-priority: 10",
            "--header", "content-type: application/json",
            "--data-binary", "@-",
            f"https://{host}/3/device/{delivery['token']}",
        ]
        try:
            result = subprocess.run(command, input=payload, capture_output=True, timeout=25, check=False)
        except (OSError, subprocess.SubprocessError) as exc:
            return False, str(exc), False
        output = result.stdout.decode("utf-8", "replace")
        response_body, _, raw_status = output.rpartition("\n")
        try:
            status = int(raw_status)
        except ValueError:
            return False, result.stderr.decode("utf-8", "replace") or "APNs returned no status.", False
        if status == 200:
            return True, None, False
        try:
            reason = json.loads(response_body).get("reason", f"APNs HTTP {status}")
        except json.JSONDecodeError:
            reason = f"APNs HTTP {status}"
        invalid = status == 410 or reason in {"BadDeviceToken", "DeviceTokenNotForTopic", "Unregistered"}
        return False, reason, invalid

    def _provider_token(self) -> str:
        with self._token_lock:
            now = int(time.time())
            if self._token and now - self._token_created_at < 45 * 60:
                return self._token
            header = _base64url(json.dumps(
                {"alg": "ES256", "kid": self.key_id}, separators=(",", ":")
            ).encode())
            claims = _base64url(json.dumps(
                {"iss": self.team_id, "iat": now}, separators=(",", ":")
            ).encode())
            signing_input = f"{header}.{claims}".encode("ascii")
            result = subprocess.run(
                ["openssl", "dgst", "-sha256", "-sign", str(self.private_key)],
                input=signing_input, capture_output=True, timeout=10, check=False,
            )
            if result.returncode != 0:
                raise RuntimeError("The APNs provider token could not be signed.")
            signature = _base64url(_ecdsa_der_to_raw(result.stdout))
            self._token = f"{header}.{claims}.{signature}"
            self._token_created_at = now
            return self._token


class APNSPushDispatcher:
    """Drains pending push deliveries without delaying API mutation responses."""

    def __init__(self, database: PushDatabase):
        self.database = database
        self.sender = APNSPushSender.from_environment()
        self._condition = threading.Condition()
        self._stopped = False
        self._thread: threading.Thread | None = None

    @property
    def enabled(self) -> bool:
        return self.sender is not None

    def start(self) -> None:
        if not self.sender or self._thread:
            return
        self._thread = threading.Thread(target=self._run, name="customer-flow-apns", daemon=True)
        self._thread.start()

    def wake(self) -> None:
        if not self.sender:
            return
        with self._condition:
            self._condition.notify_all()

    def stop(self) -> None:
        with self._condition:
            self._stopped = True
            self._condition.notify_all()
        if self._thread:
            self._thread.join(timeout=3)

    def _run(self) -> None:
        while True:
            with self._condition:
                if self._stopped:
                    return
                self._condition.wait(timeout=30)
                if self._stopped:
                    return
            for delivery in self.database.pending_push_deliveries():
                try:
                    delivered, error, invalid = self.sender.send(delivery)  # type: ignore[union-attr]
                except Exception as exc:
                    delivered, error, invalid = False, str(exc), False
                self.database.complete_push_delivery(
                    delivery["delivery_id"], delivered=delivered, error=error,
                    invalid_device_id=delivery["device_id"] if invalid else None,
                )
