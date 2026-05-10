# Scoring Model V2: First-Principles Specification

Purpose: define the target scoring model before changing SQL or frontend ranking.

This model treats scores as directional decision signals, not precise forecasts. Every component score should be explainable from visible source metrics.

Canonical repo config:

```text
supabase/scoring_model_v2.config.json
```

Important: Supabase Postgres functions do not read this repository JSON file at runtime. If the JSON config changes, the related SQL scoring functions must be regenerated or manually updated and redeployed before the new formula is executed.

## Score Scale

For positive scores, higher is better:

- `0-3`: weak / adverse
- `4-6`: moderate / neutral
- `7-8`: good
- `9-10`: strong

For risk score only, lower is better:

- `0-3`: low risk
- `4-6`: moderate risk
- `7-10`: elevated risk

## Affordability Gates

Affordability is a filter, not the main investment score.

Exclude a suburb from recommendations when:

- `median_price > user_budget`
- `estimated_weekly_out_of_pocket > user_max_weekly_out_of_pocket`

Do not rank a suburb higher just because it is cheaper once it has passed the affordability gates.

## Yield Score

Purpose: rental return strength.

Primary metric:

- `gross_yield`

Recommended formula:

```text
yield_score = piecewise_linear(gross_yield_pct)

3.0% = 0
4.5% = 5
5.5% = 7
7.0% = 9
8.0%+ = 10
```

Interpretation:

- `< 3.5%`: weak
- `3.5-4.5%`: moderate
- `4.5-5.5%`: good
- `5.5-7.0%`: strong
- `> 7.0%`: very strong, but check risk separately

Reason: the previous simple cap made too many suburbs score `10/10`, which collapsed ranking separation.

## Demand Score

Purpose: rental and market tightness.

Inputs and weights:

```text
vacancy_rate: 40%
days_on_market: 30%
renters_pct: 15%
stock_on_market_pct: 15%
```

Metric direction:

- Lower `vacancy_rate` is better.
- Lower `days_on_market` is better.
- Higher `renters_pct` is better for rental demand.
- Lower `stock_on_market_pct` is better for listed-supply tightness.

Stock on market interpretation:

- `< 1%`: very tight listed supply
- `1-2%`: tight listed supply
- `2-4%`: moderate listed supply
- `4-6%`: elevated listed supply
- `> 6%`: high listed-supply pressure

Important: low stock on market is not a risk pressure signal. It supports demand and reduces supply risk.

## Growth Score

Purpose: capital growth potential from market momentum and population momentum.

Inputs and weights:

```text
population_growth_vs_state_pct / population_momentum: 35%
days_on_market: 25%
stock_on_market_pct: 25%
vendor_discount_pct: 15%
```

Explicit exclusions:

- Do not use `vacancy_rate` in growth score.
- Do not use `gross_yield` in growth score.

Metric direction:

- Higher population growth versus state benchmark is better.
- Lower days on market is better.
- Lower stock on market is better.
- Lower vendor discount magnitude is better. Use `abs(vendor_discount_pct)` where discounts are stored as negative percentages.

Reasoning:

- Growth should be driven by population momentum and sale-market tightness.
- Vacancy rate is primarily a rental-market signal, so it belongs in demand/risk rather than growth.
- Days on market increases to `25%` because fast sale absorption is a direct market-momentum signal.
- The removed vacancy weight is redistributed to stock on market, lifting stock on market to `25%` because constrained listed supply is directly growth-relevant.

Missing population data:

- Do not invent population growth.
- Prefer a separate `score_confidence` flag.
- For MVP scoring, either redistribute missing population weight across the remaining growth inputs or use a neutral population component only when clearly labelled as neutral.

## Risk Score

Purpose: downside / caution signal. Lower is better.

Inputs and weights:

```text
stock_on_market_pct: 30%
vacancy_rate: 25%
days_on_market: 20%
vendor_discount_pct: 15%
data_missing_penalty: 10%
```

Metric direction:

- Higher stock on market increases risk.
- Higher vacancy increases risk.
- Longer days on market increases risk.
- Larger vendor discount magnitude increases risk. Use `abs(vendor_discount_pct)` where discounts are stored as negative percentages.
- Missing required source metrics increases confidence risk.

Risk commentary must follow the inverse scale:

- `0-3`: low risk penalty
- `4-6`: moderate risk penalty
- `7-10`: elevated risk penalty

## Strategy-Specific Total Scores

Retire generic `base_total_score` and use strategy-specific total scores.

```text
risk_safety_score = 10 - risk_score
```

Growth strategy total:

```text
growth_strategy_total_score =
  growth_score * 0.45
+ demand_score * 0.25
+ yield_score * 0.15
+ risk_safety_score * 0.15
```

Yield strategy total:

```text
yield_strategy_total_score =
  yield_score * 0.40
+ demand_score * 0.30
+ growth_score * 0.15
+ risk_safety_score * 0.15
```

Both totals remain on a `0-10` scale.

## Recommendation Ranking

The app should sort suburbs by the strategy-specific total score:

```text
if strategy = growth:
  order by growth_strategy_total_score desc

if strategy = yield:
  order by yield_strategy_total_score desc
```

Suggested deterministic tie-breakers:

```text
1. selected strategy total score desc
2. selected strategy primary component desc
   - growth: growth_score desc
   - yield: yield_score desc
3. demand_score desc
4. risk_score asc
5. suburb_key asc
```

Do not sort by generic `base_total_score`.

## Output Fields

Target fields for `public.suburb_base_scores` or a successor scoring table:

```text
base_growth_score
base_yield_score
base_demand_score
base_risk_score
base_growth_strategy_total_score
base_yield_strategy_total_score
score_confidence
score_explanation_payload
```

`base_total_score` is retired after scoring model v2. New scoring refreshes, recommendation payloads, app ranking, and report commentary should use strategy-specific totals.

## Commentary Rules

All commentary must be derived from score bands and raw metric bands.

Examples:

- `stock_on_market_pct = 0.65%` means very tight listed supply, not stock pressure.
- `risk_score = 1.3/10` means low risk penalty.
- A `yield_score` above `7/10` must never be described as weak, low, or a risk.
- Growth strategy may still mention a strong yield score as a secondary strength.
- Yield strategy may still mention a strong growth score as a secondary strength.
