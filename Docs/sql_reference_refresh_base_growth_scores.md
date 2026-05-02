# SQL Reference: `refresh_base_growth_scores`

Purpose:
- recompute `public.suburb_base_scores.base_growth_score`
- keep growth scoring isolated from the frontend and recommendation engine
- blend market-momentum signals with source-backed population growth
- update `refreshed_at` for every suburb row that receives a refreshed growth score

## Function Body

The current deployable implementation is captured in:

[patch_growth_score_with_population_momentum.sql](../sql/patch_growth_score_with_population_momentum.sql)

That patch creates or replaces:

```sql
public.refresh_population_growth_scores()
public.refresh_base_growth_scores()
```

## Scoring Behavior

The growth model now has two parts:

1. Market momentum score
2. Population growth score

`public.refresh_base_growth_scores()` calls:

```sql
public.refresh_population_growth_scores()
```

before recomputing `base_growth_score`.

### Population Growth Score

Population growth uses source-backed rows from `public.suburb_population_metrics`.

The raw momentum value stored in `suburb_base_scores.population_growth_pct` is:

```text
population_momentum_pct =
  growth_2024_2025_pct * 0.70
+ growth_2023_2024_pct * 0.30
```

That value is normalized to:

```text
base_population_growth_score
```

on a `0-100` scale from:

```text
population_growth_vs_state_pct =
  population_momentum_pct
- state_population_momentum_pct
```

The state benchmark is calculated as a population-weighted average from loaded source-backed `suburb_population_metrics` rows for each state. This avoids letting small-base suburbs dominate ranking just because their raw percentage growth is high.

Missing population source rows receive neutral `base_population_growth_score = 50`, while `population_growth_pct` and `population_growth_vs_state_pct` remain null. This keeps missing source data from being invented or unfairly punished.

### Market Momentum Score

The function calculates dataset-wide min/max values across complete suburb rows only. A row is considered complete for market momentum scoring when all of these fields are present:

- `base_demand_score`
- `days_on_market`
- `stock_on_market_pct`
- `vendor_discount_pct`
- `vacancy_rate`

Each component is normalized to `0-100`:

- `base_demand_score`: higher is better
- `days_on_market`: lower is better
- `stock_on_market_pct`: lower is better
- `vendor_discount_pct`: lower is better
- `vacancy_rate`: lower is better

If a component has no spread across the scored dataset, meaning its min and max are equal, the function assigns that component a neutral score of `50`.

## Weighted Formula

```text
market_momentum_score =
  dsr_score * 0.40
+ dom_score * 0.20
+ stock_score * 0.15
+ discount_score * 0.15
+ vacancy_score * 0.10

base_growth_score =
  market_momentum_score * 0.65
+ base_population_growth_score * 0.35
```

The final value is rounded to 3 decimal places.

## Operational Notes

- Rows with nulls in any required growth input are not updated by this function.
- `refreshed_at` is updated only for rows included in the scored result set.
- The recommendation engine consumes `base_growth_score`; it does not calculate it.
- Future changes to growth scoring should be made in `public.refresh_base_growth_scores()` without changing the frontend or `public.run_recommendation_engine()` unless output fields change.
- Future changes to population momentum logic should be made in `public.refresh_population_growth_scores()`.

## Related Base Score Refresh Guardrail

The base score load/refresh process must not create score rows from `public.suburbs` alone. Raw metric values must come from verified source rows in `public.suburb_key_metrics_quarterly`.

The patch reference for the current no-made-up-data refresh pattern is:

[patch_refresh_suburb_base_scores_no_made_up_data.sql](../sql/patch_refresh_suburb_base_scores_no_made_up_data.sql)

Key rule:
- `public.refresh_suburb_base_scores()` loads raw metrics and simple derived scores from verified source rows only.
- `public.refresh_base_growth_scores()` remains the owner of `base_growth_score`.
- `public.refresh_population_growth_scores()` remains the owner of population momentum and `base_population_growth_score`.
- Missing source data should produce no new score row, not a row that looks processed.
- `base_growth_score` is stored on a `0-100` scale, so total-score formulas must divide it by `10` before combining it with `0-10` component scores.
- `gross_yield` is stored as a decimal, for example `0.045` for `4.5%`, so yield-score formulas must account for that scale.
- `public.suburb_key_metrics_quarterly` is the only active source table for current market metrics. `public.suburb_monthly_data` is not part of the active recommendation/report data path.
