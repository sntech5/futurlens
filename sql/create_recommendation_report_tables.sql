-- Reference: Docs/recommendation_pdf_report_workflow.md
-- Purpose: MVP schema for stored customer-facing recommendation PDF reports.

create table if not exists public.recommendation_reports (
  id uuid primary key default gen_random_uuid(),

  report_code text not null unique,

  recommendation_run_id uuid not null
    references public.recommendation_runs(id)
    on delete restrict,

  recommendation_id uuid null
    references public.recommendations(id)
    on delete set null,

  customer_name text not null,
  customer_email text not null,

  generated_by_user_profile_id uuid not null
    references public.user_profiles(id)
    on delete restrict,

  report_date date not null default current_date,
  daily_sequence integer not null,

  pdf_storage_path text null,
  pdf_file_name text null,

  report_status text not null default 'draft'
    check (report_status in ('draft', 'generating', 'generated', 'failed')),

  generated_at timestamptz null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (report_date, daily_sequence)
);

create table if not exists public.recommendation_report_suburbs (
  id uuid primary key default gen_random_uuid(),

  report_id uuid not null
    references public.recommendation_reports(id)
    on delete cascade,

  suburb_key text not null
    references public.suburbs(suburb_key)
    on delete restrict,

  source_rank integer not null check (source_rank > 0),
  report_rank integer not null check (report_rank > 0),

  suburb_snapshot jsonb not null,

  created_at timestamptz not null default now(),

  unique (report_id, suburb_key),
  unique (report_id, report_rank)
);

create index if not exists idx_recommendation_reports_run
  on public.recommendation_reports (recommendation_run_id, created_at desc);

create index if not exists idx_recommendation_reports_code
  on public.recommendation_reports (report_code);

create index if not exists idx_recommendation_report_suburbs_report
  on public.recommendation_report_suburbs (report_id, report_rank);
