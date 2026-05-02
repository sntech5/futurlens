# Feature Requests

Purpose:
- capture product and operational improvements that should be considered after the current milestone work
- keep useful ideas visible without derailing the active implementation path

## Open Requests

### 1. CSV Header Normalizer For Staging Imports

Status:
- requested

Problem:
- fresh suburb metric CSV files often arrive with header names that do not exactly match
  `public.suburb_import_staging`
- this causes repeated manual cleanup before every import or refresh
- import failures slow down the quarterly data refresh workflow

Requested feature:
- develop a script that automatically converts incoming CSV field names into the exact
  staging-table-compatible header names required by `public.suburb_import_staging`

Desired behavior:
- accept a source CSV file with common header variants
- normalize header names to the required staging schema
- preserve all row data
- flag unknown or unmapped columns clearly
- optionally emit a cleaned CSV ready for Supabase import

Target staging schema:

```text
state
post_code
suburb
avg_vendor_discount
days_on_market
demand_to_supply_ratio
percent_renters_in_market
percent_stock_on_market
statistical_reliability
typical_value
vacancy_rate
gross_rental_yield
```

Why it matters:
- reduces manual effort every quarter
- lowers the chance of import errors caused by header mismatches
- makes the data refresh process more repeatable and less fragile

Suggested milestone fit:
- Milestone 4 follow-on operational improvement

### 2. One-Click Data Ingestion And Validation Workflow

Status:
- requested

Problem:
- refreshing fresh suburb data currently requires running multiple SQL steps manually
- the process is error-prone because each refresh depends on the correct order of:
  staging import, suburb master sync, quarterly metric load, base score refresh, and validation
- manual copy/paste makes every refresh slower and increases the chance of missing a step

Requested feature:
- develop a single-action workflow that runs all required SQL steps for data ingestion,
  refresh, and validation in the correct order

Desired behavior:
- trigger one workflow action after the CSV has been loaded into `public.suburb_import_staging`
- insert or update missing suburb master rows in `public.suburbs`
- load metrics into `public.suburb_key_metrics_quarterly`
- refresh `public.suburb_base_scores`
- run validation checks automatically
- produce a clear success/failure summary with counts and any blocking issues

Suggested workflow sequence:

```text
suburb_import_staging
-> suburbs sync
-> suburb_key_metrics_quarterly load
-> refresh_suburb_base_scores()
-> validation summary
```

Why it matters:
- reduces repeated manual SQL work every refresh cycle
- lowers the chance of operator error
- makes quarterly refreshes predictable and faster
- improves confidence before end-to-end app testing

Suggested milestone fit:
- Milestone 4 operational improvement before repeat refresh cycles

### 3. Affordability Score For Suburb Ranking

Status:
- requested

Problem:
- `max_out_of_pocket` entered by the user is currently used as an eligibility filter only
- once a suburb passes the weekly out-of-pocket threshold, lower OOP does not improve its rank
- this can make recommendations feel misaligned with user intent because a suburb near the
  user's maximum weekly OOP can outrank a much more affordable suburb solely because its
  growth or yield score is higher
- the current OOP calculation is embedded directly in `public.run_recommendation_engine`,
  which makes future finance-model changes harder to isolate

Requested feature:
- add an affordability score that converts estimated weekly out-of-pocket cost into a
  ranking factor
- keep OOP calculation in modular database logic so the finance formula can be enhanced
  without rewriting the recommendation engine, frontend, or report-generation flow

Desired behavior:
- keep `max_out_of_pocket` as a hard filter so unaffordable suburbs are excluded
- calculate `estimated_oop` using a dedicated database function or equivalent isolated
  SQL module
- calculate `affordability_score` from the estimated OOP and the user's maximum OOP
- include `affordability_score` in suburb ranking so lower weekly OOP improves rank
- include `affordability_score` in `top_suburbs` payloads for transparency and report use
- preserve strategy intent: growth recommendations should still prioritize growth, yield
  recommendations should still prioritize yield, but affordability should influence ordering
  among eligible suburbs

Proposed modular design:

```text
public.calculate_estimated_weekly_oop(
  median_price,
  median_rent_weekly
)
-> numeric

public.calculate_affordability_score(
  estimated_weekly_oop,
  max_out_of_pocket
)
-> numeric

public.run_recommendation_engine(p_run_id)
-> calls the modular functions
-> filters on estimated_weekly_oop <= max_out_of_pocket
-> ranks using strategy score plus affordability_score
```

