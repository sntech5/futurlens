-- Reference: Docs/recommendation_pdf_report_workflow.md
-- Purpose: MVP functions for creating recommendation PDF report metadata
-- and updating stored PDF status.

create or replace function public.create_recommendation_report_with_suburbs(
  p_recommendation_run_id uuid,
  p_recommendation_id uuid,
  p_customer_name text,
  p_customer_email text,
  p_generated_by_user_profile_id uuid,
  p_selected_suburb_keys text[]
)
returns public.recommendation_reports
language plpgsql
as $$
declare
  v_report_date date := current_date;
  v_daily_sequence integer;
  v_name_slug text;
  v_report_code text;
  v_report public.recommendation_reports;
  v_inserted_count integer;
begin
  if nullif(trim(p_customer_name), '') is null then
    raise exception 'customer_name is required';
  end if;

  if nullif(trim(p_customer_email), '') is null then
    raise exception 'customer_email is required';
  end if;

  if p_selected_suburb_keys is null or array_length(p_selected_suburb_keys, 1) is null then
    raise exception 'At least one suburb must be selected';
  end if;

  select coalesce(max(daily_sequence), 0) + 1
  into v_daily_sequence
  from public.recommendation_reports
  where report_date = v_report_date;

  v_name_slug :=
    upper(
      regexp_replace(
        regexp_replace(trim(p_customer_name), '[^a-zA-Z0-9]+', '-', 'g'),
        '(^-|-$)',
        '',
        'g'
      )
    );

  if v_name_slug = '' then
    v_name_slug := 'CUSTOMER';
  end if;

  v_report_code :=
    v_name_slug
    || '-'
    || to_char(v_report_date, 'YYYYMMDD')
    || '-'
    || lpad(v_daily_sequence::text, 3, '0');

  insert into public.recommendation_reports (
    report_code,
    recommendation_run_id,
    recommendation_id,
    customer_name,
    customer_email,
    generated_by_user_profile_id,
    report_date,
    daily_sequence,
    report_status
  )
  values (
    v_report_code,
    p_recommendation_run_id,
    p_recommendation_id,
    trim(p_customer_name),
    trim(p_customer_email),
    p_generated_by_user_profile_id,
    v_report_date,
    v_daily_sequence,
    'draft'
  )
  returning * into v_report;

  insert into public.recommendation_report_suburbs (
    report_id,
    suburb_key,
    source_rank,
    report_rank,
    suburb_snapshot
  )
  select
    v_report.id,
    elem.suburb_key,
    elem.source_rank,
    elem.report_rank,
    elem.suburb_snapshot
  from (
    select
      item.value ->> 'suburb' as suburb_key,
      item.ordinality::integer as source_rank,
      selected.ordinality::integer as report_rank,
      item.value as suburb_snapshot
    from public.recommendations r
    cross join lateral jsonb_array_elements(r.top_suburbs) with ordinality as item(value, ordinality)
    join unnest(p_selected_suburb_keys) with ordinality as selected(suburb_key, ordinality)
      on selected.suburb_key = item.value ->> 'suburb'
    where r.id = p_recommendation_id
  ) elem
  order by elem.report_rank;

  get diagnostics v_inserted_count = row_count;

  if v_inserted_count = 0 then
    raise exception 'None of the selected suburb keys were found in the recommendation result';
  end if;

  return v_report;
end;
$$;

create or replace function public.update_recommendation_report_pdf_status(
  p_report_id uuid,
  p_report_status text,
  p_pdf_storage_path text default null,
  p_pdf_file_name text default null
)
returns public.recommendation_reports
language plpgsql
as $$
declare
  v_report public.recommendation_reports;
begin
  if p_report_status not in ('generated', 'failed') then
    raise exception 'p_report_status must be generated or failed';
  end if;

  if p_report_status = 'generated' then
    if nullif(trim(p_pdf_storage_path), '') is null then
      raise exception 'pdf_storage_path is required when report_status is generated';
    end if;

    if nullif(trim(p_pdf_file_name), '') is null then
      raise exception 'pdf_file_name is required when report_status is generated';
    end if;
  end if;

  update public.recommendation_reports
  set
    report_status = p_report_status,
    pdf_storage_path = case
      when p_report_status = 'generated' then trim(p_pdf_storage_path)
      else pdf_storage_path
    end,
    pdf_file_name = case
      when p_report_status = 'generated' then trim(p_pdf_file_name)
      else pdf_file_name
    end,
    generated_at = case
      when p_report_status = 'generated' then now()
      else generated_at
    end,
    updated_at = now()
  where id = p_report_id
  returning * into v_report;

  if v_report.id is null then
    raise exception 'Report % not found', p_report_id;
  end if;

  return v_report;
end;
$$;
