# Testing

Tests are how an agent verifies its own work. A feature with failing or skipped
tests is not done.

```bash
pnpm typecheck   # tsc --noEmit
pnpm lint
pnpm test        # vitest
pnpm test:e2e    # playwright
```

---

## Priority order

Spend effort here, in this order. UI snapshot tests are low value on this project.

### 1 · RLS policies — the highest-value tests in the repo

Write tests that **attempt** forbidden access and assert failure:

- Member in community A cannot read a profile in community B
- Region admin for Marathwada cannot read a Vidarbha profile
- Non-super-admin cannot execute `purge_user()`
- No member-facing query can reach `profile_private`
- Anonymous access returns nothing

### 2 · Database triggers

- Same-gender interest → rejected
- Cross-community interest → rejected
- Sub-caste from another community → rejected
- Video over 60s → rejected
- Second primary photo → rejected

### 3 · Payment webhook idempotency

Deliver the same Razorpay webhook twice. Assert exactly one subscription, one
conversation unlock, and no double charge recorded. This is the most expensive
possible bug.

### 4 · Consent

Publishing without both required consents fails. Consent rows are inserted, never
updated. `v_current_consents` returns the latest.

### 5 · Soft delete

Every read path excludes `deleted_at IS NOT NULL`. A deleted profile appears in no
feed, no search, no interest list.

---

## E2E flows worth automating

1. Claim link → OTP → review → photos → prompts → consent → published
2. Discover → open profile → express interest
3. Receive interest → accept → paywall → pay (test mode) → chat opens for both
4. Report a message → flag appears in admin
5. "Still looking?" email → Found a match → profile hidden

---

## Conventions

- Test names describe behaviour: `rejects same-gender interest`, not `test trigger 3`
- Use a seeded test database, reset between suites
- Never mock the database for RLS tests — the whole point is the real policy engine
- Mock Razorpay and the Claude API; never call them in tests
- No network calls in unit tests
