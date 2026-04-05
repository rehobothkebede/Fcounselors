import logging
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from app.services.ai_service import recommend_courses
from app.services.scraper_service import load_courses, scrape_vt_major_catalog, resolve_subject_for_major

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/advisor", tags=["Advisor"])


class PlanRequest(BaseModel):
    completed_courses: list[str]
    major: str
    constraints: list[str] = []


class RecommendedCourse(BaseModel):
    code: str
    name: str
    reason: str


class PlanResponse(BaseModel):
    recommended_courses: list[RecommendedCourse]
    reasoning: str
    warnings: list[str]


def _resolve_subject(major: str) -> str:
    """Resolve a major name to a VT subject code for timetable lookup."""
    return resolve_subject_for_major(major)


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
        raise HTTPException(status_code=400, detail="major cannot be empty")

    # 1. Load timetable courses (cached)
    subject = _resolve_subject(request.major)
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
            available_courses=available_courses,
            major_requirements=major_requirements,
        )
    except Exception as e:
        raise HTTPException(status_code=502, detail=f"AI service error: {str(e)}")

    return PlanResponse(**result)
