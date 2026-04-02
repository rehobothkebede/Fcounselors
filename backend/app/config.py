import os
from dotenv import load_dotenv

load_dotenv()

OPENAI_API_KEY = os.getenv("OPENAI_API_KEY", "")
OPENAI_MODEL = os.getenv("OPENAI_MODEL", "gpt-5.4-nano")
APP_ENV = os.getenv("APP_ENV", "development")

DATA_DIR = os.path.join(os.path.dirname(__file__), "..", "data")
COURSES_DIR = os.path.join(DATA_DIR, "courses")

os.makedirs(COURSES_DIR, exist_ok=True)
