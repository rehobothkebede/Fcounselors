type ChatMessage = {
  role: "system" | "user" | "assistant" | "tool";
  content: string;
};

type TranscriptEntry = {
  code: string;
  name?: string;
  grade?: string | null;
  semester?: string | null;
  credits?: number | null;
};

type ChatRequest = {
  messages?: ChatMessage[];
  major?: string;
  transcript?: TranscriptEntry[];
  in_progress_courses?: string[];
  transcript_notes?: string[];
  chat_memories?: string[];
};

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const systemPrompt = `You are Hokie Advisor, a personalized academic advisor and CS/math tutor for Virginia Tech students.

Operating rules:
- If the student asks about degree planning, scheduling, prerequisites, grades, transcripts, or audits, answer as an academic advisor.
- If the student asks about course material, programming, math, proofs, algorithms, or debugging, answer as a tutor.
- Use the student's transcript context when provided. Do not ask them to check their transcript if the answer is available in context.
- For transcript rulings, answer yes/no first, then explain the specific courses and grades.
- C or better means C, C+, B-, B, B+, A-, A, or A+. C- does not satisfy C-or-better requirements.
- Treat transfer/awarded credit grades such as T, TR, TRANSFER, P, CR, or CREDIT as satisfying exact mapped VT course codes.
- Never fabricate requirements. If a requirement is not in context, say what is known and what still needs confirmation.
- Be concise, warm, and concrete. Prefer short paragraphs and bullets.
- For math, algorithms, proofs, matrices, and recurrence relations, use LaTeX where helpful.
- For visual graph/tree/path topics, include a fenced graph block when useful.`;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return json({ detail: "Method not allowed" }, 405);
  }

  let body: ChatRequest;
  try {
    body = await req.json();
  } catch {
    return json({ detail: "Invalid JSON body." }, 400);
  }

  if (!body.messages?.length) {
    return json({ detail: "messages cannot be empty" }, 400);
  }

  const openAIKey = Deno.env.get("OPENAI_API_KEY");
  if (!openAIKey) {
    return json({ detail: "OPENAI_API_KEY is not configured." }, 500);
  }

  const openAIModel = Deno.env.get("OPENAI_MODEL") || "gpt-5.4-nano";
  const prompt = await buildPrompt(body);
  const messages = [
    { role: "system", content: prompt },
    ...body.messages.map((message) => ({
      role: sanitizeRole(message.role),
      content: String(message.content ?? ""),
    })),
  ];

  const shouldStream = new URL(req.url).pathname.endsWith("/stream");

  try {
    const openAIResponse = await fetch("https://api.openai.com/v1/chat/completions", {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${openAIKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: openAIModel,
        messages,
        max_completion_tokens: 1500,
        stream: shouldStream,
      }),
    });

    if (!openAIResponse.ok) {
      const detail = await safeErrorText(openAIResponse);
      console.warn(`Chat OpenAI request failed with status ${openAIResponse.status}: ${detail}`);
      return json({
        detail: {
          code: "CHAT_AI_REQUEST_FAILED",
          message: "We could not reach the advisor right now. Check your connection and try again.",
        },
      }, 502);
    }

    if (shouldStream) {
      return streamOpenAIResponse(openAIResponse);
    }

    const data = await openAIResponse.json();
    return json({ reply: data.choices?.[0]?.message?.content ?? "" });
  } catch (error) {
    console.warn(`Chat AI service error: ${errorMessage(error)}`);
    return json({
      detail: {
        code: "CHAT_AI_REQUEST_FAILED",
        message: "We could not reach the advisor right now. Check your connection and try again.",
      },
    }, 502);
  }
});

async function buildPrompt(body: ChatRequest): Promise<string> {
  const parts = [systemPrompt];
  const studentContext = buildStudentContext(body);
  if (studentContext) {
    parts.push(studentContext);
  }

  const courseContext = await buildCourseContext(body.major || "Computer Science");
  if (courseContext) {
    parts.push(`Department course catalog context:\n${courseContext}`);
  }

  return parts.join("\n\n");
}

