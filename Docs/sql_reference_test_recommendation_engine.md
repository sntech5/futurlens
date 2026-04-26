# SQL Reference: test_recommendation_engine.sql

File:
[test_recommendation_engine.sql](/Users/sujithnair/Documents/Passionproject/Suburb Recommender/sql/test_recommendation_engine.sql)

## Context
Assertion-style function tests for recommendation engine behavior.

## Purpose
- Validate recommendation row creation.
- Validate `top_suburbs` type and null safety.
- Validate budget/OOP filter behavior.
- Validate key payload fields.

## Execution Notes
- Transactional script with rollback.
- Intended for staging first, then controlled production checks.

