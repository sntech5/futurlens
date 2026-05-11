# Project Milestone Plan

Purpose:
- keep the project focused on agreed milestones
- avoid drifting into new scope unless the plan is explicitly changed
- provide a simple reference for what is done, in progress, and pending

Working rule:
- Follow this plan in order by default.
- Do not change milestone priority unless the user explicitly confirms a change in plan.
- If a new idea appears, capture it as a future consideration unless it directly supports the current milestone.
- Guardrail: no made-up suburb data or hidden placeholder logic may be used in recommendations or generated reports. See [no_made_up_data_guardrail.md](no_made_up_data_guardrail.md).

## Milestones

| # | Milestone | Status | Notes |
|---|-----------|--------|-------|
| 1 | Base Version: Testable version with app, DB and reports | DONE | Core app flow, database functions/tables, report draft workflow, and report preview/export foundations are available for testing. |
| 2 | Report Generation Final | IN PROGRESS | Professional report preview, PDF export, storage upload, duplicate-export guard, and report-code retrieval are implemented; final end-to-end verification is still in progress. |
| 3 | Suburb Factors Data Ingestion | PENDING | Add ingestion path for report enrichment factors such as developable land supply, amenities, household growth, professional occupation growth, affordability, and employment diversity. |
| 4 | Real Data Ingestion for Suburb Metrics One Time | PENDING | Load verified real suburb metric data into the existing suburb scoring tables, remove/replace demo data, and validate recommendation quality. |
| 5 | Critical Algorithm Function Review | PENDING | After data refresh, critically analyse every database function that contains scoring, ranking, recommendation, or report-selection logic. Store/review those function bodies in `sql/functions-logic/`. |
| 6 | DEMO to at least 3 prospective clients | PENDING | Use the testable product to gather feedback from at least three prospective clients. Must replace MVP anon report-storage policies with authenticated user policies before demo. |

## Current Focus

Current milestone:

```text
2. Report Generation Final
```

Definition of done:
- report PDF looks professional and readable: implemented, pending final visual acceptance
- report is personalised for the entered customer: implemented
- selected suburbs and rankings are correctly represented: implemented
- PDF can be generated reliably: implemented, pending repeated browser testing
- generated PDF can be stored: implemented, pending final storage verification
- report metadata can be marked as generated: implemented
- report can be retrieved later without regenerating: implemented, pending user confirmation
- temporary anon storage policy is documented as MVP-only: implemented
- report no longer uses synthetic map or historical price trend visuals: implemented

## Guardrails

Before taking on new work, check whether it supports the current milestone.

Allowed during Milestone 2:
- improve report layout and readability
- improve customer personalisation
- fix PDF export quality
- add PDF upload/storage
- connect generated report status to database
- add report retrieval by report code
- fix bugs that block report generation
- document any temporary MVP security shortcuts clearly

Required before Milestone 6 demo:
- replace anonymous report storage upload/update policies with authenticated user policies
- confirm report PDFs cannot be uploaded, overwritten, or read by unintended users
- confirm suburb metrics used in recommendations and reports come from verified source data
- confirm no report chart, insight, or suburb factor is based on synthetic placeholder data unless explicitly labelled as illustrative

## No-Made-Up-Data Todo List

These tasks protect the milestone plan from drifting into polished but unsupported outputs.

Milestone 2:
- keep report wording factual and based on stored recommendation snapshots
- do not show historical trend charts until historical data is ingested
- do not show generated/fake location graphics; use real map/location data only when available

Milestone 3:
- create a source-backed ingestion path for suburb report factors
- keep factors out of PDF factual claims until source data exists
- document source, refresh date, and meaning for each factor

Milestone 4:
- apply or replace [patch_drop_base_total_score_scoring_v2.sql](../sql/patch_drop_base_total_score_scoring_v2.sql)
- load verified quarterly metric source rows before refreshing `suburb_base_scores`
- validate that `suburb_base_scores` has no empty rows created from suburb master data alone
- remove or clearly quarantine old demo/stale metric rows
- rerun recommendation smoke tests after real metric load

Milestone 5:
- collect every algorithm-bearing database function into `sql/functions-logic/`
- review scoring formulas, weights, normalisation, null handling, and ranking order critically
- verify each function uses source-backed metrics only and does not introduce hidden placeholder logic
- document the intended business meaning of each score or recommendation output
- update SQL patch files only after the reviewed function logic is accepted

Defer until later:
- new scoring model changes
- new suburb factor ingestion
- real data reloads
- customer master table
- AI narrative generation beyond simple template text
- major app redesign outside report generation

## Future Considerations

These should not interrupt the current milestone unless explicitly prioritised:
- server-side PDF generation
- AI-generated report commentary
- reusable customer records
- admin report dashboard
- richer suburb map integration
- report analytics or client engagement tracking
