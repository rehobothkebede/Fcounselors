import {
  corsHeaders,
  errorResponse,
  extractJsonFromOpenAI,
  json,
  methodNotAllowed,
  numberOrNull,
  objectArray,
  persistRows,
  readMultipartFile,
  resolveAuthContext,
  slug,
  stringArray,
} from "../_shared/academic.ts";

const ALLOWED_TYPES = new Set(["application/pdf", "image/png", "image/jpeg"]);
const MAX_BYTES = 12 * 1024 * 1024;

const DARS_EXTRACT_PROMPT = `You are parsing an official Virginia Tech uAchieve/DARS degree audit report.

Extract the audit exactly as the report presents it. uAchieve/DARS is the source of truth.
Do not infer missing requirements from a checksheet. Only report what is visible in the audit.

Return ONLY valid JSON in this exact structure:
{
  "student_name": null,
  "student_id": null,
  "program": null,
  "program_code": null,
  "catalog_year": null,
  "graduation_date": null,
  "prepared_on": null,
  "job_id": null,
  "audit_type": null,
  "university_gpa": null,
  "in_major_gpa": null,
  "categories": [
    {
      "id": "major",
      "title": "Major",
      "status": "in_progress",
      "complete_hours": null,
      "in_progress_hours": null,
      "unfulfilled_hours": null,
      "planned_hours": 0,
      "required_hours": null,
      "gpa": null,
      "notes": []
    }
  ],
  "sections": [
    {
      "title": "Requirement section title",
      "status": "complete",
      "matched_courses": ["CS 1114"],
      "missing_items": [],
      "notes": []
    }
  ],
  "warnings": ["any unreadable or ambiguous data"]
}

STATUS RULES:
- Use exactly one of: "complete", "in_progress", "unfulfilled", "planned", "unknown".
- Green/complete graph regions map to complete_hours.
- Blue/in-progress graph regions map to in_progress_hours.
- Red/unfulfilled graph regions map to unfulfilled_hours.
- Purple/planned graph regions map to planned_hours.
- If a category row appears but exact numbers are not printed, estimate only if the report graph visibly labels them; otherwise use null and add a warning.

COMMON TOP-LEVEL CATEGORIES:
- University GPA
- Minimum Hours
- Major
- General Ed
- In Major GPA
- Electives
- Minor(s)

COURSE HISTORY:
- If the Course History tab or expanded sections are present, extract course codes, grades, transfer markers, and terms into sections.
- Transfer grades T/TR/TRANSFER mean awarded transfer credit.

Keep every string short and preserve official DARS wording where possible.`;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return methodNotAllowed();
  }

  const auth = await resolveAuthContext(req);
  if (auth.response) return auth.response;

  const upload = await readMultipartFile(req, ALLOWED_TYPES, MAX_BYTES, "DARS", "DARS");
  if (upload instanceof Response) return upload;

  const extracted = await extractJsonFromOpenAI({
    prompt: DARS_EXTRACT_PROMPT,
    fileName: upload.fileName,
    mimeType: upload.mimeType,
    bytes: upload.bytes,
    errorCodePrefix: "DARS",
  });
  if (extracted instanceof Response) return extracted;

  const result = normalizeDarsAudit(extracted);
  if (!hasVisibleDarsEvidence(result)) {
    return errorResponse(
      "DARS_PARSE_FAILED",
      "We could not read an official DARS audit from this file. Upload a readable DARS PDF, PNG, or JPG.",
      422,
    );
  }

  await persistDarsAudit(auth.userId, result);
  return json(result);
});

type DarsAudit = {
  student_name: string | null;
  student_id: string | null;
  program: string | null;
  program_code: string | null;
  catalog_year: string | null;
  graduation_date: string | null;
  prepared_on: string | null;
  job_id: string | null;
  audit_type: string | null;
  university_gpa: number | null;
  in_major_gpa: number | null;
  categories: DarsCategory[];
  sections: DarsSection[];
  warnings: string[];
};

type DarsCategory = {
  id: string;
  title: string;
  status: string;
  complete_hours: number | null;
  in_progress_hours: number | null;
  unfulfilled_hours: number | null;
  planned_hours: number | null;
  required_hours: number | null;
  gpa: number | null;
  notes: string[];
};

