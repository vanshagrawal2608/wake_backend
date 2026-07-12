"""Print the Gemini models this API key can use for generateContent."""
import os
from google import genai

client = genai.Client(api_key=os.environ["GEMINI_API_KEY"])
for m in client.models.list():
    actions = getattr(m, "supported_actions", None) or getattr(m, "supported_generation_methods", [])
    if not actions or "generateContent" in actions:
        print(m.name, "|", actions)
