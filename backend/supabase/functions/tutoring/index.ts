import {
  corsHeaders,
  errorResponse,
  json,
  methodNotAllowed,
  stringArray,
} from "../_shared/academic.ts";

type TutoringRequest = {
  struggling_courses?: string[];
  completed_courses?: string[];
  major?: string;
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return methodNotAllowed();
  }

  let body: TutoringRequest;
  try {
    body = await req.json();
  } catch {
    return errorResponse("TUTORING_INVALID_JSON", "Invalid JSON body.", 400);
  }

  const strugglingCourses = stringArray(body.struggling_courses);
  if (!strugglingCourses.length) {
    return errorResponse("TUTORING_COURSES_REQUIRED", "struggling_courses cannot be empty", 400);
  }

  return json({
    resources: [
      {
        name: "Virginia Tech Student Success Center",
        type: "Tutoring",
        description: `Start with tutoring or academic coaching for ${strugglingCourses.slice(0, 3).join(", ")}.`,
        link: "https://studentsuccess.vt.edu/",
      },
      {
        name: "CS Office Hours and Course Staff",
        type: "Course support",
        description: "Use the current course Canvas page, TA office hours, and instructor office hours for assignment-specific help.",
        link: null,
      },
      {
        name: "Hokie Advisor Chat",
        type: "AI tutor",
        description: "Ask the Advisor tab for a worked example, concept explanation, or study plan tied to your transcript.",
        link: null,
      },
    ],
    tips: [
      "Bring one concrete problem or confusing lecture topic to each help session.",
      "Ask for feedback on your approach before asking for the final answer.",
      "Schedule support early in the week so you have time to apply it before deadlines.",
    ],
    encouragement: `You are not behind because you need help with ${strugglingCourses[0]}. Treat this like debugging: isolate the smallest confusing step, get feedback, and iterate.`,
  });
});
