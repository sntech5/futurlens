import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

const CONTEXT_PROMPT_VERSION = "suburb_context_facts_v1";
const AI_WEB_SEARCH_TIMEOUT_MS = 90_000;
const DEFAULT_LIMIT = 1;
const MAX_LIMIT = 25;

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

type JsonObject = Record<string, unknown>;

type ClaimedJob = {
  job_id: string;
  suburb_key: string;
  suburb_name: string;
  state: string;
  postcode: string | null;
  prompt_version: string;
  ai_provider: string;
  model: string;
};

const contextPrompt = `Extract cited, investment-relevant local context facts for an Australian suburb report.

Use web search and return only schema-valid JSON. Include a fact only when it has a citation URL.

Prefer direct source URLs from government, council, public health, education, transport, infrastructure, economic development, or regional development pages. Avoid returning Google/Vertex grounding redirect URLs when a direct source URL is available.

Every evidence_url must be a complete absolute URL beginning with https:// or http://. Do not return citation handles such as turn0search0, footnote ids, or source labels.

Do not use Wikipedia, generic suburb-profile sites, property portals, real estate agency pages, SEO pages, blogs, or suburb directory pages as evidence. Examples of disallowed source types include property guides, suburb profile aggregators, and wiki pages.

Allowed categories only: nearest major/regional city distance, healthcare, CBD/activity/employment centre, economic/employment drivers, university/TAFE, material transport, major demand-relevant infrastructure.

Return at most one strongest fact per array category. Choose the most investment-relevant official/source-backed fact. If no strong fact exists for a category, return an empty array for that category.

Exclude cemeteries, heritage-only facts, random addresses, parks, churches, clubs, minor facilities, sporting complexes, walking/cycling trails, veterinary clinics, lifestyle amenities, utility easements/pipelines that only constrain subdivision, postcode-only confirmation, trivia, estate/developer marketing claims, promotional adjectives, investment claims, and uncited or inferred facts.

Use developer/estate pages only when they document a material town-centre or infrastructure project and no official source is available. If developer/marketing pages are used, set confidence to medium or low.

Return exactly one JSON object as plain text. Do not return markdown, citations outside JSON, commentary, or an empty response.`;

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
        healthcare: { type: "array", maxItems: 1, items: factItemSchema() },
        activity_centres: { type: "array", maxItems: 1, items: factItemSchema() },
        local_drivers: { type: "array", maxItems: 1, items: factItemSchema() },
        transport: { type: "array", maxItems: 1, items: factItemSchema() },
        education: { type: "array", maxItems: 1, items: factItemSchema() },
        infrastructure: { type: "array", maxItems: 1, items: factItemSchema() },
      },
    },
    confidence: { type: "string", enum: ["high", "medium", "low"] },
    data_limitations: { type: "array", items: { type: "string" } },
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
    verifyBatchSecret(req);

    const payload = await req.json().catch(() => ({})) as JsonObject;
    const limit = clampLimit(payload.limit);
    const lockedBy = stringOrDefault(payload.locked_by, "refresh-suburb-context-batch");

    const supabaseUrl = requiredEnv("SUPABASE_URL");
    const supabaseServiceRoleKey =
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ??
        requiredEnv("FUTURLENS_SUPABASE_SERVICE_ROLE_KEY");
    const supabase = createSupabaseRestClient(supabaseUrl, supabaseServiceRoleKey);

    const jobs = await supabase.rpc("claim_suburb_context_refresh_jobs", {
      p_limit: limit,
      p_locked_by: lockedBy,
    }) as ClaimedJob[];

    const results = [];
    for (const job of jobs) {
      results.push(await processJob(supabase, job));
    }

    return jsonResponse({
      requested_limit: limit,
      claimed_count: jobs.length,
      completed_count: results.filter((result) => result.status === "completed").length,
      failed_count: results.filter((result) => result.status === "failed").length,
      results,
    });
  } catch (error) {
    return jsonResponse({ error: error instanceof Error ? error.message : String(error) }, 400);
  }
});

function verifyBatchSecret(req: Request) {
  const expectedSecret = requiredEnv("BATCH_WORKER_SECRET");
  const providedSecret = req.headers.get("x-batch-secret") ?? "";
  if (providedSecret !== expectedSecret) {
    throw new Error("Unauthorized batch worker request");
  }
}

