from contextlib import asynccontextmanager
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from app.routes import chat, courses
from app.routes import advisor
from app.config import OPENAI_API_KEY, OPENAI_MODEL


@asynccontextmanager
async def lifespan(app: FastAPI):
    key_loaded = "YES" if OPENAI_API_KEY else "NO"
    print(f"OpenAI key loaded: {key_loaded}")
    print(f"Model: {OPENAI_MODEL}")
    print("Server running on http://localhost:8000")
    yield


app = FastAPI(
    title="Fcounselors API",
    description="AI-powered academic advising backend for Virginia Tech students.",
    version="0.2.0",
    lifespan=lifespan,
)

# Allow requests from localhost (for iOS Simulator and local testing)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Tighten this before production
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(chat.router)
app.include_router(courses.router)
app.include_router(advisor.router)


@app.get("/", tags=["Health"])
def root():
    return {"status": "ok", "service": "Fcounselors API"}


@app.get("/health", tags=["Health"])
def health():
    return {"status": "ok"}
