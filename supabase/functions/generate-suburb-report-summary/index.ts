import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

const CONTEXT_PROMPT_VERSION = "suburb_context_facts_v1";
const SUMMARY_PROMPT_VERSION = "suburb_report_summary_v2";
const SUMMARY_TYPE = "recommendation_report";
const AI_TEXT_TIMEOUT_MS = 50_000;
const AI_WEB_SEARCH_TIMEOUT_MS = 90_000;

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
  strategy?: string;
  strategy_label?: string;
  metrics: JsonObject;
  normalized_scores?: JsonObject;
  score_scale?: JsonObject;
  force_refresh_context?: boolean;
  force_refresh_summary?: boolean;
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

const summaryPrompt = `Write an executive-style suburb investment summary as schema-valid JSON.

Use only supplied metrics and cited context_facts. Do not use outside knowledge or add local facts. Mention hospitals, CBDs, industries, transport, education, infrastructure, distances, or drivers only if present in context_facts.

Interpret scores exactly as supplied:
- All normalized_scores are on a 0 to 10 scale.
- For total_score, growth_score, yield_score, demand_score, and population_growth_score: higher is better. 8-10 is strong, 7-7.9 is good, 4-6.9 is moderate, below 4 is weak.
- For risk_penalty only: lower is better. 0-3 is low risk, 4-6 is moderate risk, above 6 is elevated risk.
- For stock_on_market_pct: lower generally means tighter listed supply. Below 1% is very tight supply and should not be described as stock pressure. 1-2% is tight, 2-4% is moderate, 4-6% is elevated, and above 6% is high listed-supply pressure.
- Never describe a positive score of 7 or above as low, weak, poor, or a risk. For example, yield_score 9.3/10 is a strong yield signal, not a low yield signal.
- Use the selected strategy to decide emphasis. For a Capital Growth strategy, yield can be a secondary strength or neutral point; do not call a strong yield score a risk just because the strategy is growth. For a Rental Yield strategy, growth can be secondary.
- Put only genuinely adverse signals in risk_notes: positive score below 4, risk_penalty above 6, stock_on_market_pct at least 4%, or clearly adverse raw metrics where supplied. If stock_on_market_pct is below 1% and risk_penalty is 0-3, treat it as low supply-risk rather than stock pressure. If no clear adverse signal exists, return an empty risk_notes array.

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

    const supabaseUrl = requiredEnv("SUPABASE_URL");
    const supabaseServiceRoleKey =
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ??
        requiredEnv("FUTURLENS_SUPABASE_SERVICE_ROLE_KEY");
    const aiProvider = Deno.env.get("AI_PROVIDER") ?? "openai";
    if (aiProvider !== "openai" && aiProvider !== "gemini") {
      throw new Error(`Unsupported AI_PROVIDER: ${aiProvider}`);
    }
    const model = Deno.env.get("AI_MODEL") ?? "gpt-4o";
    const aiApiKey = requiredEnv(aiProvider === "gemini" ? "GEMINI_API_KEY" : "OPENAI_API_KEY");
    const aiApiUrl = getAiApiUrl(aiProvider, model);

    const supabase = createSupabaseRestClient(supabaseUrl, supabaseServiceRoleKey);

    const contextInput = {
      suburb_key: payload.suburb.suburb_key,
      suburb_name: payload.suburb.name,
      state: payload.suburb.state,
      postcode: payload.suburb.postcode ?? "",
      country: "Australia",
    };
    const contextInputHash = await sha256(canonicalJson({
      ai_provider: aiProvider,
      model,
      input: contextInput,
    }));

    const allowLiveContextRefresh = Deno.env.get("ALLOW_LIVE_CONTEXT_REFRESH") === "true";
    let contextRow = payload.force_refresh_context && allowLiveContextRefresh
      ? null
      : await findContextCache(supabase, payload.suburb.suburb_key, contextInputHash);

    if (!contextRow) {
      contextRow = await findLatestContextCache(supabase, payload.suburb.suburb_key);
    }

    if (!contextRow && allowLiveContextRefresh) {
      const factsPayload = await callAiStructuredJson({
        aiProvider,
        aiApiKey,
        aiApiUrl,
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

    const contextFacts = contextRow?.facts_payload as JsonObject | undefined;
    const summaryInput = {
      suburb: payload.suburb,
      strategy: payload.strategy ?? null,
      strategy_label: payload.strategy_label ?? null,
      metrics: payload.metrics,
      normalized_scores: payload.normalized_scores ?? normalizeScoresFromMetrics(payload.metrics),
      score_scale: payload.score_scale ?? defaultScoreScale(),
      context_facts: contextFacts?.facts ?? {},
      data_coverage: {
        has_local_context_facts: contextFacts ? countEvidenceUrls(contextFacts) > 0 : false,
        ai_provider: aiProvider,
        model,
        context_prompt_version: CONTEXT_PROMPT_VERSION,
        summary_prompt_version: SUMMARY_PROMPT_VERSION,
      },
    };
    const summaryInputHash = await sha256(canonicalJson(summaryInput));

    let summaryRow = payload.force_refresh_summary
      ? null
      : await findSummaryCache(supabase, payload.suburb.suburb_key, summaryInputHash);

    if (!summaryRow) {
      const summaryPayload = await callAiStructuredJson({
        aiProvider,
        aiApiKey,
        aiApiUrl,
        model,
        prompt: summaryPrompt,
        input: summaryInput,
        schemaName: "suburb_report_summary",
        schema: summarySchema,
        useWebSearch: false,
        state: payload.suburb.state,
      });
      sanitizeSummaryPayload(summaryPayload, summaryInput.normalized_scores as JsonObject, summaryInput.metrics as JsonObject);

      summaryRow = await upsertSummaryCache(supabase, {
        suburb_key: payload.suburb.suburb_key,
        summary_type: SUMMARY_TYPE,
        prompt_version: SUMMARY_PROMPT_VERSION,
        input_hash: summaryInputHash,
        input_payload: summaryInput,
        summary_payload: summaryPayload,
        model,
        confidence: stringOrNull(summaryPayload.confidence),
        context_facts_id: contextRow?.id ?? null,
        generated_at: new Date().toISOString(),
      });
    }

    return jsonResponse({
      suburb_key: payload.suburb.suburb_key,
      context_cache_id: contextRow?.id ?? null,
      summary_cache_id: summaryRow.id,
      context_facts: contextRow?.facts_payload ?? null,
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

function defaultScoreScale() {
  return {
    range: "0 to 10",
    positive_scores:
      "For total_score, growth_score, yield_score, demand_score, and population_growth_score: higher is better. 8-10 is strong, 7-7.9 is good, 4-6.9 is moderate, below 4 is weak.",
    risk_penalty:
      "For risk_penalty only: lower is better. 0-3 is low risk, 4-6 is moderate risk, above 6 is elevated risk.",
    stock_on_market_pct:
      "For stock_on_market_pct: lower generally means tighter listed supply. Below 1% is very tight supply and should not be described as stock pressure. 1-2% is tight, 2-4% is moderate, 4-6% is elevated, and above 6% is high listed-supply pressure.",
    risk_notes_rule:
      "Only mention stock-on-market in risk_notes when stock_on_market_pct is at least 4% or risk_penalty is above 6. If stock_on_market_pct is below 1% and risk_penalty is 0-3, treat it as low supply-risk rather than pressure.",
    interpretation_rule: "Never describe a positive score of 7 or above as low, weak, poor, or a risk.",
  };
}

function normalizeScoresFromMetrics(metrics: JsonObject) {
  return {
    total_score: normalizeScore(metrics.total_score),
    growth_score: normalizeScore(metrics.growth_score),
    yield_score: normalizeScore(metrics.yield_score),
    demand_score: normalizeScore(metrics.demand_score),
    risk_penalty: normalizeScore(metrics.risk_penalty),
    population_growth_score: normalizeScore(metrics.population_growth_score),
  };
}

function normalizeScore(value: unknown) {
  const num = Number(value);
  if (!Number.isFinite(num)) return null;
  const normalized = num > 10 ? num / 10 : num;
  return Math.max(0, Math.min(10, normalized));
}

function sanitizeSummaryPayload(summaryPayload: JsonObject, normalizedScores: JsonObject, metrics: JsonObject) {
  const riskNotes = summaryPayload.risk_notes;
  if (!Array.isArray(riskNotes)) return;

  summaryPayload.risk_notes = riskNotes.filter((note) => {
    if (typeof note !== "string") return false;
    if (contradictsLowStockRisk(note, normalizedScores, metrics)) return false;
    return !contradictsStrongScore(note, normalizedScores);
  });
}

function contradictsLowStockRisk(note: string, normalizedScores: JsonObject, metrics: JsonObject) {
  const text = note.toLowerCase();
  const mentionsStockPressure = /\b(stock|supply|listing|listed|inventory)\b/.test(text)
    && /\b(pressure|risk|concern|elevated|high|oversupply|excess)\b/.test(text);
  if (!mentionsStockPressure) return false;

  const riskPenalty = Number(normalizedScores.risk_penalty);
  const stockOnMarketPct = Number(metrics.stock_on_market_pct);
  return Number.isFinite(riskPenalty)
    && Number.isFinite(stockOnMarketPct)
    && riskPenalty <= 3
    && stockOnMarketPct < 1;
}

function contradictsStrongScore(note: string, normalizedScores: JsonObject) {
  const text = note.toLowerCase();
  const negativeWords = /\b(low|weak|poor|limited|soft|risk|concern|underperform|below|lagging)\b/;
  if (!negativeWords.test(text)) return false;

  const checks: Array<[string, string[]]> = [
    ["yield_score", ["yield", "rent", "rental"]],
    ["growth_score", ["growth", "capital"]],
    ["demand_score", ["demand"]],
    ["population_growth_score", ["population", "momentum"]],
    ["total_score", ["overall", "total"]],
  ];

  return checks.some(([scoreKey, keywords]) => {
    const score = Number(normalizedScores[scoreKey]);
    if (!Number.isFinite(score) || score < 7) return false;
    return keywords.some((keyword) => text.includes(keyword));
  });
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

async function callAiStructuredJson(args: {
  aiProvider: string;
  aiApiKey: string;
  aiApiUrl: string;
  model: string;
  prompt: string;
  input: JsonObject;
  schemaName: string;
  schema: JsonObject;
  useWebSearch: boolean;
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

  const timeoutMs = args.useWebSearch ? AI_WEB_SEARCH_TIMEOUT_MS : AI_TEXT_TIMEOUT_MS;
  const abortController = new AbortController();
  const timeoutId = setTimeout(() => abortController.abort(), timeoutMs);

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
        tools,
        tool_choice: args.useWebSearch ? "auto" : "none",
        include: args.useWebSearch ? ["web_search_call.action.sources"] : undefined,
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

async function callGeminiStructuredJson(args: {
  aiApiKey: string;
  aiApiUrl: string;
  model: string;
  prompt: string;
  input: JsonObject;
  schemaName: string;
  schema: JsonObject;
  useWebSearch: boolean;
  state: string;
}) {
  const timeoutMs = args.useWebSearch ? AI_WEB_SEARCH_TIMEOUT_MS : AI_TEXT_TIMEOUT_MS;
  const abortController = new AbortController();
  const timeoutId = setTimeout(() => abortController.abort(), timeoutMs);

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
          parts: [{ text: JSON.stringify(getGeminiInputPayload(args)) }],
        }],
        tools: args.useWebSearch ? [{ google_search: {} }] : undefined,
        generationConfig: getGeminiGenerationConfig(args),
      }),
    });
  } catch (error) {
    if (error instanceof DOMException && error.name === "AbortError") {
      throw new Error(`Gemini request timed out after ${timeoutMs / 1000}s`);
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

function getGeminiInputPayload(args: {
  input: JsonObject;
  schema: JsonObject;
  useWebSearch: boolean;
}) {
  if (!args.useWebSearch) {
    return args.input;
  }

  return {
    input: args.input,
    output_schema: args.schema,
  };
}

function getGeminiGenerationConfig(args: {
  schema: JsonObject;
  useWebSearch: boolean;
}) {
  const config: JsonObject = {
    maxOutputTokens: 4000,
    temperature: 0.2,
  };

  if (!args.useWebSearch) {
    config.responseMimeType = "application/json";
    config.responseSchema = toGeminiSchema(args.schema);
  }

  return config;
}

function stripJsonCodeFence(text: string) {
  const trimmed = text.trim();
  const fenced = trimmed.match(/^```(?:json)?\s*([\s\S]*?)\s*```$/i);
  return fenced ? fenced[1].trim() : trimmed;
}

function toGeminiSchema(schema: unknown): unknown {
  if (Array.isArray(schema)) {
    return schema.map(toGeminiSchema);
  }
  if (!schema || typeof schema !== "object") {
    return schema;
  }

  const input = schema as JsonObject;
  if (Array.isArray(input.type)) {
    const { type, ...rest } = input;
    return {
      anyOf: type.map((entry) => {
        if (entry === "null") return { type: "null" };
        return {
          ...(toGeminiSchema(rest) as JsonObject),
          type: entry,
        };
      }),
    };
  }

  const output: JsonObject = {};
  for (const [key, value] of Object.entries(input)) {
    if (key === "additionalProperties") continue;
    output[key] = toGeminiSchema(value);
  }
  return output;
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

async function findLatestContextCache(
  supabase: ReturnType<typeof createSupabaseRestClient>,
  suburbKey: string,
) {
  const query = new URLSearchParams({
    suburb_key: `eq.${suburbKey}`,
    prompt_version: `eq.${CONTEXT_PROMPT_VERSION}`,
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
