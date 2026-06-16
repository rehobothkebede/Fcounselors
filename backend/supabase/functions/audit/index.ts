import {
  corsHeaders,
  errorResponse,
  json,
  methodNotAllowed,
  normalizeCode,
  normalizeGrade,
  numberOrNull,
  persistRows,
  resolveAuthContext,
  stringArray,
} from "../_shared/academic.ts";

type TranscriptEntry = {
  code: string;
  name: string;
  grade: string | null;
  semester: string | null;
  credits: number;
};

type AuditBucket = {
  id: string;
  title: string;
  status: string;
  required_credits: number;
  completed_credits: number;
  required_count?: number | null;
  completed_count?: number | null;
  matched_courses: string[];
  missing_items: string[];
  notes: string[];
};

type DegreeAuditResponse = {
  major: string;
  degree: string;
  catalog_year: string;
  total_required_credits: number;
  completed_credits: number;
  percent_complete: number;
  complete_bucket_count: number;
  total_bucket_count: number;
  buckets: AuditBucket[];
  warnings: string[];
};

type CourseRequirement = {
  code: string;
  name: string;
  credits: number;
  gradeRequired?: "C";
};

const TOTAL_REQUIRED_CREDITS = 123;
const FREE_ELECTIVE_CREDITS = 10;

const GRADE_POINTS: Record<string, number> = {
  "A": 4.0,
  "A-": 3.7,
  "B+": 3.3,
  "B": 3.0,
  "B-": 2.7,
  "C+": 2.3,
  "C": 2.0,
  "C-": 1.7,
  "D+": 1.3,
  "D": 1.0,
  "D-": 0.7,
  "F": 0.0,
  "W": 0.0,
  "WF": 0.0,
};

const NON_CREDIT_GRADES = new Set(["F", "W", "WF", "I", "NG"]);
const AWARDED_CREDIT_GRADES = new Set(["P", "PASS", "CR", "CREDIT", "T", "TR", "TRANSFER"]);

const REQUIRED_COURSES: CourseRequirement[] = [
  { code: "CS 1114", name: "Intro to Software Design", credits: 3, gradeRequired: "C" },
  { code: "ENGE 1215", name: "Foundations of Engineering", credits: 2 },
  { code: "ENGL 1105", name: "First-Year Writing", credits: 3 },
  { code: "MATH 1225", name: "Calculus of a Single Variable I", credits: 4 },
  { code: "CS 2114", name: "Software Design & Data Structures", credits: 3, gradeRequired: "C" },
  { code: "ENGE 1216", name: "Foundations of Engineering", credits: 2 },
  { code: "ENGL 1106", name: "First-Year Writing", credits: 3 },
  { code: "MATH 1226", name: "Calculus of a Single Variable II", credits: 4 },
  { code: "CS 1944", name: "CS First Year Seminar", credits: 1 },
  { code: "CS 2104", name: "Intro to Problem Solving in CS", credits: 3, gradeRequired: "C" },
  { code: "CS 2505", name: "Intro to Computer Organization I", credits: 3, gradeRequired: "C" },
  { code: "MATH 2534", name: "Intro to Discrete Mathematics", credits: 3 },
  { code: "CS 2506", name: "Intro to Computer Organization II", credits: 3, gradeRequired: "C" },
  { code: "MATH 2114", name: "Intro to Linear Algebra", credits: 3 },
  { code: "MATH 2204", name: "Intro to Multivariable Calculus", credits: 3 },
  { code: "CS 3114", name: "Data Structures & Algorithms", credits: 3, gradeRequired: "C" },
  { code: "MATH 3134", name: "Applied Combinatorics", credits: 3 },
  { code: "ENGE 3900", name: "Bridge Experience", credits: 0 },
  { code: "CS 3214", name: "Computer Systems", credits: 3 },
  { code: "CS 3604", name: "Professionalism in Computing", credits: 3 },
  { code: "CS 3304", name: "Comparative Languages", credits: 3 },
  { code: "CS 4944", name: "CS Seminar", credits: 1 },
  { code: "CS 4094", name: "Computer Science Capstone", credits: 3 },
];

const SUBSTITUTIONS: Record<string, string[]> = {
  "ENGE 1215": ["ENGE 1414"],
  "ENGE 1216": ["ENGE 1414"],
  "MATH 2114": ["MATH 2405H", "MATH 2406H"],
  "MATH 2204": ["MATH 2405H", "MATH 2406H"],
  "CS 1114": ["CS 2064", "ECE 2514"],
  "CS 2114": ["ECE 3514"],
  "CS 2505": ["ECE 2564"],
};

