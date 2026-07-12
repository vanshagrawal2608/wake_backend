"""
Smoke test for the /judge endpoint — proves the Gemini key + model work end-to-end.

Usage (server running in another terminal, WAKE_APP_SECRET set here too):
    python test_match.py path/to/morning.aiff

Make a clip fast with macOS `say`:
    say -o /tmp/awake.aiff "I'm awake"
    say -o /tmp/wrong.aiff "where is my coffee"
    python test_match.py /tmp/awake.aiff
    python test_match.py /tmp/wrong.aiff
"""

import base64
import os
import sys

import requests

SECRET = os.environ.get("WAKE_APP_SECRET")
if not SECRET:
    sys.exit("WAKE_APP_SECRET not set in this terminal. Re-run:\n"
             "  export WAKE_APP_SECRET=<the value the server is using>")

if len(sys.argv) != 2:
    sys.exit("Usage: python test_match.py <morning.aiff>")

path = sys.argv[1]
ext = os.path.splitext(path)[1].lower()
mime = {".aiff": "audio/aiff", ".aif": "audio/aiff", ".m4a": "audio/mp4",
        ".mp4": "audio/mp4", ".wav": "audio/wav", ".mp3": "audio/mp3"}.get(ext, "audio/mp4")

with open(path, "rb") as f:
    audio_b64 = base64.b64encode(f.read()).decode()

payload = {
    "morning_audio_b64": audio_b64,
    "audio_mime": mime,
    "heard_phrase": True,
    "local_clarity": 0.6,
}

print("Posting to http://localhost:8000/judge ...")
resp = requests.post(
    "http://localhost:8000/judge",
    json=payload,
    headers={"Authorization": f"Bearer {SECRET}"},
    timeout=30,
)
print("HTTP", resp.status_code)
print(resp.text)
