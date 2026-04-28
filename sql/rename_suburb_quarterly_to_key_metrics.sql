-- Purpose:
-- Rename the active quarterly market metric table to a clearer name:
--
--   public.suburb_quarterly_data
--   -> public.suburb_key_metrics_quarterly
--
-- Safe to run once. If the new table already exists, this script does not rename.

do $$
begin
  if to_regclass('public.suburb_key_metrics_quarterly') is null
     and to_regclass('public.suburb_quarterly_data') is not null then
    alter table public.suburb_quarterly_data rename to suburb_key_metrics_quarterly;
  end if;
end;
$$;

alter table public.suburb_key_metrics_quarterly
  add column if not exists median_price numeric,
  add column if not exists median_rent_weekly numeric,
  add column if not exists gross_yield numeric;
