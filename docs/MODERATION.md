# Moderation & Safety

## The framing that decides everything

In a closed, single-caste community, **identity is the moderation system**.
Nobody harasses someone their aunt might know by surname. This is structurally
different from an anonymous dating app, where anonymity is the product.

The realistic threat here is **not** explicit content. It is **matrimonial
financial fraud** — trust built over weeks, then a family emergency, then a UPI
request. Tune for money, not for skin.

---

## Build in v1

| Control | Why |
|---|---|
| **Text-only chat** | Architectural. No image or file upload means the media problem cannot exist |
| **Verified badge**, human-approved against samaj records | Prevention beats detection. A profile traceable to a register number behaves |
| **~200-term pattern filter** | Weighted toward money requests and contact leaks |
| **One-tap report**, context auto-attached | The real detection layer at this scale |
| **Instant block, always free** | Safety is never behind a paywall |
| **Max 5 new conversations/day** | Kills copy-paste solicitation before it starts |

---

## Do NOT build in v1

- **ML classifier** — at 150 members you'll see ~2 flags a week. Reviewing them
  personally is cheaper, more accurate, and teaches you the vocabulary a real
  term list needs. Revisit at ~1,000 members
- **Behavioural signals view** — needs volume to mean anything
- **Automated escalation ladder** — run it by hand. Better calls for the first
  hundred cases, and you learn what the rules should be

---

## The term list

`moderation_terms`, seeded per language with severity 1–3.

**Roman-transliterated Marathi and Hindi are mandatory.** An English-only list
catches almost nothing here — transliteration is the primary evasion path. Shipping
without it is the same as shipping no filter.

| Category | Examples |
|---|---|
| `money_request` | UPI, GPay, PhonePe, paisa, transfer, account-number patterns |
| `contact_leak` | 10-digit phone patterns, @gmail, Instagram handles |
| `external_platform` | "WhatsApp me", "add me on" |
| `sexual_solicitation` | Explicit terms in all four languages + roman |

Severity 1 → warn the sender before send. Severity 3 → block the send and file a
flag. Response is graded, never binary.

---

## Escalation ladder (run manually in v1)

| Strike | Trigger | Action |
|---|---|---|
| 1 | First upheld flag, low severity | Warning, message removed |
| 2 | Second upheld flag | 7-day chat mute, profile stays visible |
| 3 | Third, or any sexual solicitation | Suspend, unpublish, refund pro-rata |
| Immediate | Money request, minor involved, threat | Suspend on first instance |

Refunding on suspension is deliberate — it removes the incentive to argue and is
the cheaper outcome.

---

## Highest-precision signal available

**Multiple recipients blocking the same sender within a short window.**

Better than any content classifier, and it requires reading zero messages.
Surface it in the admin before any content review. Implemented as
`v_abuse_signals` — wire it up when volume justifies it.

---

## What members see

Top of every new thread:

> Keep the conversation here until you're comfortable. Never send money. Report
> anything that feels off — we act on every report.

On the Plus purchase screen:

> Chat is monitored automatically for safety.

Stated deterrence prevents more than any filter catches.

---

## Response commitment

Act on every report within 24 hours and tell the reporter what you did.

In a single-community app, a mishandled report travels faster than any marketing
you will ever do.
