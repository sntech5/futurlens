# OpenAI Web Search Smoke Test

Purpose:
- test OpenAI web search from Supabase Edge Functions
- avoid structured JSON schema, cache writes, and report-summary logic
- isolate whether web search latency/tool behavior is the blocker

Function:
- [supabase/functions/openai-web-search-smoke/index.ts](../supabase/functions/openai-web-search-smoke/index.ts)

## Deploy

From repo root:

```sh
supabase functions deploy openai-web-search-smoke
```

## Test

Replace `YOUR_SUPABASE_ANON_KEY` with the Supabase anonymous API key.

```sh
curl -i --max-time 90 -X POST 'https://mvmhapzbidspyzdkkyyp.supabase.co/functions/v1/openai-web-search-smoke' \
  -H 'Authorization: Bearer YOUR_SUPABASE_ANON_KEY' \
  -H 'Content-Type: application/json' \
  -d '{
    "suburb_name": "Millbank",
    "state": "QLD",
    "postcode": "4670"
  }'
```

## Expected Success Shape

```json
{
  "ok": true,
  "elapsed_ms": 12345,
  "model": "gpt-5-2025-08-07",
  "status": "completed",
  "incomplete_details": null,
  "output_text": "Brief web-backed fact...",
  "output_summary": {}
}
```

## What This Does Not Test

- structured JSON schema
- report summary cache writes
- context fact cache writes
- final report integration
