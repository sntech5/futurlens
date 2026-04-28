# FuturLens MVP Handoff

_Last updated: 2026-04-22 (Australia/Sydney)_

This file documents the **current working MVP** for the suburb recommendation app so development can continue in Codex without reconstructing context.

---

## 1. Current MVP scope

The MVP currently does this end to end:

1. User enters:
   - budget
   - max weekly out of pocket
   - strategy (`growth` or `yield`)
2. Frontend creates a `recommendation_runs` row.
3. Frontend calls `run_recommendation_engine(p_run_id)` via Supabase RPC.
4. Engine reads the run inputs and current suburb score data.
5. Engine writes a row into `recommendations`.
6. Frontend fetches the recommendation and renders suburb cards.

This is currently working.

---

## 2. Current architecture

### Frontend
- Single-file static frontend: `index.html`
- Hosted/planned to be hosted on **Cloudflare Pages**
- No React/Vite in the current working MVP path
- Uses direct `fetch()` calls to Supabase REST/RPC endpoints

### Backend / data
- **Supabase**
- Public schema exposed to the Data API
- Core logic is in Postgres functions

### Why this stack was chosen
React/Vite was started but created too much setup friction for the MVP. The current static HTML + JS approach is much simpler and already works.

---

## 3. Core tables in use

### `user_profiles`
Purpose:
- stores app-level user/profile records
- linked to Supabase auth users
- also supports admin role

Important columns used/known:
- `id` (UUID primary key, used throughout app)
- `auth_user_id`
- `email`
- `role` (`user` / `admin`)

Notes:
- manual creation of auth users did **not** auto-create profile rows at first
- this was fixed with a trigger/function on `auth.users`

---

### `recommendation_runs`
Purpose:
- one row per recommendation request / session
- source of truth for what the engine should process

Current important columns:
- `id` UUID PK
- `user_profile_id` UUID NOT NULL
- `run_status` text NOT NULL default `'pending'`
- `created_at` timestamptz NOT NULL default `now()`
- `completed_at` timestamptz NULL
- `created_by` UUID NULL
- `input_budget` numeric
- `input_rent` numeric _(legacy, now effectively superseded)_
- `strategy_type` text
- `max_out_of_pocket` numeric

Important relationships:
- `user_profile_id` → `user_profiles.id`
- `created_by` → `user_profiles.id`

Current design decision:
- **keep `recommendation_runs` as the source of truth**
- frontend creates the run first
- engine receives only `p_run_id`
- engine reads all inputs from the run row

---

### `recommendations`
Purpose:
- stores final generated recommendation for a run

Current important columns:
- `id`
- `recommendation_run_id`
- `user_profile_id`
- `top_suburbs` JSONB
- `strategy_type`
- `ai_summary`
- `created_at`

Notes:
- RLS had to be opened up for MVP insert/select
- engine currently inserts one recommendation row per run
- duplicate rows for same run are possible during repeated testing; this should be improved later

---

### `recommendation_reports`
Purpose:
- stores one customer-facing PDF report created from a recommendation result
- allows multiple reports to be created from one recommendation run
- stores customer details directly for MVP instead of using a customer master table

Current important columns:
- `id`
- `report_code`
- `recommendation_run_id`
- `recommendation_id`
- `customer_name`
- `customer_email`
- `generated_by_user_profile_id`
- `report_date`
- `daily_sequence`
- `pdf_storage_path`
- `pdf_file_name`
- `report_status`
- `generated_at`
- `created_at`
- `updated_at`

Notes:
- `report_code` is unique and follows `CUSTOMER-NAME-YYYYMMDD-###`
- PDF files are stored and retrieved later instead of regenerated from live score data
- detailed workflow reference: [recommendation_pdf_report_workflow.md](recommendation_pdf_report_workflow.md)

---

### `recommendation_report_suburbs`
Purpose:
- stores the suburbs selected for a PDF report
- preserves the engine rank and the report order separately
- stores a JSON snapshot of the suburb data used at report generation time

Current important columns:
- `id`
- `report_id`
- `suburb_key`
- `source_rank`
- `report_rank`
- `suburb_snapshot`
- `created_at`

Notes:
- `source_rank` is the original recommendation engine order
- `report_rank` is the selected display order in the PDF report
- users should select suburbs from the generated recommendation result, not arbitrary suburbs from the whole database

---

### `suburbs`
Purpose:
- master suburb table
- foreign key parent for score/snapshot tables

Current important columns/usage:
- `suburb_key` (key format like `MAITLAND_NSW_2320`)
- `suburb_name`
- `state`
- `postcode`

