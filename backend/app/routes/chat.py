from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from app.services.ai_service import chat_with_advisor

router = APIRouter(prefix="/chat", tags=["AI Advisor"])


class Message(BaseModel):
    role: str  # "user" or "assistant"
    content: str


class ChatRequest(BaseModel):
    messages: list[Message]


class ChatResponse(BaseModel):
    reply: str


@router.post("", response_model=ChatResponse)
def chat(request: ChatRequest):
    """
    Send a conversation to the AI advisor.
    Pass the full message history so the advisor has context.

    Example body:
    {
      "messages": [
        {"role": "user", "content": "What CS courses should I take freshman year?"}
      ]
    }
    """
    if not request.messages:
        raise HTTPException(status_code=400, detail="messages cannot be empty")

    messages = [m.model_dump() for m in request.messages]

    try:
        reply = chat_with_advisor(messages)
    except Exception as e:
        raise HTTPException(status_code=502, detail=f"AI service error: {str(e)}")

    return ChatResponse(reply=reply)
