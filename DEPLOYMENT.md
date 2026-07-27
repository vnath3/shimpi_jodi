# Deployment

## Platforms

| Piece | Platform | Cost |
|---|---|---|
| Frontend | Cloudflare Pages | Free, unlimited bandwidth |
| Database, auth, functions | Supabase | Free tier initially |
| Photos, video | Cloudflare R2 | Free to 10 GB, **zero egress** |
| Payments | Razorpay | ~2% per transaction, no monthly fee |
| Domain | Registrar of choice | ~₹900/year |

Choose the region closest to India at signup. Verify current availability — providers
move these.

---

## First-time setup

1. Buy the domain
2. Create the Supabase project
3. Run migrations in order: `schema.sql` → `v2-addendum` → `v3-addendum`
4. Seed lookups: regions, cities, education levels, occupations, income bands,
   plans, prompts, **sub-castes** (replace the placeholder list)
5. Create the R2 bucket, configure CORS for signed uploads
6. **Set up both GitHub Actions on day one:**
   - Anti-pause ping every 3 days (free-tier Supabase pauses after 7 days idle)
   - Nightly `pg_dump` → R2
7. Point Cloudflare Pages at the frontend repo
8. Razorpay onboarding — PAN + bank account, individual/sole proprietor is
   accepted. Verify current KYC requirements at signup
9. Publish Terms, Privacy, Refund pages **before** requesting gateway activation

---

## The backup rule

The free tier has **no automatic backups**. That is a bigger risk than any size
cap. The nightly `pg_dump` GitHub Action is not optional — losing member data once
ends this project.

Test a restore before launch. An untested backup is not a backup.

---

## Free-tier limits worth knowing

- Postgres 500 MB — thousands of profiles and millions of short messages fit
- 50,000 monthly active users
- 5 GB egress
- 2 active projects
- **Projects pause after 7 days of inactivity** — this is the limit that catches
  people, not the size caps
- No backups, no SLA

---

## The upgrade trigger — decide now, not later

| Stage | Trigger | Monthly |
|---|---|---|
| Now | Building, first members | **₹0** |
| **Upgrade** | **10 paying subscribers (~₹8,000 collected)** | ~₹2,100 — no pausing, daily backups |
| Later | 500+ profiles, or video getting heavy | +₹500–1,500 |

Free is right until money changes hands. After that, "no backups, can pause, no
SLA" stops being thrift and becomes a liability — you'd be holding 150 families'
personal data with no recovery path.

Write the trigger somewhere you will see it.

---

## Android app, later

| Route | Effort | Gets you |
|---|---|---|
| TWA (Bubblewrap / PWABuilder) | ~1 hour | Play Store listing, full-screen |
| Capacitor | ~1 day | Native push, camera, file picker |

Play Store developer account: one-time ~₹2,100. Defer iOS entirely (~₹8,500/year)
until Android proves the product.

Play applies stricter policies to matrimony and dating apps — expect extra
declarations at submission.

---

## Pre-launch checklist

- [ ] Backup restore tested
- [ ] Anti-pause ping running
- [ ] Terms, Privacy, Refund pages live
- [ ] Razorpay in live mode, one real ₹1 transaction verified end to end
- [ ] Webhook idempotency tested with a duplicate delivery
- [ ] RLS cross-community access tests passing
- [ ] `noindex` verified on all profile routes
- [ ] Real sub-caste list seeded (not the placeholders)
- [ ] Moderation term list includes roman-transliterated Marathi and Hindi
- [ ] Admin accounts created, super-admin 2FA enabled
