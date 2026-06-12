const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "DELETE, OPTIONS",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "DELETE") {
    return json({ detail: "Method not allowed" }, 405);
  }

  const supabaseURL = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") || serviceRoleKey;
  if (!supabaseURL || !serviceRoleKey || !anonKey) {
    return json({ detail: "Supabase account deletion is not configured." }, 500);
  }

  const authorization = req.headers.get("authorization") || "";
  if (!authorization.toLowerCase().startsWith("bearer ")) {
    return json({ detail: "Missing bearer token." }, 401);
  }

  const userResponse = await fetch(`${supabaseURL}/auth/v1/user`, {
    headers: {
      "apikey": anonKey,
      "Authorization": authorization,
    },
  });
  if (!userResponse.ok) {
    return json({ detail: "Invalid or expired session." }, 401);
  }

  const user = await userResponse.json();
  if (!user?.id) {
    return json({ detail: "Could not resolve authenticated user." }, 401);
  }

  const deleteResponse = await fetch(`${supabaseURL}/auth/v1/admin/users/${user.id}`, {
    method: "DELETE",
    headers: {
      "apikey": serviceRoleKey,
      "Authorization": `Bearer ${serviceRoleKey}`,
    },
  });
  if (!deleteResponse.ok) {
    return json({ detail: await safeErrorText(deleteResponse) }, 502);
  }

  return json({ deleted: true });
});

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
    return data?.msg || data?.message || data?.error_description || JSON.stringify(data);
  } catch {
    return await response.text();
  }
}
