[FOREMAN]

Use the `code-reviewer` subagent to review pull request `{REPO}#{PR_NUMBER}`.

Steps:
1. Dispatch the `code-reviewer` subagent with input: `{REPO}#{PR_NUMBER}`.
2. The subagent will fetch the PR via `gh pr view {PR_NUMBER} --repo {REPO}` and `gh pr diff {PR_NUMBER} --repo {REPO}`, then evaluate against its severity tiers (Blocker / Major / Nit).
3. The subagent will return a single JSON object (because of the `[FOREMAN]` marker above):

```json
{"findings": [...], "verdict": "<LGTM|LGTM with nits|Needs changes|Blocked>"}
```

Each finding has keys: `severity`, `file`, `line`, `rule`, `snippet`, `why`, `fix`.

4. Print that JSON object as your final message, verbatim, with no surrounding prose, no markdown fence, and no commentary. Foreman parses your final message as JSON.

If the subagent cannot be dispatched or returns nothing parseable, print:

```json
{"findings": [], "verdict": "Skip", "error": "<short reason>"}
```
