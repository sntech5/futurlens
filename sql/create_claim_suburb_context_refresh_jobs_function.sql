-- Purpose:
-- Claim the next due suburb context refresh jobs for a batch worker.
--
-- Usage example:
--   select *
--   from public.claim_suburb_context_refresh_jobs(10, 'manual-smoke-test');

create or replace function public.claim_suburb_context_refresh_jobs(
  p_limit integer default 25,
  p_locked_by text default 'suburb-context-refresh-worker',
  p_stale_after interval default interval '30 minutes'
)
returns table (
  job_id uuid,
  suburb_key text,
  suburb_name text,
  state text,
  postcode text,
  refresh_month date,
  prompt_version text,
  ai_provider text,
  model text,
  attempt_count integer
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_limit is null or p_limit <= 0 then
    raise exception 'p_limit must be greater than 0';
  end if;

  return query
  with due_jobs as (
    select j.id
    from public.suburb_context_refresh_jobs j
    where (
        j.status = 'pending'
        or (
          j.status = 'failed'
          and j.attempt_count < j.max_attempts
        )
        or (
          j.status = 'processing'
          and j.locked_at < now() - p_stale_after
          and j.attempt_count < j.max_attempts
        )
      )
      and j.attempt_count < j.max_attempts
    order by
      j.priority asc,
      j.created_at asc,
      j.id asc
    limit p_limit
    for update skip locked
  ),
  claimed as (
    update public.suburb_context_refresh_jobs j
    set
      status = 'processing',
      locked_at = now(),
      locked_by = coalesce(nullif(trim(p_locked_by), ''), 'suburb-context-refresh-worker'),
      started_at = coalesce(j.started_at, now()),
      completed_at = null,
      last_error = null,
      attempt_count = j.attempt_count + 1
    from due_jobs
    where j.id = due_jobs.id
    returning
      j.id,
      j.suburb_key,
      j.refresh_month,
      j.prompt_version,
      j.ai_provider,
      j.model,
      j.attempt_count
  )
  select
    c.id as job_id,
    c.suburb_key,
    s.suburb_name,
    s.state,
    s.postcode,
    c.refresh_month,
    c.prompt_version,
    c.ai_provider,
    c.model,
    c.attempt_count
  from claimed c
  join public.suburbs s on s.suburb_key = c.suburb_key
  order by c.attempt_count desc, c.suburb_key asc;
end;
$$;
