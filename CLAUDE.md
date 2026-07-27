# CLAUDE.md — Rules for this repository

Read this before writing any code. Read `docs/ARCHITECTURE.md` and `docs/SCHEMA.md`
before touching the backend, and `docs/DESIGN-SYSTEM.md` before touching UI.

---

## What this is

**Shimpi Jodi** — a matrimony web app for the Shimpi community in Maharashtra.
Built as a PWA, mobile-first, Android-first. ~150 seed profiles at launch,
designed to scale to 100k and to host additional communities (Maratha, etc.)
on the same codebase.

Owner: Vivek. Sole reviewer. Treat him as an experienced engineer who is new to
this specific stack — explain stack-specific choices, don't explain programming.

---

## Non-negotiable rules

These are not preferences. Breaking any of them is a defect, regardless of
whether tests pass.

1. **Never bypass Row-Level Security.** Do not use the Supabase service-role key
   in any code path that serves a member request. Service role is for
   background jobs and admin functions only.
2. **Community isolation is absolute.** A member must never see, match with, or
   message anyone from a different `community_id`. This is enforced by RLS and a
   DB trigger — never work around either.
3. **Opposite-gender matching only.** Enforced by DB trigger. Do not add
   application logic that assumes otherwise.
4. **No hard deletes.** Every delete is `deleted_at` + `deleted_by`. The only
   exception is `purge_user()`, which is super-admin-only and already written.
5. **Never expose `profile_private`** (phone, address) to a member-facing
   endpoint or response type. Admin-only, always.
6. **Photos and videos are never public.** Signed URLs only, short expiry, never
   indexable. No `<meta>` tags, no sitemap entries, `noindex` on all profile routes.
7. **Chat is text-only.** Do not add image, file, or voice upload to messages.
   This is a safety decision, not a scope decision.
8. **Money is integer paise.** Never float, never rupee decimals in the DB.
9. **Every new table gets RLS enabled** and a policy before it ships.

---

## Stop and ask

Build features end-to-end without checking in. But **stop and ask Vivek** before:

- Any **database migration** or schema change
- Anything touching **RLS policies, auth, or consent flows**
- Anything touching the **payment or subscription flow**
- Adding a **new third-party dependency or paid service**
- Changing **pricing, plan structure, or the paywall trigger point**

Everything else: build it, test it, report back.

---

## Definition of done

A feature is not done until all of these pass locally:

```bash
pnpm typecheck   # tsc --noEmit, zero errors
pnpm lint        # eslint, zero errors
pnpm test        # vitest, all green
pnpm test:e2e    # playwright, for user-facing flows
```

Do not report a task complete with a failing or skipped check. If something
can't pass, say so explicitly and explain why.

---

## Design reference

`/design-reference/*.html` contains working prototypes of every screen.

**These are visual truth, not code to copy.** They are vanilla CSS; the app is
React + Tailwind. Reproduce the *appearance* using tokens from
`docs/DESIGN-SYSTEM.md`. Do not port stylesheets, do not import them, do not
reference them at runtime.

If a prototype and this documentation disagree, the documentation wins — flag
the conflict rather than guessing.

---

## Code conventions

- **TypeScript strict mode.** No `any`. No `@ts-ignore` without a comment
  explaining why and a linked issue.
- **Zod schemas are the single source of truth** for validation. Define once in
  `packages/shared`, import in both frontend and edge functions. Never write
  the same validation twice.
- **Database types are generated**, never hand-written:
  `supabase gen types typescript`. Regenerate after every migration.
- **No barrel files** (`index.ts` re-exports). They break tree-shaking and make
  imports ambiguous.
- **Server state** → TanStack Query. **Client state** → Zustand. Do not put
  server data in Zustand.
- **Forms** → React Hook Form + Zod resolver.
- Components are function components. No class components.
- File naming: `kebab-case.tsx` for files, `PascalCase` for components.

---

## Copy and language

- The app ships in **English, Marathi, Hindi, Telugu**. Every user-facing string
  goes through i18n from day one — never hardcode display text.
- Tone: warm, direct, second person. "Tell us about yourself", not "Complete
  your KYC profile."
- Never use dating-app language. This is marriage: "express interest", not
  "like"; "not a match", not "reject".
- Devanagari and Telugu strings run longer than English. Design and test for
  ~40% text expansion.

---

## Things that look like bugs but are intentional

- **Compatibility differences are shown, not hidden.** "Different on relocation"
  appearing on a card is correct behaviour. Do not filter these out.
- **Declines are silent.** The sender is never notified. Do not add a
  notification for it.
- **One payment unlocks the conversation for both people.** The other party
  never pays. Do not add a second paywall.
- **The Daily Five is capped at five.** Do not add infinite scroll to discovery.
- **Profile completion below 80% hides the profile from search.** Intentional
  data-quality gate.

---

## Testing priorities

Test these first, in this order:

1. RLS policies — write tests that *attempt* cross-community access and assert failure
2. The opposite-gender and same-community triggers on `interests`
3. Payment webhook idempotency (Razorpay retries — never double-grant a subscription)
4. Consent recording on publish
5. Soft-delete filtering on every read path

UI snapshot tests are low value here. Spend the effort on the five above.

---

## Current phase

See `docs/ROADMAP.md`. Do not build Phase 3+ items while Phase 1 is incomplete,
even if they seem quick.
