#!/bin/bash
# Phase 1: Review open PRs across eligible repos
# Checks CI, runs Claude review, merges clean auto/ PRs
# POSTS: Automated review:, CI flag:
# READS: Automated review:, Automated repair:
set -euo pipefail
unset CLAUDECODE 2>/dev/null || true

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$SCRIPT_DIR/config/model-routing.sh"
DATE=$(date +%Y-%m-%d)
LOG="$SCRIPT_DIR/results/$DATE.log"

# REPOS dynamically loaded from ~/Projects/.index.json (projects with board.project_number).
# Foreman is appended explicitly because it owns the registry but doesn't have a board entry
# in .index.json (and adding one would change BUILD-phase semantics — see CLAUDE.md
# "Foreman itself is self-improve only"). Review-only inclusion lives here.
INDEX_PATH="${HOME}/Projects/.index.json"
if [ ! -r "$INDEX_PATH" ]; then
  echo "REVIEW FAIL: ${INDEX_PATH} not readable" >&2
  exit 1
fi
# Source board constants early so we can filter by PROJECT_NUMBER from config
source "$SCRIPT_DIR/config/board-ids.sh"
# CI policy: advisory checks (e.g., SonarCloud) don't block automerge.
source "$SCRIPT_DIR/config/ci-policy.sh"
REPOS=()
while IFS= read -r repo; do
  [ -z "$repo" ] && continue
  REPOS+=("$repo")
done < <(jq -r --argjson pn "$PROJECT_NUMBER" '.projects | to_entries[] | select(.value.board.project_number == $pn) | select(.value.status != "archived" and .value.status != "parked") | .value.repos[]?' "$INDEX_PATH")
REPOS+=("getqatalyst/foreman")

repo_to_dir() {
  local repo="$1"
  jq -r --arg repo "$repo" '.projects | to_entries[] | select(.value.repos[]? == $repo) | (.value.local_path // .key)' "${HOME}/Projects/.index.json" 2>/dev/null \
    | head -1 \
    | sed 's|^|/Users/jorjani/Projects/|'
}

# Board move helpers (constants already sourced above for PROJECT_NUMBER)

REVIEWED=0
MERGED=0
FLAGGED=0
REPAIRED=0
COLLISIONS=0

# Extract linked issue number from PR body (Closes/Refs/Fixes/Resolves #N)
extract_linked_issue() {
  local pr_num="$1" repo="$2"
  gh pr view "$pr_num" --repo "$repo" --json body -q '.body' 2>/dev/null | python3 -c "
import re, sys
body = sys.stdin.read()
match = re.search(r'(?:Closes|Fixes|Resolves|Refs)\s+#(\d+)', body, re.IGNORECASE)
print(match.group(1) if match else '')
" 2>/dev/null || true
}

# Migration directory for repos that have them
migration_dir_for_repo() {
  case "$1" in
    getqatalyst/Sage) echo "src/db/migrations/" ;;
    getqatalyst/product-studio) echo "server/src/db/migrations/" ;;
    *) echo "" ;;
  esac
}

# Check if a collision warning marker already exists on a PR
has_collision_warning() {
  local pr_num="$1" repo="$2" marker="$3"
  gh pr view "$pr_num" --repo "$repo" --json comments --jq \
    ".comments[] | select(.body | contains(\"$marker\"))" 2>/dev/null | grep -q .
}

# Post collision warning on a PR (with dedup marker)
post_collision_warning() {
  local pr_num="$1" repo="$2" marker="$3" message="$4"
  if ! has_collision_warning "$pr_num" "$repo" "$marker"; then
    gh pr comment "$pr_num" --repo "$repo" --body "<!-- $marker -->
:warning: **Collision detected**

$message

_Automated detection by Foreman review phase._" 2>/dev/null || true
  fi
}

