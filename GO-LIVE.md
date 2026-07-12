# Taking Wake live — free, your devices + a few you share with

No App Store, no $99 developer account, **no server**. The app talks to Gemini directly
with your own key (protected by a budget cap), and **SideStore** installs it and keeps it
from expiring. One-time setup, then it just runs.

---

## Part A — Get your Gemini key (free, 2 min)

1. Get a key at [aistudio.google.com/apikey](https://aistudio.google.com/apikey).
2. **Set a spending cap** (AI Studio → Billing/limits) — the app calls Gemini only when its
   on-device check is unsure, but the cap means a lost/shared device can never cost you more
   than $X. This is your safety net for embedding the key in the app.

---

## Part B — Put the key in the app (never committed)

The key goes in a **gitignored** file, not in source:
```bash
cd Wake
cp Secrets.example.xcconfig Secrets.xcconfig     # Secrets.xcconfig is gitignored
# edit Secrets.xcconfig →  WAKE_GEMINI_KEY = your-key-here
```
That's it — the build injects it into the app as `WakeGeminiKey`, and cloud judging turns
on automatically. Offline or if Gemini is unreachable, the app judges fully on-device, so
it never gets stuck.

> Rotating the key: change it in AI Studio, update `Secrets.xcconfig`, rebuild. Do this if a
> shared device ever leaves your circle.

---

## Part C — Build the app (one time, in Xcode)

You need a Mac with Xcode (free) and a free Apple ID.

1. Generate the Xcode project: `brew install xcodegen && cd Wake && xcodegen generate`, then `open Wake.xcodeproj`.
2. Signing & Capabilities → select your free Apple ID (personal team).
3. Plug in your iPhone, pick it as the run target, **⌘R** — it installs directly.
   *(This alone works, but the app expires in 7 days. SideStore below fixes that.)*
4. To share / avoid the weekly expiry, export an **`.ipa`**: Product → Archive →
   Distribute App → **Debugging** (or Development) → Export. You'll get a `Wake.ipa`.

---

## Part D — Install & keep it alive with SideStore (free, no weekly chore)

SideStore re-signs the app in the background so it never expires, with no App Store and
no always-on computer.

**For each device (yours + anyone you share the `.ipa` with):**
1. Follow the SideStore setup at [sidestore.io](https://sidestore.io) (one-time: pair the
   device, install the SideStore app, sign in with **that device's own free Apple ID**).
2. In SideStore → **+** → pick `Wake.ipa` → install.
3. Enable **background refresh** for SideStore so it auto-renews the 7-day signature.

That's it — the app stays installed, refreshes itself, and talks to Gemini directly.
Free, private, and shareable with the people you choose.

---

## What each person needs
| | You | A friend you share with |
|---|---|---|
| The `.ipa` file | build it once (your key baked in) | you send it to them |
| Gemini key | yours (in the app, budget-capped) | nothing — uses yours |
| SideStore + free Apple ID | yes | yes (their own) |

> Your key is inside the `.ipa` you share, so shared devices spend against **your**
> budget cap. That's the trade for having no server. If that circle ever changes, rotate
> the key (Part B). For truly public distribution you'd switch to the hosted-backend path —
> the [`backend/`](backend/) code is still in the repo for exactly that.

## Honest limits on this free path
- **7-day signature** is a free-Apple-ID rule; SideStore's background refresh hides it, but if a device is offline for >7 days the app needs a manual refresh.
- **Alarm reliability:** without a paid account + Critical Alerts/AlarmKit, the escalation is time-sensitive **notifications**, not a guaranteed silent-mode override. Fine for personal use; know the ceiling.
- **Embedded key:** extractable from the `.ipa`. The budget cap is what makes this safe for a small trusted circle — not for public release.
