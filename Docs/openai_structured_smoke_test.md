# OpenAI Structured Smoke Test

Purpose:
- test OpenAI connectivity from Supabase Edge Functions
- test structured JSON output without web search
- avoid cache writes, report logic, and suburb context extraction while diagnosing API behavior

Function:
- [supabase/functions/openai-structured-smoke/index.ts](../supabase/functions/openai-structured-smoke/index.ts)

## Deploy

From repo root:

```sh
supabase functions deploy openai-structured-smoke
```

## Test

Replace `YOUR_SUPABASE_ANON_KEY` with the Supabase anonymous API key.

```sh
curl -i --max-time 60 -X POST 'https://mvmhapzbidspyzdkkyyp.supabase.co/functions/v1/openai-structured-smoke' \
  -H 'Authorization: Bearer YOUR_SUPABASE_ANON_KEY' \
  -H 'Content-Type: application/json' \
  -d '{}'
```

## Expected Success Shape

```json
{
  "ok": true,
  "elapsed_ms": 1234,
  "model": "gpt-5",
  "result": {
    "ok": true,
    "summary": "Structured output works.",
    "checks": [
      {
        "name": "structured_output",
        "status": "pass"
      }
    ]
  }
}
```

## What This Does Not Test

- OpenAI web search
- suburb context fact extraction
- Supabase cache table writes
- final report summary generation
