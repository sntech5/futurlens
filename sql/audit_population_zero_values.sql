-- Purpose:
-- Find zero population values, which should be treated as missing source data.
--
-- Safe: read-only checks.

select count(*) as population_metric_rows_with_zero_population
from public.suburb_population_metrics
where population_2025 = 0;

select
  suburb_key,
  suburb_name,
  state,
  postcode,
  population_2025,
  source_name
from public.suburb_population_metrics
where population_2025 = 0
order by state, suburb_name, postcode;

select count(*) as recommendation_payload_items_with_zero_population
from public.recommendations r
cross join lateral jsonb_array_elements(coalesce(r.top_suburbs, '[]'::jsonb)) as item(value)
where item.value ->> 'population_2025' = '0';
