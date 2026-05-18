"""
Parses the VT Pathways Course Guide (alpha-sorted PDF) and writes
backend/data/pathways.json organized by pathway concept and subsection.
"""

import json
import re
from pathlib import Path

import pdfplumber

PDF_PATH = Path(__file__).parent.parent / "data" / "catalog" / "Pathways Course Guide by Alpha 25-26.pdf"
OUT_PATH = Path(__file__).parent.parent / "data" / "pathways.json"

PATHWAY_META = {
    "1f": {"concept": 1, "section_id": "1f", "section_name": "Foundational",
           "concept_name": "Discourse",
           "credit_hours": "9 total: 6 foundational + 3 advanced/applied"},
    "1a": {"concept": 1, "section_id": "1a", "section_name": "Advanced/Applied",
           "concept_name": "Discourse",
           "credit_hours": "9 total: 6 foundational + 3 advanced/applied"},
    "2":  {"concept": 2, "section_id": "2",  "section_name": None,
           "concept_name": "Critical Thinking in the Humanities",
           "credit_hours": "6 credits"},
    "3":  {"concept": 3, "section_id": "3",  "section_name": None,
           "concept_name": "Reasoning in the Social Sciences",
           "credit_hours": "6 credits"},
    "4":  {"concept": 4, "section_id": "4",  "section_name": None,
           "concept_name": "Reasoning in the Natural Sciences",
           "credit_hours": "6 credits (+ 2 lab credits for some majors)"},
    "5f": {"concept": 5, "section_id": "5f", "section_name": "Foundational",
           "concept_name": "Quantitative and Computational Thinking",
           "credit_hours": "9 total: 3 foundational + 3 advanced/applied + 3 either"},
    "5a": {"concept": 5, "section_id": "5a", "section_name": "Advanced/Applied",
           "concept_name": "Quantitative and Computational Thinking",
           "credit_hours": "9 total: 3 foundational + 3 advanced/applied + 3 either"},
    "6a": {"concept": 6, "section_id": "6a", "section_name": "Arts",
           "concept_name": "Critique and Practice in Design and the Arts",
           "credit_hours": "6 credits: 3 design + 3 arts, or 6 integrated"},
    "6d": {"concept": 6, "section_id": "6d", "section_name": "Design",
           "concept_name": "Critique and Practice in Design and the Arts",
           "credit_hours": "6 credits: 3 design + 3 arts, or 6 integrated"},
    "7":  {"concept": 7, "section_id": "7",  "section_name": None,
           "concept_name": "Critical Analysis of Identity and Equity in the United States",
           "credit_hours": "3 credits (double-counted with another concept)"},
}


def parse_concepts(raw: str) -> list[str]:
    """'3 AND 7' -> ['3', '7'],  '2 OR 3' -> ['2', '3'],  '6a OR 6d' -> ['6a', '6d']"""
    if not raw:
        return []
    tokens = re.split(r"\s+(?:AND|OR)\s+", raw.strip())
    return [t.strip() for t in tokens if t.strip()]


def parse_prerequisites(raw: str) -> list[str]:
    if not raw:
        return []
    # each prereq looks like "SUBJ-NNNN/UG/P" or similar; strip the /UG/P suffix
    codes = re.findall(r"[A-Z]{2,4}-\d{4}[A-Z]?(?:/[A-Z]+)*", raw)
    clean = []
    for c in codes:
        c = re.sub(r"(/UG/P|/UG|/P)$", "", c).replace("-", " ")
        clean.append(c)
    return clean


