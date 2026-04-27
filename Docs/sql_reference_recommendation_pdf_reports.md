# SQL Reference: Recommendation PDF Reports

Files:
- [create_recommendation_report_tables.sql](../sql/create_recommendation_report_tables.sql)
- [create_recommendation_report_functions.sql](../sql/create_recommendation_report_functions.sql)

## Context

Adds MVP database support for stored customer-facing PDF reports generated from recommendation results.

## Purpose

- Create `recommendation_reports`.
- Create `recommendation_report_suburbs`.
- Add indexes for report lookup and selected suburb retrieval.
- Add `public.create_recommendation_report_with_suburbs(...)`.
- Add `public.update_recommendation_report_pdf_status(...)`.

## Expected Outcome

- A user can create a draft report from an existing recommendation result.
- The selected suburbs are stored with both source ranking and report ranking.
- Customer details are stored directly on the report for MVP.
- Generated PDF metadata can be saved for later retrieval.

## Apply Order

Run in this order:

```sql
-- sql/create_recommendation_report_tables.sql
```

Then:

```sql
-- sql/create_recommendation_report_functions.sql
```

## Related Design Doc

[recommendation_pdf_report_workflow.md](recommendation_pdf_report_workflow.md)
