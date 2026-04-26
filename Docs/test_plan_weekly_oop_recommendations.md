# Weekly OOP Output Test Plan

Last updated: 2026-04-23 (Australia/Sydney)

## Objective
Validate that `estimated_oop` in recommendation outputs is:
- calculated correctly
- filtered correctly against `max_out_of_pocket`
- consistent across DB output, API response, and UI rendering

## Current Formula (Source of Truth)
For each suburb in recommendation output:

`estimated_oop = ((median_price * 0.8 * 0.06) / 52) - median_rent_weekly`

Assumptions in current MVP:
- loan-to-value ratio: `80%`
- interest rate: `6%`
- simple weekly interest approximation

## Scope
In scope:
- `run_recommendation_engine(p_run_id)` output accuracy for `estimated_oop`
- filter behavior using `max_out_of_pocket`
- edge behavior (negative, zero, decimal, boundary)

Out of scope:
- personalized finance model (fees, insurance, rates, tax)
- interest-rate sensitivity beyond current fixed assumption

## Test Method
1. Create test runs in `recommendation_runs`.
2. Execute `public.run_recommendation_engine(run_id)`.
3. Read `recommendations.top_suburbs`.
4. Recompute OOP from returned `price` and `rent` in SQL and compare with `estimated_oop`.
5. Confirm inclusion/exclusion boundary with `max_out_of_pocket`.

## Pass Criteria
- Per-row OOP delta `abs(expected_oop - estimated_oop) <= 0.01`
- No returned suburb has `estimated_oop > max_out_of_pocket`
- Boundary values equal to threshold are included
- No `NULL` `estimated_oop` in returned suburb objects

## Test Scenarios

| ID | Scenario | Inputs | Expected |
|---|---|---|---|
| OOP-001 | Basic positive OOP | budget high enough, `max_oop = 500` | Returned rows have correct OOP values and all `<= 500` |
| OOP-002 | Boundary include | choose threshold equal to known suburb OOP | Suburb with exact OOP is included |
| OOP-003 | Boundary exclude | threshold just below known suburb OOP | Suburb is excluded |
| OOP-004 | Zero threshold | `max_oop = 0` | Only suburbs with `estimated_oop <= 0` returned |
| OOP-005 | Negative OOP support | `max_oop = -10` | Only cash-flow-positive suburbs (`estimated_oop <= -10`) returned |
| OOP-006 | Very restrictive no-match | low budget + low max_oop | Recommendation row inserted with empty `top_suburbs` array |
| OOP-007 | High threshold does not bypass budget | high `max_oop`, low budget | Price filter still enforced |
| OOP-008 | Decimal precision | thresholds with decimals (`250.25`) | Filtering and stored values are precise and stable |
| OOP-009 | Strategy invariance for OOP | same inputs, `growth` vs `yield` | OOP formula same; only ranking field changes |
| OOP-010 | Payload integrity | valid run | each suburb object has numeric `price`, `rent`, `estimated_oop` |

## Concrete Calculation Examples
Use these as deterministic spot checks:

1. Example A  
- `median_price = 800000`, `median_rent_weekly = 650`  
- Expected OOP = `((800000 * 0.8 * 0.06)/52) - 650`  
- Expected OOP = `88.461538...` (round display as needed)

2. Example B  
- `median_price = 500000`, `median_rent_weekly = 700`  
- Expected OOP = `((500000 * 0.8 * 0.06)/52) - 700`  
- Expected OOP = `-238.461538...`

## SQL Validation Query (Run-level)
Replace `<run_id>` with a generated run id:

```sql
with top_rows as (
  select
    r.recommendation_run_id,
    elem
  from public.recommendations r,
       jsonb_array_elements(r.top_suburbs) elem
  where r.recommendation_run_id = '<run_id>'::uuid
),
calc as (
  select
    recommendation_run_id,
    (elem->>'suburb') as suburb_key,
    (elem->>'price')::numeric as price,
    (elem->>'rent')::numeric as rent,
    (elem->>'estimated_oop')::numeric as estimated_oop,
    (((elem->>'price')::numeric * 0.8 * 0.06) / 52) - (elem->>'rent')::numeric as expected_oop
  from top_rows
)
select
  recommendation_run_id,
  suburb_key,
  estimated_oop,
  expected_oop,
  round(abs(expected_oop - estimated_oop), 6) as abs_delta
from calc
order by abs_delta desc;
```

## SQL Filter Rule Check
Replace placeholders:

```sql
select
  rr.id as run_id,
  rr.max_out_of_pocket,
  max((elem->>'estimated_oop')::numeric) as max_returned_oop
from public.recommendation_runs rr
join public.recommendations r
  on r.recommendation_run_id = rr.id
left join lateral jsonb_array_elements(r.top_suburbs) elem on true
where rr.id = '<run_id>'::uuid
group by rr.id, rr.max_out_of_pocket;
```

Pass condition:
- `max_returned_oop <= max_out_of_pocket`
- or `max_returned_oop is null` for empty arrays

## UI Verification
For one selected suburb card:
1. Note card `Median Price`, `Weekly Rent`, `Weekly OOP`.
2. Recompute expected OOP using formula.
3. Confirm displayed OOP is consistent with computed value (rounding-only differences).

## Defect Logging Template
- Test ID:
- Run ID:
- Input budget:
- Input max_oop:
- Strategy:
- Suburb key:
- Expected OOP:
- Actual OOP:
- Delta:
- Severity (`P0/P1/P2`):
- Notes:

