# Architecture Decisions

Every decision below lists what was chosen, why, what else was considered, and
why it was rejected. Where a choice is genuinely close, that is stated.

**Context that drove most of these:** solo owner, zero infrastructure budget at
launch, ~150 seed profiles, an AI agent writing the code, and a schema that leans
heavily on Postgres Row-Level Security.

---

## 1 · Backend platform → **Supabase**

**Why:** The schema's security model *is* RLS — community isolation, region
scoping, and private-data access are all Postgres policies. Supabase is the only
managed option where RLS is the native, first-class model rather than something
bolted on. It also supplies email-OTP auth and edge functions, removing a large
amount of backend code.

| Rejected | Reason |
|---|---|
| **Firebase / Firestore** | Document store. Your product is filter-heavy relational data (multi-table joins across profile, family, preferences, locations). Firestore's query model can't express these without heavy denormalisation, and it has no equivalent of RLS at the row level with SQL expressiveness |
| **Custom Node/Bun + managed Postgres** | More control, but you'd hand-write auth, sessions, OTP, storage signing, and RLS session plumbing. Weeks of work with no product benefit |
| **PocketBase** | Genuinely simple, single binary — but SQLite-based, no true RLS, and self-hosting means you own uptime |
| **AWS Amplify** | Too much surface area for one person. IAM alone would consume the build time |

**Weakness to accept:** vendor lock-in on auth and storage APIs. The database
itself is plain Postgres and portable, which caps the risk.

---

## 2 · Language → **TypeScript end to end**

**Why:** The code is agent-written. Types are the tightest correctness feedback
loop available — the compiler catches errors before anything runs. One language
across frontend, edge functions, and shared validation means no drift between a
Python Pydantic model, a JSON payload, and a TS interface.

| Rejected | Reason |
|---|---|
| **Python + FastAPI** | Your strongest language, and a legitimate choice. Rejected because it forces two languages (Python backend, TS frontend), duplicated validation, and Supabase edge functions are Deno/TS-native — you'd need a separate host for the Python service, breaking the zero-cost, two-platform setup |
| **Ruby / Rails** | Excellent for solo developers, but it's a full-stack framework that would replace Supabase, not complement it. Also needs an always-on server |

**This is the most debatable decision here.** If you'd rather debug in Python,
FastAPI on Fly.io with Supabase-as-database-only is a coherent alternative. The
cost is a second platform, duplicated validation, and losing edge functions.

---

## 3 · Frontend → **React + Vite (SPA)**

**Why:** Profiles must never be indexed by search engines — a locked privacy
decision. That removes the main argument for server-side rendering. Vite gives
fast builds, simple output, and hosts anywhere as static files.

| Rejected | Reason |
|---|---|
| **Next.js** | SSR you don't need, more concepts to hold, and its best hosting is Vercel — whose hobby tier restricts commercial use, and you're charging money |
| **SvelteKit** | Smaller bundles, arguably nicer. Rejected on training-data volume: React has vastly more, which materially affects how reliably an agent writes it |
| **Plain HTML + htmx** | Attractively simple, but the profile card, filters, and chat need real client state |

---

## 4 · Mobile → **PWA first**

**Why:** One codebase, no app-store review cycle, installable, works on mid-range
Android. Web push works on Android Chrome without a wrapper. A TWA wrapper for
Play Store is ~1 hour later; Capacitor for native push/camera ~1 day. Neither is
a rewrite.

| Rejected | Reason |
|---|---|
| **React Native** | Second codebase, native build toolchain, app-store cycles on every fix. Not justified before you have paying users asking for it |
| **Flutter** | Third language (Dart), no code shared with the web app |

**Weakness:** iOS PWA push requires the user to add to home screen first. Accepted
because launch is Android-first.

---

## 5 · Hosting → **Cloudflare Pages + R2**

**Why:** Free with unlimited bandwidth, no commercial-use restriction, same mental
model as Netlify which you already know. R2 gives 10 GB free with **zero egress
charges** — decisive when serving video.

| Rejected | Reason |
|---|---|
| **Vercel / Netlify** | Hobby tiers restrict commercial use, and bandwidth is metered. You're charging money |
| **Supabase Storage** | 1 GB and 5 GB egress on free tier. Video exhausts it immediately |
| **AWS S3 + CloudFront** | Egress charges scale with video views — the worst possible cost curve here |
| **Cloudinary** | Excellent transcoding, but the free tier's credit model makes video costs unpredictable |
| **A VPS (Hetzner, DigitalOcean)** | Cheapest on paper. Rejected because you'd own patching, backups, and 2am outages — as a solo owner with a day job, ops time is the scarcest resource |

---

## 6 · Multi-tenancy → **Shared database, `community_id` + RLS**

**Why:** Simplest thing that works. Launching a new community is four INSERTs and
a domain. One database to back up, one migration to run, one deployment.

| Rejected | Reason |
|---|---|
| **Database per community** | True isolation, but N backups, N migrations, N monitoring surfaces. Operationally fatal for one person |
| **Schema per community** | Same migration multiplication with less isolation benefit |

**Weakness:** a bug in an RLS policy could leak across communities. Mitigated by
testing policies directly — that's why RLS tests are priority #1 in `TESTING.md`.

---

## 7 · Authorization → **RLS in the database, not the API layer**

**Why:** An application bug cannot leak data across communities if the database
itself refuses. Every access path — REST, edge function, direct client query — is
governed by one set of policies rather than scattered `if` statements.

**Rejected:** application-layer authorization. It's the common approach and it's
what fails: authorization checks get forgotten on the one new endpoint nobody
reviewed. Given an agent is writing endpoints, that risk is higher, not lower.

**Weakness:** RLS is harder to debug than an `if` statement, and policies can hurt
query planning at scale. Neither matters below ~50k rows.

---

## 8 · Styling → **Tailwind**

**Why:** The design system is already expressed as tokens; Tailwind is tokens.
Colocated with markup, so an agent has no separate stylesheet to keep in sync —
a common source of drift in generated code.

| Rejected | Reason |
|---|---|
| **CSS Modules** | Separate files to keep in sync. More agent drift |
| **styled-components** | Runtime cost, and it fights the design-token model |
| **MUI / Chakra** | Component libraries impose their own visual identity. This brand is deliberately not a default-looking app |

---

## 9 · Validation → **Zod, shared between client and server**

**Why:** One schema, imported by both sides. Validation cannot diverge. Also
generates TypeScript types, so schema and type never drift.

**Rejected:** Yup (weaker type inference), io-ts (steeper), and per-side
hand-written validation — which is how "the frontend allows it but the backend
rejects it" bugs happen.

---

## 10 · Payments → **Razorpay**

**Why:** Per-transaction only (~2%), no setup or monthly fee. Onboards
unregistered individuals with PAN + bank account, so no company registration is
needed. UPI, cards, and net banking in one integration.

| Rejected | Reason |
|---|---|
| **Direct UPI to a personal number** | No webhook, so every payment is manually verified and every chat manually unlocked. Personal-account tax mess, banks flag high-frequency inbound P2P as business use, no invoice or dispute trail. And decisively: your own chat banner says *"never send money"* — asking members to UPI a personal number teaches them the exact behaviour scammers exploit |
| **Stripe** | Weaker UPI support and Indian entity requirements |
| **Cashfree / PhonePe PG** | Comparable. Razorpay chosen for documentation depth and easier individual onboarding |

---

## 11 · Auth → **Email OTP, phone as a profile field**

**Why:** Free, instant, no regulatory approvals. SMS OTP in India requires DLT
registration — sender ID and template approval taking days — which would block
launch entirely.

| Rejected | Reason |
|---|---|
| **SMS OTP** | Lower friction for users and the natural identifier here, but DLT registration is the longest-lead item in the project. Deferred to v2, with real users to justify it |
| **Passwords** | More friction, more support load, password reset flows to build |
| **Google OAuth** | Many members won't have or want to link a Google account |

**Weakness accepted:** the sample biodata had a phone number and no email, so some
members will need an email created or provided at claim time. Mitigated by
delivering claim links over WhatsApp, where the community already coordinates.

---

## 12 · Testing → **Vitest + Playwright**

**Why:** Vitest shares Vite's config, so no separate build pipeline. Playwright is
more reliable than Cypress for multi-tab and mobile-viewport flows. Both matter
more than usual here: tests are how an agent verifies its own work.

**Rejected:** Jest (slower, separate config) and Cypress (weaker multi-context
support).

---

## 13 · Repo → **Single monorepo, pnpm workspaces**

```
apps/web            frontend
supabase/functions  edge functions
packages/shared     Zod schemas + generated DB types
```

**Why:** Shared validation and types must live somewhere both sides import from.
Separate repos would mean publishing a package or duplicating code.

**Rejected:** separate frontend/backend repos (version skew, no shared types),
and Nx or Turborepo (build orchestration you don't need at this size).
