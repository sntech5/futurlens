# OpenAI Web Search Structured Smoke Test

Purpose:
- test OpenAI web search and structured JSON output together
- avoid cache writes and the full suburb context schema
- validate the exact combination needed by the report-summary flow

Function:
- [supabase/functions/openai-web-structured-smoke/index.ts](../supabase/functions/openai-web-structured-smoke/index.ts)

## Deploy

From repo root:

```sh
supabase functions deploy openai-web-structured-smoke
```

## Test

Replace `YOUR_SUPABASE_ANON_KEY` with the Supabase anonymous API key.

```sh
curl -i --max-time 120 -X POST 'https://mvmhapzbidspyzdkkyyp.supabase.co/functions/v1/openai-web-structured-smoke' \
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
  "result": {
    "suburb_name": "Millbank",
    "state": "QLD",
    "fact": "Short cited fact.",
    "evidence_url": "https://...",
    "confidence": "high"
  },
  "output_summary": {}
}
```

## What This Does Not Test

- full context fact schema
- Supabase cache table writes
- final report summary generation
- frontend report integration
