# Sprite Generation Pipeline — Assistant Guide

Everything in this directory generates PNG sprites for the game via
**Gemini 3 Pro Image** ("Nano Banana Pro", `gemini-3-pro-image-preview`)
and post-processes the output with background removal. Kept separate from
the Swift app target so it doesn't mix with game code.

## Layout

```
sprites/
├── sprite_prompts.py       # Shared prompt clauses, build_prompt, Gemini client,
│                           # post-processing (bg removal, alpha channel)
├── generate_sprites.py     # Sprite registry (107 Sprite dataclass entries) + CLI
├── web_ui.py               # Local web UI for interactive generation (stdlib only)
├── SPRITE_PROMPTS.md       # Human-readable catalogue mirroring the registry
├── ASSETS_PLAN.md          # Original Russian asset design plan
├── generated_sprites/      # Gitignored: default output dir used by CLI + web UI
│   ├── raw/<category>/*.png      # model output, pre-alpha
│   ├── processed/<category>/*.png # alpha-keyed final sprite
│   └── generation_log.json        # per-sprite status, resume checkpoint
├── generated/              # Legacy alternate output dir from earlier sessions
└── legacy/                 # Gitignored: frozen outputs from deleted test scripts
```

## Model constraints

- Fixed aspect ratios: `1:1, 2:3, 3:2, 3:4, 4:3, 9:16, 16:9, 21:9, 4:5, 5:4`
- Fixed sizes: `1K`, `2K`, `4K` (no arbitrary pixel dimensions)
- **Cannot produce transparent PNGs** — sprites are generated on solid
  `bg="white" | "black" | "fill"` and alpha-keyed in post-processing.

## Background modes (`Sprite.bg`)

| `bg` | Post-process | When to use |
|---|---|---|
| `"white"` | `remove_bg_by_color` — corners sampled, fed to alpha | Opaque objects with clear outlines (drones, towers, side-view missiles) |
| `"black"` | `luminosity_to_alpha` — alpha = max(R,G,B) | Self-luminous glows (muzzle flash, tracers, flames, explosions) |
| `"fill"` | No removal | Seamless tiles, full-screen UI panels |

**Robustness shim:** `bg="black"` post-processing first checks corner
brightness. If the model ignored the "pure black background" instruction
and rendered on light gray/white, it falls back to `white_to_alpha_glow`
(a soft white→alpha pass tuned for glow sprites, preserving radial
falloff without amplifying noise).

## Style conventions for prompts

Style-canonical prompts (any of the already-generated drones, towers, or
side-view missiles) share six markers — copy them into new Sprite entries:

1. `"From above/side you see:"` followed by enumerated features
2. Explicit geometry — counts, X-shape, grids, barrel layouts
3. Color-exclusion clauses: `"NOT white, NOT olive, no specular highlights,
   no bright spots — surfaces clearly darker than pure white"`
4. `"floats alone with nothing beneath/around it"`
5. Hex-coded palette with per-part roles
6. For overlays: `"SEPARATE game sprite — do NOT draw the [parent]"`

For `bg="black"` glow sprites, ALSO add:
`"NO black outline, NO dark border — pure soft glow with radial falloff"`
Without this clause the model tends to add a cartoon outline, which the
alpha extraction then eats.

## CLI runner

```bash
# Generate / regenerate a single sprite
python3 sprites/generate_sprites.py --api-key $KEY --name drone_shahed --force

# A glob / family
python3 sprites/generate_sprites.py --api-key $KEY --name 'tower_autocannon_*'

# A whole category (towers|drones|projectiles|vfx|settlements|tiles|ui|special)
python3 sprites/generate_sprites.py --api-key $KEY --category ui

# Dry-run: preview the assembled prompt without hitting the API
python3 sprites/generate_sprites.py --dry-run --name drone_shahed --print-prompt

# Re-run ONLY post-processing on existing raw files (no API, no tokens)
python3 sprites/generate_sprites.py --skip-generation --reprocess --name projectile_ciws
```

Resume is automatic via `generation_log.json` — sprites marked `complete`
are skipped on reruns. `--force` regenerates anyway; `--reprocess` re-runs
background removal only (still calls API unless `--skip-generation`).

### Retry + timeout flags

- `--timeout 600` — HTTP client read timeout in seconds (default 600).
  Nano Banana Pro image generation normally takes 30-80 s; we use
  `generate_content_stream` so the proxy can emit keepalive chunks and
  Cloudflare's 100 s origin cap (HTTP 524) is rarely hit.
