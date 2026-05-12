import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

type JsonObject = Record<string, unknown>;

type AccessRequestPayload = {
  name?: unknown;
  email?: unknown;
  source?: unknown;
  website?: unknown;
};

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return jsonResponse({ ok: false, error: "Method not allowed" }, 405);
  }

  let accessRequestId: string | null = null;

  try {
    const payload = await req.json() as AccessRequestPayload;
    const name = cleanText(payload.name, 120);
    const email = cleanEmail(payload.email);
    const source = cleanText(payload.source, 80) || "landing_page";
    const honeypot = cleanText(payload.website, 200);

    if (honeypot) {
      return jsonResponse({ ok: true });
    }

    if (!name) {
      return jsonResponse({ ok: false, error: "Name is required." }, 400);
    }
    if (!email || !isValidEmail(email)) {
      return jsonResponse({ ok: false, error: "A valid email is required." }, 400);
    }

    const supabaseUrl = requiredEnv("SUPABASE_URL");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ??
      requiredEnv("FUTURLENS_SUPABASE_SERVICE_ROLE_KEY");
    const resendApiKey = requiredEnv("RESEND_API_KEY");
    const notifyEmail = requiredEnv("ACCESS_NOTIFY_EMAIL");
    const fromEmail = requiredEnv("ACCESS_FROM_EMAIL");
    const appAccessUrl = requiredEnv("APP_ACCESS_URL");
    const replyTo = Deno.env.get("ACCESS_REPLY_TO") || notifyEmail;

    const inserted = await insertAccessRequest(supabaseUrl, serviceRoleKey, {
      name,
      email,
      normalized_email: email.toLowerCase(),
      source,
      requester_user_agent: req.headers.get("user-agent") || null,
      requester_ip: getRequesterIp(req),
    });
    accessRequestId = inserted.id;

    await sendEmail(resendApiKey, {
      from: fromEmail,
      to: [notifyEmail],
      reply_to: email,
      subject: "New Plenz access request",
      html: buildNotifyHtml({ name, email, source }),
      text: [
        "New Plenz access request",
        `Name: ${name}`,
        `Email: ${email}`,
        `Source: ${source}`,
      ].join("\n"),
    });

    await sendEmail(resendApiKey, {
      from: fromEmail,
      to: [email],
      reply_to: replyTo,
      subject: "Your Plenz access link",
      html: buildWelcomeHtml({ name, appAccessUrl }),
      text: [
        `Hi ${name},`,
        "",
        "Thanks for requesting access to Plenz.",
        `You can open the app here: ${appAccessUrl}`,
        "",
        "Plenz helps property professionals find suburbs aligned with client affordability, budget, and investment strategy using data-backed scoring and report generation.",
        "",
        "Plenz",
      ].join("\n"),
    });

    await updateAccessRequest(supabaseUrl, serviceRoleKey, accessRequestId, {
      status: "emailed",
      notify_email_sent_at: new Date().toISOString(),
      welcome_email_sent_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
    });

    return jsonResponse({ ok: true });
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);

    if (accessRequestId) {
      try {
        const supabaseUrl = requiredEnv("SUPABASE_URL");
        const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ??
          requiredEnv("FUTURLENS_SUPABASE_SERVICE_ROLE_KEY");
        await updateAccessRequest(supabaseUrl, serviceRoleKey, accessRequestId, {
          status: "email_failed",
          error_message: message.slice(0, 1000),
          updated_at: new Date().toISOString(),
        });
      } catch (_) {
        // Preserve the original failure for the caller.
      }
    }

    return jsonResponse({ ok: false, error: message }, 400);
  }
});

async function insertAccessRequest(
  supabaseUrl: string,
  serviceRoleKey: string,
  row: JsonObject,
) {
  const response = await fetch(`${supabaseUrl}/rest/v1/access_requests?select=id`, {
    method: "POST",
    headers: supabaseHeaders(serviceRoleKey, {
      Prefer: "return=representation",
    }),
    body: JSON.stringify(row),
  });

  const body = await response.json();
  if (!response.ok) {
    throw new Error(`Failed to store access request: ${JSON.stringify(body)}`);
  }

  const inserted = Array.isArray(body) ? body[0] : null;
  if (!inserted || typeof inserted.id !== "string") {
    throw new Error("Access request insert did not return an id.");
  }

  return inserted as { id: string };
}

async function updateAccessRequest(
  supabaseUrl: string,
  serviceRoleKey: string,
  id: string,
  patch: JsonObject,
) {
  const response = await fetch(
    `${supabaseUrl}/rest/v1/access_requests?id=eq.${encodeURIComponent(id)}`,
    {
      method: "PATCH",
      headers: supabaseHeaders(serviceRoleKey),
      body: JSON.stringify(patch),
    },
  );

  if (!response.ok) {
    const body = await response.text();
    throw new Error(`Failed to update access request: ${body}`);
  }
}

async function sendEmail(resendApiKey: string, body: JsonObject) {
  const response = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${resendApiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(body),
  });

  if (!response.ok) {
    const errorBody = await response.text();
    throw new Error(`Resend email failed (${response.status}): ${errorBody}`);
  }
}

function buildNotifyHtml({ name, email, source }: { name: string; email: string; source: string }) {
  return `
    <div style="font-family:Arial,sans-serif;color:#07122f;line-height:1.5">
      <h2>New Plenz access request</h2>
      <p><strong>Name:</strong> ${escapeHtml(name)}</p>
      <p><strong>Email:</strong> ${escapeHtml(email)}</p>
      <p><strong>Source:</strong> ${escapeHtml(source)}</p>
    </div>
  `;
}

function buildWelcomeHtml({ name, appAccessUrl }: { name: string; appAccessUrl: string }) {
  return `
    <div style="font-family:Arial,sans-serif;color:#07122f;line-height:1.55">
      <h2>Your Plenz access link</h2>
      <p>Hi ${escapeHtml(name)},</p>
      <p>Thanks for requesting access to Plenz.</p>
      <p>
        <a href="${escapeHtml(appAccessUrl)}" style="display:inline-block;background:#07122f;color:#fff;text-decoration:none;padding:12px 18px;border-radius:8px;font-weight:700">
          Open Plenz
        </a>
      </p>
      <p>Plenz helps property professionals find suburbs aligned with client affordability, budget, and investment strategy using data-backed scoring and report generation.</p>
      <p style="color:#64748b;font-size:13px">If the button does not work, open this link: ${escapeHtml(appAccessUrl)}</p>
    </div>
  `;
}

function supabaseHeaders(serviceRoleKey: string, extra: Record<string, string> = {}) {
  return {
    apikey: serviceRoleKey,
    Authorization: `Bearer ${serviceRoleKey}`,
    "Content-Type": "application/json",
    ...extra,
  };
}

function getRequesterIp(req: Request) {
  return req.headers.get("x-forwarded-for")?.split(",")[0]?.trim() ??
    req.headers.get("cf-connecting-ip") ??
    null;
}

function cleanText(value: unknown, maxLength = 200) {
  if (typeof value !== "string") return "";
  return value.trim().replace(/\s+/g, " ").slice(0, maxLength);
}

function cleanEmail(value: unknown) {
  if (typeof value !== "string") return "";
  return value.trim().toLowerCase().slice(0, 254);
}

function isValidEmail(value: string) {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value);
}

function escapeHtml(value: string) {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}

function requiredEnv(name: string) {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`Missing environment variable: ${name}`);
  return value;
}

function jsonResponse(body: JsonObject, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
    },
  });
}