const NATURAL_SCIENCE = new Set(["BIOL 1105", "BIOL 1115", "CHEM 1035", "CHEM 1045", "PHYS 2305"]);
const ADVANCED_SCIENCE = new Set(["BIOL 1106", "BIOL 1116", "CHEM 1036", "CHEM 1046", "PHYS 2306"]);
const COMMUNICATIONS = new Set(["COMM 2004", "COMM 2014"]);
const WRITING = new Set(["ENGL 3764", "ENGL 3804", "ENGL 3814", "ENGL 3824", "ENGL 3834", "ENGL 3844", "ENGL 4824"]);

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return methodNotAllowed();
  }

  const auth = await resolveAuthContext(req);
  if (auth.response) return auth.response;

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return errorResponse("AUDIT_INVALID_JSON", "Invalid JSON body.", 400);
  }

  const major = String(body.major || "Computer Science").trim();
  if (!major) {
    return errorResponse("AUDIT_MAJOR_REQUIRED", "major cannot be empty", 400);
  }
  if (!["computer science", "cs", "computer science bs", "computer science b.s."].includes(major.toLowerCase())) {
    return errorResponse("AUDIT_INVALID_REQUEST", "Degree audit currently supports Computer Science B.S. only.", 400);
  }

  const transcript = Array.isArray(body.transcript) ? body.transcript.map(normalizeEntry).filter((entry) => entry.code) : [];
  const inProgressCourses = stringArray(body.in_progress_courses).map(normalizeCode).filter(Boolean);
  const result = await runDegreeAudit(transcript, inProgressCourses);
  await persistDegreeAudit(auth.userId, result);
  return json(result);
});

async function runDegreeAudit(transcript: TranscriptEntry[], inProgressCourses: string[]): Promise<DegreeAuditResponse> {
  const inProgress = new Set(inProgressCourses);
  const courseAttempts = groupAttempts(transcript);
  const passingCourses = transcript.filter((course) => isPassing(course.grade));
  const passingCodes = new Set(passingCourses.map((course) => course.code));
  const totalCompletedCredits = passingCourses.reduce((sum, course) => sum + (course.credits || 0), 0);

  const { buckets: requiredBuckets, retakes, satisfiedCodes } = auditRequiredCourses(courseAttempts, passingCodes, inProgress);
  const electiveResult = auditElectives(passingCourses, satisfiedCodes);
  const pathwaysBuckets = await auditPathways(passingCourses, passingCodes);

  const usedBeforeFree = new Set([...satisfiedCodes, ...electiveResult.usedCodes]);
  const freeCourses = passingCourses.filter((course) => !usedBeforeFree.has(course.code));
  const freeCompleted = freeCourses.reduce((sum, course) => sum + (course.credits || 0), 0);
  const freeBucket = bucket({
    id: "free_elective",
    title: "Free Electives / Overflow Credits",
    requiredCredits: FREE_ELECTIVE_CREDITS,
    completedCredits: Math.min(freeCompleted, FREE_ELECTIVE_CREDITS),
    matchedCourses: courseLabels(freeCourses).slice(0, 12),
    missingItems: freeCompleted < FREE_ELECTIVE_CREDITS ? [`${Math.floor(FREE_ELECTIVE_CREDITS - freeCompleted)} more credits`] : [],
    notes: ["Pathways 7 is suspended for this catalog; the replacement credits are counted here."],
  });

  const totalBucket = bucket({
    id: "total_credits",
    title: "Total Credits",
    requiredCredits: TOTAL_REQUIRED_CREDITS,
    completedCredits: totalCompletedCredits,
    matchedCourses: [],
    missingItems: totalCompletedCredits < TOTAL_REQUIRED_CREDITS ? [`${Math.floor(TOTAL_REQUIRED_CREDITS - totalCompletedCredits)} more credits`] : [],
    notes: [`${Math.floor(totalCompletedCredits)} of ${TOTAL_REQUIRED_CREDITS} credits completed.`],
  });

  const buckets = [totalBucket, ...requiredBuckets, ...electiveResult.buckets, freeBucket, ...pathwaysBuckets];
  const completeBucketCount = buckets.filter((item) => item.status === "complete").length;
  const warnings: string[] = [];
  if (retakes.length) warnings.push(`Retake required: ${retakes.join(", ")}`);
  warnings.push(...electiveResult.notes);

  return {
    major: "Computer Science",
    degree: "B.S.",
    catalog_year: "2025-2026",
    total_required_credits: TOTAL_REQUIRED_CREDITS,
    completed_credits: totalCompletedCredits,
    percent_complete: Math.min(Math.round((totalCompletedCredits / TOTAL_REQUIRED_CREDITS) * 100), 100),
    complete_bucket_count: completeBucketCount,
    total_bucket_count: buckets.length,
    buckets,
    warnings,
  };
}

