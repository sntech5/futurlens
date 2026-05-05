-- Purpose:
-- Mark suburb context refresh jobs as completed or failed after a worker attempt.

create or replace function public.complete_suburb_context_refresh_job(
  p_job_id uuid,
  p_context_facts_id uuid
)
returns public.suburb_context_refresh_jobs
language plpgsql
security definer
set search_path = public
as $$
declare
  v_job public.suburb_context_refresh_jobs;
begin
  if p_job_id is null then
    raise exception 'p_job_id is required';
  end if;

  if p_context_facts_id is null then
    raise exception 'p_context_facts_id is required';
  end if;

  update public.suburb_context_refresh_jobs
  set
    status = 'completed',
    context_facts_id = p_context_facts_id,
    completed_at = now(),
    locked_at = null,
    locked_by = null,
    last_error = null
  where id = p_job_id
  returning *
  into v_job;

  if not found then
    raise exception 'suburb_context_refresh_jobs row not found for id %', p_job_id;
  end if;

  return v_job;
end;
$$;

create or replace function public.fail_suburb_context_refresh_job(
  p_job_id uuid,
  p_error text
)
returns public.suburb_context_refresh_jobs
language plpgsql
security definer
set search_path = public
as $$
declare
  v_job public.suburb_context_refresh_jobs;
begin
  if p_job_id is null then
    raise exception 'p_job_id is required';
  end if;

  update public.suburb_context_refresh_jobs
  set
    status = 'failed',
    completed_at = null,
    locked_at = null,
    locked_by = null,
    last_error = left(coalesce(nullif(trim(p_error), ''), 'Unknown refresh error'), 4000)
  where id = p_job_id
  returning *
  into v_job;

  if not found then
    raise exception 'suburb_context_refresh_jobs row not found for id %', p_job_id;
  end if;

  return v_job;
end;
$$;