function buildStudentContext(body: ChatRequest): string {
  const lines: string[] = [];

  if (body.major) {
    lines.push(`Student major: ${body.major}`);
  }

  if (body.transcript?.length) {
    lines.push("Transcript courses:");
    for (const course of body.transcript.slice(0, 160)) {
      const details = [
        course.name,
        course.grade ? `grade: ${course.grade}` : undefined,
        course.semester,
        typeof course.credits === "number" ? `${course.credits} credits` : undefined,
      ].filter(Boolean).join(", ");
      lines.push(`- ${course.code}${details ? ` (${details})` : ""}`);
    }
  }

  if (body.in_progress_courses?.length) {
    lines.push("Current/upcoming course context:");
    for (const course of body.in_progress_courses.slice(0, 80)) {
      lines.push(`- ${course}`);
    }
  }

  if (body.transcript_notes?.length) {
    lines.push("Private transcript parser notes:");
    for (const note of body.transcript_notes.slice(0, 20)) {
      lines.push(`- ${note}`);
    }
  }

  if (body.chat_memories?.length) {
    lines.push("Student preferences and recurring context:");
    for (const memory of body.chat_memories.slice(0, 20)) {
      lines.push(`- ${memory}`);
    }
  }

  return lines.join("\n");
}

async function buildCourseContext(major: string): Promise<string> {
  const subject = subjectForMajor(major);
  if (!subject) {
    return "";
  }

  const supabaseURL = Deno.env.get("SUPABASE_URL");
  const supabaseKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || Deno.env.get("SUPABASE_ANON_KEY");
  if (!supabaseURL || !supabaseKey) {
    return "";
  }

  const url = new URL(`${supabaseURL}/rest/v1/coe_courses`);
  url.searchParams.set("select", "code,name,credits,prerequisites,description");
  url.searchParams.set("subject", `eq.${subject}`);
  url.searchParams.set("order", "code.asc");
  url.searchParams.set("limit", "80");

  const response = await fetch(url, {
    headers: {
      "apikey": supabaseKey,
      "Authorization": `Bearer ${supabaseKey}`,
    },
  });
  if (!response.ok) {
    return "";
  }

  const courses = await response.json();
  return courses.map((course: Record<string, unknown>) => {
    const prereqs = course.prerequisites ? `; prereqs: ${course.prerequisites}` : "";
    const description = course.description ? `; ${String(course.description).slice(0, 220)}` : "";
    return `- ${course.code}: ${course.name} (${course.credits ?? "?"} credits${prereqs})${description}`;
  }).join("\n");
}

function subjectForMajor(major: string): string {
  const normalized = major.trim().toLowerCase();
  if (["computer science", "cs"].includes(normalized)) {
    return "CS";
  }
  return "";
}

function sanitizeRole(role: string): ChatMessage["role"] {
  if (role === "user" || role === "assistant" || role === "system" || role === "tool") {
    return role;
  }
  return "user";
}

function streamOpenAIResponse(openAIResponse: Response): Response {
  const decoder = new TextDecoder();
  const encoder = new TextEncoder();
  let buffer = "";

  const stream = new ReadableStream({
    async start(controller) {
      const reader = openAIResponse.body?.getReader();
      if (!reader) {
        controller.enqueue(encoder.encode("data: [DONE]\n\n"));
        controller.close();
        return;
      }

      try {
        while (true) {
          const { done, value } = await reader.read();
          if (done) break;
          buffer += decoder.decode(value, { stream: true });
          const lines = buffer.split("\n");
          buffer = lines.pop() ?? "";

          for (const line of lines) {
            if (!line.startsWith("data: ")) continue;
            const payload = line.slice(6).trim();
            if (payload === "[DONE]") {
              controller.enqueue(encoder.encode("data: [DONE]\n\n"));
              controller.close();
              return;
            }
            try {
              const data = JSON.parse(payload);
              const token = data.choices?.[0]?.delta?.content;
              if (token) {
                controller.enqueue(encoder.encode(`data: ${JSON.stringify(token)}\n\n`));
              }
            } catch {
              // Ignore malformed provider chunks and keep streaming.
            }
          }
        }
        controller.enqueue(encoder.encode("data: [DONE]\n\n"));
        controller.close();
      } catch (error) {
        controller.error(error);
      }
    },
  });

  return new Response(stream, {
    headers: {
      ...corsHeaders,
      "Content-Type": "text/event-stream",
      "Cache-Control": "no-cache",
    },
  });
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
    },
  });
}

async function safeErrorText(response: Response): Promise<string> {
  try {
    const data = await response.json();
    return data.error?.message || data.message || JSON.stringify(data).slice(0, 800);
  } catch {
    return (await response.text()).slice(0, 800);
  }
}

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}