function auditRequiredCourses(
  courseAttempts: Map<string, TranscriptEntry[]>,
  passingCodes: Set<string>,
  inProgress: Set<string>,
): { buckets: AuditBucket[]; retakes: string[]; satisfiedCodes: Set<string> } {
  const retakes: string[] = [];
  const satisfiedCodes = new Set<string>();
  const buckets: AuditBucket[] = [];

  for (const requirement of REQUIRED_COURSES) {
    const attempts = courseAttempts.get(requirement.code) || [];
    const directSatisfied = attempts.some((attempt) => courseSatisfies(attempt, requirement.gradeRequired));
    const substitute = satisfiedSubstitute(requirement, courseAttempts);
    const isInProgress = inProgress.has(requirement.code);

    const matched: string[] = [];
    const missing: string[] = [];
    const notes: string[] = [];
    let completedCredits = 0;
    let statusOverride: string | undefined;

    if (directSatisfied) {
      const best = bestAttempt(attempts);
      matched.push(courseLabel(best));
      completedCredits = requirement.credits || best.credits || 0;
      satisfiedCodes.add(requirement.code);
    } else if (substitute) {
      matched.push(`${substitute.code} substitutes for ${requirement.code}`);
      completedCredits = requirement.credits;
      satisfiedCodes.add(requirement.code);
    } else if (attempts.length && requirement.gradeRequired) {
      const best = bestAttempt(attempts);
      retakes.push(`${requirement.code} (${best.grade || "N/A"})`);
      missing.push(`${requirement.code} with ${requirement.gradeRequired} or better`);
      notes.push(`${requirement.code} requires ${requirement.gradeRequired} or better; ${best.grade || "N/A"} does not satisfy it.`);
      statusOverride = "attention";
    } else if (attempts.length && !attempts.some((attempt) => isPassing(attempt.grade))) {
      const best = bestAttempt(attempts);
      retakes.push(`${requirement.code} (${best.grade || "N/A"})`);
      missing.push(requirement.code);
      notes.push(`${requirement.code} was attempted but did not earn degree credit.`);
      statusOverride = "attention";
    } else if (isInProgress) {
      missing.push(`${requirement.code} in progress`);
      notes.push("Currently enrolled; will count after a passing final grade.");
      statusOverride = "in_progress";
    } else {
      missing.push(requirement.code);
    }

    buckets.push(bucket({
      id: `required_${requirement.code.toLowerCase().replaceAll(" ", "_")}`,
      title: `${requirement.code} - ${requirement.name}`,
      requiredCredits: requirement.credits,
      completedCredits,
      matchedCourses: matched,
      missingItems: missing,
      notes,
      statusOverride,
    }));
  }

  return { buckets, retakes, satisfiedCodes };
}

