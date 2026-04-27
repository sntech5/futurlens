# Suburb Factors for Reports

Purpose:
- define additional suburb-level factors that should be considered in generated PDF reports
- sit alongside existing suburb data and scores from `suburb_base_scores`
- provide a reusable reference that can be expanded as more report factors are added

These factors are not yet assumed to be part of the current recommendation score unless explicitly added to the scoring SQL. They are intended to enrich suburb reports with context beyond the existing base scores.

## Report Factor List

### 1. Developable Land Supply

What to capture:
- available or future developable land supply in and around the suburb
- whether land supply is constrained, moderate, or abundant
- nearby greenfield estates, rezoning areas, or major release areas

Why it matters:
- constrained land supply can support price growth when demand is strong
- abundant land supply can limit scarcity and slow capital growth
- future supply can affect rental competition and resale performance

Suggested report language:
- "Developable land supply appears constrained/moderate/high, which may support/limit scarcity-driven price growth."

Possible data fields:
- `developable_land_supply_level`
- `developable_land_supply_notes`
- `nearby_land_release_flag`
- `zoning_or_release_area_notes`

### 2. Amenities

What to capture:
- access to schools
- hospitals and medical services
- public transport
- parks and recreation
- shopping and retail centres

Why it matters:
- stronger amenities improve liveability and tenant appeal
- amenity depth can support both owner-occupier demand and rental demand
- transport, schools, and shopping access can influence long-term suburb desirability

Suggested report language:
- "The suburb has strong/moderate/limited amenity access, with key support from schools, transport, parks, shopping, and health services."

Possible data fields:
- `school_access_score`
- `hospital_access_score`
- `public_transport_access_score`
- `parks_recreation_score`
- `shopping_access_score`
- `overall_amenity_score`
- `amenity_notes`

### 3. Households Increasing Faster Than State Average

What to capture:
- household growth rate for the suburb
- state household growth average
- whether the suburb is growing faster than the state benchmark

Why it matters:
- faster household growth can indicate rising underlying housing demand
- household formation is often more directly relevant to dwelling demand than population alone

Suggested report language:
- "Household growth is above/below the state average, indicating stronger/weaker relative demand formation."

Possible data fields:
- `household_growth_pct`
- `state_household_growth_pct`
- `household_growth_vs_state`
- `household_growth_above_state_flag`

### 4. Professional Occupation Increasing Faster Than State Average

What to capture:
- growth in professional occupations within the suburb
- state benchmark for professional occupation growth
- whether the suburb is attracting a higher-income employment profile

Why it matters:
- increasing professional occupation share can indicate improving income profile
- this can support borrowing capacity, owner-occupier demand, and resilience

Suggested report language:
- "Professional occupation growth is above/below the state average, suggesting the suburb's resident employment profile is strengthening/lagging."

Possible data fields:
- `professional_occupation_growth_pct`
- `state_professional_occupation_growth_pct`
- `professional_growth_vs_state`
- `professional_growth_above_state_flag`

### 5. Rent Payments Less Than 30% of Household Income

What to capture:
- percentage of renting households where rent is less than 30% of household income
- affordability trend compared with state or metro benchmark

Why it matters:
- rent below 30% of income suggests rental affordability is healthier
- this may support tenant stability and reduce rental stress risk
- very high affordability can also indicate room for rent growth, depending on market context

Suggested report language:
- "A high/moderate/low share of renters pay less than 30% of income toward rent, indicating lower/higher rental stress."

Possible data fields:
- `rent_under_30_income_pct`
- `state_rent_under_30_income_pct`
- `rental_affordability_vs_state`
- `rental_stress_notes`

### 6. Mortgage Payments Less Than 30% of Household Income

What to capture:
- percentage of mortgaged households where mortgage payments are less than 30% of household income
- affordability trend compared with state or metro benchmark

Why it matters:
- lower mortgage stress can indicate owner-occupier resilience
- stronger affordability can reduce downside risk during rate or income shocks
- poor affordability may constrain future buyer depth

Suggested report language:
- "A high/moderate/low share of mortgaged households pay less than 30% of income toward repayments, indicating lower/higher mortgage stress."

Possible data fields:
- `mortgage_under_30_income_pct`
- `state_mortgage_under_30_income_pct`
- `mortgage_affordability_vs_state`
- `mortgage_stress_notes`

### 7. Diverse Employment Industries

What to capture:
- spread of resident employment across industries
- reliance on one or two dominant sectors
- whether employment diversity is stronger or weaker than the state/metro benchmark

Why it matters:
- diverse employment exposure can improve suburb resilience
- heavy reliance on a single industry can increase risk if that industry weakens
- diversity can support more stable rental and resale demand

Suggested report language:
- "Employment is broadly diversified/concentrated, which may reduce/increase local economic risk."

Possible data fields:
- `employment_diversity_score`
- `top_employment_industry_1`
- `top_employment_industry_1_pct`
- `top_employment_industry_2`
- `top_employment_industry_2_pct`
- `top_employment_industry_3`
- `top_employment_industry_3_pct`
- `industry_concentration_notes`

## Suggested Report Structure

When generating a PDF report, these factors can be presented after the core recommendation result:

1. Recommendation summary
2. Existing suburb metrics and scores
3. Additional suburb factors
4. Risks and caveats
5. Final investment suitability summary

## Implementation Notes

- Keep these factors separate from the base score until the scoring model is intentionally updated.
- Store raw numeric values where possible, not just text labels.
- Store benchmark values alongside suburb values when comparing against state averages.
- Prefer explicit flags for report generation, for example `household_growth_above_state_flag`, so the report can generate consistent text.
- Use notes fields for human-readable context that cannot be captured cleanly as a number.

## Future Additions

Add new factors using the same structure:

```text
### N. Factor Name

What to capture:
- ...

Why it matters:
- ...

Suggested report language:
- ...

Possible data fields:
- ...
```
