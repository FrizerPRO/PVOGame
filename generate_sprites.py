#!/usr/bin/env python3
"""
Sprite generator for PVOGame using Gemini API.

Usage:
    python generate_sprites.py --api-key <KEY>
    python generate_sprites.py --api-key <KEY> --only tower_autocannon_base tower_autocannon_turret
    python generate_sprites.py --api-key <KEY> --category towers
    python generate_sprites.py --api-key <KEY> --skip-generation
    python generate_sprites.py --api-key <KEY> --no-rembg
    python generate_sprites.py --api-key <KEY> --dry-run
"""

import argparse
import json
import os
import re
import sys
import time
from datetime import datetime
from pathlib import Path

import numpy as np
from PIL import Image
from google import genai
from google.genai import types

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

SCRIPT_DIR = Path(__file__).parent
PROMPTS_FILE = SCRIPT_DIR / "SPRITE_PROMPTS.md"
OUTPUT_DIR = SCRIPT_DIR / "generated_sprites"
LOG_FILE = OUTPUT_DIR / "generation_log.json"

MODEL_NAME = "gemini-3-pro-image-preview"
BASE_URL = "https://api.artemox.com"

DEFAULT_DELAY = 2.0  # seconds between API calls

# Sprite name prefixes/names -> background removal category
LUMINOSITY_PREFIXES = ("fx_",)
LUMINOSITY_NAMES = {
    "tower_autocannon_muzzle",
    "tower_ciws_muzzle",
    "tower_gepard_muzzle",
    "projectile_autocannon",
    "projectile_ciws",
    "projectile_gepard",
}
NO_REMOVAL_PREFIXES = ("tile_",)
NO_REMOVAL_NAMES = {
    "ui_hud_bar",
    "ui_menu_background",
    "ui_pause_panel",
    "AppIcon",
}

# ---------------------------------------------------------------------------
# Reference chains: sprite_name -> [(ref_name, description)]
# When generating a sprite, previously generated reference images are sent
# to the API as multimodal input to ensure visual consistency.
# ---------------------------------------------------------------------------

SPRITE_REFS: dict[str, list[tuple[str, str]]] = {
    # Tower: autocannon (base → turret; muzzle has no ref — pure VFX)
    "tower_autocannon_turret": [("tower_autocannon_base", "base/chassis that this turret sits on")],
    # Tower: CIWS (base → turret; muzzle has no ref)
    "tower_ciws_turret": [("tower_ciws_base", "truck chassis that this combat module sits on")],
    # Tower: SAM (base → launcher)
    "tower_sam_launcher": [("tower_sam_base", "truck chassis that this launcher sits on")],
    # Tower: interceptor (base → launcher)
    "tower_interceptor_launcher": [("tower_interceptor_base", "trailer that this launcher sits on")],
    # Tower: radar (base → antenna)
    "tower_radar_antenna": [("tower_radar_base", "vehicle that this antenna sits on")],
    # Tower: EW (base → array)
    "tower_ew_array": [("tower_ew_base", "truck chassis that this antenna array sits on")],
    # Tower: PZRK (base → soldier)
    "tower_pzrk_soldier": [("tower_pzrk_base", "sandbag bunker that this soldier stands in")],
    # Tower: Gepard (base → turret; muzzle has no ref)
    "tower_gepard_turret": [("tower_gepard_base", "tracked hull that this turret sits on")],
    # Explosion: small (f1 → f2 → ... → f5)
    "fx_explosion_small_f2": [("fx_explosion_small_f1", "previous frame (1/5) of this explosion")],
    "fx_explosion_small_f3": [("fx_explosion_small_f2", "previous frame (2/5) of this explosion")],
    "fx_explosion_small_f4": [("fx_explosion_small_f3", "previous frame (3/5) of this explosion")],
    "fx_explosion_small_f5": [("fx_explosion_small_f4", "previous frame (4/5) of this explosion")],
    # Explosion: medium (f1 → f2 → ... → f6)
    "fx_explosion_medium_f2": [("fx_explosion_medium_f1", "previous frame (1/6) of this explosion")],
    "fx_explosion_medium_f3": [("fx_explosion_medium_f2", "previous frame (2/6) of this explosion")],
    "fx_explosion_medium_f4": [("fx_explosion_medium_f3", "previous frame (3/6) of this explosion")],
    "fx_explosion_medium_f5": [("fx_explosion_medium_f4", "previous frame (4/6) of this explosion")],
    "fx_explosion_medium_f6": [("fx_explosion_medium_f5", "previous frame (5/6) of this explosion")],
    # Explosion: large (f1 → f2 → ... → f7)
    "fx_explosion_large_f2": [("fx_explosion_large_f1", "previous frame (1/7) of this explosion")],
    "fx_explosion_large_f3": [("fx_explosion_large_f2", "previous frame (2/7) of this explosion")],
    "fx_explosion_large_f4": [("fx_explosion_large_f3", "previous frame (3/7) of this explosion")],
    "fx_explosion_large_f5": [("fx_explosion_large_f4", "previous frame (4/7) of this explosion")],
    "fx_explosion_large_f6": [("fx_explosion_large_f5", "previous frame (5/7) of this explosion")],
    "fx_explosion_large_f7": [("fx_explosion_large_f6", "previous frame (6/7) of this explosion")],
    # Button states (normal → pressed → disabled)
    "ui_btn_start_wave_pressed": [("ui_btn_start_wave_normal", "normal state of this button")],
    "ui_btn_start_wave_disabled": [("ui_btn_start_wave_normal", "normal state of this button")],
}

