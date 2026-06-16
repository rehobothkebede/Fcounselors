import {
  corsHeaders,
  errorResponse,
  extractJsonFromOpenAI,
  json,
  methodNotAllowed,
  normalizeCode,
  normalizeGrade,
  numberOrNull,
  objectArray,
  openAIModel,
  persistRows,
  readMultipartFile,
  resolveAuthContext,
  stringArray,
} from "../_shared/academic.ts";

const ALLOWED_TYPES = new Set(["application/pdf", "image/png", "image/jpeg"]);
const MAX_BYTES = 10 * 1024 * 1024;

const EXTRACT_PROMPT = `You are parsing a Virginia Tech student academic transcript.

Current date: ${new Date().toISOString().slice(0, 10)}

Extract every course from this transcript into three lists: completed courses, in-progress courses,
and planned/future registered courses.

Return ONLY valid JSON in this exact structure:
{
  "courses": [
    {
      "code": "CS 2114",
      "name": "Software Design and Data Structures",
      "credits": 3,
      "grade": "A",
      "semester": "Fall 2023"
    }
  ],
  "in_progress_courses": [
    {
      "code": "CS 2104",
      "name": "Problem Solving in Science",
      "credits": 3,
      "semester": "Spring 2026"
    }
  ],
  "planned_courses": [
    {
      "code": "CS 2505",
      "name": "Computer Organization I",
      "credits": 3,
      "semester": "Fall 2026"
    }
  ],
  "warnings": ["list any ambiguous entries or data quality issues here"]
}

GRADE RULES:
- Standard letter grades (A, A+, A-, B+, B, B-, C+, C, C-, D+, D, D-): courses
- P or PASS: courses, use grade "P"
- CR or CREDIT: courses, use grade "CR"
- T, TR, or TRANSFER: courses, use grade "T"
- W, I, CD, withdrawals, incompletes, credit disallowed: exclude entirely
- Currently enrolled no-grade courses whose semester has started: in_progress_courses
- Future registered no-grade courses whose semester has not started: planned_courses
- Do not use quality points to decide completion; use the grade code

SEMESTER START HEURISTIC:
- Spring starts in January
- Summer starts in May
- Fall starts in August
- If unsure whether a no-grade course is in-progress or planned, use planned_courses and add a warning

COURSE CODE RULES:
- Use VT format "SUBJECT NNNN" such as "CS 2114"
- Transfer credits without a specific VT course number: use placeholder "SUBJ 1XXX" and warn that they count as electives only
- Include pathway/bridge codes such as "CS 1XXP" when visible
- credits must be numeric
- semester format: "Season YYYY"; use "Transfer" for AP/transfer credit without a VT semester

COURSE NAME RULES:
- Strip campus/institution prefixes such as "Blacksburg UG"; keep only the actual course title
- If the title is unreadable, use "Untitled course" and add a warning`;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return methodNotAllowed();
  }

  const auth = await resolveAuthContext(req);
  if (auth.response) return auth.response;

  const upload = await readMultipartFile(req, ALLOWED_TYPES, MAX_BYTES, "TRANSCRIPT", "transcript");
  if (upload instanceof Response) return upload;

  const extracted = await extractJsonFromOpenAI({
    prompt: EXTRACT_PROMPT,
    fileName: upload.fileName,
    mimeType: upload.mimeType,
    bytes: upload.bytes,
    errorCodePrefix: "TRANSCRIPT",
  });
  if (extracted instanceof Response) return extracted;

  const result = normalizeTranscriptResult(extracted);
  if (
    result.courses.length === 0 &&
    result.in_progress_courses.length === 0 &&
    result.planned_courses.length === 0
  ) {
    return errorResponse(
      "TRANSCRIPT_PARSE_FAILED",
      "We could not find transcript courses in this file. Upload a readable Virginia Tech transcript PDF, PNG, or JPG.",
      422,
    );
  }

  await persistTranscript(auth.userId, result, {
    fileName: upload.fileName,
    mimeType: upload.mimeType,
    size: upload.size,
  });

  return json({
    courses: result.courses,
    in_progress_courses: result.in_progress_courses,
    planned_courses: result.planned_courses,
    course_count: result.courses.length,
    warnings: result.warnings,
  });
});

type TranscriptCourse = {
  code: string;
  name: string;
  credits: number | null;
  grade?: string | null;
  semester?: string | null;
};

type OpenCourse = {
  code: string;
  name: string;
  credits: number | null;
  semester?: string | null;
};

type TranscriptResult = {
  courses: TranscriptCourse[];
  in_progress_courses: OpenCourse[];
  planned_courses: OpenCourse[];
  warnings: string[];
};

