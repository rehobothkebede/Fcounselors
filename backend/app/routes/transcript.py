import asyncio
from typing import List, Optional

from fastapi import APIRouter, File, HTTPException, UploadFile
from pydantic import BaseModel
from app.services.transcript_service import parse_transcript

router = APIRouter(prefix="/transcript", tags=["Transcript"])

_ALLOWED_TYPES = {"application/pdf", "image/png", "image/jpeg", "image/jpg"}
_MAX_BYTES = 10 * 1024 * 1024  # 10 MB


class TranscriptCourse(BaseModel):
    code: str
    name: str
    credits: Optional[float] = None
    grade: Optional[str] = None
    semester: Optional[str] = None


class InProgressCourse(BaseModel):
    code: str
    name: str
    credits: Optional[float] = None


class TranscriptResponse(BaseModel):
    courses: List[TranscriptCourse]
    in_progress_courses: List[InProgressCourse]
    course_count: int
    warnings: List[str]


@router.post("/upload", response_model=TranscriptResponse)
async def upload_transcript(file: UploadFile = File(...)):
    """
    Upload a transcript (PDF, PNG, or JPG) and extract the list of completed courses.
    """
    content_type = (file.content_type or "").split(";")[0].strip().lower()
    if content_type not in _ALLOWED_TYPES:
        raise HTTPException(
            status_code=415,
            detail=f"Unsupported file type '{content_type}'. Upload a PDF, PNG, or JPG.",
        )

    file_bytes = await file.read()
    if len(file_bytes) > _MAX_BYTES:
        raise HTTPException(status_code=413, detail="File too large. Maximum size is 10 MB.")
    if len(file_bytes) == 0:
        raise HTTPException(status_code=400, detail="Uploaded file is empty.")

    try:
        result = await asyncio.to_thread(parse_transcript, file_bytes, content_type)
    except ValueError as e:
        raise HTTPException(status_code=422, detail=str(e))
    except RuntimeError as e:
        raise HTTPException(status_code=500, detail=str(e))

    return TranscriptResponse(
        courses=[TranscriptCourse(**c) for c in result["courses"]],
        in_progress_courses=[InProgressCourse(**c) for c in result["in_progress_courses"]],
        course_count=len(result["courses"]),
        warnings=result["warnings"],
    )
