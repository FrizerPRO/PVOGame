"""Shared sprite-generation helpers for PVOGame.

Holds common prompt clauses, the prompt builder, the Gemini 3 Pro Image
("Nano Banana Pro") API wrapper, and the post-processing pipeline.

The model has a fixed set of output aspect ratios (1:1, 2:3, 3:2, 3:4, 4:3,
9:16, 16:9, 21:9, 4:5, 5:4) and image sizes (1K/2K/4K). It cannot produce
transparent backgrounds — sprites are generated on a solid colour and the
background is removed in post-processing.
"""

from __future__ import annotations

import os
import threading
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

from google import genai
from google.genai import types
from PIL import Image
import numpy as np


# ---------------------------------------------------------------------------
# API key discovery
# ---------------------------------------------------------------------------

API_KEY_CONFIG_DIR = Path.home() / ".google-genai"
API_KEY_CONFIG_FILE = API_KEY_CONFIG_DIR / "config"

API_KEY_TEMPLATE = """\
# google-genai / Gemini API key for PVOGame sprite generation.
#
# Fill in GEMINI_API_KEY below — the key is read by both the CLI
# (sprites/generate_sprites.py) and the local web UI (sprites/web_ui.py)
# when --api-key is not passed explicitly.
#
# Discovery order (first non-empty wins):
#   1. --api-key / form field
#   2. $GEMINI_API_KEY or $GOOGLE_API_KEY env var
#   3. this file
#
# This file should be chmod 600 — only your user can read it.

GEMINI_API_KEY=
"""


def _parse_env_file(path: Path) -> dict[str, str]:
    """Minimal .env parser: strips comments, blank lines, surrounding quotes.
    Unknown lines are silently ignored so the file stays forgiving to edit by hand."""
    out: dict[str, str] = {}
    try:
        text = path.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError):
        return out
    for raw in text.splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if "=" not in line:
            continue
        key, _, value = line.partition("=")
        key = key.strip()
        value = value.strip().strip('"').strip("'")
        if key:
            out[key] = value
    return out


def ensure_api_key_config_file() -> Path:
    """Create ~/.google-genai/config with a template if it doesn't exist.
    Returns the path. Sets chmod 700 on the dir and 600 on the file."""
    API_KEY_CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    try:
        os.chmod(API_KEY_CONFIG_DIR, 0o700)
    except OSError:
        pass
    if not API_KEY_CONFIG_FILE.exists():
        API_KEY_CONFIG_FILE.write_text(API_KEY_TEMPLATE, encoding="utf-8")
    try:
        os.chmod(API_KEY_CONFIG_FILE, 0o600)
    except OSError:
        pass
    return API_KEY_CONFIG_FILE


def resolve_api_key(explicit: str | None = None) -> str | None:
    """Resolve the Gemini API key in this priority order:

    1. `explicit` argument (from --api-key or the web UI form)
    2. environment variable `$GEMINI_API_KEY` or `$GOOGLE_API_KEY`
    3. `~/.google-genai/config` file (`.env`-format, `GEMINI_API_KEY=...`)

    Returns None if nothing is set anywhere.
    """
    if explicit and explicit.strip():
        return explicit.strip()
    for env_var in ("GEMINI_API_KEY", "GOOGLE_API_KEY"):
        v = os.environ.get(env_var, "").strip()
        if v:
            return v
    if API_KEY_CONFIG_FILE.exists():
        env = _parse_env_file(API_KEY_CONFIG_FILE)
        for k in ("GEMINI_API_KEY", "GOOGLE_API_KEY"):
            v = env.get(k, "").strip()
            if v:
                return v
    return None


# Wall-clock deadline for a single streaming attempt. Protects against the
# pathological case where the proxy keeps the connection alive with keepalive
# chunks but never delivers the actual image — in that scenario HttpOptions.timeout
# resets on every keepalive and the loop would otherwise spin forever.
#
# Successful generations empirically run 30-80s on Nano Banana Pro; 180s is a
# generous buffer before we abandon the thread. Paired with a small max_retries
# default, a stuck sprite surfaces as a failure within a few minutes instead of
# blocking the whole UI for 15-50 min.
STREAM_WALL_CLOCK_SECONDS = 180.0


