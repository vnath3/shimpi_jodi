# Architecture

## The shape

```
                    Cloudflare CDN
                          │
        ┌─────────────────┼──────────────────┐
        │                 │                  │
  Cloudflare Pages   Cloudflare R2      Supabase
  (React PWA)        (photos, video)    ├─ Postgres + RLS
                                        ├─ Auth (email OTP)
                                        └─ Edge Functions
                                              │
                                    ┌─────────┴─────────┐
                                Razorpay          Claude API
                                (payments)     (PDF extraction)
```

No server to patch, no container to orchestrate. Two platforms, one database.

---

## Key decisions and why

### Single shared member pool, region-scoped admins

Regions (**Marathwada**, **Vidarbha**, …) scope *who can administer whom*. They
never scope who can *see* whom — a Pune profile must be discoverable by a Mumbai
member or the product has no value.

### Community is the tenant boundary

Communities (Shimpi, Maratha, …) are true tenants with hard data isolation.
Enforced by RLS on `community_id` plus a trigger on `interests`. Launching a new
community is four INSERTs and a domain — no code change, no fork, no separate
deployment.

Hierarchy: **Community → Region → Members.**

### RLS at the database, not the API

Community isolation, region scoping, and private-data access are all Postgres
policies. An application-layer bug cannot leak data across communities. This is
the main reason Supabase was chosen — RLS is its native security model.

### PWA, not native

One codebase, no app-store review cycle, installable, works on mid-range Android.
Web push works on Android Chrome without any wrapper. If a Play Store listing is
needed later, a TWA wrapper takes about an hour; Capacitor (for native push and
camera) about a day. Neither requires a rewrite.

### Vite SPA, not Next.js

No SSR needed — profiles must never be indexed by search engines, which removes
the only strong argument for server rendering. Simpler build, simpler hosting,
no framework-specific hosting lock-in.

### TypeScript end to end

One language across frontend, edge functions, and shared validation. Types are
the tightest available correctness feedback loop, which matters because most code
here is agent-written. Zod schemas are shared between client and server so
validation cannot drift.

### Cloudflare R2 for media

Supabase free storage is 1 GB with 5 GB egress — video exhausts that immediately.
R2 gives 10 GB free with **zero egress charges**, which is decisive when serving
video.

---

## Media pipeline

Originals are never served.

| Asset | Variants | Delivery |
|---|---|---|
| Photo | `thumb` 160px, `card` 720px, `full` 1440px — AVIF + WebP | `<picture>` with fallback chain. Feed loads `card` only |
| Video (v1, free tier) | Client-compressed MP4, 30s / 8 MB cap, poster frame | `preload="none"`, poster until tap. No autoplay in feed |
| Video (post-upgrade) | HLS ladder 360/540/720p, 60s cap | Adaptive streaming |

**Blurhash** is stored on every photo and rendered as an instant coloured
placeholder. This is what makes the feed feel fast on 4G, and it is not optional.

---

## Background work

| Job | Runs on | Trigger |
|---|---|---|
| PDF extraction | Edge Function → Claude API | Admin uploads a batch; one PDF per invocation |
| Image transcoding | Edge Function | On upload |
| Daily Five generation | Scheduled function, 08:00 IST | Cron |
| "Still looking?" check-in | Scheduled function | Daily sweep, 60-day inactivity |
| Nightly `pg_dump` → R2 | GitHub Action | Cron, free tier |
| Anti-pause DB ping | GitHub Action | Every 3 days (free-tier Supabase only) |

---

## Scale path

Do not build any of this now. The schema is designed so each step is additive.

| Stage | Profiles | Change |
|---|---|---|
| Now | < 5,000 | Plain indexed queries. Nothing else needed |
| Growth | 5k–50k | Redis for the Daily Five; `profile_cards` materialised view |
| Scale | 50k+ | Typesense/Elasticsearch for discovery; partition `messages`; read replicas for analytics |

`activity_events` and `profile_views` are partitioned by month **from day one**,
because retrofitting partitions later is painful.
