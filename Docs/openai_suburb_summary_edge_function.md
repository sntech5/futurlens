# OpenAI Suburb Summary Edge Function

Purpose:
- document the server-side function that generates cached AI suburb context facts and report summaries
- keep the OpenAI API key out of the frontend
- describe the exact request payload needed by the app when report integration is added

Function:
- [supabase/functions/generate-suburb-report-summary/index.ts](../supabase/functions/generate-suburb-report-summary/index.ts)

Related contract:
- [openai_structured_suburb_summary_contract.md](openai_structured_suburb_summary_contract.md)

Before testing this full report-summary function, first validate basic OpenAI structured output with:
- [openai_structured_smoke_test.md](openai_structured_smoke_test.md)

Then validate OpenAI web search separately with:
- [openai_web_search_smoke_test.md](openai_web_search_smoke_test.md)

Then validate web search and structured output together with:
- [openai_web_structured_smoke_test.md](openai_web_structured_smoke_test.md)

## What The Function Does

On each request for one suburb:

1. Builds the context-fact input from suburb identity.
2. Checks `public.suburb_ai_context_facts` using `suburb_key + prompt_version + input_hash`.
3. If no valid context cache exists, calls OpenAI with web search and stores cited structured facts.
4. Builds the report-summary input from supplied app metrics plus cached context facts.
5. Checks `public.suburb_report_ai_summaries` using `suburb_key + summary_type + prompt_version + input_hash`.
6. If no summary cache exists, calls OpenAI without web search and stores the structured report summary.
7. Returns the cached or newly generated context facts and report summary.

Current context-extraction guardrail:
- web search uses a 90-second timeout
- context facts must be investment-relevant
- cemetery, heritage-only, random-address, postcode-only, and trivia facts are excluded
- categories can be returned empty when reliable report-useful evidence is not found

## Required Secrets

Set these in Supabase before deploying/running the function:

```sh
supabase secrets set OPENAI_API_KEY=...
supabase secrets set OPENAI_MODEL=gpt-5
supabase secrets set FUTURLENS_SUPABASE_SERVICE_ROLE_KEY=...
```

The function also expects the standard Supabase project URL:

```text
SUPABASE_URL
```

Do not expose `OPENAI_API_KEY` or `SUPABASE_SERVICE_ROLE_KEY` in frontend config.
Do not expose `FUTURLENS_SUPABASE_SERVICE_ROLE_KEY` in frontend config.

Security note:
- do not wire this to the frontend until the app has an agreed auth/rate-limit approach, because every uncached request can spend OpenAI credits

## Request Payload

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
  }
}
```

Optional flags:

```json
{
  "force_refresh_context": true,
  "force_refresh_summary": true
}
```

## Response Shape

```json
{
  "suburb_key": "MILLBANK_QLD_4670",
  "context_cache_id": "uuid",
  "summary_cache_id": "uuid",
  "context_facts": {},
  "report_summary": {
    "summary": "string",
    "strengths": ["max 3 strings"],
    "local_drivers": ["max 3 strings"],
    "risk_notes": ["max 2 strings"],
    "data_limitations": ["max 3 strings"],
    "confidence": "high"
  }
}
```

## Frontend Integration Status

Integrated in [suburb-app/index.html](../suburb-app/index.html).

Current behavior:
- report draft creation calls this Edge Function once per selected suburb
- each response is attached to the in-memory report item
- `report_summary` and cited `context_facts` render in the PDF preview before the report metadata/footer
- if one suburb's AI request fails, the report still opens and shows an explicit unavailable/error message for that suburb instead of invented commentary
