# Security & Privacy

The governing question for any decision here: *would a member be comfortable if
they saw exactly what we do with this?*

---

## Data classification

| Class | Fields | Visibility |
|---|---|---|
| **Public to members** | Name, age, height, education, occupation, city, family type, prompts, photos, video | Signed-in, verified members of the same community |
| **Private** | Phone, full address (`profile_private`) | Admins only. Released to another member only after mutual accept **and** explicit share |
| **Never displayed** | Email, IP, user agent, payment identifiers | System only |
| **Sensitive** | Sub-caste, community, income band | Members of the same community only. Never in URLs, logs, or analytics payloads |

---

## Access control

Three enforcement layers, in order of trust:

1. **RLS policies** — community isolation, region scoping, `profile_private`
   access. Cannot be bypassed by an application bug
2. **DB triggers** — opposite-gender rule, cross-community interest block,
   sub-caste consistency
3. **Application** — session handling, rate limits, UI gating

Never use the service-role key in a member-facing path.

---

## DPDP compliance

- **Consent is append-only and versioned.** Never update a consent row; insert a
  new one. `v_current_consents` reads the latest state
- **Two consents are required** to publish: publish-profile, store-personal-data.
  Two are optional: email notifications, family-managed access
- **Right to access** — self-service export from Settings, via `data_requests`
- **Right to erasure** — soft delete is self-service; hard purge is super-admin
  only via `purge_user()`, which anonymises the user row, deletes media from
  object storage, tombstones messages, and writes an immutable audit record
- **Every admin action** is written to `audit_log` with before/after state

---

## Media privacy

- Signed URLs, short expiry. No permanently public object keys
- `noindex` on every profile route. No sitemap entries, no Open Graph tags
  containing member data
- Photos are visible only to signed-in members — never blurred, since blur adds
  friction without adding real protection

---

## Chat privacy — the rule that matters most

**No human reads private chats routinely.**

Automated scanning happens (pattern filter and, later, a classifier), but no
admin sees message content unless a specific flag or report exists — and then
only the messages around that flag, never the whole history.

Every such read calls `log_moderation_read()` and lands in `audit_log`.

State it plainly in the privacy policy:

> Messages are automatically scanned for safety. Our team reads messages only
> when a message is reported or flagged.

In a community where the admin is someone's neighbour, blanket access to private
conversations is both a DPDP problem and a trust catastrophe.

---

## Application security

- Rate limits: OTP requests per email per hour, interests per sender per day,
  **max 5 new conversations started per day**
- Payment webhooks: verify Razorpay signature; make handlers idempotent —
  retries must never double-grant a subscription
- No secrets in the client bundle. Only the Supabase anon key ships
- Input validation via shared Zod schemas on both sides

---

## Required public pages

Payment gateway onboarding requires these to exist before launch:

- Terms of Service
- Privacy Policy — must describe automated chat scanning in plain language
- Refund & Cancellation Policy — see below
- Contact information

**Refund policy:** no refunds once chat is unlocked, since the service is
delivered immediately. One exception: if an account is suspended in error, refund
pro-rata. Publishing this removes the incentive to argue.

*Not legal advice — have these reviewed locally before launch.*
