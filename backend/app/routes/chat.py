from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from app.services.ai_service import chat_with_advisor
from app.services.coe_service import get_coe_context_for_major, resolve_full_major_name

router = APIRouter(prefix="/chat", tags=["AI Advisor"])


class Message(BaseModel):
    role: str  # "user" or "assistant"
    content: str


class ChatRequest(BaseModel):
    messages: list[Message]
    major: str = "Computer Science"  # defaults to CS; used to inject course catalog into context


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

    try:
        reply = chat_with_advisor(messages, course_context=course_context)
    except Exception as e:
        raise HTTPException(status_code=502, detail=f"AI service error: {str(e)}")

    return ChatResponse(reply=reply)
