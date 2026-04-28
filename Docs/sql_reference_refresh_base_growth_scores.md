# SQL Reference: `refresh_base_growth_scores`

Purpose:
- recompute `public.suburb_base_scores.base_growth_score`
- keep growth scoring isolated from the frontend and recommendation engine
- update `refreshed_at` for every suburb row that receives a refreshed growth score

## Function Body

This is the current Supabase implementation body for:

```sql
public.refresh_base_growth_scores()
```

```sql
declare
  v_weight_dsr numeric := 0.40;
  v_weight_dom numeric := 0.20;
  v_weight_stock numeric := 0.15;
  v_weight_discount numeric := 0.15;
  v_weight_vacancy numeric := 0.10;
begin
  with stats as (
    select
      min(base_demand_score) as min_dsr,
      max(base_demand_score) as max_dsr,
      min(days_on_market) as min_dom,
      max(days_on_market) as max_dom,
      min(stock_on_market_pct) as min_stock,
      max(stock_on_market_pct) as max_stock,
      min(vendor_discount_pct) as min_discount,
      max(vendor_discount_pct) as max_discount,
      min(vacancy_rate) as min_vacancy,
      max(vacancy_rate) as max_vacancy
    from public.suburb_base_scores
    where base_demand_score is not null
      and days_on_market is not null
      and stock_on_market_pct is not null
      and vendor_discount_pct is not null
      and vacancy_rate is not null
  ),
  scored as (
    select
      s.suburb_key,
      case
        when stats.max_dsr = stats.min_dsr then 50
        else 100 * (s.base_demand_score - stats.min_dsr) / nullif(stats.max_dsr - stats.min_dsr, 0)
      end as dsr_score,

      case
        when stats.max_dom = stats.min_dom then 50
        else 100 * (stats.max_dom - s.days_on_market) / nullif(stats.max_dom - stats.min_dom, 0)
      end as dom_score,

      case
        when stats.max_stock = stats.min_stock then 50
        else 100 * (stats.max_stock - s.stock_on_market_pct) / nullif(stats.max_stock - stats.min_stock, 0)
      end as stock_score,

      case
        when stats.max_discount = stats.min_discount then 50
        else 100 * (stats.max_discount - s.vendor_discount_pct) / nullif(stats.max_discount - stats.min_discount, 0)
      end as discount_score,

      case
        when stats.max_vacancy = stats.min_vacancy then 50
        else 100 * (stats.max_vacancy - s.vacancy_rate) / nullif(stats.max_vacancy - stats.min_vacancy, 0)
      end as vacancy_score
    from public.suburb_base_scores s
    cross join stats
    where s.base_demand_score is not null
      and s.days_on_market is not null
      and s.stock_on_market_pct is not null
      and s.vendor_discount_pct is not null
      and s.vacancy_rate is not null
  )
  update public.suburb_base_scores t
  set
    base_growth_score =
      round((
        scored.dsr_score * v_weight_dsr +
        scored.dom_score * v_weight_dom +
        scored.stock_score * v_weight_stock +
        scored.discount_score * v_weight_discount +
        scored.vacancy_score * v_weight_vacancy
      )::numeric, 3),
    refreshed_at = now()
  from scored
  where t.suburb_key = scored.suburb_key;
end;
```

## Scoring Behavior

The function first calculates dataset-wide min/max values across complete suburb rows only. A row is considered complete for growth scoring when all of these fields are present:

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
base_growth_score =
  dsr_score * 0.40
+ dom_score * 0.20
+ stock_score * 0.15
+ discount_score * 0.15
+ vacancy_score * 0.10
```

The final value is rounded to 3 decimal places.

## Operational Notes

- Rows with nulls in any required growth input are not updated by this function.
- `refreshed_at` is updated only for rows included in the scored result set.
- The recommendation engine consumes `base_growth_score`; it does not calculate it.
- Future changes to growth scoring should be made in `public.refresh_base_growth_scores()` without changing the frontend or `public.run_recommendation_engine()` unless output fields change.

## Related Base Score Refresh Guardrail

The base score load/refresh process must not create score rows from `public.suburbs` alone. Raw metric values must come from verified source rows in `public.suburb_key_metrics_quarterly`.

The patch reference for the current no-made-up-data refresh pattern is:

[patch_refresh_suburb_base_scores_no_made_up_data.sql](../sql/patch_refresh_suburb_base_scores_no_made_up_data.sql)

Key rule:
- `public.refresh_suburb_base_scores()` loads raw metrics and simple derived scores from verified source rows only.
- `public.refresh_base_growth_scores()` remains the owner of `base_growth_score`.
- Missing source data should produce no new score row, not a row that looks processed.
- `base_growth_score` is stored on a `0-100` scale, so total-score formulas must divide it by `10` before combining it with `0-10` component scores.
- `gross_yield` is stored as a decimal, for example `0.045` for `4.5%`, so yield-score formulas must account for that scale.
- `public.suburb_key_metrics_quarterly` is the only active source table for current market metrics. `public.suburb_monthly_data` is not part of the active recommendation/report data path.
