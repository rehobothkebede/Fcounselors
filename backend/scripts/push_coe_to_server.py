"""
push_coe_to_server.py

Uploads all local backend/data/coe/*.json files to a remote Fcounselors server
via the POST /admin/seed-coe endpoint.

Usage:
    python scripts/push_coe_to_server.py --server http://your-server-url
    python scripts/push_coe_to_server.py --server http://localhost:8000  # local test
"""

import argparse
import json
import os
import sys

import requests

COE_DIR = os.path.join(os.path.dirname(__file__), "..", "data", "coe")


def push(server_url: str, dry_run: bool = False):
    server_url = server_url.rstrip("/")
    endpoint = f"{server_url}/admin/seed-coe"

    files = [f for f in os.listdir(COE_DIR) if f.endswith(".json") and f != "manifest.json"]
    if not files:
        print("No COE JSON files found in", COE_DIR)
        sys.exit(1)

    print(f"Pushing {len(files)} COE files to {endpoint}\n")
    success, failed = [], []

    for fname in sorted(files):
        subject = fname.replace(".json", "")
        path = os.path.join(COE_DIR, fname)

        with open(path) as f:
            data = json.load(f)

        course_count = len(data.get("courses", []))
        print(f"  {subject:6s}  ({course_count} courses)", end="  ")

        if dry_run:
            print("DRY RUN — skipped")
            continue

        try:
            resp = requests.post(
                endpoint,
                json={"subject": subject, "data": data},
                timeout=15,
            )
            if resp.status_code == 200:
                print("OK")
                success.append(subject)
            else:
                print(f"FAILED ({resp.status_code}: {resp.text[:80]})")
                failed.append(subject)
        except requests.RequestException as e:
            print(f"ERROR ({e})")
            failed.append(subject)

    print(f"\nDone: {len(success)} uploaded, {len(failed)} failed.")
    if failed:
        print("Failed subjects:", failed)
        sys.exit(1)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--server", default="http://localhost:8000", help="Base server URL")
    parser.add_argument("--dry-run", action="store_true", help="Print files without uploading")
    args = parser.parse_args()
    push(args.server, dry_run=args.dry_run)