Initial OOP formula:

```text
estimated_weekly_oop = ((median_price * 0.8 * 0.06) / 52) - median_rent_weekly
```

Important modularity requirement:
- the current 80% loan / 6% interest / simple weekly interest assumption must live in the
  dedicated OOP calculation function, not inline in ranking SQL
- future enhancements such as user deposit, interest rate, repayment type, management fees,
  insurance, strata, council rates, vacancy allowance, or tax assumptions should be made in
  the OOP module without changing ranking orchestration

Possible first-pass affordability score:

```text
affordability_score =
  100 when estimated_weekly_oop <= 0
  otherwise 100 * (1 - estimated_weekly_oop / max_out_of_pocket), clamped to 0..100
```

Ranking direction:
- higher `affordability_score` is better
- negative or zero OOP should score best because the suburb is cash-flow neutral or positive
- suburbs above `max_out_of_pocket` remain excluded rather than merely down-ranked

Open scoring decision:
- decide whether affordability is:
  - a secondary tie-breaker after strategy score
  - a weighted factor blended into a new recommendation score
  - strategy-dependent, for example higher weight for yield users than growth users

Suggested first implementation:
- add affordability as a secondary weighted factor while preserving existing strategy-first
  behavior
- example concept:

```text
growth ranking = growth_score weighted heavily + affordability_score weighted lightly
yield ranking = yield_score weighted heavily + affordability_score weighted moderately
```

Acceptance criteria:
- changing the OOP formula requires updating only the modular OOP calculation function
- changing the affordability scoring curve requires updating only the affordability score
  function
- `estimated_oop` remains present in each returned suburb object
- `affordability_score` is present in each returned suburb object
- no returned suburb has `estimated_oop > max_out_of_pocket`
- with all else equal, a suburb with lower estimated OOP ranks above a suburb with higher
  estimated OOP
- restrictive no-match runs still insert a recommendation row with `top_suburbs = []`
- tests cover positive OOP, zero OOP, negative OOP, and boundary cases at exactly
  `max_out_of_pocket`

Why it matters:
- better matches user expectations when they provide a weekly affordability limit
- makes recommendations feel more personalized and financially practical
- prevents affordability from being treated as a hidden pass/fail gate only
- creates a clean foundation for a more realistic finance model later

Suggested milestone fit:
- Milestone 5 scoring model review and ranking improvement

### 4. Resolve WA Population Metrics Coverage Gap

Status:
- requested

Problem:
- `public.suburb_population_metrics` currently covers 149 of 164 suburbs in the recommendation universe
- the 15 missing suburbs are all WA suburbs and were absent from the population staging CSV
- population metrics are intended for source-backed report context and possible future scoring work
- reports must not invent population data, so these suburbs currently need an unavailable-data fallback

Known missing suburbs:

```text
ALKIMOS_WA_6038
ASHBY_WA_6065
BALLAJURA_WA_6066
BEECHBORO_WA_6063
BUTLER_WA_6036
GIRRAWHEEN_WA_6064
KOONDOOLA_WA_6064
LOCKRIDGE_WA_6054
MERRIWA_WA_6030
MIDDLE SWAN_WA_6056
PEARSALL_WA_6065
RIDGEWOOD_WA_6030
STRATTON_WA_6056
WANNEROO_WA_6065
WAROONA_WA_6215
```

Requested feature:
- improve population-source coverage for recommendation suburbs by finding and loading verified source-backed population rows for the missing WA suburbs

Desired behavior:
- rerun [audit_population_metrics_coverage.sql](../sql/audit_population_metrics_coverage.sql) after each population import
- identify whether missing suburbs require alternate SA2 mapping, suburb/postcode alias handling, or an additional verified source extract
- load only verified source-backed population rows through `public.suburb_population_metrics_staging`
- keep report fallback behavior for suburbs where population metrics remain unavailable

Acceptance criteria:
- population metric coverage reaches 100% for current `public.suburb_base_scores` rows, or remaining gaps are explicitly documented with reason
- no synthetic or manually guessed population values are inserted
- all loaded rows retain source/allocation metadata
- post-load validation reports `population_metrics_without_suburb = 0`

Suggested milestone fit:
- Milestone 3 report-factor data quality follow-up, or Milestone 5 scoring-model review if population growth becomes a ranking factor
