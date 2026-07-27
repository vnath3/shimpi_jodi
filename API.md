# API

Most reads go directly through the Supabase client with RLS enforcing access.
Edge Functions exist only where server-side secrets or multi-step logic are
required.

---

## Direct Supabase reads (RLS-enforced)

```ts
// Feed — always through the function, never hand-rolled eligibility
supabase.rpc('candidates_for', { p_profile: myProfileId })

// Profile detail
supabase.from('v_active_profiles').select('*').eq('id', id).single()

// Interests received
supabase.from('interests')
  .select('*, sender:profiles!sender_profile_id(*)')
  .eq('receiver_profile_id', myProfileId)
  .eq('status', 'pending')
```

Never query `profiles` directly for member-facing reads — use `v_active_profiles`
or `candidates_for()`. They apply soft-delete, published-status, block, and
eligibility rules in one place.

---

## Edge Functions

| Function | Purpose | Auth |
|---|---|---|
| `auth-otp-send` | Issue email OTP | Public, rate-limited |
| `auth-otp-verify` | Verify, create session | Public, rate-limited |
| `claim-profile` | Redeem a claim token → link draft to a user | Public + token |
| `profile-publish` | Validate completeness, record consents, publish | Member |
| `media-upload-url` | Signed R2 upload URL | Member |
| `media-process` | Transcode, generate variants + blurhash | Internal |
| `interest-send` | Create interest (triggers enforce the rules) | Member |
| `interest-respond` | Accept or decline | Member |
| `payment-create-order` | Razorpay order | Member |
| `payment-webhook` | **Idempotent.** Verify signature, activate subscription, open conversation | Razorpay signature |
| `message-send` | Pattern filter, then insert | Member, subscription required |
| `report-create` | File a report with context | Member |
| `admin-import-pdf` | One PDF → Claude API → draft | Admin |
| `admin-approve-draft` | Approve, generate claim token | Admin |
| `cron-daily-five` | 08:00 IST | Scheduled |
| `cron-still-looking` | 60-day check-in email | Scheduled |

---

## Conventions

- Validate every input with a shared Zod schema from `packages/shared`
- Return `{ data, error }` — never throw across the boundary
- Errors carry a stable `code` string; the client maps codes to localised copy.
  Never return raw Postgres errors to the client
- Every mutation writes to `activity_events`
- Every admin mutation additionally writes to `audit_log`

## Idempotency

`payment-webhook` **must** be idempotent. Razorpay retries. Key on
`gateway_payment_id` with a unique constraint and treat a duplicate as success.
Double-granting a subscription is a money bug and money bugs are unrecoverable.