class StreamDeadlineExceeded(TimeoutError):
    """Raised when the streaming generate loop runs past STREAM_WALL_CLOCK_SECONDS
    without producing an image. The outer retry policy treats this as a transient
    timeout and retries with backoff."""


MODEL = "gemini-3-pro-image-preview"
DEFAULT_BASE_URL = "https://api.artemox.com"

SUPPORTED_ASPECTS = {
    "1:1", "2:3", "3:2", "3:4", "4:3",
    "9:16", "16:9", "21:9", "4:5", "5:4",
}
SUPPORTED_IMAGE_SIZES = {"1K", "2K", "4K"}


# ---------------------------------------------------------------------------
# Shared prompt clauses
# ---------------------------------------------------------------------------

VIEW_TOPDOWN = (
    "CRITICAL REQUIREMENT: This sprite MUST be drawn in a STRICT TOP-DOWN / BIRD'S-EYE VIEW "
    "(camera looking straight down from above). No isometric, no 3/4 view, no side view, "
    "no perspective — purely overhead as if photographed by a satellite."
)

VIEW_TOPDOWN_REMINDER = (
    "REMINDER: Strictly top-down overhead view. The camera is directly above looking straight down. "
    "No tilted perspective."
)

VIEW_SIDE = (
    "Side view. The subject is drawn in strict side profile, pointing upward toward the top edge "
    "of the image. The subject floats alone with nothing around it."
)

STYLE_CARTOON = (
    "2D cartoon style like Plants vs Zombies / Kingdom Rush — bold outlines, simplified shapes, "
    "flat colors with soft cel-shading, minimal surface detail. Not photorealistic."
)

BG_WHITE = (
    "Solid pure white background (#FFFFFF). No gradients, no ground plane, no shadows on background. "
    "The object floats on perfectly flat white."
)

BG_BLACK = (
    "CRITICAL: The background MUST be solid pure black (#000000) — not white, not gray, not "
    "transparent, not a light color. The entire area around the subject is filled with pure black. "
    "No gradients, no ground plane, no shadows on background. The subject (a glow or bright effect) "
    "is drawn ON TOP OF this pure black backdrop."
)

# Every bg=black sprite runs through alpha extraction from luminosity, so a dark
# cartoon outline (which the model tends to draw by default) would get eaten by
# the extractor and leave a torn / shrunken sprite. This clause is auto-appended
# to every bg=black prompt so we never forget it per-sprite.
BG_BLACK_NO_OUTLINE = (
    "NO black outline, NO dark border, NO hard cartoon edge around the effect — "
    "only soft light fading smoothly into the black background. Edges must dissolve "
    "by luminosity, not by a drawn line."
)

BG_FILL = (
    "The sprite MUST fill the entire frame edge-to-edge — there is NO surrounding background. "
    "The subject occupies the full image, with content extending right up to all four edges."
)

NO_JUNK = "No text, no labels, no watermarks, no photorealism, no 3D rendering."

STYLE_REF_PREAMBLE = (
    "Below is a STYLE REFERENCE ONLY — a different sprite from the same game. "
    "Copy ONLY the rendering style: cartoon line weight, flat cel-shading, color saturation level. "
    "Do NOT copy the shape, layout, composition, perspective, or subject matter from it. "
    "The sprite you generate must look completely different — it is a different object."
)

# Used when refs are frames of the SAME animation (fire → grow → smoke → dissipate).
# We explicitly want shape/center/palette carried over — the opposite of STYLE_REF_PREAMBLE.
TEMPORAL_REF_PREAMBLE = (
    "Below are TEMPORAL REFERENCE FRAMES from the same animation sequence. "
    "PRESERVE the exact center alignment of the effect, canvas composition, color palette, "
    "line style, cartoon treatment, and overall visual footprint — this frame must look like "
    "the next-in-time step from the reference, not a different effect. "
    "ONLY the stage of the effect evolves (size, brightness, smoke mix); everything else stays fixed."
)


# ---------------------------------------------------------------------------
# Sprite model + prompt assembly
# ---------------------------------------------------------------------------

