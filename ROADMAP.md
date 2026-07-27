# Roadmap

Build in order. Do not start a later phase while an earlier one is incomplete,
even if the later item looks quick.

---

## Phase 1 — Foundation

- Repo, tooling, CI (typecheck, lint, test on every push)
- Supabase project, all three migrations, seed data
- **Real sub-caste list** (not the placeholders)
- Auth: email OTP, session handling
- Design tokens, base components
- R2 bucket, signed upload flow
- **GitHub Actions: anti-pause ping + nightly backup** — day one, not later

**Done when:** a user can sign up, and a restore from backup has been tested.

---

## Phase 2 — Profile

- Profile schema forms, all dropdowns
- Photo upload → variants + blurhash
- Video upload (client-compressed MP4, 30s / 8 MB cap in v1)
- Prompts, locations, family, preferences
- Completion scoring
- **The one-glance profile card** — every other screen composes from it
- Full profile view

**Done when:** a profile can be created by hand and renders correctly on a phone.

---

## Phase 3 — Claim pipeline

- Admin PDF upload → `import_batches`
- Extraction Edge Function → Claude API → `extracted_drafts` with confidence scores
- Admin review queue with amber flags on low-confidence fields
- Approve → claim token → WhatsApp link, sent manually
- Claim flow: token → OTP → pre-filled review → publish
- Consent recording

**Done when:** all ~150 seed profiles are through the queue and claimable.

---

## Phase 4 — Discovery and interests

- `candidates_for()` wired to the feed
- Daily Five scheduled job, 08:00 IST
- Filters, compatibility chips
- Express interest with intent tags
- Interests inbox: accept, silent decline
- Shortlist, block

**Done when:** two test members can find each other and reach a mutual accept.

---

## Phase 5 — Payments and chat

- Razorpay: order creation, checkout, **idempotent webhook**
- Plans, subscription lifecycle
- Paywall at mutual accept
- Text-only chat, pattern filter on send
- Safety banner, one-tap report, instant block
- Max 5 new conversations per day

**Done when:** a real ₹1 transaction unlocks a conversation for both parties, and
a duplicate webhook delivery changes nothing.

---

## Phase 6 — Admin

- Overview: KPIs, funnels, **filter usage**
- Review queue, members, activity log, reports
- Region scoping verified by test
- Approve / auto-approve toggle (publish only — never the badge)
- Verified badge, human-approved

**Done when:** a region admin provably cannot see another region's data.

---

## Phase 7 — Retention and exit

- Web push (Android): interest received, accepted, new message. **Nothing else**
- "Still looking?" email at 60 days → Still looking / Found a match / Pause
- `match_outcomes`
- Settings, notification preferences, data export, account deletion
- About page with the Dr. R. P. Nath tribute

**Done when:** a member can leave gracefully and the outcome is recorded.

---

## Launch

Pre-launch checklist in `DEPLOYMENT.md`. Then send claim links in **small batches**
— 20 at a time, not 150. The first batch will surface problems, and you only get
one chance at a first impression with each family.

---

## Deliberately not in v1

Revisit only when real usage demands it:

- ML content classifier — at ~1,000 members
- Behavioural abuse signals — needs volume
- Automated moderation escalation — run it manually first
- SMS / phone verification, DLT registration
- Live events
- Native app wrapper
- Second community (Maratha) — the schema supports it; don't exercise it until
  the first one works
- Redis, materialised views, search engine

---

## Open questions

| # | Question | Blocks |
|---|---|---|
| 1 | Gender ratio across the 150 seed profiles | May require interest caps or a delayed launch. Imbalance kills matrimony platforms more reliably than bad design |
| 2 | Who verifies profiles day to day | Phase 6 |
| 3 | Real sub-caste list | Phase 1 — must be settled before collecting data |
| 4 | Legal entity and bank account for Razorpay | Phase 5 |
