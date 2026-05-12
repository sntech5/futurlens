-- Purpose:
-- Read-only dry-run preflight for NSW Run 2 market metrics refresh.
--
-- Source CSV:
-- ../futurlens_data/temp_csv/DSR-Data-NSW-Run2-26thMay2026.csv
--
-- Target quarter_period:
-- 2026-06
--
-- Safe:
-- Read-only SELECT checks only. No writes, no truncates, no imports.
--
-- Supabase SQL Editor note:
-- Run one numbered query at a time. Do not run this whole file in one go.

-- Query 1: Current table row counts.
with csv_suburbs(suburb_key, suburb_name, state, postcode) as (
  values
    ('CHITTAWAY BAY_NSW_2261', 'CHITTAWAY BAY', 'NSW', '2261'),
    ('BLUE HAVEN_NSW_2262', 'BLUE HAVEN', 'NSW', '2262'),
    ('MOUNT HUTTON_NSW_2290', 'MOUNT HUTTON', 'NSW', '2290'),
    ('SHORTLAND_NSW_2307', 'SHORTLAND', 'NSW', '2307'),
    ('RUTHERFORD_NSW_2320', 'RUTHERFORD', 'NSW', '2320'),
    ('TELARAH_NSW_2320', 'TELARAH', 'NSW', '2320'),
    ('BERESFIELD_NSW_2322', 'BERESFIELD', 'NSW', '2322'),
    ('WOODBERRY_NSW_2322', 'WOODBERRY', 'NSW', '2322'),
    ('METFORD_NSW_2323', 'METFORD', 'NSW', '2323'),
    ('WESTON_NSW_2326', 'WESTON', 'NSW', '2326'),
    ('MUSWELLBROOK_NSW_2333', 'MUSWELLBROOK', 'NSW', '2333'),
    ('SCONE_NSW_2337', 'SCONE', 'NSW', '2337'),
    ('EAST TAMWORTH_NSW_2340', 'EAST TAMWORTH', 'NSW', '2340'),
    ('HILLVUE_NSW_2340', 'HILLVUE', 'NSW', '2340'),
    ('WAUCHOPE_NSW_2446', 'WAUCHOPE', 'NSW', '2446'),
    ('NAMBUCCA HEADS_NSW_2448', 'NAMBUCCA HEADS', 'NSW', '2448'),
    ('BOAMBEE EAST_NSW_2452', 'BOAMBEE EAST', 'NSW', '2452'),
    ('TOORMINA_NSW_2452', 'TOORMINA', 'NSW', '2452'),
    ('WEST BALLINA_NSW_2478', 'WEST BALLINA', 'NSW', '2478'),
    ('GOONELLABAH_NSW_2480', 'GOONELLABAH', 'NSW', '2480'),
    ('MURWILLUMBAH_NSW_2484', 'MURWILLUMBAH', 'NSW', '2484'),
    ('BILAMBIL HEIGHTS_NSW_2486', 'BILAMBIL HEIGHTS', 'NSW', '2486'),
    ('TWEED HEADS SOUTH_NSW_2486', 'TWEED HEADS SOUTH', 'NSW', '2486'),
    ('CRINGILA_NSW_2502', 'CRINGILA', 'NSW', '2502'),
    ('TULLIMBAR_NSW_2527', 'TULLIMBAR', 'NSW', '2527'),
    ('BATEHAVEN_NSW_2536', 'BATEHAVEN', 'NSW', '2536'),
    ('NORTH NOWRA_NSW_2541', 'NORTH NOWRA', 'NSW', '2541'),
    ('SOUTH NOWRA_NSW_2541', 'SOUTH NOWRA', 'NSW', '2541'),
    ('WEST NOWRA_NSW_2541', 'WEST NOWRA', 'NSW', '2541'),
    ('KARABAR_NSW_2620', 'KARABAR', 'NSW', '2620'),
    ('EAST ALBURY_NSW_2640', 'EAST ALBURY', 'NSW', '2640'),
    ('GLENROY_NSW_2640', 'GLENROY', 'NSW', '2640'),
    ('THURGOONA_NSW_2640', 'THURGOONA', 'NSW', '2640'),
    ('BOURKELANDS_NSW_2650', 'BOURKELANDS', 'NSW', '2650'),
    ('ESTELLA_NSW_2650', 'ESTELLA', 'NSW', '2650'),
    ('KOORINGAL_NSW_2650', 'KOORINGAL', 'NSW', '2650'),
    ('EGLINTON_NSW_2795', 'EGLINTON', 'NSW', '2795'),
    ('LLANARTH_NSW_2795', 'LLANARTH', 'NSW', '2795'),
    ('WINDRADYNE_NSW_2795', 'WINDRADYNE', 'NSW', '2795'),
    ('ORANGE_NSW_2800', 'ORANGE', 'NSW', '2800'),
    ('DUBBO_NSW_2830', 'DUBBO', 'NSW', '2830')
),
row_counts as (
  select 'suburbs' as check_name, count(*)::text as result from public.suburbs
  union all
  select 'suburb_import_staging', count(*)::text from public.suburb_import_staging
  union all
  select 'suburb_key_metrics_quarterly', count(*)::text from public.suburb_key_metrics_quarterly
  union all
  select 'suburb_base_scores', count(*)::text from public.suburb_base_scores
  union all
  select 'suburb_population_metrics', count(*)::text from public.suburb_population_metrics
)
select *
from row_counts
order by check_name;