async function processJob(
  supabase: ReturnType<typeof createSupabaseRestClient>,
  job: ClaimedJob,
) {
  try {
    const aiProvider = job.ai_provider;
    if (aiProvider !== "openai" && aiProvider !== "gemini") {
      throw new Error(`Unsupported AI provider for job: ${aiProvider}`);
    }

    const aiApiKey = requiredEnv(aiProvider === "gemini" ? "GEMINI_API_KEY" : "OPENAI_API_KEY");
    const aiApiUrl = getAiApiUrl(aiProvider, job.model);

    const contextInput = {
      suburb_key: job.suburb_key,
      suburb_name: job.suburb_name,
      state: job.state,
      postcode: job.postcode ?? "",
      country: "Australia",
    };
    const inputHash = await sha256(canonicalJson({
      ai_provider: aiProvider,
      model: job.model,
      input: contextInput,
    }));

    const rawFactsPayload = await callAiStructuredJson({
      aiProvider,
      aiApiKey,
      aiApiUrl,
      model: job.model,
      prompt: contextPrompt,
      input: contextInput,
      schemaName: "suburb_context_facts",
      schema: contextSchema,
      state: job.state,
    });
    const factsPayload = cleanContextFactsPayload(rawFactsPayload);
    const sourceCount = countEvidenceUrls(factsPayload);
    if (sourceCount === 0) {
      throw new Error("AI context extraction returned no valid absolute evidence URLs");
    }

    const contextRow = await supabase.upsertOne(
      "suburb_ai_context_facts",
      "suburb_key,prompt_version,input_hash",
      {
        suburb_key: job.suburb_key,
        prompt_version: job.prompt_version || CONTEXT_PROMPT_VERSION,
        input_hash: inputHash,
        input_payload: contextInput,
        facts_payload: factsPayload,
        model: job.model,
        confidence: stringOrNull(factsPayload.confidence),
        source_count: sourceCount,
        generated_at: new Date().toISOString(),
        expires_at: daysFromNow(45),
      },
    );

    await supabase.rpc("complete_suburb_context_refresh_job", {
      p_job_id: job.job_id,
      p_context_facts_id: contextRow.id,
    });

    return {
      job_id: job.job_id,
      suburb_key: job.suburb_key,
      status: "completed",
      context_facts_id: contextRow.id,
      source_count: sourceCount,
    };
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    await supabase.rpc("fail_suburb_context_refresh_job", {
      p_job_id: job.job_id,
      p_error: message,
    });
    return {
      job_id: job.job_id,
      suburb_key: job.suburb_key,
      status: "failed",
      error: message,
    };
  }
}

function getAiApiUrl(provider: string, model: string) {
  const configuredUrl =
    provider === "gemini"
      ? Deno.env.get("GEMINI_API_URL") ?? Deno.env.get("AI_API_URL")
      : Deno.env.get("OPENAI_API_URL");
  if (configuredUrl) {
    return configuredUrl.replace("{model}", encodeURIComponent(model));
  }

  if (provider === "gemini") {
    return `https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(model)}:generateContent`;
  }

  return "https://api.openai.com/v1/responses";
}

function cleanContextFactsPayload(payload: JsonObject) {
  const cleaned = structuredClone(payload) as JsonObject;
  const facts = cleaned.facts;
  if (!facts || typeof facts !== "object" || Array.isArray(facts)) {
    return cleaned;
  }

  const factsObject = facts as JsonObject;
  for (const key of [
    "healthcare",
    "activity_centres",
    "local_drivers",
    "transport",
    "education",
    "infrastructure",
  ]) {
    const value = factsObject[key];
    if (!Array.isArray(value)) continue;
    factsObject[key] = value
      .filter((item) => isAllowedFactItem(item))
      .filter((item) => hasValidEvidenceUrl(item))
      .slice(0, 1);
  }

  const nearestMajorCity = factsObject.nearest_major_city;
  if (
    nearestMajorCity &&
    typeof nearestMajorCity === "object" &&
    !Array.isArray(nearestMajorCity) &&
    !hasValidEvidenceUrl(nearestMajorCity)
  ) {
    factsObject.nearest_major_city = null;
  }

  if (hasRedirectEvidenceUrl(cleaned) && cleaned.confidence === "high") {
    cleaned.confidence = "medium";
    const limitations = Array.isArray(cleaned.data_limitations) ? cleaned.data_limitations : [];
    limitations.push("Some evidence URLs are provider grounding redirects rather than direct source URLs.");
    cleaned.data_limitations = limitations;
  }

  return cleaned;
}

