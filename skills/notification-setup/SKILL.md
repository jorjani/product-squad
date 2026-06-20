---
name: notification-setup
description: Set up a transactional email sending domain end-to-end so DNS records match what your provider's verifier expects on the first try, not the third. Walks DKIM / SPF / DMARC record creation, propagation checks with dig, the dashboard "verify" click, and a real-send confirmation. Uses AWS SES as the worked example; the pattern transfers to Resend, Postmark, SendGrid, Mailgun — swap the record values for whatever your provider's dashboard shows. Use when wiring a new sending domain or debugging a stuck PENDING verification.
---

# /notification-setup — Verify a Transactional Email Sending Domain

Generic purpose: get a domain verified for transactional/notification email on the **first** attempt by adding the exact DNS records your provider expects, confirming they propagate, then verifying and sending a real test.

**This skill uses AWS SES as the concrete example.** The same five steps work for Resend, Postmark, SendGrid, or Mailgun — only the record names and values change. Wherever you see `amazonses.com` below, substitute your provider's equivalent host.

**Usage:** `/notification-setup <domain>` — e.g. `/notification-setup example.com`

## The one rule that prevents most failures

**Match the provider dashboard literally.** Email providers do an exact-string match on DNS values. "Standards-driven improvements" cost round-trips:

- A DKIM TXT value shown as a bare `p=<key>` must be entered as-is. Do **not** prepend the `v=DKIM1; k=rsa;` prefix that the RFC recommends — many providers reject the enriched form.
- An SPF record that says `include:amazonses.com` means the *underlying sending host*, not your provider's marketing domain. Adding what "looks logical" (`include:<provider>.io`) is the single most common first-time error.

The dashboard **is** the spec. If you're helping someone set this up, ask for the dashboard screenshot before recommending any values — see the visual-first principle in [`debrief`](../debrief/SKILL.md) for why external references should be read, not guessed.

## Workflow

### 1. Identify the records the provider requires

A typical AWS-SES-backed provider asks for four records (a fifth if you want inbound):

- **Verification (DKIM):** TXT at `<selector>._domainkey.<domain>` → value `p=<public-key>`
- **Sending:**
  - MX at `<subdomain>.<domain>` → `feedback-smtp.<region>.amazonses.com` priority 10
  - TXT at `<subdomain>.<domain>` → `v=spf1 include:amazonses.com ~all`
  - TXT at `_dmarc.<domain>` → `v=DMARC1; p=none;`
- **Receiving (optional):** MX at `@<domain>` → `inbound-smtp.<region>.amazonaws.com`

Other providers collapse these (Resend gives one DKIM CNAME + one MX + one TXT). Read your dashboard.

### 2. Add the records at your DNS provider

For each record: Type and Name exactly as shown; value pasted **literally**, no prefix additions, no host rewrites; TTL Auto; proxy **off** (DNS-only / gray cloud — TXT can't be proxied, MX won't route proxied). See [`dns-setup`](../dns-setup/SKILL.md) for the record-management mechanics.

### 3. Verify propagation BEFORE clicking "Verify"

```bash
dig +short TXT <selector>._domainkey.<domain> @1.1.1.1
dig +short TXT <subdomain>.<domain> @1.1.1.1
dig +short MX  <subdomain>.<domain> @1.1.1.1
dig +short TXT _dmarc.<domain> @1.1.1.1
```

Each should return the value the dashboard showed. Empty → wait 1–2 min and re-query. Still empty → the record didn't save; check the DNS provider UI. Clicking "Verify" before records resolve burns a cooldown on some providers.

### 4. Click "Verify" / "Re-check" in the provider dashboard

Status should flip PENDING → ACTIVE. If it stays PENDING with all records resolving, the provider may want an extra selector or CNAME not in the standard set — re-read the dashboard for additional requirements.

### 5. Confirm with a real send

Fire your app's send endpoint (or the provider's test-send) scoped to a single recipient, then check the inbox for `From: <expected>@<domain>` — not the provider's default sender. If the From is still the provider's domain, verification hasn't taken effect on their side yet.

## Hard rules

- **Literal match over standards.** The dashboard value wins every time.
- **Verify propagation before verifying the domain.** `dig` first, click second.
- **One template per email type, named `<product>_<purpose>`** (e.g. `app_weekly_digest`, `app_password_reset`) if your provider hosts templates. Keeps the code call site stable: `mailer.send({ type: "app_password_reset", ... })`.

## Swapping providers

| Provider | DKIM form | SPF include | Notes |
|---|---|---|---|
| AWS SES (direct or wrapped) | bare `p=...` TXT | `include:amazonses.com` | the worked example above |
| Resend | CNAME records | `include:amazonses.com` (SES-backed) | one MX + one TXT |
| Postmark | DKIM TXT | `include:spf.mtasv.net` | return-path CNAME too |
| SendGrid | CNAME-based DKIM | `include:sendgrid.net` | three CNAMEs, no raw TXT |

The verify-propagation-then-send loop in steps 3–5 is identical for all of them.