function normalizeTranscriptResult(raw: Record<string, unknown>): TranscriptResult {
  const warnings = stringArray(raw.warnings);
  const courses = objectArray(raw.courses).map((course) => normalizeCompletedCourse(course, warnings));
  const planned = objectArray(raw.planned_courses).map((course) => normalizeOpenCourse(course, warnings));

  const inProgress: OpenCourse[] = [];
  for (const course of objectArray(raw.in_progress_courses).map((item) => normalizeOpenCourse(item, warnings))) {
    if (course.semester && !semesterHasStarted(course.semester, new Date())) {
      planned.push(course);
      warnings.push(`${course.code || "A course"} is listed for ${course.semester}, which has not started yet; moved to planned_courses.`);
    } else {
      inProgress.push(course);
    }
  }

  return {
    courses: dedupeCourses(courses),
    in_progress_courses: dedupeCourses(inProgress),
    planned_courses: dedupeCourses(planned),
    warnings,
  };
}

function normalizeCompletedCourse(course: Record<string, unknown>, warnings: string[]): TranscriptCourse {
  const code = normalizeCode(course.code);
  return {
    code,
    name: courseName(course.name, code, warnings),
    credits: numberOrNull(course.credits),
    grade: normalizeGrade(course.grade),
    semester: optionalString(course.semester),
  };
}

function normalizeOpenCourse(course: Record<string, unknown>, warnings: string[]): OpenCourse {
  const code = normalizeCode(course.code);
  return {
    code,
    name: courseName(course.name, code, warnings),
    credits: numberOrNull(course.credits),
    semester: optionalString(course.semester),
  };
}

function courseName(value: unknown, code: string, warnings: string[]): string {
  const name = String(value || "").trim();
  if (name) return name;
  warnings.push(`${code || "Unknown course"} did not include a course title in the parser response.`);
  return "Untitled course";
}

function optionalString(value: unknown): string | null {
  const stringValue = String(value || "").trim();
  return stringValue ? stringValue : null;
}

function semesterHasStarted(semester: string, now: Date): boolean {
  const parts = semester.trim().split(/\s+/);
  if (parts.length !== 2) return true;
  const season = parts[0].toLowerCase();
  if (season === "transfer") return true;
  const year = Number(parts[1]);
  if (!Number.isFinite(year)) return true;

  const startMonth = {
    spring: 0,
    summer: 4,
    fall: 7,
    winter: 11,
  }[season];
  if (startMonth === undefined) return true;
  return new Date(year, startMonth, 1) <= now;
}

function dedupeCourses<T extends { code: string; semester?: string | null }>(courses: T[]): T[] {
  const seen = new Set<string>();
  const result: T[] = [];
  for (const course of courses) {
    const key = `${course.code}|${course.semester || ""}`;
    if (seen.has(key)) continue;
    seen.add(key);
    result.push(course);
  }
  return result;
}

async function persistTranscript(
  userId: string | null,
  result: TranscriptResult,
  metadata: { fileName: string; mimeType: string; size: number },
) {
  if (!userId) return;

  const inserted = await persistRows("transcripts", [
    {
      user_id: userId,
      source_type: "uploaded",
      parser_model: openAIModel(),
      transcript_notes: result.warnings,
      metadata: {
        file_name: metadata.fileName,
        content_type: metadata.mimeType,
        size_bytes: metadata.size,
        course_count: result.courses.length,
      },
    },
  ], { returnRepresentation: true });

  const transcriptId = inserted?.[0]?.id;
  if (typeof transcriptId !== "string") return;

  const rows = [
    ...result.courses.map((course) => ({
      transcript_id: transcriptId,
      user_id: userId,
      code: course.code,
      name: course.name,
      credits: course.credits,
      grade: course.grade,
      semester: course.semester,
      status: "completed",
      source: { parser: "transcript_edge_function" },
    })),
    ...result.in_progress_courses.map((course) => ({
      transcript_id: transcriptId,
      user_id: userId,
      code: course.code,
      name: course.name,
      credits: course.credits,
      grade: null,
      semester: course.semester,
      status: "in_progress",
      source: { parser: "transcript_edge_function" },
    })),
    ...result.planned_courses.map((course) => ({
      transcript_id: transcriptId,
      user_id: userId,
      code: course.code,
      name: course.name,
      credits: course.credits,
      grade: null,
      semester: course.semester,
      status: "planned",
      source: { parser: "transcript_edge_function" },
    })),
  ];

  await persistRows("transcript_courses", rows);
}