Notes:
- `suburb_base_scores.suburb_key` references this table
- when bulk-loading score rows, suburbs must exist here first

---

### `suburb_base_scores`
Purpose:
- current suburb-level scoring snapshot used by the recommendation engine
- this is the main table the app reads for recommendation ranking

Current columns:
- `suburb_key`
- `median_price`
- `median_rent_weekly`
- `gross_yield`
- `vacancy_rate`
- `renters_pct`
- `stock_on_market_pct`
- `days_on_market`
- `vendor_discount_pct`
- `population_growth_pct`
- `infrastructure_score`
- `base_growth_score`
- `base_yield_score`
- `base_demand_score`
- `base_risk_score`
- `base_total_score`
- `refreshed_at`

Current important behavior:
- one current row per suburb
- not a historical time series table
- recommendation engine reads this table directly

---

### `suburb_key_metrics_quarterly`
Purpose:
- current quarterly market metric source table
- active source for refreshing `suburb_base_scores`

Important design clarification:
- **one row per suburb only**
- quarterly refresh updates the row
- not one row per suburb per quarter

Current active design:
- all current market metrics are refreshed quarterly
- `suburb_monthly_data` is not part of the active recommendation/report path
- price, rent, yield, vacancy, stock, days on market, vendor discount, and related factors should be loaded into `suburb_key_metrics_quarterly`
- `suburb_base_scores` is refreshed from `suburb_key_metrics_quarterly`, not from suburb master records

---

### `suburb_import_staging`
Purpose:
- temporary staging table for bulk CSV import from Excel
- used to normalize external suburb data safely before loading into final tables

Current imported columns:
- `state`
- `post_code`
- `suburb`
- `avg_vendor_discount`
- `days_on_market`
- `demand_to_supply_ratio`
- `percent_renters_in_market`
- `percent_stock_on_market`
- `statistical_reliability`
- `typical_value`
- `vacancy_rate`
- `gross_rental_yield`
- `imported_at`

Notes:
- text-heavy by design to tolerate messy CSV values
- cleaned and transformed into `suburb_key_metrics_quarterly`
- `suburb_base_scores` is then refreshed from `suburb_key_metrics_quarterly`

---

## 4. Key relationships

### Current important FK logic
- `recommendation_runs.user_profile_id` → `user_profiles.id`
- `recommendation_runs.created_by` → `user_profiles.id`
- `recommendations.recommendation_run_id` → `recommendation_runs.id`
- `recommendations.user_profile_id` → `user_profiles.id`
- `suburb_base_scores.suburb_key` → `suburbs.suburb_key`

### Practical consequence
- recommendation data is isolated per user/profile
- admin support is possible because `created_by` can differ from `user_profile_id`
- score rows require suburb master rows to exist first

---

## 5. Auth/profile behavior

### Current working behavior
- creating a Supabase auth user now auto-creates a `user_profiles` row
- this was fixed with a trigger on `auth.users`

### Intended usage
- normal user: uses own `user_profile_id`
- admin: can create runs for another profile while preserving `created_by`

---

## 6. Supabase Data API / RLS learnings

These were important blockers and should be remembered.

### Data API exposure
The public schema / relevant objects needed to be exposed for Data API usage.

### RLS
RLS is enabled and permissive MVP policies were added to unblock the flow.

Tables that needed insert/select access for MVP:
- `recommendation_runs`
- `recommendations`

### Important frontend request header issue
The frontend initially hit `graphql_public` schema unexpectedly.
This was fixed by explicitly sending:
- `Content-Profile: public`
- `Accept-Profile: public`

Without this, requests failed even though the table existed.

### Important API URL lesson
Supabase base URL in the frontend config should be only:

```text
https://<project>.supabase.co
```

Not `/rest/v1`.
The JS code appends `/rest/v1/...` itself.

---

## 7. Current working frontend flow

### Current frontend style
Single static `index.html` with JS helpers and `fetch()` calls.

### Config currently hardcoded in JS
- `supabaseUrl`
- `supabaseKey` (publishable key)
- `userProfileId`

### Current user inputs
- `budget`
- `maxOop` (max weekly out of pocket)
- `strategy`

### Current UX behavior
- one button: `Generate Recommendation`
- validation prevents blank budget/OOP submission
- output rendered as suburb cards
- explanation text aligned to selected strategy

### Important frontend logic decisions
- use selected strategy from the current UI state for explanation rendering
- do **not** rely on stale `recommendation.strategy_type` from fetched rows for explanation text