-- Query 2: How many CSV suburbs already exist in suburb master.
with csv_suburbs(suburb_key, suburb_name, state, postcode) as (
  values
    ('CHITTAWAY BAY_NSW_2261', 'CHITTAWAY BAY', 'NSW', '2261'),
    ('BLUE HAVEN_NSW_2262', 'BLUE HAVEN', 'NSW', '2262'),
    ('MOUNT HUTTON_NSW_2290', 'MOUNT HUTTON', 'NSW', '2290'),
    ('SHORTLAND_NSW_2307', 'SHORTLAND', 'NSW', '2307'),
    ('RUTHERFORD_NSW_2320', 'RUTHERFORD', 'NSW', '2320'),
    ('TELARAH_NSW_2320', 'TELARAH', 'NSW', '2320'),
    ('BERESFIELD_NSW_2322', 'BERESFIELD', 'NSW', '2322'),
    ('WOODBERRY_NSW_2322', 'WOODBERRY', 'NSW', '2322'),
    ('METFORD_NSW_2323', 'METFORD', 'NSW', '2323'),
    ('WESTON_NSW_2326', 'WESTON', 'NSW', '2326'),
    ('MUSWELLBROOK_NSW_2333', 'MUSWELLBROOK', 'NSW', '2333'),
    ('SCONE_NSW_2337', 'SCONE', 'NSW', '2337'),
    ('EAST TAMWORTH_NSW_2340', 'EAST TAMWORTH', 'NSW', '2340'),
    ('HILLVUE_NSW_2340', 'HILLVUE', 'NSW', '2340'),
    ('WAUCHOPE_NSW_2446', 'WAUCHOPE', 'NSW', '2446'),
    ('NAMBUCCA HEADS_NSW_2448', 'NAMBUCCA HEADS', 'NSW', '2448'),
    ('BOAMBEE EAST_NSW_2452', 'BOAMBEE EAST', 'NSW', '2452'),
    ('TOORMINA_NSW_2452', 'TOORMINA', 'NSW', '2452'),
    ('WEST BALLINA_NSW_2478', 'WEST BALLINA', 'NSW', '2478'),
    ('GOONELLABAH_NSW_2480', 'GOONELLABAH', 'NSW', '2480'),
    ('MURWILLUMBAH_NSW_2484', 'MURWILLUMBAH', 'NSW', '2484'),
    ('BILAMBIL HEIGHTS_NSW_2486', 'BILAMBIL HEIGHTS', 'NSW', '2486'),
    ('TWEED HEADS SOUTH_NSW_2486', 'TWEED HEADS SOUTH', 'NSW', '2486'),
    ('CRINGILA_NSW_2502', 'CRINGILA', 'NSW', '2502'),
    ('TULLIMBAR_NSW_2527', 'TULLIMBAR', 'NSW', '2527'),
    ('BATEHAVEN_NSW_2536', 'BATEHAVEN', 'NSW', '2536'),
    ('NORTH NOWRA_NSW_2541', 'NORTH NOWRA', 'NSW', '2541'),
    ('SOUTH NOWRA_NSW_2541', 'SOUTH NOWRA', 'NSW', '2541'),
    ('WEST NOWRA_NSW_2541', 'WEST NOWRA', 'NSW', '2541'),
    ('KARABAR_NSW_2620', 'KARABAR', 'NSW', '2620'),
    ('EAST ALBURY_NSW_2640', 'EAST ALBURY', 'NSW', '2640'),
    ('GLENROY_NSW_2640', 'GLENROY', 'NSW', '2640'),
    ('THURGOONA_NSW_2640', 'THURGOONA', 'NSW', '2640'),
    ('BOURKELANDS_NSW_2650', 'BOURKELANDS', 'NSW', '2650'),
    ('ESTELLA_NSW_2650', 'ESTELLA', 'NSW', '2650'),
    ('KOORINGAL_NSW_2650', 'KOORINGAL', 'NSW', '2650'),
    ('EGLINTON_NSW_2795', 'EGLINTON', 'NSW', '2795'),
    ('LLANARTH_NSW_2795', 'LLANARTH', 'NSW', '2795'),
    ('WINDRADYNE_NSW_2795', 'WINDRADYNE', 'NSW', '2795'),
    ('ORANGE_NSW_2800', 'ORANGE', 'NSW', '2800'),
    ('DUBBO_NSW_2830', 'DUBBO', 'NSW', '2830')
)
select
  count(*) as csv_suburb_count,
  count(s.suburb_key) as already_in_suburb_master,
  count(*) - count(s.suburb_key) as missing_from_suburb_master