# Sprite name prefix -> output subdirectory
CATEGORY_MAP = [
    ("tower_", "towers"),
    ("drone_", "drones"),
    ("projectile_", "projectiles"),
    ("missile_", "projectiles"),
    ("bomb_", "projectiles"),
    ("fx_", "vfx"),
    ("settlement_", "settlements"),
    ("tile_", "tiles"),
    ("ui_", "ui"),
    ("sprite_", "special"),
]

# ---------------------------------------------------------------------------
# Prompt parser
# ---------------------------------------------------------------------------

HEADER_RE = re.compile(
    r"^##\s+\d+[a-g]?\.\s+(\S+)\s+\((\d+)\s*[×x]\s*(\d+)\s*px\)",
    re.IGNORECASE,
)


def parse_prompts(path: Path) -> list[dict]:
    """Parse SPRITE_PROMPTS.md and return a list of sprite definitions."""
    text = path.read_text(encoding="utf-8")
    blocks = re.split(r"\n---\n", text)

    sprites = []
    for block in blocks:
        lines = block.strip().splitlines()
        for i, line in enumerate(lines):
            m = HEADER_RE.match(line.strip())
            if m:
                name = m.group(1)
                width = int(m.group(2))
                height = int(m.group(3))
                # Prompt = everything after the header line (skip blanks)
                prompt_lines = [l for l in lines[i + 1 :] if l.strip()]
                prompt = "\n".join(prompt_lines).strip()
                if prompt:
                    sprites.append(
                        {
                            "name": name,
                            "width": width,
                            "height": height,
                            "prompt": prompt,
                            "category": _classify_category(name),
                            "bg_removal": _classify_bg_removal(name),
                        }
                    )
                break
    return sprites


def _classify_category(name: str) -> str:
    for prefix, cat in CATEGORY_MAP:
        if name.startswith(prefix):
            return cat
    return "special"


# ---------------------------------------------------------------------------
# Perspective injection
# ---------------------------------------------------------------------------

# Sprites that MUST be rendered top-down (overhead, bird's-eye)
TOPDOWN_PREFIXES = ("tower_", "drone_", "settlement_")
TOPDOWN_NAMES = {"bomb_aerial", "sprite_fighter_jet"}
# Exclude VFX sub-sprites of towers
TOPDOWN_EXCLUDE = {"tower_autocannon_muzzle", "tower_ciws_muzzle", "tower_gepard_muzzle"}

TOPDOWN_PREFIX = (
    "CRITICAL REQUIREMENT: This sprite MUST be drawn in a STRICT TOP-DOWN / BIRD'S-EYE VIEW "
    "(camera looking straight down from above). No isometric, no 3/4 view, no side view, "
    "no perspective — purely overhead as if photographed by a satellite.\n\n"
)

TOPDOWN_SUFFIX = (
    "\n\nREMINDER: Strictly top-down overhead view. "
    "The camera is directly above looking straight down. No tilted perspective."
)


def _needs_topdown(name: str) -> bool:
    if name in TOPDOWN_EXCLUDE:
        return False
    if name in TOPDOWN_NAMES:
        return True
    return any(name.startswith(p) for p in TOPDOWN_PREFIXES)


