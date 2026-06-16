import os
from dotenv import load_dotenv

load_dotenv(override=True)

OPENAI_API_KEY = os.getenv("OPENAI_API_KEY", "")
OPENAI_MODEL = os.getenv("OPENAI_MODEL", "gpt-5.4-nano")
TRANSCRIPT_MODEL = os.getenv("TRANSCRIPT_MODEL", "gpt-5.4-nano")
APP_ENV = os.getenv("APP_ENV", "development")
CORS_ALLOWED_ORIGINS = [
    origin.strip()
    for origin in os.getenv("CORS_ALLOWED_ORIGINS", "").split(",")
    if origin.strip()
]
if not CORS_ALLOWED_ORIGINS and APP_ENV != "production":
    CORS_ALLOWED_ORIGINS = [
        "http://localhost:3000",
        "http://127.0.0.1:3000",
        "http://localhost:5173",
        "http://127.0.0.1:5173",
    ]

SUPABASE_URL = os.getenv("SUPABASE_URL", "").rstrip("/")
SUPABASE_ANON_KEY = os.getenv("SUPABASE_ANON_KEY", "")
SUPABASE_SERVICE_ROLE_KEY = os.getenv("SUPABASE_SERVICE_ROLE_KEY", "")

DATA_DIR = os.path.join(os.path.dirname(__file__), "..", "data")
COURSES_DIR = os.path.join(DATA_DIR, "courses")
CATALOG_DIR = os.path.join(DATA_DIR, "catalog")
COE_DIR = os.path.join(DATA_DIR, "coe")

VT_FULL_CATALOG_PATH = os.path.join(DATA_DIR, "vt_full_catalog.json")
VT_SUBJECTS_PATH = os.path.join(DATA_DIR, "vt_subjects.json")
VT_PROGRAMS_PATH = os.path.join(DATA_DIR, "vt_programs.json")

os.makedirs(COURSES_DIR, exist_ok=True)
os.makedirs(CATALOG_DIR, exist_ok=True)
