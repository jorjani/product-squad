#!/bin/bash
# Auto-Enrich: mechanically fill spec gaps and extract oversized bodies.
# Board-first: queries Project #5 for Backlog items (fill-mode) and Ready items
# with the `oversized` label (extract-mode).
# Handles file paths, schema refs, size estimates from codebase context only.
# For product judgment and full scoping, use Sarge (getqatalyst/sarge).
# Usage: ./orchestrator.sh auto-enrich
# POSTS: SPEC-UPDATED:, ESCALATION:, ESCALATE-DEDUP (via comments.sh helper)
# READS: NEEDS-SPEC:, SPEC-UPDATED:, BUILD-OVERSIZED:, `oversized` label
set -euo pipefail
unset CLAUDECODE 2>/dev/null || true

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RESULTS_DIR="$SCRIPT_DIR/results"
DATE=$(date +%Y-%m-%d)
LOG="$RESULTS_DIR/$DATE.log"

mkdir -p "$RESULTS_DIR"
source "$SCRIPT_DIR/config/board-ids.sh"
source "$SCRIPT_DIR/config/model-routing.sh"
source "$SCRIPT_DIR/lib/comments.sh"
source "$SCRIPT_DIR/lib/repos.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/questions.sh"

ELIGIBLE_REPOS="$(eligible_repos)"

# Collect codebase context from a repo's .studio/ and CLAUDE.md
collect_context() {
  local project_dir="$1"
  local context=""

  if [ -f "$project_dir/.studio/project.json" ]; then
    context="### .studio/project.json\n\n$(cat "$project_dir/.studio/project.json")\n\n"
  fi
  if [ -f "$project_dir/.studio/context.md" ]; then
    context="${context}### .studio/context.md\n\n$(cat "$project_dir/.studio/context.md")\n\n"
  fi
  if [ -f "$project_dir/.studio/features.yaml" ]; then
    context="${context}### .studio/features.yaml\n\n$(cat "$project_dir/.studio/features.yaml")\n\n"
  fi
  if [ -f "$project_dir/CLAUDE.md" ]; then
    context="${context}### CLAUDE.md\n\n$(cat "$project_dir/CLAUDE.md")\n\n"
  elif [ -f "$project_dir/.claude/CLAUDE.md" ]; then
    context="${context}### CLAUDE.md\n\n$(cat "$project_dir/.claude/CLAUDE.md")\n\n"
  fi
  if [ -f "$project_dir/.studio/SCHEMA.md" ]; then
    context="${context}### SCHEMA.md\n\n$(cat "$project_dir/.studio/SCHEMA.md")\n\n"
  fi

  echo "$context"
}

# Slug from title (same algorithm as build-ticket.sh:67 — see specs/125-* §Slug)
slug_from_title() {
  echo "$1" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-//' | sed 's/-$//' | head -c 40
}

# Per-size body target. Falls back to 4800 when size is unset/unknown.
# XS=500, S=1500, M=2500 per issue-conventions.md §3. L/XL are exempt from the
# 5000c rule (Foreman never builds them) — use 4800 so extract still slims them.
body_target_for_size() {
  case "$1" in
    XS) echo 500 ;;
    S)  echo 1500 ;;
    M)  echo 2500 ;;
    *)  echo 4800 ;;
  esac
}

ENRICHED=0
ESCALATED=0
SKIPPED=0
EXTRACTED=0
EXTRACT_CAP=3  # Per-cycle extraction cap (deep-dive §Loop budget)

echo "AUTO-ENRICH PHASE: Scanning Backlog items for NEEDS-SPEC comments" >> "$LOG"

