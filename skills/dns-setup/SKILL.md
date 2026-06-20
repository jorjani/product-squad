---
name: dns-setup
description: Manage DNS records (list / add / delete subdomains) across the domains in your DNS provider account through that provider's API or CLI, with a confirm-before-delete safety gate and a registry doc kept in sync after every change. Uses Cloudflare (via a small add/list/delete script wrapper) as the worked example; the pattern transfers to Route 53, Namecheap, Porkbun, or any API-driven DNS provider. Use when pointing a subdomain at a hosted app, auditing what's live, or removing a stale record.
---

# /dns-setup — Manage DNS Records via Your Provider

Generic purpose: add, list, and delete DNS records across your domains through your provider's API or CLI — never by hand-editing in a web console where a typo goes live unreviewed.

**This skill uses Cloudflare as the worked example**, driven by three small scripts (`list-subdomains.sh`, `add-subdomain.sh`, `delete-subdomain.sh`) that wrap the Cloudflare API. The pattern transfers to AWS Route 53 (`aws route53 change-resource-record-sets`), Namecheap, Porkbun, or any DNS API — replace the script calls with your provider's CLI.

**Usage:** `/dns-setup <domain-alias> <action> [args]` — e.g. `/dns-setup mysite list`, `/dns-setup mysite add app myapp.up.railway.app`

## How it works

Records are managed by per-domain config (an `.env.<alias>` holding the zone ID + API token) plus a provider script. One config per domain keeps credentials scoped and makes "which domains can I manage?" a directory listing.

### 1. Parse the arguments

- **Domain alias** (first word) — which domain's config to load.
- **Action** (second word) — `list`, `add`, `delete`. Default to `list` if only an alias is given.
- **Remaining args** — subdomain name, target, flags.

If no arguments at all, list the domains you can manage (one `.env.<alias>` per domain):

```bash
ls <dns-config-dir>/.env.* | sed 's/.*\.env\./  - /'
```

### 2. Execute the action

```bash
# List
<dns-config-dir>/list-subdomains.sh --domain <alias>

# Add  (subdomain → target)
<dns-config-dir>/add-subdomain.sh --domain <alias> <subdomain> <target> [--no-proxy]

# Delete
<dns-config-dir>/delete-subdomain.sh --domain <alias> <subdomain>
```

**Proxy / CDN gotcha (the transferable nugget):** when the target is a platform-hosted app (Railway, Render, Fly, Vercel) that terminates its own SSL, the record must be **DNS-only** — Cloudflare calls this the gray cloud (`--no-proxy`). A proxied record breaks the platform's own cert provisioning. If the target matches a known platform pattern (`*.up.railway.app`, `*.onrender.com`, `*.fly.dev`, `*.vercel.app`), force DNS-only automatically.

### 3. After any change

1. Run `list` to confirm the change landed.
2. Update your DNS registry doc (e.g. `DOMAINS.md`) — add/remove the record from that domain's table. A registry that drifts from reality is worse than none.
3. Show the user what changed.

## Adding a new domain to the system

1. Create `.env.<alias>` with the provider's zone ID, API token, and domain name.
2. The zone ID lives on the provider dashboard → domain → overview.
3. Add the domain to the registry doc's portfolio table.

## Hard rules

- **Confirm before any delete.** DNS deletions take effect in seconds and can drop a live service. State the record and ask first.
- **DNS-only for platform-hosted targets.** Proxying them breaks SSL.
- **Registry doc is part of the change.** A record edit isn't done until the doc reflects it.

## Neighbors

- [`notification-setup`](../notification-setup/SKILL.md) — the email DKIM/SPF/DMARC records this skill adds.
- [`domain-check`](../domain-check/SKILL.md) — check availability before you buy and point a domain.
