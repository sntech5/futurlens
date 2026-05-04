# OpenAI Structured Suburb Summary Contract

Purpose:
- define the prompt and JSON output contract for AI-generated suburb report commentary
- allow OpenAI to fetch reliable local context facts while keeping report wording source-backed
- separate local fact extraction from final report summary generation
- support cache-by-input-hash so OpenAI is called only when the input payload changes

Status:
- prompt/schema contract approved
- cache table SQL created
- Edge Function scaffold created
- do not create frontend integration until the next implementation step is approved

SQL reference:
- [create_openai_suburb_summary_cache_tables.sql](../sql/create_openai_suburb_summary_cache_tables.sql)

Edge Function reference:
- [openai_suburb_summary_edge_function.md](openai_suburb_summary_edge_function.md)

## Design Rule

OpenAI can help in two different roles:

1. Fact extractor:
   - searches for local suburb context
   - returns only cited structured facts
   - does not write investment commentary

2. Report writer:
   - receives app metrics plus cached cited context facts
   - writes concise structured report commentary
   - does not introduce new facts

This split keeps the final report readable while making the source of local context easier to audit.

## Prompt Version Names

Use explicit prompt versions so cached output can be invalidated intentionally when wording or schema rules change.

```text
suburb_context_facts_v1
suburb_report_summary_v1
```

## Context Fact Extraction Prompt

Use this for the OpenAI call that performs web-backed context extraction.

```text
Extract cited, investment-relevant local context facts for an Australian suburb report.

Use web search and return only schema-valid JSON. Include a fact only when it has a citation URL. Prefer official sources: government, council, health, education, transport, infrastructure, economic development, or regional development pages. Avoid blogs, agents, forums, SEO pages, and unsourced claims unless no stronger source exists; lower confidence if used.

Allowed categories only: nearest major/regional city distance, healthcare, CBD/activity/employment centre, economic/employment drivers, university/TAFE, material transport, major demand-relevant infrastructure. At most one concise fact per category.

Exclude cemeteries, heritage-only facts, random addresses, parks, churches, clubs, minor facilities, postcode-only confirmation, trivia, marketing language, investment claims, and uncited or inferred facts. Use empty arrays/nulls where reliable report-useful evidence is not found.
```

## Context Fact Extraction Input

Minimum input:

```json
{
  "suburb_key": "MILLBANK_QLD_4670",
  "suburb_name": "Millbank",
  "state": "QLD",
  "postcode": "4670",
  "country": "Australia"
}
```

## Context Fact Extraction Output Schema

Expected structured result:

```json
{
  "suburb_key": "string",
  "suburb_name": "string",
  "state": "string",
  "postcode": "string",
  "facts": {
    "nearest_major_city": {
      "name": "string",
      "distance_km": "number|null",
      "evidence_url": "string"
    },
    "healthcare": [
      {
        "name": "string",
        "fact": "string",
        "evidence_url": "string"
      }
    ],
    "activity_centres": [
      {
        "name": "string",
        "fact": "string",
        "evidence_url": "string"
      }
    ],
    "local_drivers": [
      {
        "name": "string",
        "fact": "string",
        "evidence_url": "string"
      }
    ],
    "transport": [
      {
        "name": "string",
        "fact": "string",
        "evidence_url": "string"
      }
    ],
    "education": [
      {
        "name": "string",
        "fact": "string",
        "evidence_url": "string"
      }
    ],
    "infrastructure": [
      {
        "name": "string",
        "fact": "string",
        "evidence_url": "string"
      }
    ]
  },
  "confidence": "high|medium|low",
  "data_limitations": ["string"]
}
```

## Report Summary Prompt

Use this for the OpenAI call that writes the final report commentary.

```text
Write an executive-style suburb investment summary as schema-valid JSON.

Use only supplied metrics and cited context_facts. Do not use outside knowledge or add local facts. Mention hospitals, CBDs, industries, transport, education, infrastructure, distances, or drivers only if present in context_facts.

Be concise, cautious, and factual. Do not guarantee performance. Prefer "may support", "is associated with", "based on supplied metrics", and "where source data is available". Omit missing facts or note them only in data_limitations.

Do not recite every metric. Highlight the most decision-relevant signals only. Limits: summary max 2 short sentences; strengths max 3; local_drivers max 3; risk_notes max 2; data_limitations max 3.
```

## Report Summary Input

The final report summary input combines app metrics and cached context facts.

```json
{
  "suburb": {
    "suburb_key": "MILLBANK_QLD_4670",
    "name": "Millbank",
    "state": "QLD",
    "postcode": "4670"
  },
  "metrics": {
    "median_price": 520000,
    "median_rent_weekly": 560,
    "gross_yield_pct": 5.6,
    "vacancy_rate_pct": 1.2,
    "days_on_market": 34,
    "vendor_discount_pct": 3.1,
    "growth_score": 72,
    "population_growth_pct": 2.8,
    "population_growth_vs_state_pct": 1.1,
    "population_growth_score": 68
  },
  "context_facts": {
    "nearest_major_city": {
      "name": "Brisbane",
      "distance_km": 360,
      "evidence_url": "https://example.com/source"
    },
    "healthcare": [],
    "activity_centres": [],
    "local_drivers": [],
    "transport": [],
    "education": [],
    "infrastructure": []
  },
  "data_coverage": {
    "has_population_metrics": true,
    "has_local_context_facts": true,
    "source_notes": [
      "Population metrics sourced from loaded ABS-derived population table",
      "Local context facts supplied by cached cited AI context extraction"
    ]
  }
}
```

## Report Summary Output Schema

Expected structured result:

```json
{
  "summary": "string",
  "strengths": ["string"],
  "local_drivers": ["string"],
  "risk_notes": ["string"],
  "data_limitations": ["string"],
  "confidence": "high|medium|low"
}
```

- `summary`: maximum 2 short sentences
- `strengths`: maximum 3 items
- `local_drivers`: maximum 3 items
- `risk_notes`: maximum 2 items
- `data_limitations`: maximum 3 items
- `confidence`: reflects input completeness and source quality, not investment certainty

## Cache Rule

Context facts and report summaries should be cached separately.

Context fact cache key:

```text
suburb_key + prompt_version + input_hash
```

Report summary cache key:

```text
suburb_key + summary_type + prompt_version + input_hash
```

The `input_hash` should be generated from canonical JSON for the exact input payload passed to OpenAI.

Regenerate context facts when:
- prompt version changes
- suburb identity input changes
- cached context is manually expired or refreshed

Regenerate report summary when:
- prompt version changes
- suburb metrics change
- cached context facts change
- report summary input payload changes

## Guardrails

- Do not call OpenAI from the frontend.
- Keep the OpenAI API key server-side only.
- Validate model output against the expected JSON schema before storing or rendering it.
- Store the input payload and output payload for auditability.
- Store the model name and prompt version with each cached result.
- Never overwrite source metrics with AI-generated values.
- Treat AI-generated context facts as report context, not scoring inputs, unless a later scoring feature explicitly adopts them.
