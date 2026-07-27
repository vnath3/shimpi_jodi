# Shimpi Jodi — Database Design

**Version:** v1 · July 2026
**Engine:** PostgreSQL 16 (+ object storage for media, Redis for cache)

---

## 1. The architectural calls, up front

| Decision | Choice | Why |
|---|---|---|
| **Tenancy model** | **Single shared member pool + region-scoped admin RBAC** — NOT multi-tenant data isolation | Matching must cross regions. A Pune profile has to be discoverable by a Mumbai member. Siloing data by region breaks the product's core value. Regions scope *who can administer whom*, never *who can see whom*. |
| Database | PostgreSQL | Relational integrity for a filter-heavy product, JSONB where flexibility is genuinely needed, native Row-Level Security (RLS) that maps cleanly onto region-scoped admins, and full-text search without a second system. |
| Filterable fields | **Lookup tables with integer FKs**, never free text | Filter integrity is the product's #1 requirement. Free text makes filters unusable and the data unmergeable. |
| Media storage | **Object storage (S3 / Cloudflare R2) + CDN.** DB stores metadata only | Never put blobs in Postgres. DB rows stay small → feed queries stay fast. |
| Deletion | **Soft delete everywhere** (`deleted_at`, `deleted_by`). Hard delete only via super-admin, and only through an audited purge routine | Your requirement — plus DPDP still requires a real erasure path, so the purge routine is mandatory, not optional. |
| PDF extraction | **Separate staging tables** (`import_batches`, `extracted_drafts`) that never touch live profiles until claimed | Keeps the add-on genuinely additive. If extraction breaks, the app is unaffected. |
| IDs | UUID v7 (time-ordered) | Sortable like an integer, safe to expose, no cross-region collision if you ever shard. |

---

## 2. Access control model

Three roles, one shared data set:

| Role | Scope | Can do |
|---|---|---|
| `super_admin` (you) | Global | Everything, including hard delete/purge, role management, plan/pricing changes, viewing audit logs |
| `region_admin` | One or more regions | Upload PDFs, review extraction drafts, send claim links, view members **in their regions**, handle reports in their regions, view region-scoped analytics |
| `moderator` (optional, later) | One or more regions | Reports and moderation only — no member data editing |

**Enforcement is at the database, not just the app.** Postgres RLS policies read `app.current_admin_id` and `app.current_admin_role` from the session, so a bug in the API layer can't leak another region's data. Members themselves are governed by application-level rules (all published profiles are visible to all verified members, subject to blocks).

Region assignment lives in `admin_region_scopes` (many-to-many), so one admin can cover Marathwada + Vidarbha without duplicating accounts.

---

## 3. Entity map

```
regions ──< cities
   │
   ├──< admin_region_scopes >── admin_users
   │
   └──< import_batches ──< extracted_drafts ──(claim)──> users

users ──1:1── profiles ──< profile_prompts
   │              ├──< media_assets ──< media_variants
   │              ├──1:1─ profile_preferences
   │              ├──1:1─ profile_family
   │              ├──< interests (sender / receiver)
   │              ├──< shortlists
   │              ├──< profile_views
   │              ├──< reports (reporter / reported)
   │              └──< blocks
   │
   ├──< consents            (append-only, DPDP audit trail)
   ├──< subscriptions ──> plans
   ├──< payments
   └──< data_requests       (export / erasure)

interests ──1:1── conversations ──< messages

activity_events   (append-only, monthly partitions, feeds the admin dashboard)
audit_log         (append-only, every admin action)
```

---

## 4. Media: photos + video introduction

This is where "loads fast, renders well" is won or lost.

**Never** serve the original upload. Every asset is transcoded into fixed variants at upload time by a background worker:

| Asset | Variants generated | Serving |
|---|---|---|
| Photo | `thumb` 160px, `card` 720px, `full` 1440px — all **AVIF + WebP**, quality ~72 | `<picture>` with AVIF → WebP → JPEG fallback. Card feed loads `card` only. |
| Video intro | `poster` (JPEG frame at 1s), **HLS ladder** 360p / 540p / 720p, max 60s, audio normalized | HLS adaptive streaming, `preload="none"`, poster shown until tap. Never autoplay in the feed. |

Additional rules baked into the schema:

- `blurhash` string on every photo → the card renders a coloured blur instantly while the image streams. This is what makes the feed *feel* fast on 4G in Marathwada.
- `status` on `media_assets` (`uploaded → processing → ready → rejected`) so the UI never shows a half-processed asset.
- `moderation_status` separate from `status` — an asset can be technically ready but pending human review.
- Video capped at **60 seconds** and one per profile. Longer intros hurt completion rates and multiply storage cost for no benefit.
- Signed, short-lived CDN URLs. Photos must never be publicly indexable — this was a locked design decision and it's enforced at the storage layer.

---

## 5. Scale path

You are building for 150 and designing for 100,000+. What changes, and when:

| Stage | Profiles | What you do |
|---|---|---|
| Now | < 5,000 | Plain indexed Postgres queries. The composite indexes in the DDL are enough. No caching layer needed. |
| Growth | 5k – 50k | Add Redis for the daily-match feed (precomputed nightly per member). Add a `profile_cards` materialized view refreshed on profile update, so the feed reads one narrow table instead of six joins. |
| Scale | 50k+ | Move discovery/search to a dedicated engine (Typesense or Elasticsearch) fed by Postgres CDC. Partition `messages` and `profile_views` by month. Read replicas for analytics so dashboards never touch the primary. |

`activity_events` is partitioned by month **from day one** — it's the fastest-growing table and retrofitting partitions later is painful.

**Do not build any of the Growth/Scale items now.** The indexes are designed so you can add them without a schema rewrite.

---

## 6. Deletion & compliance

| Action | Who | What happens |
|---|---|---|
| Member hides profile | Member | `profiles.status = 'hidden'`. Fully reversible. Disappears from all feeds. |
| Member deletes account | Member | `users.deleted_at` set, status `deleted`, profile unpublished, media marked deleted. Data retained. Login blocked. |
| Region admin removes a member | `region_admin` | Same soft delete. Requires a reason, written to `audit_log`. Cannot purge. |
| Purge | **`super_admin` only** | `purge_user(user_id, reason)` — a single audited function that anonymises the user row, hard-deletes media from object storage, tombstones messages, and writes an immutable audit record. Irreversible, deliberately hard to invoke. |

Every read path filters `deleted_at IS NULL`. Ship this as a **view** (`v_active_profiles`) rather than trusting every query to remember.

`consents` is append-only and versioned — you never update a consent row, you insert a new one. That's what makes it a defensible DPDP audit trail rather than a checkbox.

---

## 7. Open questions before you build

1. **Gender / matching direction** — the schema assumes opposite-gender matching by default. Confirm whether that's a hard rule or a preference.
2. **Sub-caste within Shimpi** — do you need it as a filterable field? If yes it's a lookup table now; retrofitting it later means re-collecting data from 150 people.
3. **Family-managed profiles** — the onboarding flow offers "let my family manage this with me." That needs a `profile_managers` table if you want more than one login per profile. Not in v1 DDL; flagged as a fast-follow.
4. **Region assignment for members** — auto-assign from `city_id`, or set explicitly by the uploading admin? Currently explicit, defaulting from city.