# Step 1: Get Backlog items from the board (board-first approach).
# Triage rejects keep issues at Backlog with a NEEDS-SPEC comment (no column
# demote), so auto-enrich looks for NEEDS-SPEC at Backlog, not Scope.
BACKLOG_ITEMS=$(fetch_board_items | python3 -c "
import json, sys
eligible = set('$ELIGIBLE_REPOS'.split())
data = json.load(sys.stdin)
for item in data.get('items', []):
    if item.get('status', '') != 'Backlog':
        continue
    content = item.get('content', {})
    repo = content.get('repository', '')
    if repo not in eligible:
        continue
    num = content.get('number', '')
    if num:
        print(f'{repo}|{num}')
" 2>/dev/null || true)

if [ -z "$BACKLOG_ITEMS" ]; then
  echo "AUTO-ENRICH PHASE: No Backlog items on board (skipping pass 1)" >> "$LOG"
fi

# Step 2: For each Backlog item, check comment state and enrich if needed
while IFS='|' read -r REPO ISSUE_NUM; do
  [ -z "$REPO" ] && continue

  ISSUE_DATA=$(gh issue view "$ISSUE_NUM" --repo "$REPO" --json title,body,comments 2>/dev/null) || {
    echo "AUTO-ENRICH: $REPO#$ISSUE_NUM - could not fetch issue" >> "$LOG"
    SKIPPED=$((SKIPPED + 1))
    continue
  }

  TITLE=$(echo "$ISSUE_DATA" | python3 -c "import json,sys; print(json.load(sys.stdin).get('title',''))" 2>/dev/null)

  COMMENT_STATUS=$(echo "$ISSUE_DATA" | python3 -c "
import json, sys
data = json.load(sys.stdin)
comments = data.get('comments', [])

def is_needs_spec(body):
    if body.startswith('NEEDS-SPEC:'):
        return True
    if body.startswith('Automated triage:') and 'promoted' not in body.lower():
        return True
    return False

has_needs_spec = False
needs_spec_idx = -1
spec_updated_idx = -1
escalation_idx = -1
for i, c in enumerate(comments):
    body = c.get('body', '')
    if is_needs_spec(body):
        has_needs_spec = True
        needs_spec_idx = i
    if body.startswith('SPEC-UPDATED:'):
        spec_updated_idx = i
    if body.startswith('ESCALATION:'):
        escalation_idx = i

if not has_needs_spec:
    print('no-feedback|0')
    sys.exit(0)

# If already escalated (ESCALATION after last NEEDS-SPEC), don't re-escalate
if escalation_idx > needs_spec_idx:
    print('already-escalated|0')
    sys.exit(0)

# If SPEC-UPDATED came after last NEEDS-SPEC, already enriched
if spec_updated_idx > needs_spec_idx:
    print('already-enriched|0')
    sys.exit(0)

# Count round-trips: SPEC-UPDATED followed by another NEEDS-SPEC
round_trips = 0
for i, c in enumerate(comments):
    body = c.get('body', '')
    if body.startswith('SPEC-UPDATED:'):
        for j in range(i+1, len(comments)):
            if is_needs_spec(comments[j].get('body', '')):
                round_trips += 1
                break

print(f'needs-enrich|{round_trips}')
" 2>/dev/null || echo "error|0")

  STATUS=$(echo "$COMMENT_STATUS" | cut -d'|' -f1)
  ROUND_TRIPS=$(echo "$COMMENT_STATUS" | cut -d'|' -f2)

  if [ "$STATUS" != "needs-enrich" ]; then
    echo "AUTO-ENRICH: $REPO#$ISSUE_NUM - $TITLE ($STATUS, skipping)" >> "$LOG"
    continue
  fi

  echo "AUTO-ENRICH: $REPO#$ISSUE_NUM - $TITLE (round_trips=$ROUND_TRIPS)" >> "$LOG"

  # Disagreement escalation: 3+ NEEDS-SPEC → SPEC-UPDATED loops without passing triage
  # (Bumped from 2 to 3: gives auto-enrich one more attempt before pulling David in.
  # Malformed responses are escalated separately at the parse step below.)
  if [ "$ROUND_TRIPS" -ge 3 ]; then
    echo "  ESCALATING (disagreement): $ROUND_TRIPS round-trips without passing triage" >> "$LOG"
    comment_dedup_or_escalate "$REPO" "$ISSUE_NUM" "ESCALATION: This issue has been through $ROUND_TRIPS rounds of NEEDS-SPEC → enrichment without passing triage (disagreement loop). @jorjani please review." "auto-enrich-escalation" || true
    ESCALATED=$((ESCALATED + 1))
    continue
  fi

  ISSUE_BODY=$(echo "$ISSUE_DATA" | python3 -c "import json,sys; print(json.load(sys.stdin).get('body',''))" 2>/dev/null)
  if [ -z "$ISSUE_BODY" ]; then
    echo "  SKIP: Empty issue body" >> "$LOG"
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  NEEDS_SPEC_FEEDBACK=$(echo "$ISSUE_DATA" | python3 -c "
import json, sys
data = json.load(sys.stdin)
comments = data.get('comments', [])
last_ns = None
for c in comments:
    body = c.get('body', '')
    if body.startswith('NEEDS-SPEC:'):
        last_ns = body
    elif body.startswith('Automated triage:') and 'promoted' not in body.lower():
        last_ns = body
if last_ns:
    print(last_ns)
" 2>/dev/null || true)

  if [ -z "$NEEDS_SPEC_FEEDBACK" ]; then
    echo "  SKIP: No NEEDS-SPEC comment found" >> "$LOG"
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  PROJECT_DIR="$(repo_to_path "$REPO")"
  if [ -z "$PROJECT_DIR" ] || [ ! -d "$PROJECT_DIR" ]; then
    echo "  SKIP: Unknown or missing project dir for $REPO" >> "$LOG"
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  CODEBASE_CONTEXT=$(collect_context "$PROJECT_DIR")

  TMPFILE=$(mktemp)

  sed \
    -e "s|{REPO}|$REPO|g" \
    -e "s|{ISSUE_NUMBER}|$ISSUE_NUM|g" \
    "$SCRIPT_DIR/prompts/auto-enrich.md" > "$TMPFILE"

  # Replace large values via python (safe for multiline content)
  READY_CHECKLIST=$(cat "$SCRIPT_DIR/config/ready-templates.md" 2>/dev/null || echo "")
  export NEEDS_SPEC_FEEDBACK CODEBASE_CONTEXT READY_CHECKLIST
  python3 -c "
import sys, os
body = sys.stdin.read()
with open(sys.argv[1], 'r') as f:
    content = f.read()
content = content.replace('{ISSUE_TITLE}', sys.argv[2])
content = content.replace('{ISSUE_BODY}', body)
content = content.replace('{NEEDS_SPEC_FEEDBACK}', os.environ.get('NEEDS_SPEC_FEEDBACK', ''))
content = content.replace('{CODEBASE_CONTEXT}', os.environ.get('CODEBASE_CONTEXT', ''))
content = content.replace('{READY_CHECKLIST}', os.environ.get('READY_CHECKLIST', ''))
with open(sys.argv[1], 'w') as f:
    f.write(content)
" "$TMPFILE" "$TITLE" <<< "$ISSUE_BODY"

  RESULT_FILE="$RESULTS_DIR/$DATE-auto-enrich-$ISSUE_NUM.log"
  ENRICH_RESULT=$(claude -p "$(cat "$TMPFILE")" \
    --model "$AUTO_ENRICH_MODEL" \
    --effort medium \
    --max-budget-usd "$AUTO_ENRICH_BUDGET" \
    --dangerously-skip-permissions \
    < /dev/null 2>"$RESULT_FILE") || {
    echo "  SKIP: Claude enrichment failed (see $RESULT_FILE)" >> "$LOG"
    SKIPPED=$((SKIPPED + 1))
    rm -f "$TMPFILE"
    continue
  }

  rm -f "$TMPFILE"

  # Parse response once — strip fences, extract JSON, re-emit clean
  ENRICH_JSON=$(echo "$ENRICH_RESULT" | python3 -c "
import json, sys, re
text = sys.stdin.read().strip()
fence_match = re.search(r'\`\`\`(?:json)?\s*\n(.*?)\n\`\`\`', text, re.DOTALL)
if fence_match:
    text = fence_match.group(1).strip()
if not text.startswith('{'):
    json_match = re.search(r'(\{.*\})', text, re.DOTALL)
    if json_match:
        text = json_match.group(1)
try:
    print(json.dumps(json.loads(text)))
except Exception as e:
    print(f'PARSE_ERROR: {e}', file=sys.stderr)
    print(f'RAW_LENGTH: {len(text)}', file=sys.stderr)
    sys.exit(1)
" 2>>"$RESULT_FILE") || {
    echo "  PARSE FAIL: enrichment response was malformed (see $RESULT_FILE)" >> "$LOG"
    # Dedup: only post DECISION-NEEDED if we haven't already flagged this issue for parse failure
    ALREADY_FLAGGED=$(echo "$ISSUE_DATA" | python3 -c "
import json, sys
data = json.load(sys.stdin)
for c in data.get('comments', []):
    if 'DECISION-NEEDED: Foreman auto-enrich could not parse' in c.get('body', ''):
        print('yes'); break
" 2>/dev/null)
    if [ "$ALREADY_FLAGGED" != "yes" ]; then
      gh issue comment "$ISSUE_NUM" --repo "$REPO" --body "DECISION-NEEDED: Foreman auto-enrich could not parse Claude's JSON response on this issue. @jorjani please review the spec manually, fix it, or re-run auto-enrich. Diagnostic log: \`$RESULT_FILE\`" 2>/dev/null || true
      ESCALATED=$((ESCALATED + 1))
    fi
    questions_register "auto-enrich-parse-fail" "$REPO" "$ISSUE_NUM" \
      "auto-enrich could not parse Claude's response while filling spec gaps. Diagnostic log: $RESULT_FILE" \
      "" "" "[]" "" || true
    SKIPPED=$((SKIPPED + 1))
    continue
  }

  UPDATED_BODY=$(echo "$ENRICH_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin)['updated_body'])" 2>>"$RESULT_FILE") || {
    echo "  SKIP: Missing updated_body in response (see $RESULT_FILE)" >> "$LOG"
    SKIPPED=$((SKIPPED + 1))
    continue
  }

  CHANGES_MADE=$(echo "$ENRICH_JSON" | python3 -c "
import json, sys
for c in json.load(sys.stdin).get('changes_made', ['Enriched spec based on codebase recon']):
    print(f'- {c}')
" 2>/dev/null || echo "- Enriched spec based on codebase recon")

  if [ -z "$UPDATED_BODY" ]; then
    echo "  SKIP: Empty updated body" >> "$LOG"
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  # Update the issue body
  gh issue edit "$ISSUE_NUM" --repo "$REPO" --body "$UPDATED_BODY" 2>/dev/null || {
    echo "  FAIL: Could not update issue body" >> "$LOG"
    SKIPPED=$((SKIPPED + 1))
    continue
  }

  # Post SPEC-UPDATED comment so foreman knows to re-triage
  comment_dedup_or_escalate "$REPO" "$ISSUE_NUM" "SPEC-UPDATED: Enriched spec based on codebase recon.

**Added:**
$CHANGES_MADE

_This issue will be re-evaluated on the next triage run._" "spec-updated" || true

  echo "  ENRICHED: $REPO#$ISSUE_NUM" >> "$LOG"
  ENRICHED=$((ENRICHED + 1))

done <<< "$BACKLOG_ITEMS"

# ---------------------------------------------------------------------------
# Pass 2: Extract oversized bodies on Ready items.
#
# Trigger:  status == Ready AND repository in ELIGIBLE_REPOS AND
#           (`oversized` label present OR body > 5000 chars).
# Output:   commit specs/<num>-<slug>.md to project main, slim issue body
#           with a `Spec: <URL>` line, remove the `oversized` label.
# Cap:      EXTRACT_CAP per cycle (deep-dive §Loop budget).
# See:      specs/125-auto-extract-deep-dive.md
# ---------------------------------------------------------------------------

echo "" >> "$LOG"
echo "AUTO-ENRICH PHASE: Pass 2 — scanning Ready items for oversized bodies" >> "$LOG"

# Fetch Ready items + Size field via GraphQL (fetch_board_items doesn't return Size).
READY_OVERSIZED=$(python3 -c "
import json, subprocess, sys
eligible = set('$ELIGIBLE_REPOS'.split())
items = []
cursor = None
while True:
    after = f', after: \"{cursor}\"' if cursor else ''
    query = '''
    {
      organization(login: \"$PROJECT_ORG\") {
        projectV2(number: $PROJECT_NUMBER) {
          items(first: 100''' + after + ''') {
            pageInfo { hasNextPage endCursor }
            nodes {
              status: fieldValueByName(name: \"Status\") {
                ... on ProjectV2ItemFieldSingleSelectValue { name }
              }
              size: fieldValueByName(name: \"Size\") {
                ... on ProjectV2ItemFieldSingleSelectValue { name }
              }
              content {
                ... on Issue {
                  number
                  repository { nameWithOwner }
                  labels(first: 20) { nodes { name } }
                }
              }
            }
          }
        }
      }
    }'''
    r = subprocess.run(['gh', 'api', 'graphql', '-f', f'query={query}'], capture_output=True, text=True)
    if r.returncode != 0:
        sys.stderr.write(f'extract-mode: GraphQL failed: {r.stderr}\n')
        break
    data = json.loads(r.stdout)
    page = data['data']['organization']['projectV2']['items']
    for n in page['nodes']:
        c = n.get('content') or {}
        if not c.get('number'):
            continue
        repo = c.get('repository', {}).get('nameWithOwner', '')
        if repo not in eligible:
            continue
        st = (n.get('status') or {}).get('name', '')
        if st != 'Ready':
            continue
        sz = (n.get('size') or {}).get('name', '') or ''
        labels = [l['name'] for l in (c.get('labels') or {}).get('nodes', [])]
        has_oversized_label = 'oversized' in labels
        print(f'{repo}|{c[\"number\"]}|{sz}|{1 if has_oversized_label else 0}')
    if not page['pageInfo']['hasNextPage']:
        break
    cursor = page['pageInfo']['endCursor']
" 2>>"$LOG" || true)

if [ -z "$READY_OVERSIZED" ]; then
  echo "AUTO-ENRICH PHASE: No Ready items on board" >> "$LOG"
  echo "enriched=$ENRICHED escalated=$ESCALATED skipped=$SKIPPED extracted=$EXTRACTED"
  exit 0
fi

while IFS='|' read -r REPO ISSUE_NUM SIZE_NAME HAS_LABEL; do
  [ -z "$REPO" ] && continue

  if [ "$EXTRACTED" -ge "$EXTRACT_CAP" ]; then
    echo "AUTO-ENRICH (extract): cap of $EXTRACT_CAP reached, skipping rest" >> "$LOG"
    break
  fi

  ISSUE_DATA=$(gh issue view "$ISSUE_NUM" --repo "$REPO" --json title,body 2>/dev/null) || {
    echo "AUTO-ENRICH (extract): $REPO#$ISSUE_NUM - could not fetch issue" >> "$LOG"
    continue
  }

  TITLE=$(echo "$ISSUE_DATA" | python3 -c "import json,sys; print(json.load(sys.stdin).get('title',''))" 2>/dev/null)
  ISSUE_BODY=$(echo "$ISSUE_DATA" | python3 -c "import json,sys; print(json.load(sys.stdin).get('body',''))" 2>/dev/null)
  BODY_CHARS=$(printf '%s' "$ISSUE_BODY" | wc -c | tr -d ' ')

  # Filter: needs the label or actually-oversized body. (A stale label with
  # a now-slim body falls through to the idempotency check below and gets
  # the label removed.)
  if [ "$HAS_LABEL" != "1" ] && [ "$BODY_CHARS" -le 5000 ]; then
    continue
  fi

  BODY_TARGET=$(body_target_for_size "$SIZE_NAME")

  # Idempotency: already slimmed OR already carries a Spec: link to this repo's specs.
  # 4800c threshold (not 5000) prevents bodies in the 4800-5000 band from re-triggering build-ticket's gate.
  HAS_SPEC_LINK=$(printf '%s' "$ISSUE_BODY" | grep -E "Spec:.*${REPO}/(blob/[^/]+/)?specs/${ISSUE_NUM}-" -q && echo yes || echo no)
  if [ "$BODY_CHARS" -le 4800 ] || [ "$HAS_SPEC_LINK" = "yes" ]; then
    echo "AUTO-ENRICH (extract): $REPO#$ISSUE_NUM idempotent (chars=$BODY_CHARS, spec_link=$HAS_SPEC_LINK), removing oversized label" >> "$LOG"
    [ "$HAS_LABEL" = "1" ] && gh issue edit "$ISSUE_NUM" --repo "$REPO" --remove-label "oversized" 2>/dev/null || true
    continue
  fi

  PROJECT_DIR="$(repo_to_path "$REPO")"
  if [ -z "$PROJECT_DIR" ] || [ ! -d "$PROJECT_DIR" ]; then
    echo "AUTO-ENRICH (extract): $REPO#$ISSUE_NUM SKIP — unknown project dir" >> "$LOG"
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  SLUG=$(slug_from_title "$TITLE")
  SPEC_REL="specs/${ISSUE_NUM}-${SLUG}.md"
  SPEC_URL="https://github.com/${REPO}/blob/main/${SPEC_REL}"

  echo "AUTO-ENRICH (extract): $REPO#$ISSUE_NUM body=${BODY_CHARS}c size=${SIZE_NAME:-unset} target=${BODY_TARGET}c spec=${SPEC_REL}" >> "$LOG"

  # Render prompt
  TMPFILE=$(mktemp)
  sed \
    -e "s|{REPO}|$REPO|g" \
    -e "s|{ISSUE_NUMBER}|$ISSUE_NUM|g" \
    -e "s|{BODY_TARGET}|$BODY_TARGET|g" \
    -e "s|{SPEC_URL}|$SPEC_URL|g" \
    "$SCRIPT_DIR/prompts/auto-extract-oversized.md" > "$TMPFILE"

  python3 -c "
import sys
body = sys.stdin.read()
with open(sys.argv[1], 'r') as f:
    content = f.read()
content = content.replace('{ISSUE_BODY}', body)
with open(sys.argv[1], 'w') as f:
    f.write(content)
" "$TMPFILE" <<< "$ISSUE_BODY"

  RESULT_FILE="$RESULTS_DIR/$DATE-auto-extract-$ISSUE_NUM.log"
  EXTRACT_RESULT=$(claude -p "$(cat "$TMPFILE")" \
    --model "$AUTO_ENRICH_MODEL" \
    --effort medium \
    --max-budget-usd "$AUTO_ENRICH_BUDGET" \
    --dangerously-skip-permissions \
    < /dev/null 2>"$RESULT_FILE") || {
    echo "  SKIP: Claude extraction failed (see $RESULT_FILE)" >> "$LOG"
    SKIPPED=$((SKIPPED + 1))
    rm -f "$TMPFILE"
    continue
  }
  rm -f "$TMPFILE"

  # Parse: strip fences, extract JSON
  EXTRACT_JSON=$(echo "$EXTRACT_RESULT" | python3 -c "
import json, sys, re
text = sys.stdin.read().strip()
fence_match = re.search(r'\`\`\`(?:json)?\s*\n(.*?)\n\`\`\`', text, re.DOTALL)
if fence_match:
    text = fence_match.group(1).strip()
if not text.startswith('{'):
    json_match = re.search(r'(\{.*\})', text, re.DOTALL)
    if json_match:
        text = json_match.group(1)
try:
    print(json.dumps(json.loads(text)))
except Exception as e:
    print(f'PARSE_ERROR: {e}', file=sys.stderr)
    sys.exit(1)
" 2>>"$RESULT_FILE") || {
    echo "  PARSE FAIL (extract): see $RESULT_FILE" >> "$LOG"
    comment_dedup_or_escalate "$REPO" "$ISSUE_NUM" "DECISION-NEEDED: Foreman auto-extract could not parse Claude's JSON response. @jorjani please review the spec manually. Diagnostic log: \`$RESULT_FILE\`" "auto-extract-parse-fail" || true
    questions_register "auto-extract-parse-fail" "$REPO" "$ISSUE_NUM" \
      "auto-extract could not parse Claude's response while slimming an oversized issue body. Diagnostic log: $RESULT_FILE" \
      "" "" "[]" "" || true
    ESCALATED=$((ESCALATED + 1))
    SKIPPED=$((SKIPPED + 1))
    continue
  }

  UPDATED_BODY=$(echo "$EXTRACT_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin).get('updated_body',''))" 2>/dev/null)
  SPEC_DOC=$(echo "$EXTRACT_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin).get('spec_doc_content',''))" 2>/dev/null)

  if [ -z "$UPDATED_BODY" ] || [ -z "$SPEC_DOC" ]; then
    echo "  SKIP: missing updated_body or spec_doc_content (see $RESULT_FILE)" >> "$LOG"
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  # Verify slimmed body contains the Spec link we asked for
  if ! printf '%s' "$UPDATED_BODY" | grep -F "$SPEC_URL" -q; then
    echo "  SKIP: slimmed body missing Spec: $SPEC_URL" >> "$LOG"
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  # Write spec doc to project main checkout, commit, push.
  # Per Projects/.studio/guardrails/spec-commits.md: commit directly to main,
  # explicit-path `git add`, message `specs(<num>): <slug>`. Pre-commit hook
  # allows commits under specs/ on main.
  SPEC_PATH="$PROJECT_DIR/$SPEC_REL"
  mkdir -p "$PROJECT_DIR/specs"
  printf '%s\n' "$SPEC_DOC" > "$SPEC_PATH"

  PUSH_OK=0
  PUSH_ATTEMPT=0
  while [ "$PUSH_ATTEMPT" -lt 2 ]; do
    PUSH_ATTEMPT=$((PUSH_ATTEMPT + 1))
    (
      set -e
      cd "$PROJECT_DIR"
      git fetch origin main --quiet
      git checkout main --quiet
      # Idempotent: rebase onto latest main; if our spec file is the only
      # local change, this either fast-forwards or replays cleanly.
      git rebase origin/main --quiet || { git rebase --abort 2>/dev/null || true; exit 21; }
      git add "$SPEC_REL"
      # Stage check: if nothing to commit (rerun with identical content), skip.
      if git diff --cached --quiet; then
        echo "  spec doc unchanged on disk, skipping commit" >> "$LOG"
        exit 0
      fi
      git commit -m "specs(${ISSUE_NUM}): ${SLUG}" --quiet
      git push origin main --quiet
    ) >> "$LOG" 2>&1
    PUSH_RC=$?
    if [ "$PUSH_RC" -eq 0 ]; then
      PUSH_OK=1
      break
    fi
    echo "  push attempt $PUSH_ATTEMPT failed rc=$PUSH_RC, retrying after fetch" >> "$LOG"
    ( cd "$PROJECT_DIR" && git fetch origin main --quiet ) || true
  done

  if [ "$PUSH_OK" -ne 1 ]; then
    echo "  FAIL: spec doc push failed after retry for $REPO#$ISSUE_NUM" >> "$LOG"
    comment_dedup_or_escalate "$REPO" "$ISSUE_NUM" "ESCALATE-DEDUP: Foreman auto-extract could not push spec doc to ${REPO}'s main (rebase/push conflict after one retry). @jorjani please investigate. Diagnostic: \`$RESULT_FILE\`" "auto-extract-rebase-conflict" || true
    ESCALATED=$((ESCALATED + 1))
    continue
  fi

  # Update the issue body
  if ! gh issue edit "$ISSUE_NUM" --repo "$REPO" --body "$UPDATED_BODY" 2>>"$LOG"; then
    echo "  FAIL: gh issue edit failed (spec doc already committed, body unchanged)" >> "$LOG"
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  # Remove the `oversized` label so build-ticket's pre-flight stops re-firing.
  gh issue edit "$ISSUE_NUM" --repo "$REPO" --remove-label "oversized" 2>/dev/null || true

  # Post-edit verification: re-fetch and confirm we cleared the 5000c gate.
  NEW_BODY=$(gh issue view "$ISSUE_NUM" --repo "$REPO" --json body -q '.body' 2>/dev/null || echo "")
  NEW_CHARS=$(printf '%s' "$NEW_BODY" | wc -c | tr -d ' ')
  if [ "$NEW_CHARS" -gt 5000 ]; then
    echo "  WARN: slimmed body still ${NEW_CHARS}c (> 5000) for $REPO#$ISSUE_NUM" >> "$LOG"
    comment_dedup_or_escalate "$REPO" "$ISSUE_NUM" "ESCALATE-DEDUP: Foreman auto-extract slimmed the body to ${NEW_CHARS} chars but it is still over the 5000-char build gate. Spec doc was committed to main at \`${SPEC_REL}\`. @jorjani please slim further manually." "auto-extract-still-oversized" || true
    ESCALATED=$((ESCALATED + 1))
    continue
  fi

  echo "  EXTRACTED: $REPO#$ISSUE_NUM (${BODY_CHARS}c -> ${NEW_CHARS}c, spec=${SPEC_REL})" >> "$LOG"
  EXTRACTED=$((EXTRACTED + 1))

done <<< "$READY_OVERSIZED"

echo "AUTO-ENRICH PHASE: enriched=$ENRICHED extracted=$EXTRACTED escalated=$ESCALATED skipped=$SKIPPED" >> "$LOG"
echo "enriched=$ENRICHED extracted=$EXTRACTED escalated=$ESCALATED skipped=$SKIPPED"
