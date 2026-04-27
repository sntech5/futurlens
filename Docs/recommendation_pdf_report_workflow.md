# Recommendation PDF Report Workflow

Purpose:
- document the MVP database design for customer-facing PDF reports
- preserve recommendation run results while allowing users to select suburbs for a report
- support report retrieval without regenerating the PDF

## Core Design

A recommendation run is the calculation event. A report is a customer-facing document created from that run.

```text
recommendation_runs
→ recommendations
→ recommendation_reports
→ recommendation_report_suburbs
```

One recommendation run can support multiple PDF reports. Each report can have different selected suburbs and customer details, while still preserving the original engine ranking.

## Why Reports Are Separate From Runs

The recommendation engine answers:

```text
Given this budget, max weekly out-of-pocket, and strategy, which suburbs match?
```

A PDF report answers:

```text
For this customer, which selected suburbs from the recommendation result should be included in a stored report?
```

These are related but different business objects.

## Ranking Rules

The engine ranking remains meaningful even when the user manually selects suburbs for a report.

- `source_rank`: original rank from the recommendation engine
- `report_rank`: order chosen for the PDF report

Example:

```text
MERBEIN_VIC_3505
source_rank = 3
report_rank = 1
```

This means the suburb was ranked third by the engine, but the user chose to place it first in the customer report.

MVP rule:
- users should select suburbs from the generated recommendation result
- users should not add arbitrary suburbs from outside that result

## Customer Handling For MVP

There is no customer master table for MVP.

Customer details are entered when generating the report and stored directly on `recommendation_reports`:

- `customer_name`
- `customer_email`

For admin users:
- customer name and email are manually entered
- `generated_by_user_profile_id` stores the admin profile

For non-admin users:
- customer email can default to the logged-in user's email
- `generated_by_user_profile_id` stores the user's profile

## Report Code

Each report has a unique human-readable code:

```text
CUSTOMER-NAME-YYYYMMDD-### 
```

Example:

```text
JOHN-CITIZEN-20260427-002
```

The sequence is daily and stored as:

- `report_date`
- `daily_sequence`

The database enforces uniqueness for:

- `report_code`
- `(report_date, daily_sequence)`

## Tables

### `recommendation_reports`

Purpose:
- one row per generated or draft PDF report
- stores customer snapshot details
- stores final PDF storage metadata after upload

Important columns:
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

Allowed statuses:

```text
draft
generating
generated
failed
```

### `recommendation_report_suburbs`

Purpose:
- stores selected suburbs for a report
- preserves the original engine rank and report order
- stores a JSON snapshot of suburb data used in the report

Important columns:
- `id`
- `report_id`
- `suburb_key`
- `source_rank`
- `report_rank`
- `suburb_snapshot`
- `created_at`

Important constraints:
- one row per selected suburb per report
- one report row per `report_rank`
- `suburb_key` references `suburbs.suburb_key`

## Functions

### `public.create_recommendation_report_with_suburbs(...)`

Purpose:
- creates a draft report
- generates the report code
- stores customer details
- stores selected suburb snapshots

Inputs:
- `p_recommendation_run_id uuid`
- `p_recommendation_id uuid`
- `p_customer_name text`
- `p_customer_email text`
- `p_generated_by_user_profile_id uuid`
- `p_selected_suburb_keys text[]`

Output:
- the inserted `recommendation_reports` row

### `public.update_recommendation_report_pdf_status(...)`

Purpose:
- updates a report after PDF generation/upload
- stores the final PDF storage path and file name
- marks the report as `generated` or `failed`

Inputs:
- `p_report_id uuid`
- `p_report_status text`
- `p_pdf_storage_path text`
- `p_pdf_file_name text`

Output:
- the updated `recommendation_reports` row

## PDF Storage Rule

The MVP stores the generated PDF file.

Recommended flow:

```text
1. User selects suburbs.
2. User enters customer details.
3. App calls create_recommendation_report_with_suburbs.
4. App generates the PDF from report data.
5. App uploads the PDF to storage.
6. App calls update_recommendation_report_pdf_status with the storage path.
7. Later retrieval uses report_code and pdf_storage_path.
```

Reports should be retrieved from stored PDF files, not regenerated from live suburb score data, because suburb data and scores may change later.

## Future Considerations

- Add RLS policies before exposing report tables directly to authenticated users.
- Add a `generating` status update if PDF generation becomes asynchronous.
- Add a customer master table only after the product needs reusable customers.
- Add report search by `report_code`, `customer_email`, and generated date.
- Consider merging `recommendations` into `recommendation_runs` only after report workflow is stable.
