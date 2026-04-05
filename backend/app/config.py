import os
from dotenv import load_dotenv

load_dotenv()

OPENAI_API_KEY = os.getenv("OPENAI_API_KEY", "")
OPENAI_MODEL = os.getenv("OPENAI_MODEL", "gpt-5.4-nano")
APP_ENV = os.getenv("APP_ENV", "development")

DATA_DIR = os.path.join(os.path.dirname(__file__), "..", "data")
COURSES_DIR = os.path.join(DATA_DIR, "courses")
CATALOG_DIR = os.path.join(DATA_DIR, "catalog")

VT_FULL_CATALOG_PATH = os.path.join(DATA_DIR, "vt_full_catalog.json")
VT_SUBJECTS_PATH = os.path.join(DATA_DIR, "vt_subjects.json")
VT_PROGRAMS_PATH = os.path.join(DATA_DIR, "vt_programs.json")

os.makedirs(COURSES_DIR, exist_ok=True)
os.makedirs(CATALOG_DIR, exist_ok=True)
