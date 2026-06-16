import logging
from contextlib import asynccontextmanager
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from app.routes import chat, courses, advisor, admin, transcript, tutoring
from app.config import APP_ENV, CORS_ALLOWED_ORIGINS, OPENAI_API_KEY, OPENAI_MODEL
from app.services.supabase_service import get_supabase_status

logger = logging.getLogger("hokie_advisor")


@asynccontextmanager
async def lifespan(app: FastAPI):
    key_loaded = "YES" if OPENAI_API_KEY else "NO"
    supabase_status = get_supabase_status()
    logger.info("OpenAI configured: %s", key_loaded)
    logger.info("Model: %s", OPENAI_MODEL)
    logger.info("Supabase configured: %s", "YES" if supabase_status["configured"] else "NO")
    logger.info("Environment: %s", APP_ENV)
    logger.info("CORS origins: %s", ", ".join(CORS_ALLOWED_ORIGINS) if CORS_ALLOWED_ORIGINS else "disabled")
    yield


app = FastAPI(
    title="Hokie Advisor API",
    description="AI-powered academic advising backend for Virginia Tech students.",
    version="0.2.0",
    lifespan=lifespan,
)

if CORS_ALLOWED_ORIGINS:
    app.add_middleware(
        CORSMiddleware,
        allow_origins=CORS_ALLOWED_ORIGINS,
        allow_methods=["*"],
        allow_headers=["*"],
    )

app.include_router(chat.router)
app.include_router(courses.router)
app.include_router(advisor.router)
app.include_router(admin.router)
app.include_router(transcript.router)
app.include_router(tutoring.router)


@app.get("/", tags=["Health"])
def root():
    return {"status": "ok", "service": "Hokie Advisor API"}


@app.get("/health", tags=["Health"])
def health():
    return {"status": "ok", "supabase": get_supabase_status()}
