---
name: analytics-setup
description: Wire client-side product analytics into a React/Vite or Next.js app the right way — install, init with first-touch UTM capture, identify real users via the auth session, flush-then-reset on signout, and name business-critical custom events. Uses PostHog as the worked example with copy-paste code; the five-piece recipe transfers to Amplitude, Mixpanel, or June — swap the SDK calls. Use when adding analytics to a new product or filling gaps (most existing setups are missing identify or the signout flush).
---

# /analytics-setup — Client-Side Product Analytics

Generic purpose: instrument a frontend so events tie to **real people with cohorts**, not anonymous device IDs. Five pieces, ~30 min per product:

1. **Install** the SDK
2. **Init** — base config + first-touch attribution (UTM capture)
3. **Identify** — link events to real users via the auth session
4. **Signout** — flush queued events, then reset identity
5. **Custom events** — name business-critical actions

**This skill uses PostHog as the worked example** with real code. The recipe is provider-agnostic: Amplitude (`amplitude.init` / `setUserId`), Mixpanel (`mixpanel.identify`), and June follow the same five beats. Swap the SDK calls; keep the structure.

## 1. Install

```bash
bun add posthog-js
```

For Next.js: analytics runs client-side, so the provider component needs `"use client"`.

## 2. Init — base config + UTM capture

The init call registers first-touch attribution **before any user event can fire**.

```typescript
"use client"; // Next.js only
import posthog from "posthog-js";
import { useEffect, useRef } from "react";

const KEY  = process.env.NEXT_PUBLIC_POSTHOG_KEY  || import.meta.env?.VITE_POSTHOG_API_KEY;
const HOST = process.env.NEXT_PUBLIC_POSTHOG_HOST || import.meta.env?.VITE_POSTHOG_HOST || "https://us.i.posthog.com";

export function AnalyticsProvider({ children }: { children: React.ReactNode }) {
  const initialized = useRef(false);
  useEffect(() => {
    if (!KEY) return;                  // graceful no-op when unset
    if (initialized.current) return;   // StrictMode mounts effects twice in dev
    initialized.current = true;

    posthog.init(KEY, {
      api_host: HOST,
      person_profiles: "identified_only", // cost control: profile only identified users
      capture_pageview: true,
      capture_pageleave: true,
      loaded: (ph) => {
        // First-touch UTM capture, inside init lifecycle, before any user event.
        const url = new URL(window.location.href);
        const utm = Object.fromEntries(
          ["utm_source","utm_medium","utm_campaign","utm_content","utm_term"]
            .map((k) => [k, url.searchParams.get(k)])
            .filter(([, v]) => v !== null),
        );
        if (Object.keys(utm).length) ph.register_once(utm); // first-touch wins
      },
    });
  }, []);
  return <>{children}</>;
}
```

- **`initialized` ref guard:** React 18+ StrictMode runs effects twice in dev. Without the guard, init fires twice → duplicate events + a corrupted device ID.
- **`register_once` not `register`:** preserves first-touch attribution across the whole session instead of overwriting with the last URL hit.
- **UTM capture inside `loaded`:** runs after init completes but before any user-triggered event, so UTMs attach to the first `$pageview`.

## 3. Identify — link events to real users

With `person_profiles: "identified_only"`, **no profile exists until you call `identify()`.** The provider usually wraps *outside* the auth provider, so put identify in a **sibling component** mounted inside the auth provider:

```typescript
"use client";
import { useSession } from "next-auth/react"; // or your auth library's hook
import posthog from "posthog-js";
import { useEffect, useRef } from "react";

export function AnalyticsIdentify() {
  const { data: session, status } = useSession();
  const identified = useRef<string | null>(null);
  // Destructure to primitives so deps don't change every render.
  const userId = session?.user?.id, role = session?.user?.role, email = session?.user?.email;

  useEffect(() => {
    if (status === "unauthenticated" && identified.current !== null) {
      if (posthog.__loaded) { posthog.capture("user_signed_out"); setTimeout(() => posthog.reset(), 200); }
      identified.current = null; return;
    }
    if (status !== "authenticated" || !userId || identified.current === userId) return;

    const run = () => {
      posthog.identify(userId, { role, email: email ?? undefined });
      posthog.people.set_once({ initial_landing_page: window.location.pathname });
      identified.current = userId;
    };
    if (posthog.__loaded) return void run();
    const t = setInterval(() => { if (posthog.__loaded) { clearInterval(t); run(); } }, 100);
    return () => clearInterval(t);
  }, [status, userId, role, email]);
  return null;
}
```

Mount order: `<AnalyticsProvider><SessionProvider><AnalyticsIdentify />{children}</SessionProvider></AnalyticsProvider>`.

- **Primitive deps** `[status, userId, role, email]`, not `[session?.user]` — object refs change every render.
- **`__loaded` polling** handles the race between async config fetch and the auth session resolving.
- **`set_once`** on landing-page/referrer preserves first-touch for the user's lifetime.

## 4. Signout — flush before identity wipe

```typescript
if (status === "unauthenticated" && identified.current !== null) {
  if (posthog.__loaded) {
    posthog.capture("user_signed_out");      // fires under previous identity
    setTimeout(() => posthog.reset(), 200);  // window for the batch to flush
  }
  identified.current = null;
}
```

The 200ms window lets the queued event leave the browser before `reset()` clears the distinct_id. The `identified.current !== null` guard prevents `reset()` firing on first-paint-before-auth-resolves.

## 5. Custom events — name business-critical actions

Convention: `{noun}_{past_tense_verb}`, snake_case — `post_published`, `application_submitted`, `first_project_created`.

```typescript
posthog.capture("first_project_created", { project_id, category, seconds_from_signup });
```

Use **autocapture** for early exploration (define actions in the UI retroactively); use **manual `capture()`** for activation/conversion/NSM events that need stable property bags for funnels.

## Environment variables

| Framework | Prefix | Example |
|---|---|---|
| Vite | `VITE_` | `VITE_POSTHOG_API_KEY` |
| Next.js | `NEXT_PUBLIC_` | `NEXT_PUBLIC_POSTHOG_KEY` |

```env
# Product analytics (optional — app works without it)
NEXT_PUBLIC_POSTHOG_KEY=phc_your_key_here
NEXT_PUBLIC_POSTHOG_HOST=https://us.i.posthog.com
```

For Docker/platform deploys, inject the public key at build time (`ARG` + `ENV`) since client bundles bake it in.

## Per-project customization

- **Auth library** — swap `useSession()` for your hook (`useUser()` for Clerk, etc.).
- **Multi-tenant** — add `orgId` to identify and call `posthog.group('organization', orgId)`.
- **Server-side events** — only for background workflows (cron, agents, webhooks); skip for CRUD apps.
- **Consent gating** — defer until GDPR/CCPA is a real concern (EU clients, thousands of MAU). The retrofit is bounded (~30 min): gate with `opt_out_capturing_by_default: true` + `capture_pageview: false`, then `opt_in_capturing()` on grant.

## Verify

After deploy, confirm `identify()` fires by checking the provider's live-events feed for events whose `distinct_id` matches a real user, not an anonymous device ID. See [`verify`](../verify/SKILL.md) for the prove-it-ran discipline.
