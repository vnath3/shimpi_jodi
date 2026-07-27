# Shimpi Jodi

A matrimony web app for the Shimpi community in Maharashtra. Mobile-first PWA,
built to serve one community well and to host additional communities on the
same codebase without a fork.

Built in memory of **Dr. R. P. Nath**, Vice-Chancellor, Dr. Babasaheb Ambedkar
Marathwada University.

---

## What makes it different

| | Typical matrimony site | Shimpi Jodi |
|---|---|---|
| Profile | Dense data table | One-glance card: photo, three facts, one personality prompt |
| Matching signal | Fake "92% match" score | Honest compatibility chips, including the differences |
| Discovery | Infinite scroll | Five curated profiles a day |
| Chat | Paywalled before any value | Free until a mutual yes; paid only to open the conversation |
| Media | Photos only | Photos + a 60-second video introduction |
| Trust | Anonymous | Community-verified, traceable to samaj records |

---

## Stack

- **Frontend** — React + Vite + TypeScript + Tailwind, deployed to Cloudflare Pages
- **Backend** — Supabase (Postgres, Auth, Edge Functions, RLS)
- **Media** — Cloudflare R2 + CDN
- **Payments** — Razorpay
- **Extraction** — Supabase Edge Function calling the Claude API

Full reasoning in `ARCHITECTURE.md`.

---

## Getting started

```bash
pnpm install
cp .env.example .env.local        # see ENV.md
pnpm supabase start               # local Postgres + auth
pnpm db:migrate                   # runs schema + addendums in order
pnpm db:seed                      # lookups, plans, prompts, sub-castes
pnpm dev
```

Migrations must run in order:
`schema.sql` → `schema-v2-addendum.sql` → `schema-v3-addendum.sql`

---

## Documentation

| File | Read it when |
|---|---|
| `CLAUDE.md` | Before writing any code. Non-negotiable rules |
| `ARCHITECTURE.md` | Understanding how the pieces fit |
| `SCHEMA.md` | Touching the database |
| `API.md` | Adding or changing an endpoint |
| `DESIGN-SYSTEM.md` | Building any UI |
| `FLOWS.md` | Implementing a user journey |
| `SECURITY-AND-PRIVACY.md` | Anything touching personal data |
| `MODERATION.md` | Chat, reports, or safety features |
| `DEPLOYMENT.md` | Shipping |
| `TESTING.md` | Writing tests |
| `ENV.md` | Configuring environments |
| `ROADMAP.md` | Deciding what to build next |

`/design-reference/` holds working HTML prototypes of every screen. Visual truth,
not code to copy.
