-- Reference: Docs/openai_structured_suburb_summary_contract.md
-- Purpose:
-- Cache OpenAI-generated suburb context facts and structured report summaries.
--
-- Design:
-- - Context facts are cached separately from report summaries.
-- - Context facts can be reused across report generations.
-- - Report summaries are regenerated only when the exact input payload changes.
-- - input_hash must be generated from canonical JSON for the exact OpenAI input.
-- - OpenAI output is stored as JSONB for auditability and future report reuse.

create table if not exists public.suburb_ai_context_facts (
  id uuid primary key default gen_random_uuid(),

  suburb_key text not null
    references public.suburbs(suburb_key)
    on delete cascade,

  prompt_version text not null default 'suburb_context_facts_v1',
  input_hash text not null,

  input_payload jsonb not null
    check (jsonb_typeof(input_payload) = 'object'),

  facts_payload jsonb not null
    check (jsonb_typeof(facts_payload) = 'object'),

  model text not null,
  confidence text null
    check (confidence is null or confidence in ('high', 'medium', 'low')),

  source_count integer not null default 0
    check (source_count >= 0),

  generated_at timestamptz not null default now(),
  expires_at timestamptz null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint suburb_ai_context_facts_cache_unique
    unique (suburb_key, prompt_version, input_hash)
);

create table if not exists public.suburb_report_ai_summaries (
  id uuid primary key default gen_random_uuid(),

  suburb_key text not null
    references public.suburbs(suburb_key)
    on delete cascade,

  summary_type text not null default 'recommendation_report',
  prompt_version text not null default 'suburb_report_summary_v1',
  input_hash text not null,

  input_payload jsonb not null
    check (jsonb_typeof(input_payload) = 'object'),

  summary_payload jsonb not null
    check (jsonb_typeof(summary_payload) = 'object'),

  model text not null,
  confidence text null
    check (confidence is null or confidence in ('high', 'medium', 'low')),

  context_facts_id uuid null
    references public.suburb_ai_context_facts(id)
    on delete set null,

  generated_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint suburb_report_ai_summaries_cache_unique
    unique (suburb_key, summary_type, prompt_version, input_hash)
);

create index if not exists idx_suburb_ai_context_facts_suburb
  on public.suburb_ai_context_facts (suburb_key, generated_at desc);

create index if not exists idx_suburb_ai_context_facts_expires_at
  on public.suburb_ai_context_facts (expires_at)
  where expires_at is not null;

create index if not exists idx_suburb_report_ai_summaries_suburb
  on public.suburb_report_ai_summaries (suburb_key, generated_at desc);

create index if not exists idx_suburb_report_ai_summaries_context_facts
  on public.suburb_report_ai_summaries (context_facts_id)
  where context_facts_id is not null;

create or replace function public.set_updated_at()
returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

drop trigger if exists trg_suburb_ai_context_facts_updated_at
on public.suburb_ai_context_facts;

create trigger trg_suburb_ai_context_facts_updated_at
before update on public.suburb_ai_context_facts
for each row
execute function public.set_updated_at();

drop trigger if exists trg_suburb_report_ai_summaries_updated_at
on public.suburb_report_ai_summaries;

create trigger trg_suburb_report_ai_summaries_updated_at
before update on public.suburb_report_ai_summaries
for each row
execute function public.set_updated_at();
