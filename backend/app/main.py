from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from app.routes import chat, courses

app = FastAPI(
    title="Fcounselors API",
    description="AI-powered academic advising backend for Virginia Tech students.",
    version="0.1.0",
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


@app.get("/", tags=["Health"])
def root():
    return {"status": "ok", "service": "Fcounselors API"}


@app.get("/health", tags=["Health"])
def health():
    return {"status": "ok"}