@dataclass
class Sprite:
    name: str
    view: str           # "topdown" | "side" | "none"
    bg: str             # "white" | "black"
    aspect: str         # one of SUPPORTED_ASPECTS
    subject: str
    palette: str = ""
    refs: tuple = ()    # names of other sprites whose raw output is used as a reference
    image_size: str = "1K"
    extra: str = ""     # sprite-specific emphasis ("IMPORTANT: Do NOT draw the truck body" etc.)
    # ref_mode="style"    → default: refs are DIFFERENT subjects, carry only rendering style
    # ref_mode="temporal" → refs are earlier frames of the SAME animation/effect; preserve
    #                       center alignment, composition, palette — evolve only the stage
    ref_mode: str = "style"
    # alpha_mode="auto"       → use bg-default algorithm:
    #                             bg=white  → remove_bg_by_color (corner sampling)
    #                             bg=black  → luminosity_to_alpha (bright = opaque, dark = transparent)
    #                             bg=fill   → no removal
    # alpha_mode="luminosity" → force luminosity-based alpha; good for pure glows / flashes where
    #                            faint-brightness == faint-alpha is desired
    # alpha_mode="keyed"      → force chroma-key against the background color; non-background
    #                            pixels stay fully opaque. Use for bg=black sprites where the
    #                            subject is INHERENTLY DARK (smoke, dust, silhouettes) — luminosity
    #                            would collapse dark gray smoke to 30% opacity.
    alpha_mode: str = "auto"

    def __post_init__(self):
        if self.aspect not in SUPPORTED_ASPECTS:
            raise ValueError(
                f"{self.name}: aspect_ratio {self.aspect!r} not supported by Gemini 3 Pro Image. "
                f"Allowed: {sorted(SUPPORTED_ASPECTS)}"
            )
        if self.image_size not in SUPPORTED_IMAGE_SIZES:
            raise ValueError(
                f"{self.name}: image_size {self.image_size!r} not supported. "
                f"Allowed: {sorted(SUPPORTED_IMAGE_SIZES)}"
            )
        if self.view not in {"topdown", "side", "none"}:
            raise ValueError(f"{self.name}: unknown view {self.view!r}")
        if self.bg not in {"white", "black", "fill"}:
            raise ValueError(f"{self.name}: unknown bg {self.bg!r}")
        if self.ref_mode not in {"style", "temporal"}:
            raise ValueError(f"{self.name}: unknown ref_mode {self.ref_mode!r}")
        if self.alpha_mode not in {"auto", "luminosity", "keyed"}:
            raise ValueError(f"{self.name}: unknown alpha_mode {self.alpha_mode!r}")


def build_prompt(sp: Sprite) -> str:
    """Assemble the final prompt from shared clauses + per-sprite unique fields."""
    blocks: list[str] = []

    if sp.view == "topdown":
        blocks.append(VIEW_TOPDOWN)
    elif sp.view == "side":
        blocks.append(VIEW_SIDE)

    body = sp.subject.strip()
    if sp.palette:
        body += f"\n\nPalette: {sp.palette.rstrip('.')}."
    blocks.append(body)

    if sp.extra:
        blocks.append(sp.extra.strip())

    blocks.append(STYLE_CARTOON)
    if sp.bg == "white":
        blocks.append(BG_WHITE)
    elif sp.bg == "black":
        blocks.append(BG_BLACK)
        blocks.append(BG_BLACK_NO_OUTLINE)
    else:  # fill
        blocks.append(BG_FILL)
    blocks.append(NO_JUNK)

    if sp.view == "topdown":
        blocks.append(VIEW_TOPDOWN_REMINDER)

    return "\n\n".join(blocks)


# ---------------------------------------------------------------------------
# API + post-processing
# ---------------------------------------------------------------------------

