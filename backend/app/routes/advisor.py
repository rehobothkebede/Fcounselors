import logging
import asyncio
from typing import Optional
from fastapi import APIRouter, File, HTTPException, UploadFile
from pydantic import BaseModel
from app.routes.errors import error_detail
from app.services.ai_service import recommend_courses
from app.services.dars_audit_service import parse_dars_audit
from app.services.degree_audit_service import run_degree_audit
from app.services.scraper_service import load_courses, scrape_vt_major_catalog, resolve_subject_for_major

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/advisor", tags=["Advisor"])

_ALLOWED_AUDIT_TYPES = {"application/pdf", "image/png", "image/jpeg", "image/jpg"}
_MAX_AUDIT_BYTES = 12 * 1024 * 1024


class PlanRequest(BaseModel):
    completed_courses: list[str]
    major: str
    constraints: list[str] = []
    in_progress_courses: list[str] = []


class RecommendedCourse(BaseModel):
    code: str
    name: str
    reason: str


class PlanResponse(BaseModel):
    recommended_courses: list[RecommendedCourse]
    reasoning: str
    warnings: list[str]


class TranscriptEntry(BaseModel):
    code: str
    name: str = ""
    grade: Optional[str] = None
    semester: Optional[str] = None
    credits: Optional[float] = None


class DegreeAuditRequest(BaseModel):
    major: str = "Computer Science"
    transcript: list[TranscriptEntry]
    in_progress_courses: list[str] = []


class AuditBucket(BaseModel):
    id: str
    title: str
    status: str
    required_credits: float
    completed_credits: float
    required_count: Optional[int] = None
    completed_count: Optional[int] = None
    matched_courses: list[str]
    missing_items: list[str]
    notes: list[str]


class DegreeAuditResponse(BaseModel):
    major: str
    degree: str
    catalog_year: str
    total_required_credits: float
    completed_credits: float
    percent_complete: int
    complete_bucket_count: int
    total_bucket_count: int
    buckets: list[AuditBucket]
    warnings: list[str]


class DarsCategory(BaseModel):
    id: str
    title: str
    status: str
    complete_hours: Optional[float] = None
    in_progress_hours: Optional[float] = None
    unfulfilled_hours: Optional[float] = None
    planned_hours: Optional[float] = None
    required_hours: Optional[float] = None
    gpa: Optional[float] = None
    notes: list[str] = []


class DarsSection(BaseModel):
    title: str
    status: str
    matched_courses: list[str] = []
    missing_items: list[str] = []
    notes: list[str] = []


class DarsAuditResponse(BaseModel):
    student_name: Optional[str] = None
    student_id: Optional[str] = None
    program: Optional[str] = None
    program_code: Optional[str] = None
    catalog_year: Optional[str] = None
    graduation_date: Optional[str] = None
    prepared_on: Optional[str] = None
    job_id: Optional[str] = None
    audit_type: Optional[str] = None
    university_gpa: Optional[float] = None
    in_major_gpa: Optional[float] = None
    categories: list[DarsCategory]
    sections: list[DarsSection]
    warnings: list[str]


@router.post("/plan", response_model=PlanResponse)
def get_plan(request: PlanRequest):
    """
    Generate a personalized course plan for the next semester.

    Example request:
    {
      "completed_courses": ["CS 1114", "MATH 1225"],
      "major": "Computer Science",
      "constraints": ["light workload", "internship focus"]
    }
    """
    if not request.major:
        raise HTTPException(status_code=400, detail=error_detail("PLAN_MAJOR_REQUIRED", "major cannot be empty"))

    # 1. Load timetable courses (cached)
    subject = resolve_subject_for_major(request.major)
    available_courses = load_courses(subject)

    # 2. Fetch degree requirements from VT catalog (with fail-safe)
    major_requirements: dict | None = None
    try:
        major_requirements = scrape_vt_major_catalog(request.major)
        if not major_requirements.get("required_courses"):
            logger.info("Catalog returned no required courses for '%s' — proceeding without it", request.major)
            major_requirements = None
    except Exception as e:
        logger.warning("Catalog fetch failed for '%s': %s — continuing without catalog", request.major, e)
        major_requirements = None

    # 3. Ask AI to build the plan
    try:
        result = recommend_courses(
            completed_courses=request.completed_courses,
            major=request.major,
            constraints=request.constraints,
            in_progress_courses=request.in_progress_courses,
            available_courses=available_courses,
            major_requirements=major_requirements,
        )
    except Exception as e:
        raise HTTPException(status_code=502, detail=error_detail("PLAN_AI_REQUEST_FAILED", f"AI service error: {str(e)}"))

    return PlanResponse(**result)


@router.post("/audit", response_model=DegreeAuditResponse)
def get_degree_audit(request: DegreeAuditRequest):
    """Audit a student's transcript against the local CS B.S. catalog data."""
    if not request.major:
        raise HTTPException(status_code=400, detail=error_detail("AUDIT_MAJOR_REQUIRED", "major cannot be empty"))

    try:
        result = run_degree_audit(
            major=request.major,
            transcript=[entry.model_dump() for entry in request.transcript],
            in_progress_courses=request.in_progress_courses,
        )
    except ValueError as e:
        raise HTTPException(status_code=400, detail=error_detail("AUDIT_INVALID_REQUEST", str(e)))
    except Exception as e:
        logger.exception("Degree audit failed")
        raise HTTPException(status_code=500, detail=error_detail("AUDIT_FAILED", f"Degree audit failed: {str(e)}"))

    return DegreeAuditResponse(**result)


@router.post("/dars/upload", response_model=DarsAuditResponse)
async def upload_dars_audit(file: UploadFile = File(...)):
    """Parse an official uAchieve/DARS audit export or screenshot."""
    content_type = (file.content_type or "").split(";")[0].strip().lower()
    if content_type not in _ALLOWED_AUDIT_TYPES:
        raise HTTPException(
            status_code=415,
            detail=error_detail(
                "DARS_UNSUPPORTED_FILE_TYPE",
                f"Unsupported file type '{content_type}'. Upload a DARS PDF, PNG, or JPG.",
            ),
        )

    file_bytes = await file.read()
    if len(file_bytes) > _MAX_AUDIT_BYTES:
        raise HTTPException(status_code=413, detail=error_detail("DARS_FILE_TOO_LARGE", "File too large. Maximum size is 12 MB."))
    if len(file_bytes) == 0:
        raise HTTPException(status_code=400, detail=error_detail("DARS_FILE_EMPTY", "Uploaded file is empty."))

    try:
        result = await asyncio.to_thread(parse_dars_audit, file_bytes, content_type)
    except ValueError as e:
        raise HTTPException(status_code=422, detail=error_detail("DARS_PARSE_FAILED", str(e)))
    except RuntimeError as e:
        raise HTTPException(status_code=502, detail=error_detail("DARS_AI_REQUEST_FAILED", str(e)))
    except Exception as e:
        logger.exception("DARS audit parse failed")
        raise HTTPException(status_code=500, detail=error_detail("DARS_PARSE_FAILED", f"DARS audit parse failed: {str(e)}"))

    return DarsAuditResponse(**result)
