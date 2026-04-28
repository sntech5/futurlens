# Project Milestone Plan

Purpose:
- keep the project focused on agreed milestones
- avoid drifting into new scope unless the plan is explicitly changed
- provide a simple reference for what is done, in progress, and pending

Working rule:
- Follow this plan in order by default.
- Do not change milestone priority unless the user explicitly confirms a change in plan.
- If a new idea appears, capture it as a future consideration unless it directly supports the current milestone.

## Milestones

| # | Milestone | Status | Notes |
|---|-----------|--------|-------|
| 1 | Base Version: Testable version with app, DB and reports | DONE | Core app flow, database functions/tables, report draft workflow, and report preview/export foundations are available for testing. |
| 2 | Report Generation Final | IN PROGRESS | Professional report preview, PDF export, storage upload, duplicate-export guard, and report-code retrieval are implemented; final end-to-end verification is still in progress. |
| 3 | Suburb Factors Data Ingestion | PENDING | Add ingestion path for report enrichment factors such as developable land supply, amenities, household growth, professional occupation growth, affordability, and employment diversity. |
| 4 | Real Data Ingestion for Suburb Metrics One Time | PENDING | Load real suburb metric data into the existing suburb scoring tables and validate recommendation quality. |
| 5 | DEMO to at least 3 prospective clients | PENDING | Use the testable product to gather feedback from at least three prospective clients. Must replace MVP anon report-storage policies with authenticated user policies before demo. |

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

Required before Milestone 5 demo:
- replace anonymous report storage upload/update policies with authenticated user policies
- confirm report PDFs cannot be uploaded, overwritten, or read by unintended users

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
