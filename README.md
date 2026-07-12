# Wake — Adaptive AI Alarm

Wake is not an alarm clock. You tell it **when you need to be out of bed**; it decides when to *begin* disturbing your sleep, how gently to start, how fast to escalate, and when to stop — and it learns your personal wake curve over time.

> Objective: **maximise sleep while guaranteeing you're fully awake exactly when you need to be.**

This folder contains two things:

| | What | Where |
|---|---|---|
| 🖥️ **Mockup** | An interactive dark-mode web prototype of the UX, for fast feedback | [`mockup/index.html`](mockup/index.html) |
| 📱 **App** | The real SwiftUI iOS project (scalable architecture) | [`Wake/`](Wake/) |
| ☁️ **Backend** | Voice-match proxy (keeps the API key off the phone) | [`backend/`](backend/) |

---

## The iOS reality (read this first)

Building a *reliable* escalating alarm on iOS is genuinely constrained. I'm designing **around** Apple's rules, not hacking against them. Here's the honest picture and how Wake handles each limit:

| What we want | iOS constraint | Wake's native approach |
|---|---|---|
| An alarm that **breaks through silent mode & Focus** at the deadline | Only the system Clock app had this — until **AlarmKit (iOS 26)**, which finally exposes it to third-party apps. | `AlarmScheduler` targets **AlarmKit** for the guaranteed deadline alarm. On < iOS 26 we fall back to **Critical Alerts** (requires a one-time Apple entitlement) + a scheduled notification ladder. |
| The **gentle → loud escalation ladder** (7 stages) | Apps can't freely run code in the background or raise volume on a timer. | Two layers: (1) a chain of **pre-scheduled local notifications** at each stage time (works fully in background), and (2) when the app *is* foregrounded during the window, an **`AVAudioSession`** plays the actual soundscape and ramps volume. AlarmKit backstops the final stages. |
| **"Gentle music keeps playing"** through the early stages | Background audio is allowed *only* with the `audio` background mode and real playback. | We use the `audio` background mode legitimately (we are genuinely playing a wake soundscape), the same mechanism Sleep Cycle/Alarmy use. |
| **Voice "I'm awake"** that only stops the alarm if you *sound* awake | On-device speech + audio needs the app active; you can't record arbitrarily in the background. | `VoiceWakeVerifier` uses the **Speech** framework on-device. It runs when the alarm UI is foregrounded (the alarm brings the app forward). "Sounds awake" is a transparent **heuristic** (response latency + speech-rate + clarity), not magic — documented as such. |
| **Sleep detection** without the user pressing "I'm going to bed" | No true background "is the user asleep" signal. | `SleepDetectionService` *infers* sleep start from: charging + screen-lock + prolonged inactivity + Focus/Sleep schedule, and reconciles against **HealthKit** sleep samples the next morning. |

Bottom line: the **deadline is guaranteed** (AlarmKit / Critical Alerts). The **gentle pre-wake ladder is best-effort** and degrades gracefully to notifications when iOS won't let us run — which is exactly the right trade for a sleep app.

---

## Architecture

Three AI modules, cleanly separated behind protocols so each can start as a heuristic and later be swapped for CoreML — without touching the UI.

```
┌─────────────── SwiftUI (Features) ───────────────┐
│  Tonight (Home)   Wake (Live)   Insights (Dash)  │
└───────────────┬──────────────────────────────────┘
                │  observes
        ┌───────▼────────┐
        │    AppState     │  single source of truth (@Observable)
        └───┬───┬───┬───┬─┘
   ┌────────┘   │   │   └──────────┐
   ▼            ▼   ▼              ▼
SleepDetection  WakePrediction   AlarmScheduler   VoiceWakeVerifier
 (infer sleep)  (compute curve)  (fire the ladder)(judge "awake")
        \           │            /
         \          ▼           /
          ─────► WakeStore ◄────   (Codable persistence of every WakeRecord)
                    │
                 LearningEngine  (recency-weighted wake-duration model → CoreML later)
```

### Modules

- **`Services/SleepDetection`** — `SleepDetectionService` protocol + `HeuristicSleepDetector`. Signal fusion (inactivity, charge, lock, Focus, HealthKit). Extensible `SleepSignal` enum so new inputs (Watch, calendar, weather) plug in without breaking callers.
- **`Services/WakePrediction`** — `WakePredictionEngine`. Turns history → a `WakePlan` (7 timed `WakeStage`s). Starts as a recency-weighted average of past *wake durations*; the `PredictionInputs` struct already carries weekday/sleep-debt/screen-time fields for the future model.
- **`Services/AlarmScheduler`** — `AlarmScheduling` protocol with a `NotificationAlarmScheduler` today and an `AlarmKitScheduler` seam for iOS 26.
- **`Services/Voice`** — `VoiceWakeVerifier`, on-device Speech + a `Wakefulness` score.
- **`Services/Learning`** — `WakeStore` (persistence) + `LearningEngine` (the model). The whole point of separation: swap heuristic → CoreML behind `WakeDurationModel`.

