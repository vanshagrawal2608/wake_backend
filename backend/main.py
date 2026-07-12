"""
Wake — voice-judge backend proxy (Gemini 2.5 Flash).

No enrollment/baseline. The app sends a single morning clip (the person should say
"I'm awake") plus the on-device clarity score. Gemini transcribes it, checks it's the
wake phrase, and judges whether it sounds alert or groggy — in absolute terms, since
there's no personal baseline to compare against. Returns a small JSON verdict.

The app calls this only when its own local clarity check is uncertain and it's online,
so most mornings never hit the network.

Privacy: nothing is persisted. Auth: a shared bearer secret gates the endpoint.
"""

import base64
import json
import os

from fastapi import FastAPI, Header, HTTPException
from google import genai
from google.genai import types
from pydantic import BaseModel, Field

MODEL = "gemini-flash-latest"   # rolling alias → current stable Flash (audio-capable)
APP_SHARED_SECRET = os.environ["WAKE_APP_SECRET"]
client = genai.Client(api_key=os.environ["GEMINI_API_KEY"])

app = FastAPI(title="Wake voice-judge proxy (Gemini)")


class JudgeRequest(BaseModel):
    morning_audio_b64: str = Field(..., description="The morning utterance")
    audio_mime: str = "audio/mp4"
    heard_phrase: bool = Field(..., description="Did on-device recognition hear 'I'm awake'?")
    local_clarity: float = Field(..., description="The app's on-device 0..1 clarity score")


VERDICT_SCHEMA = {
    "type": "object",
    "properties": {
        "heard_text": {"type": "string", "description": "What the clip actually says, transcribed."},
        "said_wake_phrase": {"type": "boolean", "description": "Does it say 'I'm awake'?"},
        "is_awake": {"type": "boolean"},
        "awake_confidence": {"type": "number", "description": "0..1 how clearly/alertly spoken"},
        "sounds_groggy": {"type": "boolean"},
        "reasoning": {"type": "string"},
    },
    "required": ["heard_text", "said_wake_phrase", "is_awake",
                 "awake_confidence", "sounds_groggy", "reasoning"],
}

INSTRUCTION = (
    "You judge whether a person is awake from ONE short recording in which they were asked "
    "to say \"I'm awake\".\n"
    "STEP 1 — Transcribe the clip into `heard_text`. It must be the wake phrase \"I'm awake\" "
    "(accept 'im awake' / 'i am awake'). If it says anything else, or is mumbled past "
    "recognition, set said_wake_phrase=false, is_awake=false, and stop.\n"
    "STEP 2 — Only if they said the phrase, judge how AWAKE they sound. There is NO personal "
    "baseline, so judge in absolute terms: a clear, promptly and crisply spoken \"I'm awake\" "
    "means awake; a slurred, mumbled, dragging, hesitant, or half-swallowed one means groggy. "
    "Err toward NOT awake when it's unclear.\n"
    "is_awake is true ONLY when they clearly said \"I'm awake\" AND it sounds alert. "
    "awake_confidence is your 0..1 clarity/alertness rating. Keep reasoning to one short "
    "sentence a person could read on a lock screen."
)


@app.post("/judge")
def judge(req: JudgeRequest, authorization: str = Header(default="")):
    if authorization != f"Bearer {APP_SHARED_SECRET}":
        raise HTTPException(status_code=401, detail="unauthorized")

    audio = base64.b64decode(req.morning_audio_b64)
    context = (
        f"On-device recognizer heard the exact phrase 'I'm awake': {req.heard_phrase}. "
        f"The app's on-device clarity score was {req.local_clarity:.2f} (uncertain — that's "
        "why you were called). Judge the recording."
    )

    try:
        response = client.models.generate_content(
            model=MODEL,
            contents=[
                INSTRUCTION,
                types.Part.from_bytes(data=audio, mime_type=req.audio_mime),
                context,
            ],
            config=types.GenerateContentConfig(
                response_mime_type="application/json",
                response_schema=VERDICT_SCHEMA,
                temperature=0.0,
            ),
        )
    except Exception as e:  # any model/transport error → app falls back on-device
        raise HTTPException(status_code=502, detail=f"model error: {e}") from e

    return json.loads(response.text)


@app.get("/healthz")
def healthz():
    return {"ok": True}
