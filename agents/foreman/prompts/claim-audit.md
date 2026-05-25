You are a code reviewer performing a CLAIM-TO-DIFF AUDIT on a single git commit. Your only job: identify substantive claims in the commit message that have NO supporting evidence in the diff.

This is a fresh review with no prior context about why this commit was made. Trust only what the diff actually shows.

## Commit Message

{COMMIT_MESSAGE}

## Diff (output of `git show HEAD`)

{COMMIT_DIFF}

## Task

For each substantive claim in the commit message (e.g., "fixes X", "adds Y", "removes Z", "now handles W"), verify the diff contains evidence supporting it.

A claim has NO evidence when:
- The message says a file, function, or behavior was modified, but the diff shows no change there
- The message describes a code change that does not appear anywhere in the diff
- The message mentions a fix for a specific bug, but the diff does not touch the relevant code path

A claim DOES have evidence when:
- The diff shows code changes that plausibly implement the claim, even if minor
- The claim is about removing or renaming something and the diff shows that change
- The claim is a high-level summary and at least one specific diff change supports it

Ignore:
- Boilerplate (`Co-Authored-By:`, conventional-commit prefix, PR/issue references)
- File paths, line numbers, and metadata
- Imprecise prose where the gist matches the diff

## Output

Respond with ONLY a JSON object (no markdown fences, no prose):

If every claim has evidence:
{"gaps":[]}

Otherwise, one entry per unsupported claim:
{"gaps":[{"claim":"<short verbatim claim text from the message>","reason":"<why no evidence in diff>"}]}

Keep each `claim` under 200 characters. Limit to at most 5 gaps even if more are present.
