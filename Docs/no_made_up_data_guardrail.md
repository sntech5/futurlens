# No Made-Up Data Guardrail

Purpose:
- prevent demo, report, and recommendation outputs from using invented values
- make placeholder logic visibly different from verified source data
- keep milestone work focused on trustworthy data and clearly documented assumptions

## Rule

Do not display, store, or report made-up suburb metrics as if they are real.

This applies to:
- median price
- weekly rent
- gross yield
- vacancy rate
- renters percentage
- stock on market
- days on market
- vendor discount
- population growth
- infrastructure score
- suburb factor data
- report commentary that claims facts about a suburb

## Allowed

The app may use calculated values when the formula is explicit and the inputs are real.

Examples:
- estimated weekly out-of-pocket calculated from median price and rent
- base score fields calculated from real metric inputs
- report ranking copied from the recommendation run

Calculated values must be treated as model outputs, not source data.

## Not Allowed

Do not:
- create suburb score rows just because a suburb exists in the master table
- fill missing suburb metrics with defaults that look real
- use synthetic trends in a report without clearly marking them as illustrative
- overwrite existing real metrics with nulls from an incomplete refresh
- use AI-generated suburb facts unless they are grounded in stored source data
- mix demo data and real data without a visible data-quality marker

## Database Guardrails

Refresh/load functions must:
- load from verified source tables only
- require source rows before creating `suburb_base_scores`
- avoid `left join` patterns that create empty score rows
- avoid overwriting existing non-null metrics with null values
- keep raw metrics separate from derived score logic
- document every scoring formula in SQL docs
- use `suburb_key_metrics_quarterly` as the active current-market metric source unless the milestone plan explicitly changes

## Report Guardrails

Generated reports must:
- show only selected suburbs from a recommendation run
- use suburb metric values from the stored recommendation snapshot
- avoid factual claims for suburb factors that have not been ingested yet
- clearly distinguish model commentary from verified data
- avoid historical charts unless historical source data exists

## Milestone Impact

Milestone 2 can continue for report generation mechanics, but report wording must avoid unsupported claims.

Milestone 3 must ingest suburb factor data before those factors appear as factual report content.

Milestone 4 must replace demo/stale suburb metrics with verified real metric data before the product is treated as demo-ready for evidence-based recommendations.
