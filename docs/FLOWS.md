# User Flows

Visual reference: `/design-reference/shimpi-jodi-06-golden-path.html`

---

## 1 · Getting profiles in (admin)

```
Region admin uploads biodata PDFs
   → import_batches
Edge Function extracts each PDF via Claude API
   → extracted_drafts (+ per-field confidence scores)
Admin reviews ONLY low-confidence fields, corrects, approves
   → status = approved, claim_token generated
Claim link sent by WhatsApp, manually, from the admin's own phone
```

**The consent gate:** approval sends a claim link and nothing more. The profile
stays unlisted and invisible until the member publishes it themselves. An admin
must never publish on someone's behalf.

Sub-caste is **not** in biodata and cannot be extracted — it must be asked at
claim time.

---

## 2 · Claim and publish (~90 seconds)

| Step | Screen |
|---|---|
| 1 | Welcome — shell opens, pearl drops |
| 2 | Email, then 6-digit OTP |
| 3 | **"We found your profile"** — pre-filled card, "Yes, this is me" |
| 4 | Review details — all dropdowns. Name splits First / Father's / Surname. Sub-caste asked here |
| 4b | Birth details — date, **time**, **place**, blood group. Skippable, but ask |
| 5 | Photos (up to 6) + optional video intro |
| 6 | Three prompts, 140 chars each |
| 7 | Locations — residence, work, native + settle intent + preferred/acceptable cities |
| 8 | Consent — two required, two optional |
| 9 | Published. Profile strength meter with one specific next action |

Phone number is pre-filled from the biodata and confirmed here. It is **never
displayed to other members** and there is no SMS verification in v1.

Income band sits **low** in step 4 and is optional — most biodata omit it, and
asking early causes abandonment.

---

## 3 · Discovery

```
08:00 IST → scheduled job builds each member's Daily Five
            from candidates_for(profile_id)
```

Five profiles. Not six, not infinite. With a small pool, rationing discovery is
what makes people return tomorrow.

Card → tap → full profile → video → Express Interest, tagged with one of:
*Impressed by your profile* / *Our families seem aligned* / *Would like to talk*.

The intent tag gives the receiver context and gives the admin real signal.

---

## 4 · Interest and accept

- Receiver sees the interest with its intent tag
- **Accept** → `conversations` row created, status `locked` → shell-and-pearl moment
- **Decline** → silent. The sender is never notified. This matters in a community
  where everyone knows everyone

---

## 5 · Paywall and chat

The paywall fires **after** a mutual accept, never before. Browsing and expressing
interest are free forever.

```
Mutual accept → paywall → plan selected → Razorpay → webhook
   → subscription active
   → conversation.status = 'open'  ← for BOTH people
```

One payment opens one conversation for both sides. The other party never pays.

Chat is **text-only**. Safety banner at the top of every new thread.

---

## 6 · Exit — the flow that measures success

At 60 days of no activity, email the member:

> **Still looking?**  ·  Still looking / Found a match / Pause for now

- **Found a match** → profile hidden, `match_outcomes` recorded
- **Pause** → hidden, reversible any time
- **No response in 14 days** → drops out of everyone's Daily Five automatically

Stale profiles of already-married people are the fastest way to lose community
trust. This flow is not optional.

`match_outcomes` is the only metric that measures whether the product worked.

---

## 7 · Admin

Five sections: Overview, Review queue, Members, Activity, Reports.

- Region admins see only their regions. Super admin sees everything
- **Either** a region admin **or** the super admin can approve a profile — not both
- An auto-approve toggle publishes after 1 day without human action
- Auto-approve **never** grants the verified badge
