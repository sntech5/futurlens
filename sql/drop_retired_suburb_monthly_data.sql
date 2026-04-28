-- Purpose:
-- Retire the old monthly metrics table after confirming quarterly metrics are the
-- only active source for recommendation/report data.
--
-- WARNING:
-- This drops public.suburb_monthly_data. Run only after backup/export if you need
-- to preserve old monthly rows.

drop table if exists public.suburb_monthly_data;
