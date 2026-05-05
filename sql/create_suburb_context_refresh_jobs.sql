-- Purpose:
-- Queue and audit monthly AI context refresh work for suburbs.
--
-- Phase 1 scope:
-- - create the job/status table
-- - support daily batches of due jobs
-- - support retry/error tracking
-- - do not change the live report flow

create table if not exists public.suburb_context_refresh_jobs (
  id uuid primary key default gen_random_uuid(),

  suburb_key text not null
    references public.suburbs(suburb_key)
    on delete cascade,

  refresh_month date not null,
  prompt_version text not null default 'suburb_context_facts_v1',
  ai_provider text not null default 'gemini',
  model text not null default 'gemini-2.5-flash-lite',

  status text not null default 'pending'
    check (status in ('pending', 'processing', 'completed', 'failed')),

  priority integer not null default 100
    check (priority >= 0),

  attempt_count integer not null default 0
    check (attempt_count >= 0),

  max_attempts integer not null default 3
    check (max_attempts > 0),

  context_facts_id uuid null
    references public.suburb_ai_context_facts(id)
    on delete set null,

  locked_at timestamptz null,
  locked_by text null,
  started_at timestamptz null,
  completed_at timestamptz null,
  last_error text null,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint suburb_context_refresh_jobs_month_start
    check (refresh_month = date_trunc('month', refresh_month)::date),

  constraint suburb_context_refresh_jobs_unique
    unique (suburb_key, refresh_month, prompt_version, ai_provider, model)
);

create index if not exists idx_suburb_context_refresh_jobs_due
  on public.suburb_context_refresh_jobs (status, priority, created_at)
  where status in ('pending', 'failed');

create index if not exists idx_suburb_context_refresh_jobs_suburb
  on public.suburb_context_refresh_jobs (suburb_key, refresh_month desc);

create index if not exists idx_suburb_context_refresh_jobs_locked
  on public.suburb_context_refresh_jobs (locked_at)
  where status = 'processing';

create or replace function public.set_updated_at()
returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

drop trigger if exists trg_suburb_context_refresh_jobs_updated_at
on public.suburb_context_refresh_jobs;

create trigger trg_suburb_context_refresh_jobs_updated_at
before update on public.suburb_context_refresh_jobs
for each row
execute function public.set_updated_at();
