# Environment Variables

Copy `.env.example` → `.env.local`. Never commit real values.

---

## Client (shipped in the bundle — public by definition)

```bash
VITE_SUPABASE_URL=
VITE_SUPABASE_ANON_KEY=        # safe to expose; RLS is the protection
VITE_R2_PUBLIC_URL=            # CDN base for media
VITE_RAZORPAY_KEY_ID=          # public key, not the secret
VITE_COMMUNITY_SLUG=shimpi     # which tenant this deployment serves
VITE_APP_ENV=development
```

Anything prefixed `VITE_` **ends up in the browser**. Never put a secret there.

---

## Server — Edge Functions only

```bash
SUPABASE_SERVICE_ROLE_KEY=     # bypasses RLS — background jobs and admin only
SUPABASE_DB_URL=

R2_ACCOUNT_ID=
R2_ACCESS_KEY_ID=
R2_SECRET_ACCESS_KEY=
R2_BUCKET=

RAZORPAY_KEY_SECRET=
RAZORPAY_WEBHOOK_SECRET=

ANTHROPIC_API_KEY=             # PDF extraction

RESEND_API_KEY=                # OTP and check-in emails
EMAIL_FROM=

VAPID_PUBLIC_KEY=              # web push
VAPID_PRIVATE_KEY=
```

---

## GitHub Actions secrets

```bash
SUPABASE_DB_URL                # nightly pg_dump
SUPABASE_URL                   # anti-pause ping
SUPABASE_ANON_KEY
R2_ACCESS_KEY_ID               # backup destination
R2_SECRET_ACCESS_KEY
```

---

## Rules

- The service-role key never appears in client code, in a `VITE_` variable, or in
  any path serving a member request
- Rotate keys if a secret is ever committed — revoking is not enough
- Local development uses `pnpm supabase start`, not the hosted project
- `VITE_COMMUNITY_SLUG` is what makes one codebase serve multiple communities.
  Each deployment sets its own
