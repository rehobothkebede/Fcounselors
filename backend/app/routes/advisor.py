from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from app.services.ai_service import recommend_courses
from app.services.scraper_service import load_courses

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

    # Try to load cached courses for the major's primary subject
    subject_map = {
        "computer science": "CS",
        "mathematics": "MATH",
        "electrical engineering": "ECE",
        "mechanical engineering": "ME",
    }
    subject = subject_map.get(request.major.lower(), request.major.split()[0].upper())
    available_courses = load_courses(subject)  # None if not yet cached — that's fine

    try:
        result = recommend_courses(
            completed_courses=request.completed_courses,
            major=request.major,
            constraints=request.constraints,
            available_courses=available_courses,
        )
    except Exception as e:
        raise HTTPException(status_code=502, detail=f"AI service error: {str(e)}")

    return PlanResponse(**result)
