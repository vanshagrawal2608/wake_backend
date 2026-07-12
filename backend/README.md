# Wake voice-judge backend (Gemini) — OPTIONAL

> **Not used on the default (personal) setup.** The app now calls Gemini **directly**
> ([`GeminiDirectJudge`](../Wake/Wake/Services/Voice/GeminiDirectJudge.swift)) with your own
> key — no server needed (see [`../GO-LIVE.md`](../GO-LIVE.md)). Keep this backend only if you
> later go **public** and want the key off-device.

A thin proxy so the iPhone never holds the API key. It receives the morning "I'm awake"
clip, asks **Gemini** (audio-native) to judge it, and returns a small JSON verdict.

```
POST /match
  Authorization: Bearer <WAKE_APP_SECRET>
  { baseline_audio_b64, morning_audio_b64, audio_mime,
    baseline_features, morning_features, heard_phrase, local_judgment }
→ { is_awake, match_confidence, sounds_groggy, reasoning }
```

The app calls this **only when its local judgment is uncertain (≤ 0.80) and it's
online** — so most mornings never touch the network.

## Run locally
```bash
cd Wake/backend
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
export GEMINI_API_KEY=...                # your Google AI Studio key, server-side only
export WAKE_APP_SECRET=$(openssl rand -hex 24)
uvicorn main:app --reload --port 8000
```
Point the app's `Config.matchBackendURL` at `http://<your-mac-ip>:8000` and set the
same `WAKE_APP_SECRET` in the app (Keychain / Info.plist `WakeBackendSecret`).

## Why Gemini here
Gemini 2.5 Flash ingests **raw audio** directly, so there's no spectrogram
workaround — the actual voice clips are compared. `Flash` keeps latency and cost low
for a 6am call. The app's `VoiceMatcher` seam means you can swap in another provider
without touching the UI.

## Before shipping
- Replace the shared-secret bearer with real per-user auth (single shared token is
  fine for a private TestFlight build, not for public release).
- Add rate limiting and request-size caps (audio clips are a few hundred KB).
- Do **not** log request bodies — they contain voice data. Nothing is persisted here.
- Serve over HTTPS.
