-- Purpose:
-- Diagnose why a suburb has population_2025 but missing/null population growth
-- fields or population momentum score.
--
-- Supabase SQL Editor note:
-- Run one numbered query block at a time.
--
-- Default target: LUTANA_TAS_7009.

-- QUERY 1: Check source population row for the target suburb
-- If growth_2023_2024_pct or growth_2024_2025_pct is null, population growth
-- momentum cannot be source-calculated for this suburb.
select
  p.suburb_key,
  p.suburb_name,
  p.state,
  p.postcode,
  p.population_2025,
  p.growth_2023_2024_pct,
  p.growth_2024_2025_pct,
  p.source_level,
  p.allocation_method,
  p.source_year,
  p.source_name,
  p.updated_at
from public.suburb_population_metrics p
where p.suburb_key = 'LUTANA_TAS_7009';


-- QUERY 2: Check current score row for the target suburb
-- Expected when only population_2025 exists:
-- - population_growth_pct is null
-- - population_growth_vs_state_pct is null
-- - base_population_growth_score should be neutral 5
select
  b.suburb_key,
  b.population_growth_pct,
  b.population_growth_vs_state_pct,
  b.base_population_growth_score,
  b.base_growth_score,
  b.base_growth_strategy_total_score,
  b.score_confidence,
  b.refreshed_at
from public.suburb_base_scores b
where b.suburb_key = 'LUTANA_TAS_7009';


-- QUERY 3: Count population rows that have population but no growth source data
-- These rows can show population_2025 but cannot produce source-backed growth
-- momentum unless growth percentages are loaded.
select
  state,
  count(*) as population_rows,
  count(*) filter (where population_2025 is not null) as rows_with_population_2025,
  count(*) filter (
    where population_2025 is not null
      and (growth_2023_2024_pct is null or growth_2024_2025_pct is null)
  ) as rows_with_population_but_missing_growth_rates,
  count(*) filter (
    where growth_2023_2024_pct is not null
      and growth_2024_2025_pct is not null
  ) as rows_with_growth_rates
from public.suburb_population_metrics
group by state
order by rows_with_population_but_missing_growth_rates desc, state;


-- QUERY 4: List scored suburbs with population but no source-backed growth rates
-- These should generally have neutral population momentum scoring, not invented
-- growth metrics.
select
  b.suburb_key,
  s.suburb_name,
  s.state,
  s.postcode,
  p.population_2025,
  p.growth_2023_2024_pct,
  p.growth_2024_2025_pct,
  b.population_growth_pct,
  b.population_growth_vs_state_pct,
  b.base_population_growth_score,
  b.score_confidence
from public.suburb_base_scores b
join public.suburbs s
  on s.suburb_key = b.suburb_key
join public.suburb_population_metrics p
  on p.suburb_key = b.suburb_key
where p.population_2025 is not null
  and (p.growth_2023_2024_pct is null or p.growth_2024_2025_pct is null)
order by s.state, s.suburb_name, s.postcode;


-- QUERY 5: Check for unexpected null population momentum scores
-- This should be 0 after refresh_population_growth_scores() runs because
-- missing growth rates receive a neutral score of 5.
select
  count(*) as scored_suburbs_missing_population_momentum_score
from public.suburb_base_scores
where base_population_growth_score is null;
