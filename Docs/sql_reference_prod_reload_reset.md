# SQL Reference: reset_domain_data_prod.sql

File:
[reset_domain_data_prod.sql](../sql/reset_domain_data_prod.sql)

## Context
Domain-data reset before loading real production data.

## Purpose
- Clear recommendation and suburb-domain tables in FK-safe order.
- Preserve user/auth profile tables by default.

## Execution Notes
- Destructive script.
- Run only after backup and write freeze.
- Follow with data load and post-load validation.