def _inject_perspective(name: str, prompt: str) -> str:
    """Wrap prompt with top-down enforcement if needed."""
    if _needs_topdown(name):
        return TOPDOWN_PREFIX + prompt + TOPDOWN_SUFFIX
    return prompt


def _classify_bg_removal(name: str) -> str:
    """Return 'luminosity', 'none', or 'color'."""
    if name in LUMINOSITY_NAMES:
        return "luminosity"
    if name in NO_REMOVAL_NAMES:
        return "none"
    for prefix in LUMINOSITY_PREFIXES:
        if name.startswith(prefix):
            return "luminosity"
    for prefix in NO_REMOVAL_PREFIXES:
        if name.startswith(prefix):
            return "none"
    return "color"


# ---------------------------------------------------------------------------
# Generation log (resume support)
# ---------------------------------------------------------------------------


def load_log() -> dict:
    if LOG_FILE.exists():
        return json.loads(LOG_FILE.read_text(encoding="utf-8"))
    return {}


def save_log(log: dict):
    LOG_FILE.parent.mkdir(parents=True, exist_ok=True)
    LOG_FILE.write_text(json.dumps(log, indent=2, ensure_ascii=False), encoding="utf-8")


# ---------------------------------------------------------------------------
# API generation
# ---------------------------------------------------------------------------


def create_client(api_key: str) -> genai.Client:
    return genai.Client(
        api_key=api_key,
        http_options=types.HttpOptions(base_url=BASE_URL),
    )


def _build_contents(prompt: str, ref_images: list[tuple[bytes, str]]) -> list:
    """Build multimodal contents list with style-only reference images."""
    if not ref_images:
        return prompt

    parts: list = []

    # Text prompt FIRST — so the model reads the full description before seeing the image
    parts.append(
        "Generate the following game sprite:\n\n" + prompt +
        "\n\n---\n"
        "Below is a STYLE REFERENCE ONLY — a different sprite from the same game. "
        "Copy ONLY the rendering style: cartoon line weight, flat cel-shading, color saturation level. "
        "Do NOT copy the shape, layout, composition, perspective, or subject matter from it. "
        "The sprite you generate must look completely different — it is a different object.\n"
    )
    for img_bytes, _description in ref_images:
        parts.append(types.Part.from_bytes(data=img_bytes, mime_type="image/png"))
    return parts


# Sprite part suffixes for style anchor matching:
# when generating a _base, look for any other existing _base as style reference, etc.
STYLE_ANCHOR_SUFFIXES = ["_base", "_turret", "_launcher", "_antenna", "_array", "_soldier"]


def resolve_references(sprite_name: str, sprites_by_name: dict[str, dict]) -> list[tuple[bytes, str]]:
    """Load reference images: explicit refs (SPRITE_REFS) + auto style anchor from same part type."""
    result = []

    # 1. Explicit refs (base→turret within same tower type)
    refs = SPRITE_REFS.get(sprite_name, [])
    for ref_name, description in refs:
        ref_sprite = sprites_by_name.get(ref_name)
        if ref_sprite is None:
            continue
        rp = raw_path(ref_sprite)
        if rp.exists():
            result.append((rp.read_bytes(), description))
            print(f"  [REF] Using {ref_name} as reference ({description})")
        else:
            print(f"  [REF] {ref_name} not yet generated, skipping reference")

    # 2. Style anchor: find first existing sprite of the same part type from a DIFFERENT tower
    #    e.g. when generating tower_sam_base, use tower_autocannon_base as style ref
    if result:
        return result  # explicit ref is enough, don't stack

    for suffix in STYLE_ANCHOR_SUFFIXES:
        if not sprite_name.endswith(suffix):
            continue
        for other_name, other_sprite in sprites_by_name.items():
            if other_name == sprite_name:
                continue
            if not other_name.endswith(suffix):
                continue
            rp = raw_path(other_sprite)
            if rp.exists():
                result.append((rp.read_bytes(), "style_anchor"))
                print(f"  [STYLE ANCHOR] Using {other_name} for cross-type style consistency")
                return result  # one anchor is enough
        break

    return result