def make_client(api_key: str, base_url: str = DEFAULT_BASE_URL, timeout_ms: int = 600_000):
    """Build the Gemini client.

    `timeout_ms` is the HTTP client read timeout in milliseconds. Default is 10 minutes —
    image generation on Nano Banana Pro routinely takes 1-3 minutes and can spike higher
    under load. Raising this does NOT bypass Cloudflare's 100s origin limit (which
    surfaces as HTTP 524), but it does stop the client from giving up too early when
    the proxy is slow but still delivering.
    """
    return genai.Client(
        api_key=api_key,
        http_options=types.HttpOptions(base_url=base_url, timeout=timeout_ms),
    )


def generate(
    client,
    prompt: str,
    ref_images: Iterable[bytes] = (),
    aspect_ratio: str = "1:1",
    image_size: str = "1K",
    seed: int | None = None,
    ref_mode: str = "style",
) -> bytes | None:
    """Call the model with prompt + optional reference images.

    `ref_mode` controls how the model should treat the ref images:
    - "style"    — refs are different subjects; copy rendering style only, NOT shape/layout.
                   Used for cross-sprite style transfer (e.g. one drone referencing another).
    - "temporal" — refs are earlier frames of the SAME animation; preserve center alignment,
                   composition, palette — evolve only the stage. Used for explosion frame
                   chains and any animated VFX where temporal continuity matters more than
                   visual variety.

    Uses `generate_content_stream` so the proxy can hold the connection open with
    keepalive chunks — necessary for image generation that routinely takes 30-80s
    (Cloudflare's 100s origin timeout kills non-streaming requests with HTTP 524).

    Returns the raw PNG bytes from the response, or None if no image came back.
    """
    ref_images = list(ref_images)
    if ref_images:
        preamble = TEMPORAL_REF_PREAMBLE if ref_mode == "temporal" else STYLE_REF_PREAMBLE
        parts = [
            "Generate the following game sprite:\n\n" + prompt + "\n\n---\n" + preamble
        ]
        for img_bytes in ref_images:
            parts.append(types.Part.from_bytes(data=img_bytes, mime_type="image/png"))
        contents = parts
    else:
        contents = prompt

    config_kwargs = dict(
        response_modalities=["IMAGE"],
        image_config=types.ImageConfig(aspect_ratio=aspect_ratio, image_size=image_size),
    )
    if seed is not None:
        config_kwargs["seed"] = seed

    # Consume the stream on a daemon worker thread with a hard `join(timeout)`.
    #
    # The deadline MUST cover both phases:
    #   (a) `generate_content_stream(...)` — initiates the HTTP request. Under
    #       httpx this blocks until the server sends status + the first body
    #       chunk. Observed in practice (2026-04): a proxy that accepted the
    #       request but never emitted the first chunk pinned us here for
    #       minutes with no output — `HttpOptions.timeout` (10 min) was the
    #       only bound, because our own deadline didn't exist yet.
    #   (b) the `for chunk in stream:` iteration — where keepalive chunks can
    #       leave `next()` blocked deep inside httpx even though nothing
    #       useful is arriving.
    #
    # So the stream is both created AND consumed inside the worker. The main
    # thread owns the deadline via `thread.join(deadline)` regardless of which
    # phase is stuck. If the worker doesn't return by the deadline we abandon
    # it — one leaked HTTP connection per hang, cleaned up when the process
    # exits. The outer `generate_with_retry` treats StreamDeadlineExceeded as
    # transient.
    #
    # We also collect non-image response fragments so we can surface a useful
    # diagnostic when the stream completes without any image. In practice this
    # happens when the model refuses (content policy) or answers with a
    # text-only explanation like "I can't generate that image" — without this
    # capture the caller just sees `None` and has no clue why.
    result: dict = {
        "data": None,
        "exc": None,
        "stream": None,           # set by worker once generate_content_stream returns
        "text_fragments": [],     # all part.text pieces across the stream
        "finish_reason": None,    # usually set on the last chunk
        "safety_ratings": None,   # list of category/probability when safety blocks
    }

    def _consume() -> None:
        try:
            stream = client.models.generate_content_stream(
                model=MODEL,
                contents=contents,
                config=types.GenerateContentConfig(**config_kwargs),
            )
            result["stream"] = stream
            for chunk in stream:
                candidates = getattr(chunk, "candidates", None) or []
                if not candidates:
                    continue
                cand = candidates[0]
                if getattr(cand, "finish_reason", None):
                    result["finish_reason"] = str(cand.finish_reason)
                if getattr(cand, "safety_ratings", None):
                    result["safety_ratings"] = [
                        f"{getattr(r, 'category', '?')}={getattr(r, 'probability', '?')}"
                        for r in cand.safety_ratings
                    ]
                content = getattr(cand, "content", None)
                if content is None:
                    continue
                for part in content.parts or []:
                    inline = getattr(part, "inline_data", None)
                    if inline and inline.mime_type and inline.mime_type.startswith("image/"):
                        result["data"] = inline.data
                        return
                    text = getattr(part, "text", None)
                    if text:
                        result["text_fragments"].append(text)
        except BaseException as e:
            result["exc"] = e

    worker = threading.Thread(target=_consume, daemon=True, name="genai-stream-consumer")
    worker.start()
    worker.join(STREAM_WALL_CLOCK_SECONDS)
    if worker.is_alive():
        # Best-effort: try to close the stream so the worker can unwind. genai
        # may or may not expose a close method — ignore any failure. The stream
        # may also be None if the worker is still stuck inside
        # `generate_content_stream(...)` itself, before it returned an iterator.
        stream = result["stream"]
        if stream is not None:
            for attr in ("close", "aclose"):
                closer = getattr(stream, attr, None)
                if callable(closer):
                    try:
                        closer()
                    except Exception:
                        pass
        phase = "iterating stream" if stream is not None else "opening stream"
        raise StreamDeadlineExceeded(
            f"stream hung past {STREAM_WALL_CLOCK_SECONDS:.0f}s while {phase} "
            f"with no image — worker thread abandoned"
        )
    if result["exc"] is not None:
        raise result["exc"]
    if result["data"] is None:
        # Stream completed normally but no image part arrived. Print whatever
        # the model DID return so the user can see refusals, safety blocks, or
        # bizarre text responses instead of just staring at a bare `FAIL`.
        diagnostic_bits: list[str] = []
        if result["finish_reason"]:
            diagnostic_bits.append(f"finish_reason={result['finish_reason']}")
        if result["safety_ratings"]:
            diagnostic_bits.append(f"safety={result['safety_ratings']}")
        if result["text_fragments"]:
            text = "".join(result["text_fragments"]).strip()
            snippet = text if len(text) <= 400 else text[:400] + "…"
            diagnostic_bits.append(f"text={snippet!r}")
        if diagnostic_bits:
            print("  [NO-IMAGE]", "  ".join(diagnostic_bits), flush=True)
        else:
            print("  [NO-IMAGE] stream ended with no image, no text, no finish_reason",
                  flush=True)
    return result["data"]


