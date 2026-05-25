#!/bin/bash
# lib/repos.sh — Centralized repo lookups derived from ~/Projects/.index.json
#
# Exports three helpers used across phases to avoid the four-file drift that
# previously left auto-enrich/triage missing `getqatalyst/foreman` from their
# eligible sets and verify/cleanup with hand-maintained case statements.
#
#   repo_to_path  <owner/repo>   -> absolute local checkout path
#   repo_to_url   <owner/repo>   -> deploy.live_url (empty if no deployment)
#   eligible_repos               -> space-separated list of repos whose
#                                   agents.foreman array contains "build"
#
# Source-of-truth file: $REPOS_INDEX_JSON (defaults to ~/Projects/.index.json).
# Override via env var for tests.

REPOS_INDEX_JSON="${REPOS_INDEX_JSON:-$HOME/Projects/.index.json}"

repo_to_path() {
  REPO="$1" INDEX="$REPOS_INDEX_JSON" python3 -c "
import json, os, sys
repo = os.environ['REPO']
with open(os.environ['INDEX']) as f:
    data = json.load(f)
for k, p in data.get('projects', {}).items():
    if repo in (p.get('repos') or []):
        lp = p.get('local_path') or k
        print(os.path.join(os.path.expanduser('~'), 'Projects', lp))
        sys.exit(0)
print('')
"
}

repo_to_url() {
  REPO="$1" INDEX="$REPOS_INDEX_JSON" python3 -c "
import json, os, sys
repo = os.environ['REPO']
with open(os.environ['INDEX']) as f:
    data = json.load(f)
for p in data.get('projects', {}).values():
    if repo in (p.get('repos') or []):
        print((p.get('deploy') or {}).get('live_url', ''))
        sys.exit(0)
print('')
"
}

eligible_repos() {
  INDEX="$REPOS_INDEX_JSON" python3 -c "
import json, os
with open(os.environ['INDEX']) as f:
    data = json.load(f)
out = []
for p in data.get('projects', {}).values():
    if 'build' in (p.get('agents', {}).get('foreman') or []):
        for repo in (p.get('repos') or []):
            out.append(repo)
print(' '.join(out))
"
}

# sarge_eligible_repos — repos whose agents.sarge array contains "scope".
# Used by phases/sarge-review.sh to pick Scope items for proactive recon
# AND by phases/sarge-pitch.sh to pick Pitch items for first-pass drafts.
# Pitch is upstream of Scope: any repo Sarge can scope is by definition one
# Sarge can pitch on, so a single capability flag covers both. Avoid adding
# a parallel "pitch" flag — it drifts (see CLAUDE.md lessons on centralizing
# constants and the inline-helper drift trap).
# Distinct from eligible_repos (foreman build) — the same project may opt
# into Sarge scope without opting into Foreman build (e.g. sourcerer).
sarge_eligible_repos() {
  INDEX="$REPOS_INDEX_JSON" python3 -c "
import json, os
with open(os.environ['INDEX']) as f:
    data = json.load(f)
out = []
for p in data.get('projects', {}).values():
    if 'scope' in (p.get('agents', {}).get('sarge') or []):
        for repo in (p.get('repos') or []):
            out.append(repo)
print(' '.join(out))
"
}

# repo_foreman_build_enabled <owner/repo> — prints "true" or "false".
# Defaults to "true" when the project entry exists but lacks board.foreman_build,
# and when the repo is not found in the index (fail-open so unknown repos build).
# Hard-disables build when project.status is archived/parked/inactive — that
# status flag is the strongest signal and overrides any explicit foreman_build.
repo_foreman_build_enabled() {
  REPO="$1" INDEX="$REPOS_INDEX_JSON" python3 -c "
import json, os, sys
repo = os.environ['REPO']
with open(os.environ['INDEX']) as f:
    data = json.load(f)
for p in data.get('projects', {}).values():
    if repo in (p.get('repos') or []):
        status = (p.get('status') or '').strip().lower()
        if status in ('archived', 'parked', 'inactive'):
            print('false')
            sys.exit(0)
        board = p.get('board') or {}
        val = board.get('foreman_build', True)
        print('true' if val else 'false')
        sys.exit(0)
print('true')
"
}

# repo_code_review_automerge_enabled <owner/repo> — prints "true" or "false".
#
# Fail-CLOSED opt-in — the inverse of repo_foreman_build_enabled, which is
# fail-open. The code-review phase (foreman#210) auto-merges a human PR only
# when the repo's .index.json entry has board.code_review_automerge: true.
# Unknown repos, repos without the flag, and archived/parked/inactive projects
# all return "false". Auto-merging a contributor PR is higher-stakes than
# building one, so a repo stays off until David opts it in explicitly.
#
# getqatalyst/foreman is the one built-in exception: it has no board entry in
# .index.json by design (phases/review.sh appends it explicitly), yet it is the
# canonical opt-in repo for code-review auto-merge — Foreman merges its own
# AC-MATCH PRs. Hardcoded here rather than added to .index.json so a board
# object on foreman's entry can't drift BUILD-phase semantics.
repo_code_review_automerge_enabled() {
  REPO="$1" INDEX="$REPOS_INDEX_JSON" python3 -c "
import json, os, sys
repo = os.environ['REPO']
if repo == 'getqatalyst/foreman':
    print('true')
    sys.exit(0)
try:
    with open(os.environ['INDEX']) as f:
        data = json.load(f)
except Exception:
    print('false')
    sys.exit(0)
for p in data.get('projects', {}).values():
    if repo in (p.get('repos') or []):
        status = (p.get('status') or '').strip().lower()
        if status in ('archived', 'parked', 'inactive'):
            print('false')
            sys.exit(0)
        board = p.get('board') or {}
        print('true' if board.get('code_review_automerge', False) else 'false')
        sys.exit(0)
print('false')
"
}
