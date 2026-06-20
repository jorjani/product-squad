---
name: guard
description: Safety mode — activate destructive-command guardrails and an edit boundary for the rest of the session. Before any bash command, checks it against a denylist (rm -rf, DROP/TRUNCATE/DELETE, git force-push / reset --hard / checkout ., kubectl delete, docker prune) and stops to confirm; restricts Edit/Write to one directory. Use when working in a sensitive repo, on production-adjacent systems, or any time a stray command could lose data. Pairs with /ship (the landing workflow it protects) and /verify (prove-it-ran before claiming done).
---

# /guard — Safety Mode

Activate safety guardrails for this session. Two protections.

## 1. Destructive Command Warnings

Before running any bash command, check it against these patterns. If matched, STOP and confirm with the user before executing:

| Pattern | Example | Risk |
|---------|---------|------|
| `rm -rf` / `rm -r` | `rm -rf /var/data` | Recursive delete |
| `DROP TABLE` / `DROP DATABASE` | `DROP TABLE users;` | Data loss |
| `TRUNCATE` | `TRUNCATE orders;` | Data loss |
| `git push --force` / `-f` | `git push -f origin main` | History rewrite |
| `git reset --hard` | `git reset --hard HEAD~3` | Uncommitted work loss |
| `git checkout .` / `git restore .` | `git checkout .` | Uncommitted work loss |
| `kubectl delete` | `kubectl delete pod` | Production impact |
| `docker system prune` | `docker system prune -a` | Container/image loss |
| `DELETE FROM` (without WHERE) | `DELETE FROM users;` | Mass data loss |

Safe exceptions (no warning needed):
- `rm -rf node_modules` / `.next` / `dist` / `__pycache__` / `.cache` / `build` / `.turbo` / `coverage`

## 2. Edit Boundary

Ask the user: "Which directory should edits be restricted to?"

Once set, ONLY edit/write files within that directory. If you need to edit outside:
- State what file and why
- Get explicit permission before proceeding

## Activation

When this command runs:
1. Print: "**Guard mode active.**"
2. Ask for the edit boundary directory
3. Print the two active protections
4. Remain active for the rest of the session

## Rules

- Every destructive bash command gets a warning — even if the user "probably wants it"
- The edit boundary is enforced on every Edit and Write call
- Read, Grep, Glob are unrestricted — only writes are scoped
- To change the boundary, run `/guard` again
- Guard mode cannot be accidentally deactivated mid-session

$ARGUMENTS