# --- Cross-PR collision scan (runs before per-PR review) ---
cross_pr_collision_scan() {
  echo "--- COLLISION SCAN ---" >> "$LOG"
  for REPO in "${REPOS[@]}"; do
    # Fetch all open PRs with files and bodies
    PR_DATA=$(gh pr list --repo "$REPO" --state open --json number,headRefName,body,files --limit 50 2>/dev/null || echo '[]')
    PR_COUNT=$(echo "$PR_DATA" | python3 -c "import json,sys; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "0")
    [ "$PR_COUNT" -lt 2 ] && continue

    # Detect collisions via python (handles both migration + close-target)
    MIGRATION_DIR=$(migration_dir_for_repo "$REPO")
    export MIGRATION_DIR
    COLLISION_RESULTS=$(echo "$PR_DATA" | python3 -c "
import json, sys, re, os

data = json.load(sys.stdin)
migration_dir = os.environ.get('MIGRATION_DIR', '')
collisions = []

# Build per-PR data
prs = []
for pr in data:
    num = pr['number']
    files = [f['path'] for f in pr.get('files', [])]
    body = pr.get('body', '') or ''
    closes = set(re.findall(r'(?:Closes|Fixes|Resolves|Refs)\s+#(\d+)', body, re.IGNORECASE))
    migration_prefixes = set()
    if migration_dir:
        for f in files:
            if f.startswith(migration_dir):
                basename = f[len(migration_dir):]
                prefix = re.match(r'^(\d+)', basename)
                if prefix:
                    migration_prefixes.add(prefix.group(1))
    prs.append({'num': num, 'files': files, 'closes': closes, 'migrations': migration_prefixes})

# Check all pairs
for i in range(len(prs)):
    for j in range(i+1, len(prs)):
        a, b = prs[i], prs[j]
        # Migration collisions
        shared_migrations = a['migrations'] & b['migrations']
        for m in shared_migrations:
            print(f'migration|{m}|{a[\"num\"]}|{b[\"num\"]}')
        # Close target collisions
        shared_closes = a['closes'] & b['closes']
        for c in shared_closes:
            print(f'closes|{c}|{a[\"num\"]}|{b[\"num\"]}')
" 2>/dev/null || true)

    [ -z "$COLLISION_RESULTS" ] && continue

    while IFS='|' read -r TYPE TARGET PR_A PR_B; do
      [ -z "$TYPE" ] && continue
      MARKER="COLLISION:${TYPE}-${TARGET}"

      if [ "$TYPE" = "migration" ]; then
        MSG="PRs #$PR_A and #$PR_B both add migration **$TARGET** in \`$MIGRATION_DIR\`. One will need renumbering before merge."
      else
        MSG="PRs #$PR_A and #$PR_B both claim to close **#$TARGET**. Only one should close it."
      fi

      echo "  COLLISION: $REPO $TYPE=$TARGET PRs #$PR_A #$PR_B" >> "$LOG"
      post_collision_warning "$PR_A" "$REPO" "$MARKER" "$MSG"
      post_collision_warning "$PR_B" "$REPO" "$MARKER" "$MSG"
      COLLISIONS=$((COLLISIONS + 1))
    done <<< "$COLLISION_RESULTS"
  done
  echo "COLLISION SCAN: found=$COLLISIONS" >> "$LOG"
}

# Remove worktree + local branch for a merged branch
# Usage: cleanup_merged_worktrees [branch_name]
# If branch_name is provided, cleans that specific one first, then sweeps all orphans.
cleanup_merged_worktrees() {
  local target_branch="${1:-}"

  # Remove a specific branch/worktree if provided
  if [ -n "$target_branch" ]; then
    local wt_path
    wt_path=$(git -C "$(repo_to_dir "${REPO}")" worktree list --porcelain 2>/dev/null \
      | awk -v t="$target_branch" '/^worktree /{path=$2} $1=="branch" && $2=="refs/heads/" t {print path}' || true)
    if [ -n "$wt_path" ] && [ -d "$wt_path" ]; then
      git -C "$(repo_to_dir "${REPO}")" worktree remove "$wt_path" --force 2>/dev/null || true
      echo "  CLEANUP: removed worktree $wt_path for branch $target_branch" >> "$LOG"
    fi
    git -C "$(repo_to_dir "${REPO}")" branch -D "$target_branch" 2>/dev/null || true
    echo "  CLEANUP: deleted local branch $target_branch" >> "$LOG"
  fi

  # Sweep: remove any worktree whose branch is fully merged into origin/main
  for sweep_repo in "${REPOS[@]}"; do
    local sweep_dir
    sweep_dir="$(repo_to_dir "$sweep_repo")"
    [ -d "$sweep_dir" ] || continue
    git -C "$sweep_dir" fetch origin main --prune 2>/dev/null || true
    git -C "$sweep_dir" worktree list --porcelain 2>/dev/null \
      | awk '/^worktree /{path=$2} /^branch /{branch=substr($2,12); print path"|"branch}' \
      | while IFS='|' read -r wt_path wt_branch; do
          [ -z "$wt_branch" ] && continue
          [ "$wt_branch" = "main" ] && continue
          # Check if branch is merged into origin/main
          if git -C "$sweep_dir" merge-base --is-ancestor "refs/heads/$wt_branch" "origin/main" 2>/dev/null; then
            git -C "$sweep_dir" worktree remove "$wt_path" --force 2>/dev/null || true
            git -C "$sweep_dir" branch -D "$wt_branch" 2>/dev/null || true
            echo "CLEANUP SWEEP: removed orphan worktree $wt_path ($sweep_repo/$wt_branch)" >> "$LOG"
          fi
        done
  done
}

# Run collision scan before reviews
cross_pr_collision_scan

for REPO in "${REPOS[@]}"; do
  PROJECT_DIR="$(repo_to_dir "$REPO")"
  if [ -z "$PROJECT_DIR" ] || [ ! -d "$PROJECT_DIR" ]; then
    echo "[$REPO] SKIP: no local dir resolved (got '$PROJECT_DIR')" >> "$LOG"
    continue
  fi

  # Get open PRs (skip drafts)
  PRS=$(gh pr list --repo "$REPO" --state open --json number,title,headRefName,isDraft,statusCheckRollup 2>/dev/null || echo '[]')

  # Per-repo required-status-checks lookup (foreman#182). Empty array means
  # the target branch has no protection — every check is informational, so
  # advisory failures (like Sage's SonarCloud quality gate) don't block
  # auto-merge.
  REQUIRED_CHECKS_JSON=$(required_checks_for_repo "$REPO")
  export REQUIRED_CHECKS_JSON

  # Process each PR (process substitution keeps variables in parent shell)
  while IFS='|' read -r PR_NUM PR_TITLE BRANCH CI_STATUS; do
    [ -z "$PR_NUM" ] && continue

    echo "[$REPO] PR #$PR_NUM: $PR_TITLE (CI: $CI_STATUS)" >> "$LOG"

    # Skip if already reviewed today (CI flags don't count — PR should be re-reviewed after CI passes)
    ALREADY=$(gh pr view "$PR_NUM" --repo "$REPO" --json comments --jq ".comments[] | select(.body | startswith(\"Automated review\")) | select(.createdAt | startswith(\"$DATE\"))" 2>/dev/null || true)
    if [ -n "$ALREADY" ]; then
      echo "  SKIP: Already reviewed today" >> "$LOG"
      continue
    fi

    # Skip if CI not passing
    if [ "$CI_STATUS" = "pending" ]; then
      echo "  SKIP: CI pending" >> "$LOG"
      continue
    fi

    if [ "$CI_STATUS" = "fail" ]; then
      gh pr comment "$PR_NUM" --repo "$REPO" --body "CI flag: CI checks are failing. Please fix before review." 2>/dev/null || true
      echo "  FLAGGED: CI failing" >> "$LOG"
      FLAGGED=$((FLAGGED + 1))
      continue
    fi

    if [ "$CI_STATUS" = "none" ]; then
      echo "  INFO: No CI checks configured, reviewing anyway" >> "$LOG"
    fi

    # Render review prompt
    TMPFILE=$(mktemp)
    sed \
      -e "s|{REPO}|$REPO|g" \
      -e "s|{PR_NUMBER}|$PR_NUM|g" \
      -e "s|{BRANCH}|$BRANCH|g" \
      "$SCRIPT_DIR/prompts/review.md" > "$TMPFILE"

    python3 -c "
import sys
with open(sys.argv[1], 'r') as f:
    content = f.read()
content = content.replace('{PR_TITLE}', sys.argv[2])
with open(sys.argv[1], 'w') as f:
    f.write(content)
" "$TMPFILE" "$PR_TITLE"

    # Run Claude review from project dir
    cd "$PROJECT_DIR"
    git fetch origin 2>/dev/null || true

    claude -p "$(cat "$TMPFILE")" \
      --model "$REVIEW_MODEL" \
      --effort high \
      --max-budget-usd "$REVIEW_BUDGET" \
      --dangerously-skip-permissions \
      < /dev/null >> "$SCRIPT_DIR/results/$DATE-review-$PR_NUM.log" 2>&1 || true

    rm -f "$TMPFILE"
    REVIEWED=$((REVIEWED + 1))

    # Check if PR was merged
    PR_STATE=$(gh pr view "$PR_NUM" --repo "$REPO" --json state -q '.state' 2>/dev/null || echo "OPEN")
    if [ "$PR_STATE" = "MERGED" ]; then
      MERGED=$((MERGED + 1))
      LINKED=$(extract_linked_issue "$PR_NUM" "$REPO")
      if [ -n "$LINKED" ]; then
        move_to_verify "$REPO" "$LINKED" >> "$LOG" 2>&1 || true
      fi
      cleanup_merged_worktrees "$BRANCH"
      echo "  MERGED" >> "$LOG"
    elif [[ "$BRANCH" == auto/* ]]; then
      # Auto/ PR with issues — attempt self-repair (max 1 per day)
      REPAIR_DONE=$(gh pr view "$PR_NUM" --repo "$REPO" --json comments --jq ".comments[] | select(.body | startswith(\"Automated repair\")) | select(.createdAt | startswith(\"$DATE\"))" 2>/dev/null || true)
      if [ -n "$REPAIR_DONE" ]; then
        echo "  SKIP REPAIR: Already attempted today" >> "$LOG"
      elif "$SCRIPT_DIR/phases/repair.sh" "$PR_NUM" "$REPO" >> "$LOG" 2>&1; then
        echo "  REPAIR OK: Re-reviewing" >> "$LOG"
        REPAIRED=$((REPAIRED + 1))

        # Re-run review on the repaired PR
        TMPFILE=$(mktemp)
        sed \
          -e "s|{REPO}|$REPO|g" \
          -e "s|{PR_NUMBER}|$PR_NUM|g" \
          -e "s|{BRANCH}|$BRANCH|g" \
          "$SCRIPT_DIR/prompts/review.md" > "$TMPFILE"

        python3 -c "
import sys
with open(sys.argv[1], 'r') as f:
    content = f.read()
content = content.replace('{PR_TITLE}', sys.argv[2])
with open(sys.argv[1], 'w') as f:
    f.write(content)
" "$TMPFILE" "$PR_TITLE"

        cd "$PROJECT_DIR"
        git fetch origin 2>/dev/null || true

        claude -p "$(cat "$TMPFILE")" \
          --model "$REVIEW_MODEL" \
          --effort high \
          --max-budget-usd "$REVIEW_BUDGET" \
          --dangerously-skip-permissions \
          < /dev/null >> "$SCRIPT_DIR/results/$DATE-review-$PR_NUM.log" 2>&1 || true

        rm -f "$TMPFILE"
        REVIEWED=$((REVIEWED + 1))

        PR_STATE=$(gh pr view "$PR_NUM" --repo "$REPO" --json state -q '.state' 2>/dev/null || echo "OPEN")
        if [ "$PR_STATE" = "MERGED" ]; then
          MERGED=$((MERGED + 1))
          LINKED=$(extract_linked_issue "$PR_NUM" "$REPO")
          if [ -n "$LINKED" ]; then
            move_to_verify "$REPO" "$LINKED" >> "$LOG" 2>&1 || true
          fi
          cleanup_merged_worktrees "$BRANCH"
          echo "  MERGED (after repair)" >> "$LOG"
        else
          echo "  REVIEWED (post-repair)" >> "$LOG"
        fi
      else
        echo "  REPAIR FAILED" >> "$LOG"
      fi
    else
      echo "  REVIEWED" >> "$LOG"
    fi
  done < <(echo "$PRS" | python3 -c "
import json, os, sys
advisory = set(json.loads(os.environ.get('ADVISORY_CHECKS_JSON', '[]')))
required = set(json.loads(os.environ.get('REQUIRED_CHECKS_JSON', '[]')))
prs = json.load(sys.stdin)
for pr in prs:
    if pr.get('isDraft', False):
        continue
    num = pr['number']
    title = pr['title']
    branch = pr['headRefName']
    checks = pr.get('statusCheckRollup', []) or []
    # A check gates auto-merge only if it's a required status check on the
    # target branch (foreman#182). When required is empty, branch protection
    # is off and nothing gates — auto-merge proceeds even on advisory fails.
    # The static advisory list is still applied for defense-in-depth.
    def is_gating(c):
        name = c.get('name') or ''
        if name in advisory:
            return False
        if not required:
            return False
        return name in required
    gating = [c for c in checks if is_gating(c)]
    if not checks:
        ci = 'none'
    elif not gating:
        # No gating checks reported — either branch is unprotected or all
        # checks are advisory. Treat as pass so auto-merge proceeds.
        ci = 'pass'
    elif any(c.get('conclusion') == 'FAILURE' or c.get('state') == 'FAILURE' for c in gating):
        ci = 'fail'
    elif all(c.get('conclusion') in ('SUCCESS', 'SKIPPED', 'NEUTRAL', None) or c.get('state') in ('SUCCESS', 'SKIPPED', 'NEUTRAL', None) for c in gating):
        ci = 'pass'
    else:
        ci = 'pending'
    print(f'{num}|{title}|{branch}|{ci}')
" 2>/dev/null)
done

# Sweep for any remaining orphaned worktrees across all repos
cleanup_merged_worktrees ""

echo "REVIEW PHASE: reviewed=$REVIEWED merged=$MERGED flagged=$FLAGGED repaired=$REPAIRED collisions=$COLLISIONS" >> "$LOG"
echo "reviewed=$REVIEWED merged=$MERGED flagged=$FLAGGED repaired=$REPAIRED collisions=$COLLISIONS"


# Label conflicting PRs with needs-rebase
for REPO in "${REPOS[@]}"; do
  CONFLICT_PRS=$(gh pr list --repo "$REPO" --state open --json number,headRefName,body,mergeable --jq '.[] | select(.mergeable == "CONFLICTING") | "\(.number)|\(.body)"' 2>/dev/null || true)
  while IFS='|' read -r PR_NUM PR_BODY; do
    [ -z "$PR_NUM" ] && continue
    # Extract linked issue from PR body (Closes/Refs/Fixes/Resolves #N)
    LINKED_ISSUE=$(extract_linked_issue "$PR_NUM" "$REPO")
    if [ -n "$LINKED_ISSUE" ]; then
      gh issue edit "$LINKED_ISSUE" --repo "$REPO" --add-label "needs-rebase" 2>/dev/null || true
      echo "  CONFLICT: $REPO#$PR_NUM -> labeled issue #$LINKED_ISSUE needs-rebase" >> "$LOG"
    fi
  done <<< "$CONFLICT_PRS"
done

# Stale PR cleanup: close auto/ PRs with merge conflicts older than 3 days
STALE_CLOSED=0
for REPO in "${REPOS[@]}"; do
  STALE_PRS=$(gh pr list --repo "$REPO" --state open --json number,headRefName,createdAt,mergeable --jq '.[] | select(.headRefName | startswith("auto/")) | select(.mergeable == "CONFLICTING") | "\(.number)|\(.createdAt)"' 2>/dev/null || true)
  while IFS='|' read -r PR_NUM CREATED_AT; do
    [ -z "$PR_NUM" ] && continue
    CREATED_EPOCH=$(python3 -c "from datetime import datetime; print(int(datetime.fromisoformat('$CREATED_AT'.replace('Z','+00:00')).timestamp()))" 2>/dev/null || echo 0)
    NOW_EPOCH=$(date +%s)
    AGE_DAYS=$(( (NOW_EPOCH - CREATED_EPOCH) / 86400 ))
    if [ "$AGE_DAYS" -ge 3 ]; then
      gh pr close "$PR_NUM" --repo "$REPO" --comment "Automated cleanup: closing stale PR with merge conflicts (age: ${AGE_DAYS} days). Issue returns to pipeline for rebuild." --delete-branch 2>/dev/null || true
      echo "  STALE CLOSED: $REPO#$PR_NUM (age: ${AGE_DAYS} days)" >> "$LOG"
      STALE_LINKED=$(extract_linked_issue "$PR_NUM" "$REPO")
      if [ -n "$STALE_LINKED" ]; then
        move_to_scope "$REPO" "$STALE_LINKED" >> "$LOG" 2>&1 || true
      fi
      STALE_CLOSED=$((STALE_CLOSED + 1))
    fi
  done <<< "$STALE_PRS"
done
echo "STALE CLEANUP: closed=$STALE_CLOSED" >> "$LOG"