def generate_image(client: genai.Client, prompt: str,
                   ref_images: list[tuple[bytes, str]] | None = None) -> bytes | None:
    """Call Gemini API and return raw image bytes, or None on failure."""
    contents = _build_contents(prompt, ref_images or [])
    max_retries = 3
    for attempt in range(max_retries):
        try:
            response = client.models.generate_content(
                model=MODEL_NAME,
                contents=contents,
                config=types.GenerateContentConfig(
                    response_modalities=["IMAGE", "TEXT"],
                ),
            )
            # Extract image from response
            for part in response.candidates[0].content.parts:
                if part.inline_data and part.inline_data.mime_type.startswith("image/"):
                    return part.inline_data.data
            print("  [WARN] No image in response, got text only")
            return None

        except Exception as e:
            err_str = str(e)
            if "429" in err_str or "rate" in err_str.lower():
                wait = 30 * (2**attempt)
                print(f"  [RATE LIMIT] Waiting {wait}s (attempt {attempt + 1}/{max_retries})")
                time.sleep(wait)
            elif "500" in err_str or "503" in err_str:
                wait = 10
                print(f"  [SERVER ERROR] Waiting {wait}s (attempt {attempt + 1}/{max_retries}): {e}")
                time.sleep(wait)
            else:
                print(f"  [ERROR] {e}")
                return None
    print("  [FAIL] Max retries exceeded")
    return None


# ---------------------------------------------------------------------------
# Post-processing
# ---------------------------------------------------------------------------


def luminosity_to_alpha(img: Image.Image) -> Image.Image:
    """Convert a light-on-black image to RGBA using luminosity as alpha."""
    arr = np.array(img.convert("RGBA"), dtype=np.float32)
    r, g, b = arr[:, :, 0], arr[:, :, 1], arr[:, :, 2]
    # Alpha = max channel value (preserves bright colors at full opacity)
    alpha = np.maximum(np.maximum(r, g), b)
    arr[:, :, 3] = np.clip(alpha, 0, 255)
    return Image.fromarray(arr.astype(np.uint8))


