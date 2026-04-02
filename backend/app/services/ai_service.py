from openai import OpenAI
from app.config import OPENAI_API_KEY, OPENAI_MODEL

client = OpenAI(api_key=OPENAI_API_KEY)

SYSTEM_PROMPT = """You are Fcounselors, an AI academic advisor for Virginia Tech students.
You help students with:
- Degree requirement planning
- Course selection and scheduling
- Major and minor exploration
- Academic milestone tracking
- Career-aligned course recommendations

Be concise, empathetic, and specific to Virginia Tech's curriculum when possible.
If you don't have specific VT data, say so honestly and give general guidance."""


def chat_with_advisor(messages: list) -> str:
    """
    Send a conversation to the AI advisor and return the response text.
    `messages` should be a list of {"role": "user"/"assistant", "content": "..."} dicts.
    """
    full_messages = [{"role": "system", "content": SYSTEM_PROMPT}] + messages

    response = client.chat.completions.create(
        model=OPENAI_MODEL,
        messages=full_messages,
        temperature=0.7,
        max_tokens=1024,
    )
    return response.choices[0].message.content


def summarize_course_data(raw_text: str) -> dict:
    """
    Given raw scraped course text, ask the AI to extract structured course info.
    Returns a dict with keys: name, code, credits, description, prerequisites.
    """
    prompt = f"""Extract structured course information from the following text.
Return ONLY valid JSON with these keys: name, code, credits, description, prerequisites (list of strings).

Text:
{raw_text[:3000]}"""

    response = client.chat.completions.create(
        model=OPENAI_MODEL,
        messages=[{"role": "user", "content": prompt}],
        temperature=0,
        max_tokens=512,
        response_format={"type": "json_object"},
    )
    import json
    return json.loads(response.choices[0].message.content)