function auditElectives(
  passingCourses: TranscriptEntry[],
  satisfiedRequiredCodes: Set<string>,
): { buckets: AuditBucket[]; usedCodes: Set<string>; notes: string[] } {
  const usedCodes = new Set<string>();
  const available = passingCourses.filter((course) => !satisfiedRequiredCodes.has(course.code));
  const byCode = new Map(available.map((course) => [course.code, course]));

  const buckets = [
    creditBucketFromCodes("natural_science", "Natural Science Sequence", 8, NATURAL_SCIENCE, byCode, usedCodes),
    creditBucketFromCodes("advanced_natural_science", "Advanced Natural Science", 4, ADVANCED_SCIENCE, byCode, usedCodes),
    countBucketFromCodes("communications", "Communications Elective", 1, COMMUNICATIONS, byCode, usedCodes),
    countBucketFromCodes("professional_writing", "Professional Writing Elective", 1, WRITING, byCode, usedCodes),
  ];

  const upperCS = available.filter((course) =>
    !usedCodes.has(course.code) && subject(course.code) === "CS" && courseNumber(course.code) >= 3000
  );
  const upper45CS = upperCS.filter((course) => courseNumber(course.code) >= 4000);
  buckets.push(creditBucket("cs_3_4_5xxx", "CS 3/4/5XXX Electives", 6, upperCS.slice(0, 2), usedCodes));
  buckets.push(creditBucket("cs_4_5xxx", "CS 4/5XXX Elective", 3, upper45CS.slice(0, 1), usedCodes));

  const technical = available.filter((course) =>
    !usedCodes.has(course.code) &&
    (["CS", "ECE", "MATH", "STAT", "CMDA"].includes(subject(course.code)) || courseNumber(course.code) >= 3000)
  );
  buckets.push(creditBucket("cs_technical", "CS Technical Elective", 3, technical.slice(0, 1), usedCodes));

  buckets.push(bucket({
    id: "statistics_elective",
    title: "Statistics Elective",
    requiredCredits: 3,
    completedCredits: 0,
    matchedCourses: [],
    missingItems: ["approved statistics elective"],
    notes: ["Approved statistics options are not in the local catalog data yet."],
  }));
  buckets.push(bucket({
    id: "cs_theory_elective",
    title: "CS Theory Elective",
    requiredCredits: 3,
    completedCredits: 0,
    matchedCourses: [],
    missingItems: ["approved CS theory elective"],
    notes: ["Approved theory options are not in the local catalog data yet."],
  }));

  return {
    buckets,
    usedCodes,
    notes: ["Statistics and CS theory elective approved lists are not loaded yet, so those buckets stay open until that data is added."],
  };
}

async function auditPathways(passingCourses: TranscriptEntry[], passingCodes: Set<string>): Promise<AuditBucket[]> {
  const matched = await pathwayMatches(passingCourses);
  const naturalScienceCodes = new Set([...NATURAL_SCIENCE, ...ADVANCED_SCIENCE]);

  const buckets = [
    pathwayBucket("1f", "Pathways 1F - Foundational Discourse", 6, passingCourses.filter((course) => ["ENGL 1105", "ENGL 1106"].includes(course.code)), ["ENGL 1105", "ENGL 1106"]),
    pathwayBucket("1a", "Pathways 1A - Advanced Discourse", 3, matched.get("1a") || passingCourses.filter((course) => ["COMM 2004", "ENGL 3764"].includes(course.code)), ["3 credits advanced discourse"]),
    pathwayBucket("2", "Pathways 2 - Humanities", 6, matched.get("2") || [], ["6 credits humanities"]),
    pathwayBucket("3", "Pathways 3 - Social Sciences", 6, matched.get("3") || [], ["6 credits social sciences"]),
    pathwayBucket("4", "Pathways 4 - Natural Sciences", 8, passingCourses.filter((course) => naturalScienceCodes.has(course.code)), ["8 credits natural sciences"]),
    pathwayBucket("5f", "Pathways 5F - Foundational Quantitative", 8, passingCourses.filter((course) => ["MATH 1225", "MATH 1226"].includes(course.code)), ["MATH 1225", "MATH 1226"]),
    pathwayBucket("5a", "Pathways 5A - Advanced Quantitative", 3, passingCourses.filter((course) => course.code === "CS 3114"), ["CS 3114"]),
    pathwayBucket("6a", "Pathways 6A - Arts", 3, matched.get("6a") || [], ["3 credits arts"]),
    pathwayBucket("6d", "Pathways 6D - Design", 4, passingCourses.filter((course) => ["ENGE 1215", "ENGE 1216", "ENGE 1414"].includes(course.code)), ["ENGE 1215 + ENGE 1216 or ENGE 1414"]),
  ];

  buckets.push(bucket({
    id: "pathways_7",
    title: "Pathways 7 - Identity and Equity",
    requiredCredits: 0,
    completedCredits: 0,
    matchedCourses: courseLabels(matched.get("7") || passingCourses.filter((course) => passingCodes.has(course.code) && false)),
    missingItems: [],
    notes: ["Suspended as of Oct. 1, 2025 for this catalog; replacement credits count as free electives."],
    statusOverride: "complete",
  }));
  return buckets;
}