def remove_bg_by_color(img: Image.Image, threshold: int = 35, feather: int = 15) -> Image.Image:
    """Detect background color from corners, remove ALL matching pixels (inside and outside)."""
    arr = np.array(img.convert("RGBA"), dtype=np.float32)
    h, w = arr.shape[:2]

    # Sample corner pixels to detect background color
    s = max(5, min(h, w) // 20)
    corners = np.concatenate([
        arr[:s, :s, :3].reshape(-1, 3),
        arr[:s, -s:, :3].reshape(-1, 3),
        arr[-s:, :s, :3].reshape(-1, 3),
        arr[-s:, -s:, :3].reshape(-1, 3),
    ])
    bg_color = np.median(corners, axis=0)
    print(f"  Detected bg color: RGB({bg_color[0]:.0f}, {bg_color[1]:.0f}, {bg_color[2]:.0f})")

    # Color distance from bg for every pixel
    dist = np.sqrt(np.sum((arr[:, :, :3] - bg_color) ** 2, axis=2))

    # Alpha: 0 near bg color, 255 far from it, smooth feathering in between
    alpha = np.clip((dist - threshold) / max(feather, 1) * 255, 0, 255)
    arr[:, :, 3] = alpha

    return Image.fromarray(arr.astype(np.uint8))


def post_process(raw_path: Path, sprite: dict) -> Image.Image:
    """Load raw image, remove background. No resize — keep original resolution."""
    img = Image.open(raw_path).convert("RGBA")

    method = sprite["bg_removal"]
    if method == "luminosity":
        img = luminosity_to_alpha(img)
    elif method == "color":
        img = remove_bg_by_color(img)
    # 'none' -> no background removal

    return img


# ---------------------------------------------------------------------------
# File helpers
# ---------------------------------------------------------------------------


def raw_path(sprite: dict) -> Path:
    return OUTPUT_DIR / "raw" / sprite["category"] / f"{sprite['name']}.png"


def processed_path(sprite: dict) -> Path:
    return OUTPUT_DIR / "processed" / sprite["category"] / f"{sprite['name']}.png"


def save_raw(data: bytes, sprite: dict) -> Path:
    p = raw_path(sprite)
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_bytes(data)
    return p


def save_processed(img: Image.Image, sprite: dict) -> Path:
    p = processed_path(sprite)
    p.parent.mkdir(parents=True, exist_ok=True)
    img.save(p, "PNG")
    return p


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------


def main():
    parser = argparse.ArgumentParser(description="Generate PVOGame sprites via Gemini API")
    parser.add_argument("--api-key", required=True, help="Gemini API key")
    parser.add_argument("--only", nargs="+", metavar="NAME", help="Generate only these sprite names")
    parser.add_argument(
        "--category",
        choices=["towers", "drones", "projectiles", "vfx", "settlements", "tiles", "ui", "special"],
        help="Generate only sprites in this category",
    )
    parser.add_argument("--skip-generation", action="store_true", help="Only run post-processing on existing raw files")
    parser.add_argument("--dry-run", action="store_true", help="Print prompts without calling API")
    parser.add_argument("--delay", type=float, default=DEFAULT_DELAY, help=f"Seconds between API calls (default: {DEFAULT_DELAY})")
    parser.add_argument("--reprocess", action="store_true", help="Re-run post-processing even for completed sprites")
    args = parser.parse_args()

    # Parse all sprites from markdown
    sprites = parse_prompts(PROMPTS_FILE)
    print(f"Parsed {len(sprites)} sprites from {PROMPTS_FILE.name}")

    # Filter
    if args.only:
        names_set = set(args.only)
        sprites = [s for s in sprites if s["name"] in names_set]
    elif args.category:
        sprites = [s for s in sprites if s["category"] == args.category]

    if not sprites:
        print("No sprites to process after filtering.")
        return

    print(f"Processing {len(sprites)} sprites")

    # Build lookup for all parsed sprites (needed for reference resolution)
    all_sprites = parse_prompts(PROMPTS_FILE)
    sprites_by_name = {s["name"]: s for s in all_sprites}

    # Dry run: just print and exit
    if args.dry_run:
        for s in sprites:
            refs = SPRITE_REFS.get(s["name"], [])
            ref_str = f" | refs={[r[0] for r in refs]}" if refs else ""
            print(f"\n{'='*60}")
            td = " | TOP-DOWN" if _needs_topdown(s['name']) else ""
            print(f"[{s['name']}] {s['width']}x{s['height']}px | cat={s['category']} | bg={s['bg_removal']}{ref_str}{td}")
            print(f"{'='*60}")
            print(s["prompt"][:500])
            if len(s["prompt"]) > 500:
                print(f"  ... ({len(s['prompt'])} chars total)")
        print(f"\nTotal: {len(sprites)} sprites")
        return

    # Initialize
    log = load_log()
    client = None if args.skip_generation else create_client(args.api_key)

    completed = 0
    skipped = 0
    failed = 0

    for i, sprite in enumerate(sprites, 1):
        name = sprite["name"]
        status = log.get(name, {}).get("status", "")

        print(f"\n[{i}/{len(sprites)}] {name} ({sprite['width']}x{sprite['height']}, bg={sprite['bg_removal']})")

        # Skip if already complete (unless reprocessing)
        if status == "complete" and not args.reprocess:
            print("  [SKIP] Already complete")
            skipped += 1
            continue

        # Step 1: Generate raw image (or skip if already generated / skip-generation mode)
        rp = raw_path(sprite)
        need_generation = status != "generated" and not rp.exists()

        if args.skip_generation:
            if not rp.exists():
                print(f"  [SKIP] No raw file found at {rp}")
                skipped += 1
                continue
        elif need_generation:
            # Resolve reference images from already-generated sprites
            ref_images = resolve_references(name, sprites_by_name)
            print("  Generating...")
            final_prompt = _inject_perspective(name, sprite["prompt"])
            img_bytes = generate_image(client, final_prompt, ref_images)
            if img_bytes is None:
                print("  [FAIL] Generation failed")
                failed += 1
                continue
            save_raw(img_bytes, sprite)
            log[name] = {
                "status": "generated",
                "timestamp": datetime.now().isoformat(),
            }
            save_log(log)
            print(f"  Raw saved: {rp}")

            # Rate limiting
            if i < len(sprites):
                time.sleep(args.delay)
        else:
            print(f"  Raw exists: {rp}")

        # Step 2: Post-process
        print(f"  Post-processing ({sprite['bg_removal']})...")
        try:
            processed_img = post_process(rp, sprite)
            pp = save_processed(processed_img, sprite)
            log[name] = {
                "status": "complete",
                "timestamp": datetime.now().isoformat(),
            }
            save_log(log)
            print(f"  Processed saved: {pp}")
            completed += 1
        except Exception as e:
            print(f"  [FAIL] Post-processing error: {e}")
            failed += 1

    # Summary
    print(f"\n{'='*60}")
    print(f"Done! Completed: {completed}, Skipped: {skipped}, Failed: {failed}")
    print(f"Raw files:       {OUTPUT_DIR / 'raw'}")
    print(f"Processed files: {OUTPUT_DIR / 'processed'}")


if __name__ == "__main__":
    main()
