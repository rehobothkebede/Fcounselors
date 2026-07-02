"""
Quick integration test for the Hokie Advisor API.
Run with: python test_api.py
Make sure the server is running: uvicorn app.main:app --reload
"""

import json
import sys
import httpx

BASE_URL = "http://localhost:8000"


def check(label: str, resp: httpx.Response):
    status = "OK" if resp.status_code < 300 else "FAIL"
    print(f"[{status}] {label} — HTTP {resp.status_code}")
    if resp.status_code >= 300:
        print(f"      Error: {resp.text}")
        return False
    return True


def pretty(data: dict):
    print(json.dumps(data, indent=2))
    print()


def test_health():
    print("=== Health Check ===")
    resp = httpx.get(f"{BASE_URL}/health")
    if check("GET /health", resp):
        pretty(resp.json())


def test_chat():
    print("=== Chat Endpoint ===")
    payload = {
        "messages": [
            {"role": "user", "content": "I'm a CS sophomore at VT. I've taken CS 1114 and MATH 1225. What should I take next?"}
        ]
    }
    resp = httpx.post(f"{BASE_URL}/chat", json=payload, timeout=30)
    if check("POST /chat", resp):
        data = resp.json()
        print(f"  Reply: {data['reply'][:300]}...\n" if len(data.get("reply", "")) > 300 else f"  Reply: {data.get('reply')}\n")


def test_advisor_plan():
    print("=== Advisor Plan Endpoint ===")
    payload = {
        "completed_courses": ["CS 1114", "MATH 1225"],
        "major": "Computer Science",
        "constraints": ["light workload", "internship focus"],
    }
    print(f"  Request: {json.dumps(payload, indent=2)}")
    resp = httpx.post(f"{BASE_URL}/advisor/plan", json=payload, timeout=30)
    if check("POST /advisor/plan", resp):
        data = resp.json()
        print("\n  Recommended courses:")
        for course in data.get("recommended_courses", []):
            print(f"    - {course['code']}: {course['name']}")
            print(f"      Reason: {course['reason']}")
        print(f"\n  Reasoning: {data.get('reasoning', '')}")
        warnings = data.get("warnings", [])
        if warnings:
            print(f"\n  Warnings:")
            for w in warnings:
                print(f"    ! {w}")
        print()


def test_courses(subject="CS"):
    print(f"=== Courses Endpoint (subject={subject}) ===")
    resp = httpx.get(f"{BASE_URL}/courses/{subject}", timeout=20)
    if check(f"GET /courses/{subject}", resp):
        data = resp.json()
        courses = data.get("courses", [])
        print(f"  Source: {data.get('source')} | Count: {len(courses)}")
        if courses:
            print(f"  First course: {courses[0].get('code')} — {courses[0].get('name')}")
        print()


if __name__ == "__main__":
    print(f"Testing Hokie Advisor API at {BASE_URL}\n")
    try:
        httpx.get(f"{BASE_URL}/health", timeout=5)
    except Exception:
        print("ERROR: Server is not running. Start it with:")
        print("  cd backend && uvicorn app.main:app --reload")
        sys.exit(1)

    test_health()
    test_chat()
    test_advisor_plan()
    # Uncomment to test course scraping (makes live VT API call):
    # test_courses("CS")
    print("Done.")