async function pathwayMatches(passingCourses: TranscriptEntry[]): Promise<Map<string, TranscriptEntry[]>> {
  const supabaseURL = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || Deno.env.get("SUPABASE_ANON_KEY");
  if (!supabaseURL || !serviceRoleKey || passingCourses.length === 0) {
    return new Map();
  }

  const uniqueCodes = [...new Set(passingCourses.map((course) => course.code))].slice(0, 120);
  const url = new URL(`${supabaseURL}/rest/v1/pathways_courses`);
  url.searchParams.set("select", "code,concept,raw");
  url.searchParams.set("code", `in.(${uniqueCodes.map((code) => `"${code.replaceAll('"', '""')}"`).join(",")})`);

  let response: Response;
  try {
    response = await fetch(url, {
      headers: {
        "apikey": serviceRoleKey,
        "Authorization": `Bearer ${serviceRoleKey}`,
      },
    });
  } catch {
    return new Map();
  }
  if (!response.ok) return new Map();

  const rows = await response.json();
  const byCode = new Map(passingCourses.map((course) => [course.code, course]));
  const matched = new Map<string, TranscriptEntry[]>();
  for (const row of Array.isArray(rows) ? rows : []) {
    const code = normalizeCode(row?.code);
    const course = byCode.get(code);
    if (!course) continue;
    const sectionId = typeof row?.raw?.section_id === "string" ? row.raw.section_id.toLowerCase() : String(row?.concept || "").toLowerCase();
    if (!sectionId) continue;
    if (!matched.has(sectionId)) matched.set(sectionId, []);
    matched.get(sectionId)?.push(course);
  }
  return matched;
}

function normalizeEntry(value: unknown): TranscriptEntry {
  const entry = value && typeof value === "object" && !Array.isArray(value) ? value as Record<string, unknown> : {};
  return {
    code: normalizeCode(entry.code),
    name: String(entry.name || ""),
    grade: normalizeGrade(entry.grade),
    semester: entry.semester ? String(entry.semester) : null,
    credits: numberOrNull(entry.credits) || 0,
  };
}

function groupAttempts(courses: TranscriptEntry[]): Map<string, TranscriptEntry[]> {
  const grouped = new Map<string, TranscriptEntry[]>();
  for (const course of courses) {
    if (!grouped.has(course.code)) grouped.set(course.code, []);
    grouped.get(course.code)?.push(course);
  }
  return grouped;
}

function satisfiedSubstitute(requirement: CourseRequirement, courseAttempts: Map<string, TranscriptEntry[]>): { code: string } | null {
  for (const code of SUBSTITUTIONS[requirement.code] || []) {
    const attempts = courseAttempts.get(code) || [];
    if (attempts.some((attempt) => courseSatisfies(attempt, "C"))) {
      return { code };
    }
  }
  return null;
}

function courseSatisfies(course: TranscriptEntry, requiredGrade?: "C"): boolean {
  if (!isPassing(course.grade)) return false;
  if (requiredGrade === "C") {
    if (isAwardedCreditGrade(course.grade)) return true;
    return (GRADE_POINTS[course.grade || ""] ?? -1) >= 2.0;
  }
  return true;
}

function isPassing(grade: string | null): boolean {
  const normalized = normalizeGrade(grade);
  if (!normalized || NON_CREDIT_GRADES.has(normalized)) return false;
  if (isAwardedCreditGrade(normalized)) return true;
  return (GRADE_POINTS[normalized] ?? 0) > 0;
}

function isAwardedCreditGrade(grade: string | null): boolean {
  const normalized = normalizeGrade(grade);
  return normalized ? AWARDED_CREDIT_GRADES.has(normalized) : false;
}

function bestAttempt(attempts: TranscriptEntry[]): TranscriptEntry {
  return attempts.reduce((best, course) => gradeRank(course.grade) > gradeRank(best.grade) ? course : best, attempts[0]);
}

function gradeRank(grade: string | null): number {
  const normalized = normalizeGrade(grade);
  if (isAwardedCreditGrade(normalized)) return 2.0;
  return GRADE_POINTS[normalized || ""] ?? -1;
}

function bucket(input: {
  id: string;
  title: string;
  requiredCredits: number;
  completedCredits: number;
  requiredCount?: number | null;
  completedCount?: number | null;
  matchedCourses: string[];
  missingItems: string[];
  notes: string[];
  statusOverride?: string;
}): AuditBucket {
  const status = input.statusOverride ||
    (input.completedCredits >= input.requiredCredits && (input.requiredCount === undefined || (input.completedCount || 0) >= input.requiredCount)
      ? "complete"
      : input.completedCredits > 0 || input.matchedCourses.length > 0
      ? "in_progress"
      : "incomplete");

  return {
    id: input.id,
    title: input.title,
    status,
    required_credits: input.requiredCredits,
    completed_credits: input.requiredCredits > 0 ? Math.min(input.completedCredits, input.requiredCredits) : input.completedCredits,
    required_count: input.requiredCount,
    completed_count: input.completedCount,
    matched_courses: input.matchedCourses,
    missing_items: input.missingItems,
    notes: input.notes,
  };
}

function creditBucketFromCodes(
  id: string,
  title: string,
  requiredCredits: number,
  codes: Set<string>,
  byCode: Map<string, TranscriptEntry>,
  usedCodes: Set<string>,
): AuditBucket {
  return creditBucket(id, title, requiredCredits, [...codes].map((code) => byCode.get(code)).filter((course): course is TranscriptEntry => !!course && !usedCodes.has(course.code)), usedCodes);
}

function countBucketFromCodes(
  id: string,
  title: string,
  requiredCount: number,
  codes: Set<string>,
  byCode: Map<string, TranscriptEntry>,
  usedCodes: Set<string>,
): AuditBucket {
  const courses = [...codes].map((code) => byCode.get(code)).filter((course): course is TranscriptEntry => !!course && !usedCodes.has(course.code));
  const selected = courses.slice(0, requiredCount);
  selected.forEach((course) => usedCodes.add(course.code));
  return bucket({
    id,
    title,
    requiredCredits: requiredCount * 3,
    completedCredits: selected.reduce((sum, course) => sum + (course.credits || 0), 0),
    requiredCount,
    completedCount: selected.length,
    matchedCourses: courseLabels(selected),
    missingItems: selected.length < requiredCount ? [`${requiredCount - selected.length} more course`] : [],
    notes: [],
  });
}

function creditBucket(id: string, title: string, requiredCredits: number, courses: TranscriptEntry[], usedCodes: Set<string>): AuditBucket {
  const selected: TranscriptEntry[] = [];
  let credits = 0;
  for (const course of courses) {
    if (usedCodes.has(course.code) || credits >= requiredCredits) continue;
    selected.push(course);
    credits += course.credits || 0;
  }
  selected.forEach((course) => usedCodes.add(course.code));
  return bucket({
    id,
    title,
    requiredCredits,
    completedCredits: credits,
    matchedCourses: courseLabels(selected),
    missingItems: credits < requiredCredits ? [`${Math.floor(requiredCredits - credits)} more credits`] : [],
    notes: [],
  });
}

function pathwayBucket(id: string, title: string, requiredCredits: number, courses: TranscriptEntry[], missingTemplate: string[]): AuditBucket {
  const unique = uniqueCourses(courses);
  const credits = unique.reduce((sum, course) => sum + (course.credits || 0), 0);
  return bucket({
    id: `pathways_${id}`,
    title,
    requiredCredits,
    completedCredits: credits,
    matchedCourses: courseLabels(unique),
    missingItems: credits < requiredCredits ? missingTemplate : [],
    notes: [],
  });
}

function uniqueCourses(courses: TranscriptEntry[]): TranscriptEntry[] {
  const seen = new Set<string>();
  const result: TranscriptEntry[] = [];
  for (const course of courses) {
    if (seen.has(course.code)) continue;
    seen.add(course.code);
    result.push(course);
  }
  return result;
}

function courseLabels(courses: TranscriptEntry[]): string[] {
  return uniqueCourses(courses).map(courseLabel);
}

function courseLabel(course: TranscriptEntry): string {
  const grade = course.grade ? ` (${course.grade})` : "";
  const creditValue = Number.isInteger(course.credits) ? String(course.credits) : String(course.credits);
  const credits = Number.isFinite(course.credits) ? ` - ${creditValue} cr` : "";
  return `${course.code}${grade}${credits}`;
}

function subject(code: string): string {
  return code.includes(" ") ? code.split(" ")[0] : code;
}

function courseNumber(code: string): number {
  const match = code.match(/(\d{4})/);
  return match ? Number(match[1]) : 0;
}

async function persistDegreeAudit(userId: string | null, result: DegreeAuditResponse) {
  if (!userId) return;
  await persistRows("degree_audits", [
    {
      user_id: userId,
      transcript_id: null,
      major: result.major,
      degree: result.degree,
      catalog_year: result.catalog_year,
      percent_complete: result.percent_complete,
      response: result,
    },
  ]);
}
