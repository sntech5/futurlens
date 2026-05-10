# Data Technical Debt

Purpose:
- track known data-quality gaps separately from product feature requests
- make source-data limitations visible before they affect scoring, reports, or recommendations
- keep each debt item actionable, auditable, and tied to a validation query where possible

## Todo

### 1. Backfill Population Growth Rates For NT/SA/TAS Population Count Backfill

Status:
- open

Context:
- On 2026-05-10, 43 NT/SA/TAS suburbs were added to `public.suburb_population_metrics`
  from `suburb_population_match_results.csv`.
- The source file contained `population_2025` only.
- It did not contain `growth_2023_2024_pct` or `growth_2024_2025_pct`.

Impact:
- Affected suburbs can show `population_2025`.
- They cannot show source-backed `population_growth_pct` or
  `population_growth_vs_state_pct`.
- `base_population_growth_score` should remain neutral at `5` until verified
  growth rates are loaded.
- Growth strategy totals remain usable, but population momentum is not
  source-backed for these suburbs.

Required data fix:
- Source verified `growth_2023_2024_pct` and `growth_2024_2025_pct` for the
  43 NT/SA/TAS suburbs.
- Load the growth rates through `public.suburb_population_metrics_staging`.
- Run `public.refresh_suburb_base_scores()` after the load.
- Re-run the population growth diagnostics and scoring validation.

Target suburbs:

```text
ANULA_NT_812
KARAMA_NT_812
LEANYER_NT_812
WULAGI_NT_812
ZUCCOLI_NT_832
BARMERA_SA_5345
BURTON_SA_5110
LOXTON_SA_5333
MOUNT GAMBIER_SA_5290
NARACOORTE_SA_5271
NOARLUNGA DOWNS_SA_5168
OTTOWAY_SA_5013
PARA HILLS WEST_SA_5096
PORT LINCOLN_SA_5606
SALISBURY PARK_SA_5109
ST AGNES_SA_5097
STRATHALBYN_SA_5255
WALLAROO_SA_5556
WILLASTON_SA_5118
AUSTINS FERRY_TAS_7011
BRIGHTON_TAS_7030
CHIGWELL_TAS_7011
CLAREMONT_TAS_7011
DODGES FERRY_TAS_7173
GEILSTON BAY_TAS_7015
GEORGE TOWN_TAS_7253
HADSPEN_TAS_7290
HOWRAH_TAS_7018
KINGSTON_TAS_7050
LONGFORD_TAS_7301
LUTANA_TAS_7009
MIDWAY POINT_TAS_7171
MORNINGTON_TAS_7018
NEW NORFOLK_TAS_7140
OLD BEACH_TAS_7017
RISDON VALE_TAS_7016
ROKEBY_TAS_7019
ROSETTA_TAS_7010
SCOTTSDALE_TAS_7260
SOMERSET_TAS_7322
ST LEONARDS_TAS_7250
SUMMERHILL_TAS_7250
WEST ULVERSTONE_TAS_7315
```

Validation:
- Use [diagnose_population_growth_score_gaps.sql](../sql/diagnose_population_growth_score_gaps.sql).
- Expected after fix:
  - `growth_2023_2024_pct` is populated for these suburbs.
  - `growth_2024_2025_pct` is populated for these suburbs.
  - `population_growth_pct` is no longer null after score refresh.
  - `population_growth_vs_state_pct` is no longer null after score refresh.
  - `base_population_growth_score` is source-backed instead of neutral fallback.

### 2. Resolve Remaining NSW Population Coverage Gaps

Status:
- open

Context:
- After the 2026-05-10 incremental refresh and NT/SA/TAS population count
  backfill, the remaining `quarterly_without_population` count is `20`.
- These are existing NSW backlog suburbs, not newly introduced by the latest
  market metrics import.

Impact:
- Reports should omit unavailable population fields for these suburbs.
- Scoring should not invent population count or population momentum.

Required data fix:
- Source verified 2025 population and growth-rate fields for the remaining NSW
  suburbs.
- Load through `public.suburb_population_metrics_staging`.
- Refresh scores and re-run population coverage validation.
