-- Purpose:
-- Audit population metric coverage across the current recommendation universe.
--
-- Safe: read-only checks.

select
  count(*) as base_score_rows,
  count(pm.suburb_key) as base_score_rows_with_population_metrics,
  count(*) - count(pm.suburb_key) as base_score_rows_missing_population_metrics,
  round((count(pm.suburb_key)::numeric / nullif(count(*), 0)) * 100, 1) as population_metric_coverage_pct
from public.suburb_base_scores s
left join public.suburb_population_metrics pm
  on pm.suburb_key = s.suburb_key;

select
  s.suburb_key,
  sub.suburb_name,
  sub.state,
  sub.postcode
from public.suburb_base_scores s
left join public.suburb_population_metrics pm
  on pm.suburb_key = s.suburb_key
left join public.suburbs sub
  on sub.suburb_key = s.suburb_key
where pm.suburb_key is null
order by sub.state, sub.suburb_name;
