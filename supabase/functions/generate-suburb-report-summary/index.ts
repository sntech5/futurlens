import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

const CONTEXT_PROMPT_VERSION = "suburb_context_facts_v1";
const SUMMARY_PROMPT_VERSION = "suburb_report_summary_v1";
const SUMMARY_TYPE = "recommendation_report";
const OPENAI_TEXT_TIMEOUT_MS = 50_000;
const OPENAI_WEB_SEARCH_TIMEOUT_MS = 90_000;

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

type JsonObject = Record<string, unknown>;

type RequestPayload = {
  suburb: {
    suburb_key: string;
    name: string;
    state: string;
    postcode?: string | null;
  };
  metrics: JsonObject;
  force_refresh_context?: boolean;
  force_refresh_summary?: boolean;
};

const contextPrompt = `Extract cited, investment-relevant local context facts for an Australian suburb report.

Use web search and return only schema-valid JSON. Include a fact only when it has a citation URL. Prefer official sources: government, council, health, education, transport, infrastructure, economic development, or regional development pages. Avoid blogs, agents, forums, SEO pages, and unsourced claims unless no stronger source exists; lower confidence if used.

Allowed categories only: nearest major/regional city distance, healthcare, CBD/activity/employment centre, economic/employment drivers, university/TAFE, material transport, major demand-relevant infrastructure. At most one concise fact per category.

Exclude cemeteries, heritage-only facts, random addresses, parks, churches, clubs, minor facilities, postcode-only confirmation, trivia, marketing language, investment claims, and uncited or inferred facts. Use empty arrays/nulls where reliable report-useful evidence is not found.`;

const summaryPrompt = `Write an executive-style suburb investment summary as schema-valid JSON.

Use only supplied metrics and cited context_facts. Do not use outside knowledge or add local facts. Mention hospitals, CBDs, industries, transport, education, infrastructure, distances, or drivers only if present in context_facts.

Be concise, cautious, and factual. Do not guarantee performance. Prefer "may support", "is associated with", "based on supplied metrics", and "where source data is available". Omit missing facts or note them only in data_limitations.

Do not recite every metric. Highlight the most decision-relevant signals only. Limits: summary max 2 short sentences; strengths max 3; local_drivers max 3; risk_notes max 2; data_limitations max 3.`;

const contextSchema = {
  type: "object",
  additionalProperties: false,
  required: ["suburb_key", "suburb_name", "state", "postcode", "facts", "confidence", "data_limitations"],
  properties: {
    suburb_key: { type: "string" },
    suburb_name: { type: "string" },
    state: { type: "string" },
    postcode: { type: "string" },
    facts: {
      type: "object",
      additionalProperties: false,
      required: [
        "nearest_major_city",
        "healthcare",
        "activity_centres",
        "local_drivers",
        "transport",
        "education",
        "infrastructure",
      ],
      properties: {
        nearest_major_city: {
          type: ["object", "null"],
          additionalProperties: false,
          required: ["name", "distance_km", "evidence_url"],
          properties: {
            name: { type: "string" },
            distance_km: { type: ["number", "null"] },
            evidence_url: { type: "string" },
          },
        },
        healthcare: { type: "array", items: factItemSchema() },
        activity_centres: { type: "array", items: factItemSchema() },
        local_drivers: { type: "array", items: factItemSchema() },
        transport: { type: "array", items: factItemSchema() },
        education: { type: "array", items: factItemSchema() },
        infrastructure: { type: "array", items: factItemSchema() },
      },
    },
    confidence: { type: "string", enum: ["high", "medium", "low"] },
    data_limitations: { type: "array", items: { type: "string" } },
  },
};