from csv_suburbs c
left join public.suburbs s on s.suburb_key = c.suburb_key;

-- Query 3: CSV suburbs missing from suburb master.
-- Important: do not create duplicate suburbs in public.suburbs.
-- Only missing suburb_keys should be considered for suburb master inserts later.
with csv_suburbs(suburb_key, suburb_name, state, postcode) as (
  values
    ('CHITTAWAY BAY_NSW_2261', 'CHITTAWAY BAY', 'NSW', '2261'),
    ('BLUE HAVEN_NSW_2262', 'BLUE HAVEN', 'NSW', '2262'),
    ('MOUNT HUTTON_NSW_2290', 'MOUNT HUTTON', 'NSW', '2290'),
    ('SHORTLAND_NSW_2307', 'SHORTLAND', 'NSW', '2307'),
    ('RUTHERFORD_NSW_2320', 'RUTHERFORD', 'NSW', '2320'),
    ('TELARAH_NSW_2320', 'TELARAH', 'NSW', '2320'),
    ('BERESFIELD_NSW_2322', 'BERESFIELD', 'NSW', '2322'),
    ('WOODBERRY_NSW_2322', 'WOODBERRY', 'NSW', '2322'),
    ('METFORD_NSW_2323', 'METFORD', 'NSW', '2323'),
    ('WESTON_NSW_2326', 'WESTON', 'NSW', '2326'),
    ('MUSWELLBROOK_NSW_2333', 'MUSWELLBROOK', 'NSW', '2333'),
    ('SCONE_NSW_2337', 'SCONE', 'NSW', '2337'),
    ('EAST TAMWORTH_NSW_2340', 'EAST TAMWORTH', 'NSW', '2340'),
    ('HILLVUE_NSW_2340', 'HILLVUE', 'NSW', '2340'),
    ('WAUCHOPE_NSW_2446', 'WAUCHOPE', 'NSW', '2446'),
    ('NAMBUCCA HEADS_NSW_2448', 'NAMBUCCA HEADS', 'NSW', '2448'),
    ('BOAMBEE EAST_NSW_2452', 'BOAMBEE EAST', 'NSW', '2452'),
    ('TOORMINA_NSW_2452', 'TOORMINA', 'NSW', '2452'),
    ('WEST BALLINA_NSW_2478', 'WEST BALLINA', 'NSW', '2478'),
    ('GOONELLABAH_NSW_2480', 'GOONELLABAH', 'NSW', '2480'),
    ('MURWILLUMBAH_NSW_2484', 'MURWILLUMBAH', 'NSW', '2484'),
    ('BILAMBIL HEIGHTS_NSW_2486', 'BILAMBIL HEIGHTS', 'NSW', '2486'),
    ('TWEED HEADS SOUTH_NSW_2486', 'TWEED HEADS SOUTH', 'NSW', '2486'),
    ('CRINGILA_NSW_2502', 'CRINGILA', 'NSW', '2502'),
    ('TULLIMBAR_NSW_2527', 'TULLIMBAR', 'NSW', '2527'),
    ('BATEHAVEN_NSW_2536', 'BATEHAVEN', 'NSW', '2536'),
    ('NORTH NOWRA_NSW_2541', 'NORTH NOWRA', 'NSW', '2541'),
    ('SOUTH NOWRA_NSW_2541', 'SOUTH NOWRA', 'NSW', '2541'),
    ('WEST NOWRA_NSW_2541', 'WEST NOWRA', 'NSW', '2541'),
    ('KARABAR_NSW_2620', 'KARABAR', 'NSW', '2620'),
    ('EAST ALBURY_NSW_2640', 'EAST ALBURY', 'NSW', '2640'),
    ('GLENROY_NSW_2640', 'GLENROY', 'NSW', '2640'),
    ('THURGOONA_NSW_2640', 'THURGOONA', 'NSW', '2640'),
    ('BOURKELANDS_NSW_2650', 'BOURKELANDS', 'NSW', '2650'),
    ('ESTELLA_NSW_2650', 'ESTELLA', 'NSW', '2650'),
    ('KOORINGAL_NSW_2650', 'KOORINGAL', 'NSW', '2650'),
    ('EGLINTON_NSW_2795', 'EGLINTON', 'NSW', '2795'),
    ('LLANARTH_NSW_2795', 'LLANARTH', 'NSW', '2795'),
    ('WINDRADYNE_NSW_2795', 'WINDRADYNE', 'NSW', '2795'),
    ('ORANGE_NSW_2800', 'ORANGE', 'NSW', '2800'),
    ('DUBBO_NSW_2830', 'DUBBO', 'NSW', '2830')
)
select c.*
from csv_suburbs c
left join public.suburbs s on s.suburb_key = c.suburb_key
where s.suburb_key is null
order by c.suburb_key;

-- Query 4: Existing quarterly rows for target quarter_period.
select
  quarter_period,
  count(*) as existing_rows_for_target_quarter
from public.suburb_key_metrics_quarterly
where quarter_period = '2026-06'
group by quarter_period;

-- Query 5: Duplicate suburb master guardrail.
-- Expected result: no rows.
select
  suburb_key,
  count(*) as duplicate_count
from public.suburbs
group by suburb_key
having count(*) > 1
order by duplicate_count desc, suburb_key;

-- Query 6: Quarterly metrics rows without suburb master.
-- Expected result: 0.
select count(*) as quarterly_without_suburb
from public.suburb_key_metrics_quarterly q
left join public.suburbs s on s.suburb_key = q.suburb_key
where s.suburb_key is null;

-- Query 7: Base score rows without any quarterly source.
-- Expected result: 0, unless base scores have not been populated yet.
select count(*) as base_scores_without_quarterly_source
from public.suburb_base_scores s
where not exists (
  select 1
  from public.suburb_key_metrics_quarterly q
  where q.suburb_key = s.suburb_key
);