This fixed the bug where growth cases still displayed yield-oriented explanations.

---

## 8. Current working recommendation engine logic

### Function in use
```sql
public.run_recommendation_engine(p_run_id uuid)
```

### Important design decision
Keep the function signature to **one parameter only**.
Do not use the abandoned 3-parameter version.

Reason:
- `recommendation_runs` is the source of truth
- avoid duplicating user/profile values in function parameters

### Current flow inside engine
1. Read from `recommendation_runs`:
   - `user_profile_id`
   - `input_budget`
   - `max_out_of_pocket`
   - `strategy_type`
2. Validate required inputs
3. Query `suburb_base_scores`
4. Filter by:
   - `median_price <= input_budget`
   - estimated OOP <= `max_out_of_pocket`
5. Sort by:
   - `base_growth_score desc` if strategy is `growth`
   - `base_yield_score desc` if strategy is `yield`
6. Build `top_suburbs` JSON
7. Insert row into `recommendations`

### Current estimated OOP formula
Current suburb-level approximation:

```text
((median_price * 0.8 * 0.06) / 52) - median_rent_weekly
```

This assumes:
- 80% loan
- 6% interest
- simple weekly interest approximation

Important:
- this is a suburb-level estimate, not a fully personalized finance calculation
- user `max_out_of_pocket` is used as a filter threshold, not as an input to OOP calculation itself

### Current recommendation output structure
Each suburb object in `top_suburbs` currently includes:
- `suburb`
- `price`
- `rent`
- `yield`
- `estimated_oop`

---

## 9. Current explanation logic in frontend

### Important bug fixed
Growth cases were incorrectly showing yield-based explanation text.

### Current rule
Explanation text uses the **currently selected UI strategy**.

### Growth explanation should mention only:
- estimated weekly OOP
- budget fit
- growth-oriented scoring
- demand/supply / tighter market style rationale

### Yield explanation may mention:
- gross rental yield
- yield-oriented scoring
- rent support

---

## 10. Bulk data import workflow that now works

### Source
Excel/CSV with columns:
- State
- Post Code
- Suburb
- Avg vendor discount
- Days on market
- Demand to Supply Ratio
- Percent renters in market
- Percent stock on market
- Statistical reliability
- Typical value
- Vacancy rate
- Gross rental yield

### Working workflow
1. Save Excel as CSV.
2. Rename CSV headers to match `suburb_import_staging` snake_case column names exactly.
3. Import into `suburb_import_staging`.
4. Insert distinct suburb keys into `suburbs` first.
5. Run cleaned transform query into `suburb_key_metrics_quarterly`.
6. Refresh `suburb_base_scores`.

### Important cleaning lesson
Transform initially failed because raw values were not clean numerics, for example:
- `90days`

Fix used:
- `regexp_replace(..., '[^0-9.]', '', 'g')`
- and for discount fields: `regexp_replace(..., '[^0-9.-]', '', 'g')`

### Important FK lesson
`suburb_base_scores` load failed until the missing suburb keys were first inserted into `suburbs`.

---

## 11. Current `base_growth_score` logic

### Goal
Make growth ranking more realistic and modular without touching the frontend or engine each time.

### Design decision
Keep growth-score logic isolated in a dedicated function:

```sql
public.refresh_base_growth_scores()
```

This is the correct modular location for future changes.

### Inputs considered in the weighted growth score
Only the following are currently relevant:
- `base_demand_score` (currently DSR-derived)
- `days_on_market`
- `stock_on_market_pct`
- `vendor_discount_pct`
- `vacancy_rate`

### Fields explicitly not used in `base_growth_score`
- `gross_yield`
- `typical_value`
- `statistical_reliability`
- `renters_pct`

### Current normalization approach
Min-max normalization to 0–100:
- higher DSR = better
- lower DOM = better
- lower stock on market = better
- lower vendor discount = better
- lower vacancy = better
- if a metric has no spread across the scored dataset, it receives a neutral component score of `50`
- only rows with all required growth inputs present are included in the score refresh

### Current weights
- DSR: `0.40`
- DOM: `0.20`
- Stock on market: `0.15`
- Vendor discount: `0.15`
- Vacancy: `0.10`

### Exact Supabase implementation
The current function body is captured in:

[sql_reference_refresh_base_growth_scores.md](sql_reference_refresh_base_growth_scores.md)

### Important design rule
If the growth model changes later, update only:

```sql
public.refresh_base_growth_scores()
```

