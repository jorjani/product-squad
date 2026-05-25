#!/bin/bash
# Per-phase model and budget assignments for foreman.
# Single source of truth for which model and dollar cap each phase uses.
# foreman/CLAUDE.md references this file rather than restating values inline.
#
# Plain variables (not associative arrays) for bash 3.2 compatibility (macOS default).

# Models
INTAKE_MODEL=opus
BUILD_MODEL=opus
REPAIR_MODEL=opus
CLAIM_AUDIT_MODEL=opus
REVIEW_MODEL=opus
AUTO_ENRICH_MODEL=opus
SARGE_REVIEW_MODEL=opus
SARGE_PITCH_MODEL=opus
SELF_IMPROVE_MODEL=opus
TRIAGE_MODEL=sonnet
VERIFY_MODEL=sonnet
NARRATIVE_MODEL=sonnet
CODE_REVIEW_MODEL=sonnet
# Code-review AC-match classifier (foreman#210): one Sonnet call judging the PR
# diff against the linked issue's acceptance criteria before auto-merge.
CODE_REVIEW_AC_MODEL=sonnet
# Inspector v1 (foreman#209): Haiku routes AC tiers, Sonnet judges captured state.
INSPECT_CLASSIFY_MODEL=haiku
INSPECT_JUDGE_MODEL=sonnet

# Budgets in USD
INTAKE_BUDGET=10
BUILD_BUDGET=20
REPAIR_BUDGET=10
# CLAIM_AUDIT: fresh-context audit on repair commit (claim-vs-diff). Tight cap
# because the prompt is a single commit message + diff; budget headroom guards
# against runaway tool use, not normal cost (~$0.01/run per foreman#241).
CLAIM_AUDIT_BUDGET=1
REVIEW_BUDGET=10
AUTO_ENRICH_BUDGET=10
# SARGE_REVIEW: per-item budget. Phase caps at 3 items per run, so the
# run-wide ceiling is ~3 * SARGE_REVIEW_BUDGET. Honors foreman#192 spec
# ("budget cap: 3 items per run, ~$3 ceiling") at $1/item.
SARGE_REVIEW_BUDGET=1
# SARGE_PITCH: per-item budget. Phase caps at 3 items per run, so the
# run-wide ceiling is ~3 * SARGE_PITCH_BUDGET. Mirrors SARGE_REVIEW_BUDGET.
SARGE_PITCH_BUDGET=1
SELF_IMPROVE_BUDGET=10
TRIAGE_BUDGET=5
VERIFY_BUDGET=5
NARRATIVE_BUDGET=0.50
CODE_REVIEW_BUDGET=2
# CODE_REVIEW_AC: per-PR budget for the foreman#210 AC-match classifier.
# Dispatched only after every cheap merge gate passes, so the run-wide ceiling
# is bounded by the count of mergeable-looking non-auto/* PRs.
CODE_REVIEW_AC_BUDGET=1
# INSPECT: per-call caps for the Inspector v1 LLM path. INSPECT_BUDGET is the
# run-wide ceiling — the phase stops dispatching LLM calls and SKIPs the
# remaining items once (classify+judge) spend would exceed it (foreman#209).
INSPECT_CLASSIFY_BUDGET=0.50
INSPECT_JUDGE_BUDGET=1
INSPECT_BUDGET=5