type DarsSection = {
  title: string;
  status: string;
  matched_courses: string[];
  missing_items: string[];
  notes: string[];
};

function normalizeDarsAudit(raw: Record<string, unknown>): DarsAudit {
  return {
    student_name: optionalString(raw.student_name),
    student_id: optionalString(raw.student_id),
    program: optionalString(raw.program),
    program_code: optionalString(raw.program_code),
    catalog_year: optionalString(raw.catalog_year),
    graduation_date: optionalString(raw.graduation_date),
    prepared_on: optionalString(raw.prepared_on),
    job_id: optionalString(raw.job_id),
    audit_type: optionalString(raw.audit_type),
    university_gpa: numberOrNull(raw.university_gpa),
    in_major_gpa: numberOrNull(raw.in_major_gpa),
    categories: objectArray(raw.categories).map(normalizeCategory),
    sections: objectArray(raw.sections).map(normalizeSection),
    warnings: stringArray(raw.warnings),
  };
}

function normalizeCategory(category: Record<string, unknown>): DarsCategory {
  const title = optionalString(category.title) || "Unknown";
  return {
    id: optionalString(category.id) || slug(title),
    title,
    status: normalizeStatus(category.status),
    complete_hours: numberOrNull(category.complete_hours),
    in_progress_hours: numberOrNull(category.in_progress_hours),
    unfulfilled_hours: numberOrNull(category.unfulfilled_hours),
    planned_hours: numberOrNull(category.planned_hours),
    required_hours: numberOrNull(category.required_hours),
    gpa: numberOrNull(category.gpa),
    notes: stringArray(category.notes),
  };
}

function normalizeSection(section: Record<string, unknown>): DarsSection {
  return {
    title: optionalString(section.title) || "Requirement",
    status: normalizeStatus(section.status),
    matched_courses: stringArray(section.matched_courses),
    missing_items: stringArray(section.missing_items),
    notes: stringArray(section.notes),
  };
}

function normalizeStatus(status: unknown): string {
  const normalized = String(status || "unknown").trim().toLowerCase().replaceAll("-", "_").replaceAll(" ", "_");
  if (
    ["unfulfilled", "incomplete", "missing", "not_satisfied"].includes(normalized) ||
    normalized.includes("unfulfilled") ||
    normalized.includes("incomplete") ||
    normalized.includes("missing")
  ) return "unfulfilled";
  if (["in_progress", "progress", "partial"].includes(normalized) || normalized.includes("in_progress")) return "in_progress";
  if (["complete", "completed", "satisfied"].includes(normalized) || normalized.includes("complete")) return "complete";
  if (["planned", "plan"].includes(normalized) || normalized.includes("planned")) return "planned";
  return "unknown";
}

function optionalString(value: unknown): string | null {
  const stringValue = String(value || "").trim();
  return stringValue ? stringValue : null;
}

function hasVisibleDarsEvidence(result: DarsAudit): boolean {
  const lowerWarnings = result.warnings.join(" ").toLowerCase();
  if (
    lowerWarnings.includes("no readable") ||
    lowerWarnings.includes("not readable") ||
    lowerWarnings.includes("prompt template") ||
    lowerWarnings.includes("schema") ||
    lowerWarnings.includes("only an image")
  ) {
    return false;
  }

  if (result.categories.length === 0 && result.sections.length === 0) {
    return false;
  }

  return result.categories.some((category) =>
    category.complete_hours !== null ||
    category.in_progress_hours !== null ||
    category.unfulfilled_hours !== null ||
    category.required_hours !== null ||
    category.gpa !== null ||
    category.notes.length > 0
  ) || result.sections.some((section) =>
    section.matched_courses.length > 0 ||
    section.missing_items.length > 0 ||
    section.notes.length > 0
  ) || !!(
    result.program ||
    result.program_code ||
    result.catalog_year ||
    result.prepared_on ||
    result.university_gpa !== null ||
    result.in_major_gpa !== null
  );
}

async function persistDarsAudit(userId: string | null, result: DarsAudit) {
  if (!userId) return;
  await persistRows("dars_audits", [
    {
      user_id: userId,
      student_id: result.student_id,
      program: result.program,
      program_code: result.program_code,
      catalog_year: result.catalog_year,
      prepared_on: result.prepared_on,
      response: result,
    },
  ]);
}
