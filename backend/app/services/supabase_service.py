import logging
from typing import Any, Optional

import httpx

from app.config import SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY, SUPABASE_URL

logger = logging.getLogger(__name__)


class SupabaseNotConfigured(RuntimeError):
    pass


class SupabaseServiceError(RuntimeError):
    pass


class SupabaseClient:
    """Minimal Supabase PostgREST client using the service-role key.

    The backend uses service-role access so row-level security can stay strict
    for mobile clients while trusted server jobs can seed and persist data.
    """

    def __init__(self, url: str, key: str, timeout: float = 20.0):
        if not url or not key:
            raise SupabaseNotConfigured("SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are required")
        self.url = url.rstrip("/")
        self.key = key
        self.timeout = timeout

    @property
    def rest_url(self) -> str:
        return f"{self.url}/rest/v1"

    def _headers(self, prefer: Optional[str] = None) -> dict[str, str]:
        headers = {
            "apikey": self.key,
            "Authorization": f"Bearer {self.key}",
            "Content-Type": "application/json",
        }
        if prefer:
            headers["Prefer"] = prefer
        return headers

    def health(self) -> dict[str, Any]:
        response = httpx.get(
            f"{self.rest_url}/catalog_subjects",
            params={"select": "code", "limit": "1"},
            headers=self._headers(),
            timeout=self.timeout,
        )
        self._raise_for_status(response)
        return {"status": "ok", "configured": True}

    def upsert(
        self,
        table: str,
        rows: list[dict[str, Any]],
        *,
        on_conflict: Optional[str] = None,
        returning: str = "minimal",
    ) -> int:
        if not rows:
            return 0

        params = {}
        if on_conflict:
            params["on_conflict"] = on_conflict

        response = httpx.post(
            f"{self.rest_url}/{table}",
            params=params,
            json=rows,
            headers=self._headers(f"resolution=merge-duplicates,return={returning}"),
            timeout=self.timeout,
        )
        self._raise_for_status(response)
        return len(rows)

    def insert(
        self,
        table: str,
        rows: list[dict[str, Any]],
        *,
        returning: str = "minimal",
    ) -> int:
        if not rows:
            return 0

        response = httpx.post(
            f"{self.rest_url}/{table}",
            json=rows,
            headers=self._headers(f"return={returning}"),
            timeout=self.timeout,
        )
        self._raise_for_status(response)
        return len(rows)

    @staticmethod
    def _raise_for_status(response: httpx.Response) -> None:
        try:
            response.raise_for_status()
        except httpx.HTTPStatusError as exc:
            body = exc.response.text[:1000]
            logger.warning("Supabase request failed: %s", body)
            raise SupabaseServiceError(body) from exc


def is_supabase_configured() -> bool:
    return bool(SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY)


def get_supabase_client() -> SupabaseClient:
    return SupabaseClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY)


def get_supabase_status() -> dict[str, Any]:
    return {
        "configured": is_supabase_configured(),
        "url": SUPABASE_URL,
        "has_anon_key": bool(SUPABASE_ANON_KEY),
        "has_service_role_key": bool(SUPABASE_SERVICE_ROLE_KEY),
    }
