#!/usr/bin/env python3
"""Sync local Hokie Advisor catalog JSON data into Supabase."""

import os
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
if ROOT not in sys.path:
    sys.path.insert(0, ROOT)

from app.services.supabase_catalog_sync import sync_catalog_to_supabase
from app.services.supabase_service import get_supabase_client, get_supabase_status


def main() -> int:
    status = get_supabase_status()
    if not status["configured"]:
        print("Supabase is not configured. Set SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY.")
        return 1

    counts = sync_catalog_to_supabase(get_supabase_client())
    print("Synced catalog data to Supabase:")
    for table, count in counts.items():
        print(f"  {table}: {count}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