- `--max-retries 5` — retries on transient codes `500/502/503/504/520/521/522/523/524` +
  rate-limit. Safe to leave high: artemox proxy support confirmed that
  **failed requests are not billed** — only successful image generations are
  charged by Google. Retrying a 524 does not risk double-billing.

## Web UI (`web_ui.py`)

Local web interface for running the same pipeline interactively.
Stdlib-only (`http.server`, no Flask / extra deps).

```bash
python3 sprites/web_ui.py              # → http://127.0.0.1:8765 (auto-opens browser)
python3 sprites/web_ui.py --port 9000 --no-browser
python3 sprites/web_ui.py --out sprites/generated   # point at the legacy dir
```

Features:

- Grid of all 107 sprites grouped by category, with thumbnails from
  `processed/` → fallback to `raw/` → placeholder
- Status badge per sprite: `complete` / `raw-only` / `missing`
- Filters: by category, or by status (`✓ complete`, `raw-only`, `missing`)
- Click a sprite → side panel with subject / palette / extra / full
  assembled prompt / refs / raw+processed thumbnails
- Per-sprite actions: `generate (force)`, `post-process only` (which maps
  to `--skip-generation --reprocess`)
- Bulk: multi-select (shift/ctrl-click or checkbox), `select all`,
  `select missing`, then `▶ generate selected`
- Live **SSE log stream** at `/api/stream` — colored lines: errors, warnings,
  OK, skipped
- Live progress bar with current sprite name + ok/fail/skip counts
- All CLI flags exposed at the top: API key, force, reprocess,
  skip-generation, seed, delay, timeout, max-retries
- Info tooltips (Russian) on every button/option via `ⓘ` icons

### Web UI architecture

- Single-file server with HTML embedded as a Python string constant (`HTML_PAGE`)
- Reuses functions from `generate_sprites.py`: `generate_with_retry`,
  `resolve_refs`, `raw_path`, `processed_path`, `load_log`, `save_log`
- Reuses `postprocess`, `build_prompt`, `make_client` from `sprite_prompts.py`
- Generation runs in a daemon thread (`run_job`); a single global `JOB_STATE`
  tracks status; only one job runs at a time (409 if attempting concurrent)
- Log lines broadcast to all connected SSE subscribers via a list of
  per-connection `queue.Queue`s

### Key endpoints

| Method | Path | Purpose |
|---|---|---|
| GET | `/` | HTML UI |
| GET | `/api/sprites` | all sprites with status (JSON) |
| GET | `/api/sprite/<name>` | full detail incl. assembled prompt |
| GET | `/api/status` | current job state |
| GET | `/api/log` | snapshot of last 1000 log lines |
| GET | `/api/stream` | SSE log stream |
| GET | `/image/raw/<name>` | raw PNG |
| GET | `/image/processed/<name>` | processed PNG |
| POST | `/api/generate` | start job `{names, api_key, force, reprocess, skip_generation, seed, delay, timeout, max_retries}` |
| POST | `/api/cancel` | request graceful cancel (stops before next sprite) |

## Output locations

By default the CLI and UI both write to `sprites/generated_sprites/`:

- `raw/<category>/<name>.png` — model output, unchanged
- `processed/<category>/<name>.png` — alpha-keyed final sprite
- `generation_log.json` — checkpoint

**Heads-up:** There is also a legacy `sprites/generated/` directory from an
earlier iteration that still holds some canonical drone / tower sprites.
Point the UI at it with `--out sprites/generated` if you need to inspect
those, or manually consolidate by copying the old `processed/` + `raw/`
into `generated_sprites/`.

Installing a finished sprite into the Swift app is a manual copy step into
`PVOGame/Assets.xcassets/<name>.imageset/`.

## Debugging recipes

- **"Background wasn't removed" / white box around glow sprite** — the model
  ignored `bg="black"` and rendered on white. The `white_to_alpha_glow`
  fallback in `postprocess` handles it automatically; re-run with
  `--skip-generation --reprocess` (no API cost).
- **"Ripple / noise on body after bg removal"** — the sprite's body color
  is too close to pure white (distance less than `remove_bg_by_color`'s
  `threshold + feather = 50`). Use medium gray (~#9A9A9A) instead of
  cream-white for the palette.
- **"Dark ring at glow edge"** — model drew a cartoon outline around a
  `bg="black"` sprite. Add explicit `"NO black outline, NO dark border"`
  to the sprite's `subject`.
- **Repeated 524 Cloudflare timeouts** — we already use
  `generate_content_stream` in `sprite_prompts.generate`, which keeps the
  connection alive past Cloudflare's 100 s origin cap via keepalive chunks.
  If 524s still appear, it's a network blip or a genuinely slow generation —
  safe to retry since the proxy operator confirmed failed calls aren't billed.
