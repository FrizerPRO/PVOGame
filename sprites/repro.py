#!/usr/bin/env python3
"""Minimal Nano Banana Pro reproduction against api.artemox.com.

Reproduces the Cloudflare 403 "Just a moment..." challenge we hit when calling
gemini-3-pro-image-preview through the artemox proxy.

Reads the API key from ~/.google-genai/config (line `GEMINI_API_KEY=sk-...`).
"""
import sys
from pathlib import Path

from google import genai
from google.genai import types

CONFIG = Path.home() / ".google-genai" / "config"
API_KEY = next(
    (line.split("=", 1)[1].strip()
     for line in CONFIG.read_text().splitlines()
     if line.strip().startswith("GEMINI_API_KEY=") and line.split("=", 1)[1].strip()),
    None,
) or sys.exit(f"no GEMINI_API_KEY in {CONFIG}")
BASE_URL = "https://api.artemox.com"
MODEL = "gemini-3-pro-image-preview"

client = genai.Client(
    api_key=API_KEY,
    http_options=types.HttpOptions(base_url=BASE_URL),
)

# Streaming: the proxy keeps the connection alive with keepalive chunks so
# Cloudflare's 100s origin cap (HTTP 524) doesn't kill slow image generations.
stream = client.models.generate_content_stream(
    model=MODEL,
    contents="red sports car",
    config=types.GenerateContentConfig(
        response_modalities=["IMAGE"],
        image_config=types.ImageConfig(aspect_ratio="1:1", image_size="1K"),
    ),
)

for chunk in stream:
    for part in chunk.candidates[0].content.parts:
        if part.inline_data:
            with open("out.png", "wb") as f:
                f.write(part.inline_data.data)
            print("saved out.png")
            sys.exit(0)

sys.exit("no image in response")
