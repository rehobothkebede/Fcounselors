export const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
};

export type UploadedFile = {
  fileName: string;
  mimeType: string;
  bytes: Uint8Array;
  size: number;
};

export type AuthContext = {
  userId: string | null;
  response?: Response;
};

type OpenAIJsonInput = {
  prompt: string;
  fileName: string;
  mimeType: string;
  bytes: Uint8Array;
  errorCodePrefix: string;
};

export function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
    },
  });
}

export function errorResponse(code: string, message: string, status: number): Response {
  return json({ detail: { code, message } }, status);
}

export function methodNotAllowed(): Response {
  return errorResponse("METHOD_NOT_ALLOWED", "Method not allowed.", 405);
}

export function openAIModel(): string {
  return Deno.env.get("OPENAI_TRANSCRIPT_MODEL") ||
    Deno.env.get("TRANSCRIPT_MODEL") ||
    "gpt-5.5";
}

export async function readMultipartFile(
  req: Request,
  allowedTypes: Set<string>,
  maxBytes: number,
  codePrefix: string,
  noun: string,
): Promise<UploadedFile | Response> {
  let formData: FormData;
  try {
    formData = await req.formData();
  } catch {
    return errorResponse(`${codePrefix}_INVALID_FORM`, "Upload a file using multipart/form-data.", 400);
  }

  const file = formData.get("file");
  if (!(file instanceof File)) {
    return errorResponse(`${codePrefix}_FILE_REQUIRED`, "Choose a file to upload.", 400);
  }

  const mimeType = normalizeMimeType(file.type);
  if (!allowedTypes.has(mimeType)) {
    return errorResponse(
      `${codePrefix}_UNSUPPORTED_FILE_TYPE`,
      `Unsupported file type '${mimeType || "unknown"}'. Upload a ${noun} PDF, PNG, or JPG.`,
      415,
    );
  }

  if (file.size > maxBytes) {
    return errorResponse(
      `${codePrefix}_FILE_TOO_LARGE`,
      `File too large. Maximum size is ${Math.floor(maxBytes / 1024 / 1024)} MB.`,
      413,
    );
  }

  if (file.size === 0) {
    return errorResponse(`${codePrefix}_FILE_EMPTY`, "Uploaded file is empty.", 400);
  }

  const buffer = await file.arrayBuffer();
  return {
    fileName: file.name || "upload",
    mimeType,
    bytes: new Uint8Array(buffer),
    size: file.size,
  };
}

export async function extractJsonFromOpenAI(input: OpenAIJsonInput): Promise<Record<string, unknown> | Response> {
  const openAIKey = Deno.env.get("OPENAI_API_KEY");
  if (!openAIKey) {
    return errorResponse(
      `${input.errorCodePrefix}_AI_NOT_CONFIGURED`,
      "We could not analyze your file right now. Check your connection and try again.",
      503,
    );
  }

  const content = fileContent(input);
  const body = {
    model: openAIModel(),
    input: [
      {
        role: "user",
        content,
      },
    ],
    max_output_tokens: 5000,
  };

  let response: Response;
  try {
    response = await fetch("https://api.openai.com/v1/responses", {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${openAIKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(body),
      signal: AbortSignal.timeout(110_000),
    });
  } catch (error) {
    const isTimeout = error instanceof DOMException && error.name === "TimeoutError";
    return errorResponse(
      isTimeout ? `${input.errorCodePrefix}_AI_TIMEOUT` : `${input.errorCodePrefix}_AI_REQUEST_FAILED`,
      "We could not analyze your file right now. Check your connection and try again.",
      isTimeout ? 504 : 502,
    );
  }

  if (!response.ok) {
    console.warn(`${input.errorCodePrefix} OpenAI request failed with status ${response.status}`);
    return errorResponse(
      `${input.errorCodePrefix}_AI_REQUEST_FAILED`,
      "We could not analyze your file right now. Check your connection and try again.",
      502,
    );
  }

  let data: Record<string, unknown>;
  try {
    data = await response.json();
  } catch {
    return errorResponse(
      `${input.errorCodePrefix}_AI_INVALID_RESPONSE`,
      "The file analyzer returned an unreadable response. Please try again.",
      502,
    );
  }

  const contentText = responseOutputText(data);
  if (!contentText) {
    return errorResponse(
      `${input.errorCodePrefix}_AI_EMPTY_RESPONSE`,
      "The file analyzer returned an empty response. Please try again.",
      502,
    );
  }

  try {
    return JSON.parse(stripJsonFence(contentText));
  } catch {
    return errorResponse(
      `${input.errorCodePrefix}_AI_INVALID_JSON`,
      "The file analyzer returned course data the app could not read. Please try again.",
      502,
    );
  }
}

export async function resolveAuthContext(req: Request): Promise<AuthContext> {
  const authorization = req.headers.get("authorization") || "";
  const token = authorization.toLowerCase().startsWith("bearer ")
    ? authorization.slice("bearer ".length).trim()
    : "";
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") || "";

  if (!token || token === anonKey) {
    return { userId: null };
  }

  const supabaseURL = Deno.env.get("SUPABASE_URL");
  if (!supabaseURL || !anonKey) {
    return { userId: null };
  }

  const userResponse = await fetch(`${supabaseURL}/auth/v1/user`, {
    headers: {
      "apikey": anonKey,
      "Authorization": `Bearer ${token}`,
    },
  });

  if (!userResponse.ok) {
    return {
      userId: null,
      response: errorResponse("AUTH_INVALID_SESSION", "Invalid or expired session. Please sign in again.", 401),
    };
  }

  const user = await userResponse.json();
  return { userId: typeof user?.id === "string" ? user.id : null };
}

export async function persistRows(
  table: string,
  rows: Record<string, unknown>[],
  options: { returnRepresentation?: boolean } = {},
): Promise<Record<string, unknown>[] | null> {
  if (!rows.length) return null;

  const supabaseURL = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseURL || !serviceRoleKey) {
    return null;
  }

  const response = await fetch(`${supabaseURL}/rest/v1/${table}`, {
    method: "POST",
    headers: {
      "apikey": serviceRoleKey,
      "Authorization": `Bearer ${serviceRoleKey}`,
      "Content-Type": "application/json",
      "Prefer": options.returnRepresentation ? "return=representation" : "return=minimal",
    },
    body: JSON.stringify(rows),
  });

  if (!response.ok) {
    const detail = await safeErrorText(response);
    console.warn(`Optional Supabase persistence failed for ${table}: ${detail}`);
    return null;
  }

  if (!options.returnRepresentation) {
    return null;
  }

  try {
    return await response.json();
  } catch {
    return null;
  }
}

