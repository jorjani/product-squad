---
name: verify
description: Terminal "prove it ran" gate — no completion words ("done", "fixed", "shipped") until you have run the real verification command and pasted its actual output. Use as the last gate before claiming any change works. Standalone discipline check; pairs with /investigate (which calls it to confirm a fix) but does no debugging itself.
---

# /verify — Prove It Ran

## IRON LAW

Do NOT output "done", "complete", "fixed", "shipped", or any completion language until you have run the actual verification command and pasted its real output here.

"Should work", "looks correct", "follows the same pattern", and "mentally verified" are prohibited. They are assertions, not verification.

If verification is impossible (no running server, no test suite): output
`BLOCKED: Cannot verify — [reason]. Task is NOT complete.`

---

Before marking any task complete, verify the change actually works. Pick the path that matches what changed.

### UI changes
1. Navigate to the affected page (browser automation).
2. Take a snapshot or screenshot.
3. Confirm the change is visible and correct.
4. Check the console for errors.

### API / backend changes
1. Run the relevant test suite, OR
2. Make a request to the endpoint.
3. Verify the response is correct.

### Build / config changes
1. Run the build command.
2. Confirm no errors.
3. Run a smoke test if one exists.

## Output

**PASS:** What you verified, with the real output.
**FAIL:** What went wrong, what needs fixing.

## Rules

- Don't skip verification even for "simple" changes.
- Can't verify (no tests, no running server)? Say so explicitly — `BLOCKED`.
- Verification failure = task not complete.

$ARGUMENTS