### Voice judging — clarity of "I'm awake", no baseline

There's **no enrollment**. The decision is how clearly you said the exact phrase, judged on-device first and by Gemini only when unsure ([`WakeJudge.swift`](Wake/Wake/Services/Voice/WakeJudge.swift)):

```
                heard "I'm awake"?  ── no ──▶ reject
                       │ yes
              on-device clarity (0…1)
                       │
        ┌──────────────┴───────────────┐
   ≥ 0.80 (clear)             < 0.80 (unsure)
        │                            │
   accept locally      online? ──no──▶ accept if ≥ 0.65, else reject
                            │ yes
                  send THIS clip to Gemini
                  (transcribe → verify "I'm awake"
                   → judge alert vs groggy, absolute)
                       │ unreachable → offline bar
```

- **No baseline** — judged in absolute terms ("does this sound like a clear, alert 'I'm awake'?"), not against a personal recording. Simpler, zero setup; the *plan* is still personalized via the onboarding wake-speed.
- **Gemini only when unsure**, and it still **transcribes and rejects wrong words** before judging alertness.
- **Offline → fully on-device**, alarm always dismissible. Gemini Flash is audio-native (raw clip, no spectrogram).
- **Default: the app calls Gemini directly** ([`GeminiDirectJudge`](Wake/Wake/Services/Voice/GeminiDirectJudge.swift)) with your own key (from a gitignored `Secrets.xcconfig`, protected by a budget cap) — no server to run. The [`backend/`](backend/) proxy is kept as an optional path if you ever go public and want the key off-device.

**Local scoring fix:** `clarity` was being counted twice (once inside the match score, once alongside it). It's now **excluded from the match score** ([`VoiceSignature.similarity`](Wake/Wake/Services/Voice/VoiceSignature.swift) is purely the other acoustic features) and added once in the final judgment: `judgment = clarity·0.5 + matchScore·0.5`.

### Design system
`DesignSystem/Theme.swift` — the night→dawn palette (intensity = warmth), spacing, and reusable card/label styles that make every screen feel like one app.

---

## Build & run it on your iPhone

There's no Xcode on this machine, so I generated the **source + an XcodeGen spec** rather than a binary `.xcodeproj`. Two ways to get it running:

**Option A — XcodeGen (cleanest)**
```bash
brew install xcodegen
cd Wake
xcodegen generate      # creates Wake.xcodeproj from project.yml
open Wake.xcodeproj
```

**Option B — no tools:** In Xcode, *File ▸ New ▸ Project ▸ iOS App* (SwiftUI, name `Wake`), delete the stub files, then drag the folders under `Wake/Wake/` in.

Then, to get it **on your device**:
1. Select your iPhone as the run target, set your Apple ID under *Signing & Capabilities* (free personal team works for 7-day installs).
2. **Run** (⌘R) — it installs directly.
3. For a persistent, shareable build → **Archive ▸ Distribute ▸ TestFlight**. TestFlight is the real "download it on my iOS later" path. AlarmKit + Critical Alerts need a paid developer account and an entitlement request; until then the notification-ladder fallback runs.

Capabilities to enable in Xcode: **Background Modes → Audio**, **Push/Local Notifications**, **HealthKit** (read sleep), **Speech Recognition**, **Microphone**. `Info.plist` usage strings are listed in [`Wake/Resources/Info-keys.md`](Wake/Resources/Info-keys.md).

---

## Status

Working foundation — architecture, models, the ember design system, three screens, and heuristic engines, all wired through `AppState`. Device APIs are now **real implementations**, not stubs:

| Area | State |
|---|---|
| **Voice wakefulness** | ✅ Real `AVAudioEngine` + on-device `SFSpeechRecognizer`. **No enrollment** — the morning utterance must be the exact phrase *"I'm awake"*, scored by recognizer **clarity**. Clear (≥0.80) → accept on-device; unsure → Gemini judges the single clip (transcribe → verify words → alert-vs-groggy); offline → accept ≥0.65. See [`WakeJudge.swift`](Wake/Wake/Services/Voice/WakeJudge.swift). |
| **HealthKit sleep** | ✅ Real `HKSampleQuery` over `.sleepAnalysis`, picks the earliest asleep segment as authoritative sleep start. |
| **Audio ramp** | ✅ `AudioRampPlayer` with a quadratic volume curve and smooth per-stage ramps over a background `.playback` session. Needs bundled soundscape assets (`birdsong.m4a`, etc.) — marked `// TODO(device)`. |
| **Notification ladder** | ✅ Free-signing friendly (`.timeSensitive`/`.active`, `.default` sound — no paid entitlement). |
| **AlarmKit / Critical Alerts** | Seam only — needs a paid account. Not on the free-signing path you chose. |

Two things still need a real device to exercise fully: the Speech/mic capture (the simulator falls back to a stubbed reading) and the soundscape audio files.

See the mockup for the intended feel, then tell me what to change.
