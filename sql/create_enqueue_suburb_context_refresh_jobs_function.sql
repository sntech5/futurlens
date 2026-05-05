-- Purpose:
-- Enqueue monthly suburb context refresh jobs from app-visible metric suburbs.
--
-- Usage examples:
--   select public.enqueue_suburb_context_refresh_jobs();
--   select public.enqueue_suburb_context_refresh_jobs(date '2026-05-01', 'gemini', 'gemini-2.5-flash-lite');

create or replace function public.enqueue_suburb_context_refresh_jobs(
  p_refresh_month date default date_trunc('month', current_date)::date,
  p_ai_provider text default 'gemini',
  p_model text default 'gemini-2.5-flash-lite',
  p_prompt_version text default 'suburb_context_facts_v1',
  p_priority integer default 100
)
returns table (
  inserted_count integer,
  existing_count integer,
  total_for_month integer
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_refresh_month date := date_trunc('month', p_refresh_month)::date;
  v_existing_count integer;
  v_inserted_count integer;
  v_total_for_month integer;
begin
  if p_ai_provider is null or trim(p_ai_provider) = '' then
    raise exception 'p_ai_provider is required';
  end if;

  if p_model is null or trim(p_model) = '' then
    raise exception 'p_model is required';
  end if;

  if p_prompt_version is null or trim(p_prompt_version) = '' then
    raise exception 'p_prompt_version is required';
  end if;

  select count(*)
  into v_existing_count
  from public.suburb_context_refresh_jobs
  where refresh_month = v_refresh_month
    and prompt_version = p_prompt_version
    and ai_provider = p_ai_provider
    and model = p_model;

  insert into public.suburb_context_refresh_jobs (
    suburb_key,
    refresh_month,
    prompt_version,
    ai_provider,
    model,
    priority
  )
  select
    s.suburb_key,
    v_refresh_month,
    p_prompt_version,
    p_ai_provider,
    p_model,
    p_priority
  from (
    select distinct suburb_key
    from public.suburb_key_metrics_quarterly
    where suburb_key is not null
  ) s
  on conflict (suburb_key, refresh_month, prompt_version, ai_provider, model)
  do nothing;

  get diagnostics v_inserted_count = row_count;

  select count(*)
  into v_total_for_month
  from public.suburb_context_refresh_jobs
  where refresh_month = v_refresh_month
    and prompt_version = p_prompt_version
    and ai_provider = p_ai_provider
    and model = p_model;

  inserted_count := v_inserted_count;
  existing_count := v_existing_count;
  total_for_month := v_total_for_month;
  return next;
end;
$$;
