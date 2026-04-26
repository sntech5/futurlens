# Suburb Recommender MVP Testing Strategy

Last updated: 2026-04-23 (Australia/Sydney)

## Goal
Validate that recommendation outputs are correct, stable, and understandable across:
- database function logic
- API flow
- frontend rendering/UX

This strategy is built for the current MVP architecture:
- `recommendation_runs` is input source of truth
- `public.run_recommendation_engine(p_run_id uuid)` generates outputs
- `recommendations.top_suburbs` stores ranked results

## Scope
In scope:
- Filtering correctness (`budget`, `max_out_of_pocket`)
- Ranking correctness (`growth` vs `yield`)
- No-match behavior (must not error)
- Output data sanity (no malformed/null critical output)
- UI display sanity (money/percent formatting and explanation alignment)

Out of scope for now:
- advanced personalization models
- long-term statistical model quality
- performance/load testing at large scale

## Test Layers
1. Function layer (Supabase SQL)
- test `run_recommendation_engine` with controlled inputs
- validate written rows and JSON structure
- validate filter and ranking constraints

2. API/data layer
- create run via REST
- call RPC
- fetch recommendations row
- confirm response shape and status behavior

3. UI layer
- input validation
- recommendation cards and detail panel correctness
- edge-case UX (no matches and service errors)

## Entry Criteria
- staging Supabase project ready
- latest DB function definitions deployed
- sufficient suburb data in `suburb_base_scores` (at least 20 suburbs)
- one valid `user_profiles.id` available for testing

## Exit Criteria (MVP sign-off)
- all P0 scenarios pass
- no DB constraint errors in normal flows
- no null `top_suburbs` inserts
- strategy switch changes ranking in expected direction
- no-match scenario renders cleanly in UI

## Environment Strategy
- Primary: staging Supabase project (recommended)
- Optional: production read-only checks for parity
- Do not run destructive setup scripts against production

## Defect Priorities
- P0: wrong recommendations, DB crashes, no-match fails, ranking/filter wrong
- P1: display/data mismatch, explanation mismatch, formatting defects
- P2: copy/style improvements

## Cadence
1. Baseline run on staging before each release candidate
2. Run regression after DB function changes
3. Run quick smoke test after frontend display changes

## Deliverables
- test case matrix: `Docs/test_case_matrix.csv`
- SQL assertion script: `sql/test_recommendation_engine.sql`
- execution notes/results (to be captured after each test cycle)

