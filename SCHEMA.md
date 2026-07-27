# Schema

Migrations run in order:
`schema.sql` → `schema-v2-addendum.sql` → `schema-v3-addendum.sql`

Types are generated, never hand-written:
```bash
pnpm supabase gen types typescript --local > packages/shared/src/db-types.ts
```
Regenerate after every migration.

---

## Core tables

| Table | Holds |
|---|---|
| `communities` | Tenants. Shimpi, Maratha, … Brand config in JSONB |
| `regions` | Admin scoping units within a community |
| `cities` | Location lookup |
| `admin_users` + `admin_region_scopes` | Admins and which regions they cover |
| `users` | Auth identity. Email is unique **per community** |
| `profiles` | The main filterable record |
| `profile_private` | Phone, address. **Never member-visible** |
| `profile_family`, `profile_siblings` | Family details with birth order |
| `profile_preferences`, `profile_location_prefs` | Partner and location expectations |
| `profile_prompts` | Personality answers |
| `media_assets` + `media_variants` | Photos and video, with transcoded variants |
| `interests`, `shortlists`, `blocks`, `profile_views` | Interactions |
| `conversations`, `messages` | Chat |
| `plans`, `payments`, `subscriptions` | Money |
| `consents`, `data_requests` | DPDP compliance, append-only |
| `reports`, `message_flags`, `moderation_actions`, `moderation_terms` | Safety |
| `import_batches`, `extracted_drafts` | PDF pipeline, isolated from live data |
| `activity_events`, `audit_log` | Analytics and admin audit, append-only |

---

## Rules that are enforced in the database

Do not reimplement these in application code, and do not work around them.

| Rule | Mechanism |
|---|---|
| Community isolation | RLS policy on `community_id` |
| Region scoping for admins | `admin_has_region()` in RLS policies |
| Opposite-gender only | `trg_check_interest` trigger |
| Cross-community interest blocked | Same trigger |
| Sub-caste belongs to its community | `trg_check_sub_community` |
| Hard delete is super-admin only | `purge_user()` raises unless role matches |
| One primary photo, one video per profile | Partial unique indexes |
| Video ≤ 60s | CHECK constraint on `duration_ms` |
| One active subscription per user | Partial unique index |

---

## Location model

Four distinct facts, because the sample biodata proved they diverge
(born Chandrapur, family address Nagpur, works Pune):

| Field | Meaning |
|---|---|
| `residence_city_id` | Where they live now |
| `work_city_id` | Where they work — often different |
| `native_city_id` | Hometown |
| `birth_city_id` | Place of birth, for kundali |

Plus intent:
- `settle_intent` — `stay_current` / `return_hometown` / `open_to_move` / `must_move`
- `profile_location_prefs` — one row per city, typed `preferred` or `acceptable`

"Who lives in Mumbai" and "who would move to Mumbai" are different queries. Both
resolve in one index hit.

---

## Filter integrity

Every filterable field is a foreign key to a lookup table. **Never free text.**
Free text makes filters unusable and data unmergeable, and filter quality is this
product's core value.

Lookups: `cities`, `education_levels`, `occupations`, `income_bands`,
`mother_tongues`, `sub_communities`, `prompts`.

Free text is allowed only where it is *display-only* and never filtered:
`about`, `job_title`, `education_field`, `expectations_text`, `employer`.

---

## Reading data

Always read through views, never raw tables:

- `v_active_profiles` — applies soft-delete and published-status filters
- `candidates_for(profile_id)` — the valid match pool: same community, opposite
  gender, not blocked either way, no interest already exchanged
- `v_current_consents` — latest consent state per type
- `v_abuse_signals` — behavioural abuse detection, reads no message content

Every feed and search query goes through `candidates_for()`. Do not hand-roll the
eligibility rules elsewhere — that is how they drift apart.

---

## Two flags that are not the same thing

| Flag | Meaning | Set by |
|---|---|---|
| `status = 'published'` | Profile is live and discoverable | Member, or the auto-approve timer |
| `is_verified` | Verified badge shown | **Human admin approval only** |

Auto-approve may publish a profile. It must never grant the badge. If the badge
can be earned without a human check, it means nothing — and it is the primary
trust signal in a single-community app.

---

## Derived, never stored

- **Age** — `profile_age(date_of_birth)`. Never a stored `age` column
- **Display name** — generated column: first + middle + last
