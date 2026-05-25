#!/bin/bash
# lib/orphan.sh — verification-gate orphan marker (foreman#238).
#
# Shared by phases/build-ticket.sh (post-claude push / PR-create failure) and
# phases/orphan-rescue.sh (rescue-push / rescue-PR-create failure, foreman#240).
#
# Callers must source lib/comments.sh first (mark_orphan uses
# comment_dedup_or_escalate) and must set two globals before calling:
#   WORKTREE_DIR — worktree holding the orphan commit + .pr-body.md
#   SCRIPT_DIR   — foreman repo root (for results/orphan-bodies/)
# mark_orphan runs `git` from the current directory, so cd into the worktree
# before calling it.

# Mark a post-verification failure as an orphan: push the commit under a
# needs-verification/<branch> namespace, persist .pr-body.md outside the
# worktree (it dies with the EXIT trap otherwise), and post DECISION-NEEDED
# on the parent issue. Per #238, no auto-PR opens for orphans — recovery is
# gated on re-running verification on the orphan commit.
mark_orphan() {
  local repo="$1" issue="$2" branch="$3" cause="$4" detail="${5:-}"
  local sha mark_ref persist_dir body_persist body_section="" detail_block=""

  sha=$(git rev-parse HEAD 2>/dev/null) || return 1
  mark_ref="needs-verification/$branch"

  # Push commit under the marker namespace. Works whether or not the original
  # branch push succeeded — same SHA, additional ref. If even this push fails
  # (network, auth), the orphan is truly lost — log and bail.
  if ! git push origin "HEAD:refs/heads/$mark_ref" 2>/dev/null; then
    echo "ORPHAN-LOST: $repo#$issue could not push marker $mark_ref for $sha ($cause)"
    return 1
  fi

  if [ -f "$WORKTREE_DIR/.pr-body.md" ]; then
    persist_dir="$SCRIPT_DIR/results/orphan-bodies"
    mkdir -p "$persist_dir"
    body_persist="$persist_dir/$(echo "$branch" | tr '/' '_').md"
    cp "$WORKTREE_DIR/.pr-body.md" "$body_persist" 2>/dev/null && \
      body_section="
**Saved PR body:** \`$body_persist\`" || true
  fi

  [ -n "$detail" ] && detail_block="
**Detail:** $detail"

  comment_dedup_or_escalate "$repo" "$issue" "DECISION-NEEDED: orphan build (verification gate)

Build produced commits, but PR creation did not complete ($cause). Per the verification gate (#238), no PR is auto-opened.${detail_block}

**Orphan commit:** \`$sha\`
**Marker branch:** \`$mark_ref\`${body_section}

To recover, re-run verification (typecheck + local build) on \`$mark_ref\`. If it passes, open a PR manually. If it fails, delete \`$mark_ref\` and return this issue to Ready." "orphan-needs-verification" || true

  # Source-reframe (D4): work was done, gate refused auto-publish.
  # Lazy-load lib/questions.sh so callers that don't already source it
  # don't have to (build-ticket.sh / orphan-rescue.sh now do, but
  # cleanup.sh's orphan-marker scan also surfaces the same condition).
  if [ -f "$SCRIPT_DIR/lib/questions.sh" ]; then
    # shellcheck disable=SC1091
    . "$SCRIPT_DIR/lib/questions.sh"
    local _title
    _title=$(gh issue view "$issue" --repo "$repo" --json title -q '.title' 2>/dev/null || echo "")
    questions_register "orphan-needs-verification" "$repo" "$issue" \
      "Orphan commit $sha on $mark_ref — $cause." \
      "Foreman built \"${_title:-#$issue}\" but the verification gate blocked auto-publish — want me to retry, or take the work?" \
      "Real commits exist on the marker branch; the gate didn't open the PR because the post-build push/PR step failed ($cause)." \
      '["Retry the publish next cycle","I will verify + open the PR by hand","Drop the work — back to Ready"]' \
      "" || true
  fi

  echo "ORPHAN: $repo#$issue marked $mark_ref ($cause)"
  return 0
}