def extract_all_rows() -> list[dict]:
    rows = []
    with pdfplumber.open(PDF_PATH) as pdf:
        for page in pdf.pages:
            tables = page.extract_tables()
            for table in tables:
                for row in table:
                    # skip header rows and empty rows
                    if not row or row[0] == "SUBJECT" or all(c is None or c == "" for c in row):
                        continue
                    subject, course_num, title, concept_raw, crosslist, prereq_raw, other_info, minors_raw = (
                        (row + [None] * 8)[:8]
                    )
                    if not subject or not course_num or not title:
                        continue
                    subject = (subject or "").strip()
                    course_num = (course_num or "").strip()
                    title = (title or "").strip().replace("\n", " ")
                    concept_raw = (concept_raw or "").strip()
                    crosslist = (crosslist or "").strip().replace("\n", " ")
                    prereq_raw = (prereq_raw or "").strip()
                    other_info = (other_info or "").strip().replace("\n", " ")
                    minors_raw = (minors_raw or "").strip().replace("\n", " ")

                    if not subject or not concept_raw:
                        continue

                    rows.append({
                        "code": f"{subject} {course_num}",
                        "subject": subject,
                        "number": course_num,
                        "name": title,
                        "concepts_raw": concept_raw,
                        "concepts": parse_concepts(concept_raw),
                        "crosslists": [c.strip() for c in crosslist.split(",") if c.strip()],
                        "prerequisites": parse_prerequisites(prereq_raw),
                        "prerequisites_raw": prereq_raw,
                        "other_info": other_info,
                        "pathways_minors": [m.strip() for m in minors_raw.split(",") if m.strip()],
                        "double_counts_concept_7": "7" in parse_concepts(concept_raw) and len(parse_concepts(concept_raw)) > 1,
                        "is_or_counted": " OR " in concept_raw,
                    })
    return rows


def build_json(rows: list[dict]) -> dict:
    # Build concept → section → courses structure
    # concept_num (int) → { meta, sections: { section_id → [courses] } }
    concepts: dict[int, dict] = {}

    for row in rows:
        for concept_key in row["concepts"]:
            if concept_key not in PATHWAY_META:
                continue
            meta = PATHWAY_META[concept_key]
            cnum = meta["concept"]

            if cnum not in concepts:
                concepts[cnum] = {
                    "concept": cnum,
                    "name": meta["concept_name"],
                    "credit_hours": meta["credit_hours"],
                    "sections": {},
                }

            sid = meta["section_id"]
            if sid not in concepts[cnum]["sections"]:
                concepts[cnum]["sections"][sid] = {
                    "id": sid,
                    "name": meta["section_name"],
                    "courses": [],
                }

            course_entry = {
                "code": row["code"],
                "name": row["name"],
                "has_prerequisites": bool(row["prerequisites"]),
                "prerequisites": row["prerequisites"],
                "prerequisites_raw": row["prerequisites_raw"],
                "crosslists": row["crosslists"],
                "pathways_minors": row["pathways_minors"],
                "other_info": row["other_info"],
                "double_counts_concept_7": row["double_counts_concept_7"],
                "is_or_counted": row["is_or_counted"],
            }
            concepts[cnum]["sections"][sid]["courses"].append(course_entry)

    # Convert to final sorted list
    pathway_list = []
    for cnum in sorted(concepts.keys()):
        c = concepts[cnum]
        sections_list = []
        for sid in sorted(c["sections"].keys()):
            sec = c["sections"][sid]
            sec["courses"] = sorted(sec["courses"], key=lambda x: x["code"])
            sections_list.append(sec)

        # If only one section with id == str(cnum), flatten (no subsections needed)
        pathway_list.append({
            "concept": c["concept"],
            "name": c["name"],
            "credit_hours": c["credit_hours"],
            "sections": sections_list,
        })

    return {
        "source": "VT Pathways Course Guide AY 2025-2026",
        "total_courses": len(rows),
        "pathways": pathway_list,
    }


if __name__ == "__main__":
    print("Parsing PDF…")
    rows = extract_all_rows()
    print(f"  Extracted {len(rows)} course-concept entries")

    data = build_json(rows)

    total = sum(
        len(sec["courses"])
        for p in data["pathways"]
        for sec in p["sections"]
    )
    print(f"  Built {len(data['pathways'])} pathways, {total} course-section entries")

    OUT_PATH.write_text(json.dumps(data, indent=2))
    print(f"  Written → {OUT_PATH}")

    # Quick summary
    for p in data["pathways"]:
        for sec in p["sections"]:
            label = f"{p['concept']}{sec['id'].replace(str(p['concept']), '')}" if sec["name"] else str(p["concept"])
            print(f"    Pathway {p['concept']} ({sec['id']}): {len(sec['courses'])} courses")
