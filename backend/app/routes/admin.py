import json
import logging
import os

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

from app.config import COE_DIR
from app.services.coe_service import load_coe_courses
from app.services.supabase_service import (
    SupabaseNotConfigured,
    SupabaseServiceError,
    get_supabase_client,
    get_supabase_status,
)

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/admin", tags=["Admin"])


class SeedCoeRequest(BaseModel):
    subject: str
    data: dict  # {"courses": [...]}


class SeedCoeResponse(BaseModel):
    subject: str
    course_count: int
    message: str


@router.post("/seed-coe", response_model=SeedCoeResponse)
def seed_coe(request: SeedCoeRequest):
    """
    Write a COE subject JSON file to disk (data/coe/{SUBJECT}.json).
    Called by scripts/push_coe_to_server.py during deployment.
    """
    subject = request.subject.upper().strip()
    if not subject.isalpha():
        raise HTTPException(status_code=400, detail="Invalid subject code")

    courses = request.data.get("courses", [])
    if not isinstance(courses, list):
        raise HTTPException(status_code=400, detail="data.courses must be a list")

    os.makedirs(COE_DIR, exist_ok=True)
    dest = os.path.join(COE_DIR, f"{subject}.json")

    try:
        with open(dest, "w") as f:
            json.dump(request.data, f)
    except Exception as e:
        logger.error("Failed to write COE file %s: %s", dest, e)
        raise HTTPException(status_code=500, detail=f"Failed to write file: {e}")

    # Bust the lru_cache so the new data is picked up immediately
    load_coe_courses.cache_clear()

    logger.info("Seeded COE data for %s (%d courses)", subject, len(courses))
    return SeedCoeResponse(
        subject=subject,
        course_count=len(courses),
        message=f"Seeded {len(courses)} courses for {subject}",
    )


@router.get("/seed-coe/status")
def seed_coe_status():
    """Return which COE subjects are currently on disk."""
    if not os.path.exists(COE_DIR):
        return {"subjects": [], "total_courses": 0}

    status = []
    total = 0
    for fname in sorted(os.listdir(COE_DIR)):
        if fname.endswith(".json") and fname != "manifest.json":
            subject = fname.replace(".json", "")
            try:
                with open(os.path.join(COE_DIR, fname)) as f:
                    count = len(json.load(f).get("courses", []))
                status.append({"subject": subject, "course_count": count})
                total += count
            except Exception:
                status.append({"subject": subject, "course_count": -1})

    return {"subjects": status, "total_courses": total}


@router.get("/supabase/status")
def supabase_status():
    """Return Supabase configuration and database reachability."""
    status = get_supabase_status()
    if not status["configured"]:
        return {**status, "status": "not_configured"}

    try:
        health = get_supabase_client().health()
    except SupabaseNotConfigured:
        return {**status, "status": "not_configured"}
    except SupabaseServiceError as exc:
        return {**status, "status": "unreachable", "detail": str(exc)}
    except Exception as exc:
        logger.exception("Supabase health check failed")
        return {**status, "status": "unreachable", "detail": str(exc)}

    return {**status, **health}