function isAllowedFactItem(item: unknown) {
  if (!item || typeof item !== "object") return false;
  const factItem = item as JsonObject;
  const text = `${String(factItem.name ?? "")} ${String(factItem.fact ?? "")}`.toLowerCase();
  const blockedPatterns = [
    "veterinary",
    "vet clinic",
    "vet hospital",
    "sporting complex",
    "sports complex",
    "walking trail",
    "cycling trail",
    "bike trail",
    "bowling green",
    "oval",
    "park",
    "church",
    "cemetery",
  ];
  return !blockedPatterns.some((pattern) => text.includes(pattern));
}

function hasValidEvidenceUrl(value: unknown) {
  if (!value || typeof value !== "object") return false;
  const evidenceUrl = (value as JsonObject).evidence_url;
  if (typeof evidenceUrl !== "string" || !/^https?:\/\//i.test(evidenceUrl)) return false;

  let hostname = "";
  try {
    hostname = new URL(evidenceUrl).hostname.toLowerCase().replace(/^www\./, "");
  } catch {
    return false;
  }

  const blockedDomains = [
    "au.propertydigger.com",
    "propertydigger.com",
    "australiansuburbs.au",
    "wikipedia.org",
  ];
  if (blockedDomains.some((domain) => hostname === domain || hostname.endsWith(`.${domain}`))) {
    return false;
  }

  return true;
}

function hasRedirectEvidenceUrl(value: unknown): boolean {
  if (Array.isArray(value)) {
    return value.some(hasRedirectEvidenceUrl);
  }
  if (value && typeof value === "object") {
    for (const [key, child] of Object.entries(value as JsonObject)) {
      if (
        key === "evidence_url" &&
        typeof child === "string" &&
        child.includes("grounding-api-redirect")
      ) {
        return true;
      }
      if (hasRedirectEvidenceUrl(child)) return true;
    }
  }
  return false;
}

async function callAiStructuredJson(args: {
  aiProvider: string;
  aiApiKey: string;
  aiApiUrl: string;
  model: string;
  prompt: string;
  input: JsonObject;
  schemaName: string;
  schema: JsonObject;
  state: string;
}) {
  if (args.aiProvider === "gemini") {
    return callGeminiStructuredJson(args);
  }
  return callOpenAiStructuredJson(args);
}

async function callOpenAiStructuredJson(args: {
  aiApiKey: string;
  aiApiUrl: string;
  model: string;
  prompt: string;
  input: JsonObject;
  schemaName: string;
  schema: JsonObject;
  state: string;
}) {
  const abortController = new AbortController();
  const timeoutId = setTimeout(() => abortController.abort(), AI_WEB_SEARCH_TIMEOUT_MS);

  let response: Response;
  try {
    response = await fetch(args.aiApiUrl, {
      method: "POST",
      signal: abortController.signal,
      headers: {
        "Authorization": `Bearer ${args.aiApiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: args.model,
        input: [
          { role: "system", content: args.prompt },
          { role: "user", content: JSON.stringify(args.input) },
        ],
        tools: [{
          type: "web_search",
          user_location: {
            type: "approximate",
            country: "AU",
            region: args.state,
            timezone: "Australia/Sydney",
          },
        }],
        tool_choice: "auto",
        include: ["web_search_call.action.sources"],
        max_output_tokens: 4000,
        text: {
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
      throw new Error(`OpenAI request timed out after ${AI_WEB_SEARCH_TIMEOUT_MS / 1000}s`);
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

async function callGeminiStructuredJson(args: {
  aiApiKey: string;
  aiApiUrl: string;
  model: string;
  prompt: string;
  input: JsonObject;
  schema: JsonObject;
}) {
  const abortController = new AbortController();
  const timeoutId = setTimeout(() => abortController.abort(), AI_WEB_SEARCH_TIMEOUT_MS);

  let response: Response;
  try {
    response = await fetch(args.aiApiUrl, {
      method: "POST",
      signal: abortController.signal,
      headers: {
        "x-goog-api-key": args.aiApiKey,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        systemInstruction: {
          parts: [{ text: args.prompt }],
        },
        contents: [{
          role: "user",
          parts: [{
            text: JSON.stringify({
              input: args.input,
              output_schema: args.schema,
              output_instruction:
                "Return exactly one JSON object matching output_schema. Put citation URLs in evidence_url fields only.",
            }),
          }],
        }],
        tools: [{ google_search: {} }],
        generationConfig: {
          maxOutputTokens: 4000,
          temperature: 0.2,
        },
      }),
    });
  } catch (error) {
    if (error instanceof DOMException && error.name === "AbortError") {
      throw new Error(`Gemini request timed out after ${AI_WEB_SEARCH_TIMEOUT_MS / 1000}s`);
    }
    throw error;
  } finally {
    clearTimeout(timeoutId);
  }

  const body = await response.json();
  if (!response.ok) {
    throw new Error(`Gemini request failed: ${JSON.stringify(body)}`);
  }

  const text = extractGeminiText(body);
  if (!text) {
    throw new Error(`Gemini response did not include output text: ${summarizeGeminiBody(body)}`);
  }

  return JSON.parse(stripJsonCodeFence(text)) as JsonObject;
}

function createSupabaseRestClient(supabaseUrl: string, serviceRoleKey: string) {
  const baseUrl = `${supabaseUrl.replace(/\/$/, "")}/rest/v1`;
  const rpcUrl = `${supabaseUrl.replace(/\/$/, "")}/rest/v1/rpc`;
  const headers = {
    "apikey": serviceRoleKey,
    "Authorization": `Bearer ${serviceRoleKey}`,
    "Content-Type": "application/json",
  };

  return {
    async rpc(functionName: string, payload: JsonObject) {
      const response = await fetch(`${rpcUrl}/${functionName}`, {
        method: "POST",
        headers: {
          ...headers,
          "Prefer": "return=representation",
        },
        body: JSON.stringify(payload),
      });
      const body = await response.json();
      if (!response.ok) throw new Error(`Supabase RPC ${functionName} failed: ${JSON.stringify(body)}`);
      return body;
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

function extractOutputText(response: JsonObject) {
  if (typeof response.output_text === "string") return response.output_text;

  const output = response.output;
  if (!Array.isArray(output)) return null;

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
  });
}

function extractGeminiText(response: JsonObject) {
  const candidates = response.candidates;
  if (!Array.isArray(candidates)) return null;

  for (const candidate of candidates) {
    if (!candidate || typeof candidate !== "object") continue;
    const content = (candidate as JsonObject).content;
    if (!content || typeof content !== "object") continue;
    const parts = (content as JsonObject).parts;
    if (!Array.isArray(parts)) continue;
    for (const part of parts) {
      if (!part || typeof part !== "object") continue;
      const text = (part as JsonObject).text;
      if (typeof text === "string") return text;
    }
  }

  return null;
}

function summarizeGeminiBody(response: JsonObject) {
  return JSON.stringify({
    promptFeedback: response.promptFeedback,
    candidates: Array.isArray(response.candidates)
      ? response.candidates.map((candidate) => {
        if (!candidate || typeof candidate !== "object") return typeof candidate;
        const candidateBody = candidate as JsonObject;
        return {
          finishReason: candidateBody.finishReason,
          safetyRatings: candidateBody.safetyRatings,
          hasContent: Boolean(candidateBody.content),
          partTypes: Array.isArray((candidateBody.content as JsonObject | undefined)?.parts)
            ? ((candidateBody.content as JsonObject).parts as unknown[]).map((part) => {
              if (!part || typeof part !== "object") return typeof part;
              return Object.keys(part as JsonObject);
            })
            : undefined,
        };
      })
      : undefined,
  });
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

function clampLimit(value: unknown) {
  const raw = typeof value === "number" ? value : Number(value ?? DEFAULT_LIMIT);
  if (!Number.isFinite(raw)) return DEFAULT_LIMIT;
  return Math.max(1, Math.min(MAX_LIMIT, Math.floor(raw)));
}

function stringOrDefault(value: unknown, fallback: string) {
  return typeof value === "string" && value.trim() ? value.trim() : fallback;
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

function daysFromNow(days: number) {
  const date = new Date();
  date.setDate(date.getDate() + days);
  return date.toISOString();
}

function stripJsonCodeFence(text: string) {
  const trimmed = text.trim();
  const fenced = trimmed.match(/^```(?:json)?\s*([\s\S]*?)\s*```$/i);
  return fenced ? fenced[1].trim() : trimmed;
}