const summarySchema = {
  type: "object",
  additionalProperties: false,
  required: ["summary", "strengths", "local_drivers", "risk_notes", "data_limitations", "confidence"],
  properties: {
    summary: { type: "string" },
    strengths: { type: "array", maxItems: 3, items: { type: "string" } },
    local_drivers: { type: "array", maxItems: 3, items: { type: "string" } },
    risk_notes: { type: "array", maxItems: 2, items: { type: "string" } },
    data_limitations: { type: "array", maxItems: 3, items: { type: "string" } },
    confidence: { type: "string", enum: ["high", "medium", "low"] },
  },
};

function factItemSchema() {
  return {
    type: "object",
    additionalProperties: false,
    required: ["name", "fact", "evidence_url"],
    properties: {
      name: { type: "string" },
      fact: { type: "string" },
      evidence_url: { type: "string" },
    },
  };
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed" }, 405);
  }

  try {
    const payload = await req.json() as RequestPayload;
    validateRequestPayload(payload);

    const openAiApiKey = requiredEnv("OPENAI_API_KEY");
    const supabaseUrl = requiredEnv("SUPABASE_URL");
    const supabaseServiceRoleKey =
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ??
        requiredEnv("FUTURLENS_SUPABASE_SERVICE_ROLE_KEY");
    const model = Deno.env.get("OPENAI_MODEL") ?? "gpt-5";

    const supabase = createSupabaseRestClient(supabaseUrl, supabaseServiceRoleKey);

    const contextInput = {
      suburb_key: payload.suburb.suburb_key,
      suburb_name: payload.suburb.name,
      state: payload.suburb.state,
      postcode: payload.suburb.postcode ?? "",
      country: "Australia",
    };
    const contextInputHash = await sha256(canonicalJson(contextInput));

    let contextRow = payload.force_refresh_context
      ? null
      : await findContextCache(supabase, payload.suburb.suburb_key, contextInputHash);

    if (!contextRow) {
      const factsPayload = await callOpenAiStructuredJson({
        openAiApiKey,
        model,
        prompt: contextPrompt,
        input: contextInput,
        schemaName: "suburb_context_facts",
        schema: contextSchema,
        useWebSearch: true,
        state: payload.suburb.state,
      });

      contextRow = await upsertContextCache(supabase, {
        suburb_key: payload.suburb.suburb_key,
        prompt_version: CONTEXT_PROMPT_VERSION,
        input_hash: contextInputHash,
        input_payload: contextInput,
        facts_payload: factsPayload,
        model,
        confidence: stringOrNull(factsPayload.confidence),
        source_count: countEvidenceUrls(factsPayload),
        generated_at: new Date().toISOString(),
        expires_at: oneYearFromNow(),
      });
    }

    const contextFacts = contextRow.facts_payload as JsonObject;
    const summaryInput = {
      suburb: payload.suburb,
      metrics: payload.metrics,
      context_facts: contextFacts.facts ?? {},
      data_coverage: {
        has_local_context_facts: countEvidenceUrls(contextFacts) > 0,
        context_prompt_version: CONTEXT_PROMPT_VERSION,
        summary_prompt_version: SUMMARY_PROMPT_VERSION,
      },
    };
    const summaryInputHash = await sha256(canonicalJson(summaryInput));

    let summaryRow = payload.force_refresh_summary
      ? null
      : await findSummaryCache(supabase, payload.suburb.suburb_key, summaryInputHash);

    if (!summaryRow) {
      const summaryPayload = await callOpenAiStructuredJson({
        openAiApiKey,
        model,
        prompt: summaryPrompt,
        input: summaryInput,
        schemaName: "suburb_report_summary",
        schema: summarySchema,
        useWebSearch: false,
        state: payload.suburb.state,
      });

      summaryRow = await upsertSummaryCache(supabase, {
        suburb_key: payload.suburb.suburb_key,
        summary_type: SUMMARY_TYPE,
        prompt_version: SUMMARY_PROMPT_VERSION,
        input_hash: summaryInputHash,
        input_payload: summaryInput,
        summary_payload: summaryPayload,
        model,
        confidence: stringOrNull(summaryPayload.confidence),
        context_facts_id: contextRow.id,
        generated_at: new Date().toISOString(),
      });
    }

    return jsonResponse({
      suburb_key: payload.suburb.suburb_key,
      context_cache_id: contextRow.id,
      summary_cache_id: summaryRow.id,
      context_facts: contextRow.facts_payload,
      report_summary: summaryRow.summary_payload,
    });
  } catch (error) {
    return jsonResponse({ error: error instanceof Error ? error.message : String(error) }, 400);
  }
});

