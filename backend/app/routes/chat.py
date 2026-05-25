from typing import Optional
from fastapi import APIRouter, HTTPException
from fastapi.responses import StreamingResponse
from pydantic import BaseModel
from app.services.ai_service import chat_with_advisor, chat_stream_with_advisor
from app.services.coe_service import get_coe_context_for_major, resolve_full_major_name

router = APIRouter(prefix="/chat", tags=["AI Advisor"])


class Message(BaseModel):
    role: str
    content: str


class TranscriptEntry(BaseModel):
    code: str
    name: str
    grade: Optional[str] = None
    semester: Optional[str] = None
    credits: Optional[float] = None


class ChatRequest(BaseModel):
    messages: list[Message]
    major: str = "Computer Science"
    transcript: list[TranscriptEntry] = []
    in_progress_courses: list[str] = []
    transcript_notes: list[str] = []
    chat_memories: list[str] = []


class ChatResponse(BaseModel):
    reply: str


@router.post("", response_model=ChatResponse)
def chat(request: ChatRequest):
    """
    Send a conversation to the Fcounselors AI (tutor / advisor).
    Pass the full message history so the bot retains context across turns.

    Optional: include `major` (e.g. "Computer Science", "ECE") to inject
    the department's course catalog into the AI's context window.

    Example body:
    {
      "major": "Computer Science",
      "messages": [
        {"role": "user", "content": "I'm really stressed about picking next semester's courses."}
      ]
    }
    """
    if not request.messages:
        raise HTTPException(status_code=400, detail="messages cannot be empty")

    messages = [m.model_dump() for m in request.messages]
    course_context = ""
    if request.major:
        full_name = resolve_full_major_name(request.major)
        course_context = f"Student's major: {full_name}\n\n" + get_coe_context_for_major(request.major)

    transcript = [e.model_dump() for e in request.transcript]
    try:
        reply = chat_with_advisor(
            messages,
            course_context=course_context,
            transcript=transcript,
            in_progress_courses=request.in_progress_courses,
            transcript_notes=request.transcript_notes,
            chat_memories=request.chat_memories,
        )
    except Exception as e:
        raise HTTPException(status_code=502, detail=f"AI service error: {str(e)}")

    return ChatResponse(reply=reply)


@router.post("/stream")
def chat_stream(request: ChatRequest):
    """Stream the AI advisor response token by token via Server-Sent Events."""
    if not request.messages:
        raise HTTPException(status_code=400, detail="messages cannot be empty")

    messages = [m.model_dump() for m in request.messages]
    course_context = ""
    if request.major:
        full_name = resolve_full_major_name(request.major)
        course_context = f"Student's major: {full_name}\n\n" + get_coe_context_for_major(request.major)

    transcript = [e.model_dump() for e in request.transcript]
    try:
        generator = chat_stream_with_advisor(
            messages,
            course_context=course_context,
            transcript=transcript,
            in_progress_courses=request.in_progress_courses,
            transcript_notes=request.transcript_notes,
            chat_memories=request.chat_memories,
        )
    except Exception as e:
        raise HTTPException(status_code=502, detail=f"AI service error: {str(e)}")

    return StreamingResponse(
        generator,
        media_type="text/event-stream",
        headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"},
    )