and do not touch the frontend or recommendation engine unless the output fields change.

---

## 12. Functions currently relevant

### `public.run_recommendation_engine(p_run_id uuid)`
Working and in use.

### `public.refresh_base_growth_scores()`
Working and created as the modular place for growth scoring logic.

### Mentioned/older function
- `refresh_suburb_base_scores` refreshes current base score rows from `suburb_key_metrics_quarterly`.
- `refresh_base_growth_scores` remains the modular owner of the growth score calculation.
- There was also an abandoned 3-parameter version of `run_recommendation_engine`; do not continue with that path.

---

## 13. Current validated scenarios

The MVP was validated with multiple test cases after loading more suburb data.

### What is now confirmed
- multiple suburbs are returned
- max OOP changes filtering correctly
- strategy changes ranking correctly
- estimated OOP differs across suburbs
- boundary test confirmed OOP filter works
- explanation text now aligns with selected strategy

### Important earlier validation issue
Testing was initially inconclusive because only one suburb existed in `suburb_base_scores`. That problem is now solved after the CSV import pipeline was fixed.

---

## 14. Known shortcuts / MVP limitations

These are intentional and should not be mistaken for final product logic.

### Finance model simplification
Estimated OOP is based on a simple fixed assumption:
- 80% loan
- 6% interest
- no detailed holding cost model

### Score model simplification
- `base_yield_score` is still simple
- `base_growth_score` is now better than pure DSR but still MVP-level
- no advanced weighting for infrastructure, population growth, etc. yet

### Recommendations table behavior
Multiple recommendation rows can be created for repeated testing of the same run logic. This should be improved later.

### Frontend config
Sensitive-looking but frontend-safe config is still hardcoded:
- publishable key
- project URL
- user profile id

This is fine for internal MVP testing but should be cleaned up before broader use.

---

## 15. What should NOT be changed casually

To avoid breaking the MVP, do not casually change:

### Do not redesign these right now
- `run_recommendation_engine` signature
- the `recommendation_runs` → function → `recommendations` flow
- the one-row-per-suburb snapshot design for monthly/quarterly/base score tables
- the `suburb_key` format

### Do not move score logic into
- frontend JS
- ad hoc insert SQL
- API calls

Keep it in dedicated DB functions.

---

## 16. Recommended next steps for Codex

### Immediate next step
**UI cleanup** only.
Do not add backend complexity first.

Suggested UI cleanup tasks:
1. remove technical/debug wording
2. improve labels and copy
3. make cards look cleaner
4. add concise result summary text
5. keep the one-button flow

### After UI cleanup
User validation tasks:
1. run with 3–5 real users
2. observe whether inputs make sense to them
3. observe whether recommendation explanations feel credible
4. collect what extra fields they ask for before building more

### Good next backend improvements after validation
1. prevent duplicate `recommendations` rows per run
2. improve `base_yield_score` modularly
3. improve summary text generation
4. add more suburb data coverage
5. later consider personalized OOP model inputs

---

## 17. Suggested guardrails for continuing in Codex

When continuing, keep asking this before making changes:

### Product guardrail
Does this directly improve:
- recommendation quality,
- user understanding,
- or demo readiness?

If not, skip it.

### Architecture guardrail
Can this be added by changing:
- one DB function,
- one transform query,
- or one frontend helper,
without touching everything else?

If yes, prefer that path.

### MVP guardrail
Do not add:
- scraping
- advanced auth flows
- dashboards/charts
- AI summaries
- more tables
until the current recommendation experience is clearly useful.

---

## 18. Short operational checklist

### To refresh suburb data from spreadsheet
1. export Excel to CSV
2. rename CSV headers to staging snake_case names
3. import into `suburb_import_staging`
4. insert missing suburbs into `suburbs`
5. run cleaned transform into `suburb_key_metrics_quarterly`:

```sql
-- sql/load_suburb_key_metrics_quarterly_from_staging.sql
```

6. refresh base scores:

```sql
select public.refresh_suburb_base_scores();
```

### To test the app
1. enter budget
2. enter max weekly out of pocket
3. choose strategy
4. click `Generate Recommendation`
5. confirm suburb cards and explanations look correct

---

## 19. Current truth summary

The MVP is currently:
- end-to-end working
- data-backed
- modular enough to continue cleanly
- ready for UI cleanup and user validation

The most important current separation is:
- **frontend** handles input and rendering
- **recommendation engine** handles run processing
- **score refresh functions** handle scoring logic
- **staging + transform** handles external data import

That separation should be preserved.