function validateRequestPayload(payload: RequestPayload) {
  if (!payload?.suburb?.suburb_key || !payload.suburb.name || !payload.suburb.state) {
    throw new Error("Missing suburb.suburb_key, suburb.name, or suburb.state");
  }
  if (!payload.metrics || typeof payload.metrics !== "object" || Array.isArray(payload.metrics)) {
    throw new Error("Missing metrics object");
  }
}

async function callOpenAiStructuredJson(args: {
  openAiApiKey: string;
  model: string;
  prompt: string;
  input: JsonObject;
  schemaName: string;
  schema: JsonObject;
  useWebSearch: boolean;
  state: string;
}) {
  const tools = args.useWebSearch
    ? [{
      type: "web_search",
      user_location: {
        type: "approximate",
        country: "AU",
        region: args.state,
        timezone: "Australia/Sydney",
      },
    }]
    : undefined;

  const timeoutMs = args.useWebSearch ? OPENAI_WEB_SEARCH_TIMEOUT_MS : OPENAI_TEXT_TIMEOUT_MS;
  const abortController = new AbortController();
  const timeoutId = setTimeout(() => abortController.abort(), timeoutMs);

  let response: Response;
  try {
    response = await fetch("https://api.openai.com/v1/responses", {
      method: "POST",
      signal: abortController.signal,
      headers: {
        "Authorization": `Bearer ${args.openAiApiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: args.model,
        input: [
          { role: "system", content: args.prompt },
          { role: "user", content: JSON.stringify(args.input) },
        ],
        tools,
        tool_choice: args.useWebSearch ? "auto" : "none",
        include: args.useWebSearch ? ["web_search_call.action.sources"] : undefined,
        reasoning: { effort: "low" },
        max_output_tokens: 4000,
        text: {
          verbosity: "low",
          format: {
            type: "json_schema",
            name: args.schemaName,
            strict: true,
            schema: args.schema,
          },
        },
      }),
    });
  } catch (error) {
    if (error instanceof DOMException && error.name === "AbortError") {
      throw new Error(`OpenAI request timed out after ${timeoutMs / 1000}s`);
    }
    throw error;
  } finally {
    clearTimeout(timeoutId);
  }

  const body = await response.json();
  if (!response.ok) {
    throw new Error(`OpenAI request failed: ${JSON.stringify(body)}`);
  }

  const text = extractOutputText(body);
  if (!text) {
    throw new Error(`OpenAI response did not include output text: ${summarizeOpenAiBody(body)}`);
  }

  return JSON.parse(text) as JsonObject;
}

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
  return JSON.stringify({
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
              part && typeof part === "object" ? (part as JsonObject).type : typeof part
            )
            : undefined,
        };
      })
      : undefined,
  });
}

function createSupabaseRestClient(supabaseUrl: string, serviceRoleKey: string) {
  const baseUrl = `${supabaseUrl.replace(/\/$/, "")}/rest/v1`;
  const headers = {
    "apikey": serviceRoleKey,
    "Authorization": `Bearer ${serviceRoleKey}`,
    "Content-Type": "application/json",
  };

  return {
    async getOne(table: string, query: string) {
      const response = await fetch(`${baseUrl}/${table}?${query}`, { headers });
      const rows = await response.json();
      if (!response.ok) throw new Error(`Supabase select failed: ${JSON.stringify(rows)}`);
      return Array.isArray(rows) && rows.length > 0 ? rows[0] as JsonObject : null;
    },
    async upsertOne(table: string, conflictColumns: string, payload: JsonObject) {
      const response = await fetch(`${baseUrl}/${table}?on_conflict=${encodeURIComponent(conflictColumns)}`, {
        method: "POST",
        headers: {
          ...headers,
          "Prefer": "resolution=merge-duplicates,return=representation",
        },
        body: JSON.stringify(payload),
      });
      const rows = await response.json();
      if (!response.ok) throw new Error(`Supabase upsert failed: ${JSON.stringify(rows)}`);
      if (!Array.isArray(rows) || rows.length === 0) throw new Error("Supabase upsert returned no rows");
      return rows[0] as JsonObject;
    },
  };
}

async function findContextCache(
  supabase: ReturnType<typeof createSupabaseRestClient>,
  suburbKey: string,
  inputHash: string,
) {
  const query = new URLSearchParams({
    suburb_key: `eq.${suburbKey}`,
    prompt_version: `eq.${CONTEXT_PROMPT_VERSION}`,
    input_hash: `eq.${inputHash}`,
    order: "generated_at.desc",
    limit: "1",
  });
  const row = await supabase.getOne("suburb_ai_context_facts", query.toString());
  if (!row) return null;

  const expiresAt = typeof row.expires_at === "string" ? new Date(row.expires_at) : null;
  if (expiresAt && expiresAt.getTime() <= Date.now()) return null;
  return row;
}

function findSummaryCache(
  supabase: ReturnType<typeof createSupabaseRestClient>,
  suburbKey: string,
  inputHash: string,
) {
  const query = new URLSearchParams({
    suburb_key: `eq.${suburbKey}`,
    summary_type: `eq.${SUMMARY_TYPE}`,
    prompt_version: `eq.${SUMMARY_PROMPT_VERSION}`,
    input_hash: `eq.${inputHash}`,
    order: "generated_at.desc",
    limit: "1",
  });
  return supabase.getOne("suburb_report_ai_summaries", query.toString());
}

function upsertContextCache(
  supabase: ReturnType<typeof createSupabaseRestClient>,
  payload: JsonObject,
) {
  return supabase.upsertOne(
    "suburb_ai_context_facts",
    "suburb_key,prompt_version,input_hash",
    payload,
  );
}

function upsertSummaryCache(
  supabase: ReturnType<typeof createSupabaseRestClient>,
  payload: JsonObject,
) {
  return supabase.upsertOne(
    "suburb_report_ai_summaries",
    "suburb_key,summary_type,prompt_version,input_hash",
    payload,
  );
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

function canonicalJson(value: unknown): string {
  return JSON.stringify(sortJson(value));
}

function sortJson(value: unknown): unknown {
  if (Array.isArray(value)) {
    return value.map(sortJson);
  }
  if (value && typeof value === "object") {
    return Object.keys(value as JsonObject).sort().reduce((acc, key) => {
      acc[key] = sortJson((value as JsonObject)[key]);
      return acc;
    }, {} as JsonObject);
  }
  return value;
}

async function sha256(value: string) {
  const data = new TextEncoder().encode(value);
  const hash = await crypto.subtle.digest("SHA-256", data);
  return Array.from(new Uint8Array(hash))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

function countEvidenceUrls(value: unknown): number {
  if (Array.isArray(value)) {
    return value.reduce((count, item) => count + countEvidenceUrls(item), 0);
  }
  if (value && typeof value === "object") {
    let count = 0;
    for (const [key, child] of Object.entries(value as JsonObject)) {
      if (key === "evidence_url" && typeof child === "string" && child.trim()) {
        count += 1;
      } else {
        count += countEvidenceUrls(child);
      }
    }
    return count;
  }
  return 0;
}

function stringOrNull(value: unknown) {
  return typeof value === "string" ? value : null;
}

function oneYearFromNow() {
  const date = new Date();
  date.setFullYear(date.getFullYear() + 1);
  return date.toISOString();
}