export function normalizeMimeType(value: string): string {
  const normalized = (value || "").split(";")[0].trim().toLowerCase();
  if (normalized === "image/jpg") return "image/jpeg";
  return normalized;
}

export function normalizeCode(code: unknown): string {
  const raw = String(code || "").trim().toUpperCase().replaceAll("-", " ");
  const match = raw.match(/([A-Z]{2,4})\s*(\d{4}[A-Z]?)/);
  return match ? `${match[1]} ${match[2]}` : raw;
}

export function normalizeGrade(grade: unknown): string | null {
  if (grade === null || grade === undefined || grade === "") return null;
  const normalized = String(grade).trim().toUpperCase();
  if (normalized === "TRANSFER" || normalized === "TR") return "T";
  if (normalized === "PASS") return "P";
  if (normalized === "CREDIT") return "CR";
  return normalized;
}

export function numberOrNull(value: unknown): number | null {
  if (value === null || value === undefined || value === "") return null;
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : null;
}

export function stringArray(value: unknown): string[] {
  return Array.isArray(value) ? value.map((item) => String(item)).filter(Boolean) : [];
}

export function objectArray(value: unknown): Record<string, unknown>[] {
  return Array.isArray(value)
    ? value.filter((item): item is Record<string, unknown> => !!item && typeof item === "object" && !Array.isArray(item))
    : [];
}

export function slug(value: string): string {
  return value
    .toLowerCase()
    .replace(/[()/]/g, " ")
    .split(/\s+/)
    .filter(Boolean)
    .join("_");
}

async function safeErrorText(response: Response): Promise<string> {
  try {
    const data = await response.json();
    return (data?.error?.message || data?.message || data?.msg || JSON.stringify(data)).slice(0, 800);
  } catch {
    return (await response.text()).slice(0, 800);
  }
}

function fileContent(input: OpenAIJsonInput): unknown[] {
  const base64 = base64Encode(input.bytes);
  if (input.mimeType === "application/pdf") {
    return [
      {
        type: "input_file",
        filename: input.fileName,
        file_data: `data:${input.mimeType};base64,${base64}`,
      },
      {
        type: "input_text",
        text: input.prompt,
      },
    ];
  }

  return [
    {
      type: "input_text",
      text: input.prompt,
    },
    {
      type: "input_image",
      image_url: `data:${input.mimeType};base64,${base64}`,
      detail: "high",
    },
  ];
}

function responseOutputText(data: Record<string, unknown>): string {
  if (typeof data.output_text === "string") {
    return data.output_text;
  }

  const output = Array.isArray(data.output) ? data.output : [];
  const parts: string[] = [];
  for (const item of output) {
    if (!item || typeof item !== "object" || Array.isArray(item)) continue;
    const content = (item as Record<string, unknown>).content;
    if (!Array.isArray(content)) continue;
    for (const part of content) {
      if (!part || typeof part !== "object" || Array.isArray(part)) continue;
      const record = part as Record<string, unknown>;
      if (typeof record.text === "string") parts.push(record.text);
    }
  }
  return parts.join("\n");
}

function stripJsonFence(value: string): string {
  return value
    .trim()
    .replace(/^```(?:json)?\s*/i, "")
    .replace(/\s*```$/i, "")
    .trim();
}

function base64Encode(bytes: Uint8Array): string {
  let binary = "";
  const chunkSize = 0x8000;
  for (let i = 0; i < bytes.length; i += chunkSize) {
    const chunk = bytes.subarray(i, i + chunkSize);
    binary += String.fromCharCode(...chunk);
  }
  return btoa(binary);
}
