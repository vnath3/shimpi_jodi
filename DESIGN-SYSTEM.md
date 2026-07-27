# Design System

Prototypes live in `/design-reference/`. They are **visual truth, not code**.
Reproduce appearance with the tokens below; do not port their CSS.

---

## Colour

```css
--indigo:      #1E3548;  /* primary text, dark surfaces, primary buttons */
--indigo-70:   #4A5F71;  /* secondary text on light */
--teal:        #2C6E75;  /* section headers, accents, success */
--teal-tint:   #E8F1F1;  /* prompt blocks, subtle fills */
--coral:       #F4633A;  /* THE call-to-action colour */
--coral-tint:  #FDEDE7;  /* sent/active states */
--cream:       #FAF7F2;  /* app background */
--surface:     #FFFFFF;  /* cards */
--ink:         #141A1F;  /* body text */
--muted:       #7C868F;  /* secondary text */
--line:        #E7E3DC;  /* borders, dividers */
```

**Coral is scarce on purpose.** It marks the primary action and the pearl,
nothing else. If two coral elements compete on one screen, one of them is wrong.

Never use: maroon/gold (the matrimony cliché this brand rejects), gradients on
text, or pure black.

---

## Type

| Role | Family | Use |
|---|---|---|
| Display | **Baloo 2** 600/700 | Logo, headings, buttons, names |
| Body | **Inter** 400/500/600 | Everything else |
| Devanagari | Noto Sans Devanagari | Marathi, Hindi |
| Telugu | Noto Sans Telugu | Telugu |

Scale: 22px page title · 16px card name · 15px body · 13px secondary · 11px labels.

Indic scripts run ~40% longer than English. Never fix a container height to
English text.

---

## Logo — the Shell & Pearl

Two shell valves (teal left, indigo right) hinged at the base, holding one coral
pearl. From `śimpī` — which in Marathi also means *oyster shell*, and a shell
holds a *moti*, a pearl. The community's own name contains the metaphor.

```
Loading    → shell closed, valves pulse
Match      → shell opens, pearl appears  ← the ONE celebration animation
Elsewhere  → the pearl alone: notification dot, active tab, unread badge
```

The pearl alone is the system's accent mark. The full shell animation appears
**only** at a mutual accept. Do not reuse it for lesser events — its scarcity is
what makes it land.

---

## Components

- **Radius** — 18px cards, 13px buttons, 12px inputs, 999px chips
- **Shadow** — `0 2px 10px rgba(30,53,72,.06)`. One elevation level only
- **Borders** — 1px `--line`. 1.5px on interactive elements
- **Touch targets** — minimum 44px
- **Icons** — outline, 1.8px stroke, rounded joins. Indigo default, coral when active

### The profile card, in order

1. Photo (blurhash placeholder → 720px variant), name, age, height, city
2. Three fact chips — education, occupation, location
3. **One prompt answer** in a teal-tinted block. This is the personality hook
4. Compatibility chips — matches in coral tint, differences in grey
5. Shortlist + Express Interest

Differences are shown, not hidden. That is the trust play.

---

## Motion

Light and purposeful. Card transitions, button press feedback, sheet slide-up
(`cubic-bezier(.32,.72,0,1)`), the match animation.

**No** confetti, streaks, badges, like-counts, or public popularity signals. In a
community where everyone knows everyone, gamification amplifies rejection.
Interactions are private by default.

Honour `prefers-reduced-motion`.

---

## Copy

| Do | Don't |
|---|---|
| Express Interest | Like, Swipe |
| Not a match | Reject, Pass |
| Tell us about yourself | Complete your profile |
| Chat opens once she accepts | Upgrade to unlock |

Warm, second person, no matrimony-industry jargon.
