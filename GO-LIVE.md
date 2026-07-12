# Taking Wake live — free, your devices + a few you share with

No App Store, no $99 developer account. Two pieces: a **free hosted backend** (so your
phone can reach Gemini from anywhere) and **SideStore** (to install the app and keep it
from expiring). One-time setup, then it just runs.

---

## Part A — Deploy the backend (free, ~10 min)

The backend is a tiny FastAPI proxy that holds your Gemini key. We'll host it free on
**Render**.

1. **Push the repo to GitHub** (private is fine) — see the repo you're creating.
2. Get a **Gemini API key** at [aistudio.google.com/apikey](https://aistudio.google.com/apikey), and **set a spending cap** (AI Studio → Billing) so a runaway can't cost you.
3. In [Render](https://render.com) → **New → Blueprint** → connect your repo. It reads [`render.yaml`](render.yaml) and creates the `wake-judge` service.
4. When prompted, paste the two secrets (they're **not** in git):
   - `GEMINI_API_KEY` = your key
   - `WAKE_APP_SECRET` = any random string (e.g. run `openssl rand -hex 24`) — keep a copy
5. Deploy. You'll get a URL like `https://wake-judge-xxxx.onrender.com`.
   Test it: open `https://…onrender.com/healthz` → should show `{"ok":true}`.

### Keep it warm (avoid the 6am cold start)
Render's free tier **sleeps after 15 min idle** and takes ~50s to wake — bad exactly when
you're standing there groggy. Two defenses, use both:

- **Overnight pinger:** create a free [UptimeRobot](https://uptimerobot.com) monitor that
  GETs `https://…onrender.com/healthz` every 5 minutes. Keeps the server awake 24/7.
- **App pre-warm:** the app already pings `/healthz` the moment your wake sequence starts
  (`AppState.prewarmJudge`), so it's warm by the time you speak. No action needed.

---

## Part B — Point the app at your backend

In [`Wake/App/Config.swift`](Wake/App/Config.swift):
```swift
static let matchBackendURL: URL? = URL(string: "https://wake-judge-xxxx.onrender.com")
```
Set `WakeBackendSecret` in Info.plist (or Keychain) to the **same** `WAKE_APP_SECRET`
you used on Render, and turn on cloud judging (the toggle / `Config.cloudMatchEnabled`).
Offline or if the server is down, the app judges fully on-device — it never gets stuck.

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

That's it — the app stays installed, refreshes itself, and talks to your hosted backend.
Free, private, and shareable with the people you choose.

---

## What each person needs
| | You | A friend you share with |
|---|---|---|
| The `.ipa` file | build it once | you send it to them |
| Backend | you deploy once (shared by all) | nothing |
| Gemini key | yours (on the server) | nothing |
| SideStore + free Apple ID | yes | yes (their own) |

## Honest limits on this free path
- **7-day signature** is a free-Apple-ID rule; SideStore's background refresh hides it, but if a device is offline for >7 days the app needs a manual refresh.
- **Alarm reliability:** without a paid account + Critical Alerts/AlarmKit, the escalation is time-sensitive **notifications**, not a guaranteed silent-mode override. Fine for personal use; know the ceiling.
- **Render free tier** can still be briefly slow after long idle despite the pinger — the on-device fallback covers those moments.