def remove_bg_by_color(img: Image.Image, threshold: float = 35, feather: float = 15) -> Image.Image:
    """Detect the background colour from the four corners and feather it to alpha=0."""
    arr = np.array(img.convert("RGBA"), dtype=np.float32)
    h, w = arr.shape[:2]
    s = max(5, min(h, w) // 20)
    corners = np.concatenate([
        arr[:s, :s, :3].reshape(-1, 3),
        arr[:s, -s:, :3].reshape(-1, 3),
        arr[-s:, :s, :3].reshape(-1, 3),
        arr[-s:, -s:, :3].reshape(-1, 3),
    ])
    bg_color = np.median(corners, axis=0)
    dist = np.sqrt(np.sum((arr[:, :, :3] - bg_color) ** 2, axis=2))
    alpha = np.clip((dist - threshold) / max(feather, 1) * 255, 0, 255)
    arr[:, :, 3] = alpha
    return Image.fromarray(arr.astype(np.uint8))


def luminosity_to_alpha(img: Image.Image) -> Image.Image:
    """For VFX sprites on a black background: alpha := max(R,G,B) so bright pixels stay."""
    arr = np.array(img.convert("RGBA"), dtype=np.float32)
    alpha = np.maximum(np.maximum(arr[:, :, 0], arr[:, :, 1]), arr[:, :, 2])
    arr[:, :, 3] = np.clip(alpha, 0, 255)
    return Image.fromarray(arr.astype(np.uint8))


def boosted_luminosity_to_alpha(img: Image.Image, boost: float = 1.8) -> Image.Image:
    """Luminosity-based alpha with a brightness multiplier.

    Pure `luminosity_to_alpha` (alpha = max(R,G,B)) collapses dark-gray smoke
    to ~20% opacity which reads as "washed out". `remove_bg_by_color` keyed
    against pure black gives the opposite extreme — 100% opaque smoke with
    hard cloud-puff edges. This function is the middle ground: boosts the
    luminosity alpha so dark smoke ends up semi-transparent-but-visible
    (60-70% opacity for mid-gray) while the soft radial falloff at edges
    is preserved (no hard edges).

    `boost=1.8` gives:
      - pure black (0)    → alpha 0    (still transparent)
      - dark gray (60)    → alpha 108  (~42% — faint smoke edge)
      - medium gray (128) → alpha 230  (~90% — main smoke body)
      - light gray (200+) → alpha 255  (fully opaque core)
    """
    arr = np.array(img.convert("RGBA"), dtype=np.float32)
    alpha = np.maximum(np.maximum(arr[:, :, 0], arr[:, :, 1]), arr[:, :, 2]) * boost
    arr[:, :, 3] = np.clip(alpha, 0, 255)
    return Image.fromarray(arr.astype(np.uint8))


def white_to_alpha_glow(img: Image.Image, noise_floor: int = 18) -> Image.Image:
    """Soft white→alpha removal for glow sprites accidentally rendered on WHITE.

    - alpha = 255 - min(R, G, B) (distance from pure white on the tightest channel)
    - pixels below `noise_floor` alpha are clamped to fully transparent to kill
      JPEG/PNG noise in near-white regions
    - the `noise_floor` band is feathered so the transition stays soft (no visible ring)
    - observed RGB is kept as-is; semi-transparent pixels look slightly milky when
      composited on black, which is acceptable for soft glows and avoids the
      noise amplification caused by unpremultiplying near-zero alpha.
    """
    arr = np.array(img.convert("RGBA"), dtype=np.float32)
    min_ch = np.min(arr[:, :, :3], axis=2)
    alpha = 255.0 - min_ch

    feather_width = max(noise_floor, 1)
    alpha = np.clip((alpha - noise_floor) / feather_width * 255.0, 0, 255)

    arr[:, :, 3] = alpha
    return Image.fromarray(arr.astype(np.uint8))


def _corner_brightness(img: Image.Image) -> float:
    """Mean max-channel across the four corners. 0 = pure black, 255 = pure white."""
    arr = np.array(img.convert("RGB"), dtype=np.float32)
    h, w = arr.shape[:2]
    s = max(5, min(h, w) // 20)
    corners = np.concatenate([
        arr[:s, :s, :].reshape(-1, 3),
        arr[:s, -s:, :].reshape(-1, 3),
        arr[-s:, :s, :].reshape(-1, 3),
        arr[-s:, -s:, :].reshape(-1, 3),
    ])
    return float(np.mean(np.max(corners, axis=1)))


def _center_brightness(img: Image.Image) -> float:
    """Mean max-channel across a small central patch. Used to distinguish
    a bright subject on a light-ish background (center ≫ corners) from a
    uniformly-bright glow on a white background (center ≈ corners)."""
    arr = np.array(img.convert("RGB"), dtype=np.float32)
    h, w = arr.shape[:2]
    s = max(5, min(h, w) // 10)
    cy, cx = h // 2, w // 2
    patch = arr[cy - s:cy + s, cx - s:cx + s, :]
    return float(np.mean(np.max(patch.reshape(-1, 3), axis=1)))


def postprocess(img: Image.Image, bg: str, alpha_mode: str = "auto") -> Image.Image:
    """Alpha-key the sprite.

    `alpha_mode` overrides the bg-default algorithm. See Sprite docstring for
    when "luminosity" vs "keyed" is appropriate — the short version is:
    glows want "luminosity" (so faint edges fade out), dark subjects on a
    black backdrop want "keyed" (so the subject stays fully opaque regardless
    of its absolute brightness).
    """
    if bg == "fill":
        return img  # seamless tile / opaque UI panel, nothing to key
    if bg == "white":
        return remove_bg_by_color(img)
    if bg == "black":
        if alpha_mode == "keyed":
            # Boosted luminosity — soft radial falloff preserved (no hard cloud
            # edges), but dark-gray smoke ends up at 50-90% opacity instead of
            # the 20-30% luminosity would give. Earlier iterations used
            # remove_bg_by_color against black, but that clamped all non-black
            # pixels to 100% opacity — smoke looked like sharp cartoon puffs.
            return boosted_luminosity_to_alpha(img)
        # Default / alpha_mode="luminosity" — use the glow-oriented path.
        # The model sometimes ignores "pure black background" and renders the
        # sprite on a light backdrop. Two failure shapes to recover from:
        #
        #   (a) Uniform bright backdrop with a bright glow subject
        #       (e.g. fireball on pure white) — corner brightness ≈ center
        #       brightness. `white_to_alpha_glow` is right: subject IS the
        #       near-white halo, `alpha = 255 - min_ch` preserves soft
        #       falloff without amplifying white-on-white noise.
        #
        #   (b) Light backdrop with a DISTINCT bright subject
        #       (e.g. white smoke puff on gray bg) — center much brighter
        #       than corners. `white_to_alpha_glow` here is catastrophic:
        #       the bright subject gets keyed OUT (min_ch close to 255
        #       → alpha near 0) while the darker-gray corners stay opaque.
        #       Observed in practice with fx_smoke_puff rendered on gray.
        #       `remove_bg_by_color` samples the corner color and keys
        #       against it, so any subject color — including white —
        #       survives cleanly.
        corner = _corner_brightness(img)
        if corner > 96:
            center = _center_brightness(img)
            if center - corner > 30:
                return remove_bg_by_color(img)
            return white_to_alpha_glow(img)
        return luminosity_to_alpha(img)
    raise ValueError(f"unknown bg mode: {bg}")


# ---------------------------------------------------------------------------
# End-to-end per-sprite pipeline
# ---------------------------------------------------------------------------

def process_sprite(
    sprite: Sprite,
    out_dir: Path,
    client,
    raw_cache: dict[str, bytes],
    force: bool = False,
    reprocess: bool = False,
    seed: int | None = None,
    dry_run: bool = False,
) -> str:
    """Generate + post-process one sprite. Returns a one-line status string."""
    raw_p = out_dir / f"{sprite.name}_raw.png"
    out_p = out_dir / f"{sprite.name}.png"

    if dry_run:
        return (
            f"[DRY] {sprite.name}  aspect={sprite.aspect}  size={sprite.image_size}  "
            f"view={sprite.view}  bg={sprite.bg}  refs={list(sprite.refs)}"
        )

    if not force and not reprocess and raw_p.exists() and out_p.exists():
        raw_cache[sprite.name] = raw_p.read_bytes()
        return f"[SKIP] {sprite.name}"

    if force or sprite.name not in raw_cache:
        ref_bytes = []
        for ref_name in sprite.refs:
            blob = raw_cache.get(ref_name)
            if blob is None:
                raw_ref = out_dir / f"{ref_name}_raw.png"
                if raw_ref.exists():
                    blob = raw_ref.read_bytes()
                    raw_cache[ref_name] = blob
            if blob is not None:
                ref_bytes.append(blob)

        prompt = build_prompt(sprite)
        data = generate(
            client,
            prompt,
            ref_images=ref_bytes,
            aspect_ratio=sprite.aspect,
            image_size=sprite.image_size,
            seed=seed,
            ref_mode=sprite.ref_mode,
        )
        if data is None:
            return f"[FAIL] {sprite.name}: no image in response"

        raw_cache[sprite.name] = data
        raw_p.write_bytes(data)

    img = Image.open(raw_p).convert("RGBA")
    img = postprocess(img, sprite.bg, sprite.alpha_mode)
    img.save(out_p, "PNG")
    return f"[OK]   {sprite.name}  ->  {out_p}  ({img.size[0]}x{img.size[1]})"
