# Shimpi Jodi — Gap Analysis & Chat Safety

Validated against a real biodata sample (TSSK PR. No. 10, Vidarbha region).

---

## Part 1 — What the sample exposed

The sample **validates** the multi-location model decisively: born in **Chandrapur**, family address in **Nagpur**, works in **Pune**. Three different cities in one profile. A single `city` field would have destroyed this record.

It also exposes ten gaps. Three are critical — meaning if you collect data from 150 people without them, you will have to go back and ask again.

### Critical

| # | Gap | Evidence in sample | Why it matters |
|---|---|---|---|
| 1 | **Middle name (father's name)** | "Vaishnavi **Dharmendra** Akkewar" | Indian naming is First + Father's + Surname. Our schema has only `first_name` / `last_name`. Splitting this wrong corrupts every name in the database, and families identify each other by the middle name. |
| 2 | **Birth time + birth place** | "03:15 PM", "Chandrapur" | Kundali matching is impossible without both. Every biodata in circulation carries them, so the data is free to collect now and expensive to chase later. This is the single most likely reason a family rejects a match in this market. |
| 3 | **Education specialisation** | "BE (**E&TC**)" | We store education *level* only. "BE" and "BE (E&TC)" are different pieces of information, and engineers filter on branch. |

### Important

| # | Gap | Evidence | Fix |
|---|---|---|---|
| 4 | **Job title** separate from occupation category | "Network Engineer" at "Tata Communications" | `occupation_id` is a filterable category; job title is display text. Both needed. |
| 5 | **Parents' names** | "Shubhangi Akkewar (Housewife)" | We captured mother's *occupation* but not her name. Families look for family names. |
| 6 | **Sibling birth order + marital status** | "1 younger brother, 1 elder sister (married)" | Counts alone lose the order. "Elder sister married" is materially different from "younger sister unmarried" to a matching family. |
| 7 | **Free-text expectations** | "Well educated, own house, stable job in Pune" | Structured filters can't hold "own house". Keep the structured fields for filtering, add a short free-text field for nuance. |
| 8 | **Owns house / assets** | "own house" | Appears in expectations, so it's a real filter criterion in this market. One boolean on the profile. |

### Capture but never publish

| # | Field | Sample | Handling |
|---|---|---|---|
| 9 | **Full street address** | "Zingabai Takli, Nagpur – 440030" | Store in a separate `profile_private` table. Admin-only, for verification. **Never** rendered in any profile view. |
| 10 | **Phone number** | "9049807063" | Same table. Released only after both sides accept *and* the subscriber requests it. Publishing this on a matrimony profile is how harassment starts. |

### Minor

- **Blood group** ("B+") — appears in almost every Indian biodata. Zero filter value, but leaving it out makes the profile feel incomplete to families. One optional field.
- **Source reference** ("TSSK PR. No. 10") — the samaj register number. Store on the extracted draft for provenance and de-duplication.
- **Sub-caste is absent from the biodata.** It cannot be extracted; it must be asked at claim time. Add it to the review step.

---

## Part 2 — Onboarding flow changes

The claim flow goes from 8 steps to 9. Net added time: roughly 25 seconds, because most of it is pre-filled from the PDF.

| Step | Change |
|---|---|
| 4 · Review details | Split name into **First / Father's / Surname**. Add education specialisation, job title, **sub-caste dropdown** (cannot be extracted — must be asked). |
| **4b · Birth details** *(new)* | Date, **time**, **place** of birth. Blood group. One short screen. Copy: "For families who match kundali — you can skip this." Skippable, but ask, because you get one shot at it. |
| 5 · Family | Add parents' names. Replace sibling counts with repeatable rows: relation + elder/younger + married yes/no. |
| 6 · Preferences | Keep structured filters. Add a 200-character free-text "What I'm looking for". Add "owns a house" to both profile and preferences. |
| 7 · Private details *(new, merged into consent step)* | Phone and full address, with an explicit line: **"Never shown on your profile. Shared only after you accept someone and agree to it."** |

**One thing to cut:** the `income_band` prompt currently sits high in the review step. In this sample it isn't stated at all — most biodata omit it. Move it lower and mark it optional, or you will bounce people at the exact moment they are most likely to abandon.

---

## Part 3 — Chat safety

### The single most effective decision: text-only chat in v1

No image, video, or file sending inside chat. This removes the nudes vector almost entirely — you cannot send what the client cannot upload. Every mainstream matrimony platform that allows in-chat media spends heavily on image moderation; you can simply not have the problem. Add media later, if ever, with the moderation budget it requires.

Everything below therefore governs **text**.

### Four layers

**Layer 1 — Pre-send pattern filter (synchronous, <5 ms)**

Runs before the message is written. Blocks or warns instantly. Catches:

- Explicit sexual solicitation terms — maintained in **Marathi, Hindi, Telugu, English, and Roman transliteration**. Transliterated Marathi abuse is the most common evasion and pure-English filters miss all of it.
- Payment requests: "UPI", "GPay", "PhonePe", "paisa", "transfer", account-number patterns
- Contact-detail leakage before the contact-share gate: 10-digit phone patterns, "@gmail", Instagram handles
- External-platform pushes: "WhatsApp me", "add me on"

Response is graded, not binary: soft terms show a warning ("This looks like a request for money — are you sure?"), hard terms block the send and file a flag.

**Layer 2 — Async classifier (post-send, ~200 ms, invisible)**

Every message is scored by a text-classification model for sexual content, harassment, threats, and scam patterns. Runs after delivery so the chat never feels slow. Scores above threshold create a flag; the message is *not* auto-deleted — false positives on a marriage conversation would be worse than the miss.

Use a hosted moderation endpoint rather than training your own. At your volume this costs a few hundred rupees a month.

**Layer 3 — Behavioural signals (no message reading required)**

Often stronger than content analysis, and completely privacy-preserving:

- Same message sent to many different people (copy-paste solicitation)
- Very high send rate to non-responders
- Multiple recipients blocking the same sender within a short window — **the highest-precision abuse signal that exists**
- Account created, subscribed, and messaging 20 people within an hour

**Layer 4 — One-tap reporting inside the thread**

Report attaches the surrounding messages automatically, so the reporter doesn't have to explain or screenshot. Reported user is not notified.

### The privacy rule that matters

**No human reads private chats routinely.** Layers 1–3 are automated; no admin sees message content. A human reads messages **only** when a flag or report exists, and only the messages around that flag — not the whole history.

This must be stated in your privacy policy in plain language: *"Messages are automatically scanned for safety. Our team reads messages only when a message is reported or flagged."* Blanket admin access to private conversations is both a DPDP problem and, in a community where everyone knows the admin personally, a trust catastrophe.

Every moderation view is written to `audit_log` — who read what, when, and why.

### Escalation ladder

| Strike | Trigger | Action |
|---|---|---|
| 1 | First upheld flag, low severity | In-app warning, message removed |
| 2 | Second upheld flag | 7-day chat mute; profile stays visible |
| 3 | Third, or any sexual solicitation | Account suspended, profile unpublished, subscription refunded pro-rata |
| Immediate | Money request, minor involvement, threat | Suspend on first instance, no ladder |

Refunding on suspension is deliberate. It removes the incentive to argue and it's the cheaper outcome.

### What to tell members

A short banner at the top of every new thread — already in the Phase 3 design:

> Keep the conversation here until you're comfortable. Never send money. Report anything that feels off — we act on every report.

Add one line to the Plus purchase screen: *"Chat is monitored automatically for safety."* Saying it up front deters more than any filter catches.
