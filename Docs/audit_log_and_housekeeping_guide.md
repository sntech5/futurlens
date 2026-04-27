# Audit Log and Housekeeping Guide

File:
[audit_log_and_housekeeping.sql](../sql/audit_log_and_housekeeping.sql)

## Why this exists
Your MVP can generate repeated runs/recommendations for the same criteria during testing and regular use.  
This package adds:
- audit visibility for usage analysis
- safe cleanup utilities to prevent table bloat

## What it adds
1. `public.app_audit_log`
- stores application events for `recommendation_runs` and `recommendations`

2. Logging triggers
- logs run creation/update/deletion
- logs recommendation creation/deletion

3. Cleanup functions
- `public.cleanup_duplicate_recommendations_per_run(p_dry_run boolean)`
- `public.cleanup_old_recommendation_runs(p_keep_latest_per_signature int, p_delete_older_than_days int, p_dry_run boolean)`

## How to apply
1. Run:
[audit_log_and_housekeeping.sql](../sql/audit_log_and_housekeeping.sql)

2. Dry-run duplicate recommendation cleanup:
```sql
select * from public.cleanup_duplicate_recommendations_per_run(true);
```

3. Execute duplicate cleanup:
```sql
select * from public.cleanup_duplicate_recommendations_per_run(false);
```

4. Dry-run old-run cleanup (keep newest 1 per criteria; only rows older than 30 days):
```sql
select * from public.cleanup_old_recommendation_runs(1, 30, true);
```

5. Execute old-run cleanup:
```sql
select * from public.cleanup_old_recommendation_runs(1, 30, false);
```

## Suggested cadence
- Daily: keep dry-run query in dashboard/alert.
- Weekly: execute cleanup with conservative thresholds.
- Monthly: review audit trends and tune retention settings.

## Usage analytics queries
Top event volume by day:
```sql
select
  date_trunc('day', event_time) as day,
  event_name,
  count(*) as events
from public.app_audit_log
group by 1, 2
order by day desc, events desc;
```

Top active profiles (last 30 days):
```sql
select
  actor_user_profile_id,
  count(*) as events
from public.app_audit_log
where event_time >= now() - interval '30 days'
group by actor_user_profile_id
order by events desc;
```

Duplicate-run pressure by criteria:
```sql
select
  user_profile_id,
  strategy_type,
  input_budget,
  max_out_of_pocket,
  count(*) as run_count
from public.recommendation_runs
group by user_profile_id, strategy_type, input_budget, max_out_of_pocket
having count(*) > 1
order by run_count desc;
```

## Notes
- Cleanup logic excludes `pending` runs by default.
- Run dry-run mode first in production.
- Keep backups and follow your runbook sequence for destructive operations.
