-- Purpose:
-- Store source-backed suburb population metrics for report context and future
-- scoring/recommendation model improvements.
--
-- Source:
-- ABS Regional Population 2024-25, Population estimates by SA2 and above.
--
-- Notes:
-- - Population metrics are keyed to public.suburbs via suburb_key.
-- - SA2 source data is allocated to suburb level using residential mesh-block
--   proportional allocation.
-- - This table is not currently part of the recommendation ranking SQL unless
--   explicitly joined into a future scoring/recommendation patch.

create table if not exists public.suburb_population_metrics (
  id bigserial primary key,

  suburb_key text not null,
  suburb_name text not null,
  state text not null,
  postcode text,

  population_2025 integer,

  growth_2023_2024_pct numeric(8,3),
  growth_2024_2025_pct numeric(8,3),

  source_level text not null default 'SA2_ALLOCATED_TO_SUBURB',
  allocation_method text not null default 'RESIDENTIAL_MB_PROPORTIONAL',
  source_year integer not null default 2025,
  source_name text not null default 'ABS Regional Population 2024-25, Population estimates by SA2 and above',

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint suburb_population_metrics_suburb_key_unique unique (suburb_key),

  constraint suburb_population_metrics_suburb_fk
    foreign key (suburb_key)
    references public.suburbs (suburb_key)
    on delete cascade
);

create index if not exists idx_suburb_population_metrics_state
on public.suburb_population_metrics (state);

create index if not exists idx_suburb_population_metrics_postcode
on public.suburb_population_metrics (postcode);

create index if not exists idx_suburb_population_metrics_population_2025
on public.suburb_population_metrics (population_2025);

create index if not exists idx_suburb_population_metrics_growth_24_25
on public.suburb_population_metrics (growth_2024_2025_pct);

create or replace function public.set_updated_at()
returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

drop trigger if exists trg_suburb_population_metrics_updated_at
on public.suburb_population_metrics;

create trigger trg_suburb_population_metrics_updated_at
before update on public.suburb_population_metrics
for each row
execute function public.set_updated_at();
