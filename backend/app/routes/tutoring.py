from typing import List, Optional
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from app.routes.errors import error_detail
from app.services.ai_service import recommend_tutoring

router = APIRouter(prefix="/tutoring", tags=["Tutoring"])


class TutoringRequest(BaseModel):
    struggling_courses: List[str]
    completed_courses: List[str] = []
    major: str = ""


class TutoringResource(BaseModel):
    name: str
    type: str
    description: str
    link: Optional[str] = None


class TutoringResponse(BaseModel):
    resources: List[TutoringResource]
    tips: List[str]
    encouragement: str


@router.post("/recommend", response_model=TutoringResponse)
def get_tutoring_recommendations(request: TutoringRequest):
    """
    Generate tutoring and academic support recommendations for a struggling student.
    """
    if not request.struggling_courses:
        raise HTTPException(
            status_code=400,
            detail=error_detail("TUTORING_COURSES_REQUIRED", "struggling_courses cannot be empty"),
        )

    try:
        result = recommend_tutoring(
            struggling_courses=request.struggling_courses,
            completed_courses=request.completed_courses,
            major=request.major,
        )
    except Exception as e:
        raise HTTPException(
            status_code=502,
            detail=error_detail("TUTORING_AI_REQUEST_FAILED", f"AI service error: {str(e)}"),
        )

    return TutoringResponse(**result)
