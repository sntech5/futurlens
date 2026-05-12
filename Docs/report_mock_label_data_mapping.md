# Report Mock Label Data Mapping

Purpose:
- map each visible label in the new report mock to current Plenz data
- identify source-backed fields, derived fields, and deliberate placeholders
- prevent report labels from implying data that has not been loaded

## Header

| Mock label | Current source | Status |
| --- | --- | --- |
| Suburb Investment Report | Static report title | Implemented |
| Month/year | Browser-generated report date | Implemented |
| Suburb name | `top_suburbs[].suburb` formatted | Implemented |
| State/postcode | `top_suburbs[].state`, `top_suburbs[].postcode` | Implemented |
| Rank number | Position in `top_suburbs`, now ordered by `base_total_score` first | Implemented |

## Left Score Panel

| Mock label | Current source | Status |
| --- | --- | --- |
| Overall Investment Score | `base_total_score * 10` | Implemented |
| Capital Growth | `base_growth_score` | Implemented |
| Rental Yield | `base_yield_score` | Implemented |
| Rental Demand | `base_demand_score` | Implemented |
| Infrastructure | `base_population_growth_score` for now | Implemented as population momentum proxy |
| Risk Profile | `base_risk_score` | Implemented |

Note:
- `Infrastructure` in the mock does not yet have a direct infrastructure dataset.
- Until infrastructure data is sourced, the report uses source-backed population momentum as the closest demand-side proxy and should avoid claiming direct infrastructure quality from this score.

## Key Metrics

| Mock label | Current source | Status |
| --- | --- | --- |
| Median house price | `median_price` | Implemented |
| Median unit price | Not currently loaded | Placeholder |
| Gross rental yield | `gross_yield` | Implemented |
| Vacancy rate | `vacancy_rate` | Implemented |
| Population | `suburb_population_metrics.population_2025`, included in recommendation payload as `population_2025` | Implemented for fresh runs after SQL patch |
| Distance to CBD | Not currently loaded | Placeholder |

## Market Signals Added To Current Report

These are not in the mock's six key-metric tiles but are available from Supabase and should be shown because they affect ranking/commentary.

| Report label | Current source | Status |
| --- | --- | --- |
| Days on market | `days_on_market` | Implemented |
| Vendor discount | `vendor_discount_pct` | Implemented |
| Stock on market | `stock_on_market_pct` | Implemented |
| Renters | `renters_pct` | Implemented |
| Weekly OOP | `estimated_oop` | Implemented |
| Population growth vs state | `population_growth_vs_state_pct` | Implemented |

## Graphs

| Mock chart | Current source | Status |
| --- | --- | --- |
| Price growth line chart | Historical price series not currently loaded in report payload | Placeholder/explanatory panel |
| Rental yield bar chart | `gross_yield` versus fixed benchmark | Implemented |
| Median weekly rent | `median_rent_weekly` | Implemented |

## Commentary

| Mock label | Current source | Status |
| --- | --- | --- |
| Key insights | Current scoring inputs and model scores | Implemented |
| Our recommendation | Current overall score, strategy, demand/risk signals | Implemented |
| AI suburb commentary | `generate-suburb-report-summary` Edge Function output | Not wired into frontend yet |

Guardrail:
- Do not describe missing values as known.
- Use `N/A` or explicit source-not-loaded wording for unavailable unit price, CBD distance, and historical price-growth series.
