import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const WEB_SEARCH_TIMEOUT_MS = 75_000;

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed" }, 405);
  }

  try {
    const payload = await req.json().catch(() => ({}));
    const suburbName = stringOrDefault(payload.suburb_name, "Millbank");
    const state = stringOrDefault(payload.state, "QLD");
    const postcode = stringOrDefault(payload.postcode, "4670");

    const openAiApiKey = requiredEnv("OPENAI_API_KEY");
    const model = Deno.env.get("OPENAI_MODEL") ?? "gpt-5";
    const startedAt = Date.now();
    const abortController = new AbortController();
    const timeoutId = setTimeout(() => abortController.abort(), WEB_SEARCH_TIMEOUT_MS);

    let response: Response;
    try {
      response = await fetch("https://api.openai.com/v1/responses", {
        method: "POST",
        signal: abortController.signal,
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
                "Use web search and return a very brief plain-text answer with one or two cited facts. Do not produce JSON.",
            },
            {
              role: "user",
              content:
                `Find one reliable local context fact for ${suburbName}, ${state} ${postcode}, Australia. Prefer official sources. Keep it under 40 words.`,
            },
          ],
          tools: [{
            type: "web_search",
            user_location: {
              type: "approximate",
              country: "AU",
              region: state,
              timezone: "Australia/Sydney",
            },
          }],
          tool_choice: "auto",
          reasoning: { effort: "low" },
          max_output_tokens: 1000,
          text: { verbosity: "low" },
        }),
      });
    } catch (error) {
      if (error instanceof DOMException && error.name === "AbortError") {
        return jsonResponse({
          ok: false,
          elapsed_ms: Date.now() - startedAt,
          error: `OpenAI web search request timed out after ${WEB_SEARCH_TIMEOUT_MS / 1000}s`,
        }, 504);
      }
      throw error;
    } finally {
      clearTimeout(timeoutId);
    }

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
    return jsonResponse({
      ok: Boolean(outputText),
      elapsed_ms: Date.now() - startedAt,
      model: body.model,
      status: body.status,
      incomplete_details: body.incomplete_details,
      output_text: outputText,
      output_summary: summarizeOpenAiBody(body),
    }, outputText ? 200 : 502);
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

function stringOrDefault(value: unknown, fallback: string) {
  return typeof value === "string" && value.trim() ? value.trim() : fallback;
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
