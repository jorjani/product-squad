---
name: domain-check
description: Domain availability search across TLD tiers — given a concept or a list of names, brainstorm creative variations and check .com → .co/.app → .so/.io for what's actually free. Uses whois for .com/.co/.io and DNS dig for .app/.so (where whois is unreliable). Use when validating a name before buying. Pairs with /namer (score the available winners on the 9-category rubric).
---

# /domain-check — Domain Availability Search

Check domain availability for a naming concept. Generate creative variations and check across TLD tiers.

## Input: $ARGUMENTS

The user provides a concept, theme, or specific domain names to check.

## TLD Tiers (check in order)

| Tier | TLDs | Cost/yr | When to check |
|------|-------|---------|---------------|
| 1 | **.com** | ~$10 | Always check first |
| 2 | **.co**, **.app** | ~$12-14 | Check if .com unavailable |
| 3 | **.so**, **.io** | ~$12-33 | Check if tiers 1-2 exhausted |

`.app` enforces HTTPS (Google registry). `.io` is the most expensive (~$33/yr).

## Workflow

1. **Parse input** — if specific domains given, check those. If a concept/theme, brainstorm 20-30 creative variations first.

2. **Brainstorm variations** (when given a concept):
   - Exact name + common prefixes (get, try, use, go, my, the, join)
   - Short abbreviations and portmanteaus
   - Made-up/invented words inspired by the concept
   - Compound words (two real words: WriteStack, Mailchimp, InkBloom)
   - Metaphorical names (forge, dojo, craft, mint, hive)
   - Keep most names under 12 characters

3. **Check availability:**
   - **whois TLDs (.com / .co / .io):** whois is authoritative here. Batch and parse the status line — never `whois | grep` blindly (false positives on rate-limit and redacted output):
     ```bash
     for d in name1.com name2.com name3.io; do
       if whois "$d" 2>/dev/null | grep -qiE 'No match|NOT FOUND|Status: free|No Data Found'; then
         echo "LIKELY AVAIL: $d"
       else
         echo "TAKEN: $d"
       fi
     done
     ```
   - **DNS TLDs (.app / .so):** whois returns unreliable "MAYBE" for these. Use a DNS check instead and mark results "likely available, verify before purchasing":
     ```bash
     for d in name1 name2; do
       result=$(dig +short "${d}.app" 2>/dev/null)
       [ -z "$result" ] && echo "LIKELY AVAIL: ${d}.app" || echo "TAKEN: ${d}.app -> $result"
     done
     ```
   - Run in batches of ~15 to avoid timeouts and registrar rate limits.
   - A no-DNS-record result is not a guarantee a domain is unregistered — confirm at a registrar before buying.

4. **Present results** in a table:
   - Only show AVAIL domains (mention the count checked/taken)
   - Group by TLD tier, then by category
   - Include character count and a one-line vibe note

5. **If the user wants evaluation**, run the available names through `/namer` for scoring.

## Rules

- whois for .com/.co/.io; DNS dig for .app/.so — never trust raw `whois | grep` alone.
- Start with Tier 1, expand to lower tiers only when needed.
- If fewer than 5 available across all tiers, automatically expand the search.
- Be honest about what's taken — don't give false hope.
