# Suburb Context Refresh Batch Workflow

Purpose:
- refresh AI/web-grounded suburb context facts outside the user-facing report flow
- process jobs from `public.suburb_context_refresh_jobs`
- keep report rendering fast by reusing cached context facts

## Phase 1 Smoke Test

Run these in order.

### 1. Confirm Secrets

The deployed function needs:

```sh
supabase secrets set AI_PROVIDER=gemini
supabase secrets set AI_MODEL=gemini-2.5-flash-lite
supabase secrets set OPENAI_API_URL=https://api.openai.com/v1/responses
supabase secrets set GEMINI_API_URL='https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent'
supabase secrets set GEMINI_API_KEY=...
supabase secrets set BATCH_WORKER_SECRET=...
supabase secrets set FUTURLENS_SUPABASE_SERVICE_ROLE_KEY=...
```

`SUPABASE_URL` is provided by the Supabase function runtime.

### 2. Deploy Worker

```sh
supabase functions deploy refresh-suburb-context-batch --no-verify-jwt
```

### 3. Enqueue Current-Month Jobs

Run in Supabase SQL Editor:

```sql
select *
from public.enqueue_suburb_context_refresh_jobs();
```

### 4. Smoke Test One Job

Call the worker with `limit: 1`.

```sh
curl -i --max-time 140 -X POST 'https://YOUR_PROJECT_REF.supabase.co/functions/v1/refresh-suburb-context-batch' \
  -H 'apikey: YOUR_SUPABASE_ANON_KEY' \
  -H 'x-batch-secret: YOUR_BATCH_WORKER_SECRET' \
  -H 'Content-Type: application/json' \
  -d '{"limit":1,"locked_by":"manual-smoke-test"}'
```

Expected response:

```json
{
  "requested_limit": 1,
  "claimed_count": 1,
  "completed_count": 1,
  "failed_count": 0
}
```

### 5. Verify Job Status

```sql
select status, count(*)
from public.suburb_context_refresh_jobs
group by status
order by status;
```

Inspect the latest completed job:

```sql
select
  j.suburb_key,
  j.status,
  j.attempt_count,
  j.context_facts_id,
  f.source_count,
  f.confidence,
  f.generated_at,
  f.expires_at
from public.suburb_context_refresh_jobs j
left join public.suburb_ai_context_facts f on f.id = j.context_facts_id
where j.status = 'completed'
order by j.completed_at desc
limit 5;
```

## Daily Batch

Once smoke testing passes, run daily with a larger limit:

```json
{"limit":25,"locked_by":"daily-cron"}
```

Increase gradually toward the target of 100 suburbs/day after observing:
- Gemini/API rate limits
- function duration
- failed job count
- source quality
