# UI Smoke Checklist (2 Minutes)

Use this before each release after backend smoke passes.

## Inputs
- Open the app and confirm no console/runtime errors on load.
- Enter `budget` and `max weekly out of pocket`, pick a strategy, click `Generate Recommendation`.

## Scenario A: Normal result
- Use: budget `900000`, max OOP `500`, strategy `growth`.
- Expected:
  - status reaches `Done`
  - recommendation cards render
  - card fields show money/percent formats correctly
  - `Why This Suburb` text is growth-aligned wording

## Scenario B: Restrictive no-match
- Use: budget `150000`, max OOP `50`, strategy `yield`.
- Expected:
  - no crash/error JSON block
  - clear no-match message appears
  - status does not show `Failed`

## Scenario C: Strategy switch
- Run same inputs twice (one `growth`, one `yield`).
- Expected:
  - ranking or explanation emphasis changes by strategy
  - growth explanation does not use yield-first phrasing
  - yield explanation can mention gross yield

## Scenario D: Detail panel formatting
- Click `View Full Details` on one result.
- Expected:
  - panel opens/closes cleanly
  - percentage fields look sane (no obvious x100/x0.01 errors)
  - vacancy and yield display with `%` and plausible scale

## Pass Criteria
- All scenarios above pass with no blocker defects.

