import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const smokeSchema = {
  type: "object",
  additionalProperties: false,
  required: ["ok", "summary", "checks"],
  properties: {
    ok: { type: "boolean" },
    summary: { type: "string" },
    checks: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        required: ["name", "status"],
        properties: {
          name: { type: "string" },
          status: { type: "string", enum: ["pass", "fail"] },
        },
      },
    },
  },
};

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed" }, 405);
  }

  try {
    const openAiApiKey = requiredEnv("OPENAI_API_KEY");
    const model = Deno.env.get("OPENAI_MODEL") ?? "gpt-5";
    const startedAt = Date.now();

    const response = await fetch("https://api.openai.com/v1/responses", {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${openAiApiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model,
        input: [
          {
            role: "system",
            content:
              "Return a tiny JSON smoke-test response. Do not use tools. Do not include any extra text.",
          },
          {
            role: "user",
            content:
              "Confirm that structured output works. Keep the summary under 12 words.",
          },
        ],
        tool_choice: "none",
        reasoning: { effort: "minimal" },
        max_output_tokens: 800,
        text: {
          verbosity: "low",
          format: {
            type: "json_schema",
            name: "openai_structured_smoke",
            strict: true,
            schema: smokeSchema,
          },
        },
      }),
    });

    const body = await response.json();
    if (!response.ok) {
      return jsonResponse({
        ok: false,
        elapsed_ms: Date.now() - startedAt,
        openai_status: response.status,
        openai_error: body,
      }, 502);
    }

    const outputText = extractOutputText(body);
    if (!outputText) {
      return jsonResponse({
        ok: false,
        elapsed_ms: Date.now() - startedAt,
        error: "OpenAI response did not include output text",
        openai_summary: summarizeOpenAiBody(body),
      }, 502);
    }

    return jsonResponse({
      ok: true,
      elapsed_ms: Date.now() - startedAt,
      model: body.model,
      result: JSON.parse(outputText),
    });
  } catch (error) {
    return jsonResponse({
      ok: false,
      error: error instanceof Error ? error.message : String(error),
    }, 400);
  }
});

type JsonObject = Record<string, unknown>;

function extractOutputText(response: JsonObject) {
  if (typeof response.output_text === "string") {
    return response.output_text;
  }

  const output = response.output;
  if (!Array.isArray(output)) {
    return null;
  }

  for (const item of output) {
    if (!item || typeof item !== "object") continue;
    const content = (item as JsonObject).content;
    if (!Array.isArray(content)) continue;
    for (const part of content) {
      if (!part || typeof part !== "object") continue;
      const text = (part as JsonObject).text;
      if (typeof text === "string") return text;
      const parsed = (part as JsonObject).parsed;
      if (parsed && typeof parsed === "object") return JSON.stringify(parsed);
    }
  }

  return null;
}

function summarizeOpenAiBody(response: JsonObject) {
  return {
    id: response.id,
    status: response.status,
    error: response.error,
    incomplete_details: response.incomplete_details,
    output_types: Array.isArray(response.output)
      ? response.output.map((item) => {
        if (!item || typeof item !== "object") return typeof item;
        const outputItem = item as JsonObject;
        return {
          type: outputItem.type,
          status: outputItem.status,
          content_types: Array.isArray(outputItem.content)
            ? outputItem.content.map((part) =>
              part && typeof part === "object"
                ? (part as JsonObject).type
                : typeof part
            )
            : undefined,
        };
      })
      : undefined,
  };
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
