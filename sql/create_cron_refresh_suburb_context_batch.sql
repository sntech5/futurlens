-- Purpose:
-- Schedule the suburb context refresh batch worker.
--
-- Before running:
-- - confirm pg_cron is enabled
-- - confirm pg_net is enabled
-- - replace YOUR_SUPABASE_ANON_KEY before executing
-- - replace YOUR_BATCH_WORKER_SECRET before executing
--
-- Initial rollout uses limit 5. Increase gradually after observing failures,
-- provider quota/rate limits, and function duration.

create extension if not exists pg_net with schema extensions;

select cron.unschedule('daily-suburb-context-refresh-batch')
where exists (
  select 1
  from cron.job
  where jobname = 'daily-suburb-context-refresh-batch'
);

select cron.schedule(
  'daily-suburb-context-refresh-batch',
  '0 2 * * *',
  $$
  select net.http_post(
    url := 'https://mvmhapzbidspyzdkkyyp.supabase.co/functions/v1/refresh-suburb-context-batch',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'apikey', 'YOUR_SUPABASE_ANON_KEY',
      'x-batch-secret', 'YOUR_BATCH_WORKER_SECRET'
    ),
    body := jsonb_build_object(
      'limit', 5,
      'locked_by', 'daily-cron'
    )
  );
  $$
);
