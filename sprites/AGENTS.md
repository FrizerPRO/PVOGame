# Sprite Generation Pipeline - Codex Guide

This is the Codex-formatted copy of `sprites/CLAUDE.md`. It applies when
working under `sprites/`. Keep `sprites/CLAUDE.md` intact for Claude Code.

Everything in this directory generates PNG sprites for the game via Gemini 3
Pro Image (`gemini-3-pro-image-preview`, "Nano Banana Pro") and post-processes
the output with background removal. The pipeline is separate from the Swift app
target so sprite generation code does not mix with game code.

## Layout

```text
sprites/
├── sprite_prompts.py        # Shared prompt clauses, Gemini client, post-processing
├── generate_sprites.py      # Sprite registry and CLI
├── web_ui.py                # Local stdlib web UI
├── SPRITE_PROMPTS.md        # Human-readable catalogue
├── ASSETS_PLAN.md           # Original Russian asset design plan
├── generated_sprites/       # Gitignored default output
│   ├── raw/<category>/*.png
│   ├── processed/<category>/*.png
│   └── generation_log.json
├── generated/               # Legacy alternate output dir
└── legacy/                  # Gitignored frozen outputs from old test scripts
```

## Model Constraints

- Fixed aspect ratios: `1:1`, `2:3`, `3:2`, `3:4`, `4:3`, `9:16`, `16:9`,
  `21:9`, `4:5`, `5:4`.
- Fixed sizes: `1K`, `2K`, `4K`.
- The model cannot produce transparent PNGs. Generate on solid
  `bg="white"`, `bg="black"`, or `bg="fill"`, then alpha-key in
  post-processing.

## Background Modes

| `Sprite.bg` | Post-process | Use case |
| --- | --- | --- |
| `white` | `remove_bg_by_color` with sampled corners | Opaque objects with clear outlines |
| `black` | `luminosity_to_alpha` | Self-luminous glows, flashes, flames, explosions |
| `fill` | No removal | Seamless tiles and full-screen panels |

For `bg="black"`, post-processing first checks corner brightness. If the
model ignored the pure-black instruction and rendered on light gray or white,
it falls back to `white_to_alpha_glow` to preserve soft glow falloff.

## Prompt Style

Canonical prompts for drones, towers, and side-view missiles should include:

1. `From above/side you see:` followed by enumerated features.
2. Explicit geometry: counts, X-shapes, grids, barrel layouts.
3. Color exclusions such as `NOT white, NOT olive, no specular highlights,
   no bright spots -- surfaces clearly darker than pure white`.
4. `floats alone with nothing beneath/around it`.
5. Hex-coded palette with per-part roles.
6. For overlays: `SEPARATE game sprite -- do NOT draw the [parent]`.

For `bg="black"` glow sprites, also include:

```text
NO black outline, NO dark border -- pure soft glow with radial falloff
```

Without that clause the model tends to add a cartoon outline that alpha
extraction removes incorrectly.

## CLI Runner

```bash
# Generate or regenerate a single sprite
python3 sprites/generate_sprites.py --api-key "$KEY" --name drone_shahed --force

# A glob or family
python3 sprites/generate_sprites.py --api-key "$KEY" --name 'tower_autocannon_*'

# A whole category: towers, drones, projectiles, vfx, settlements, tiles, ui, special
python3 sprites/generate_sprites.py --api-key "$KEY" --category ui

# Dry-run prompt preview without API calls
python3 sprites/generate_sprites.py --dry-run --name drone_shahed --print-prompt

# Re-run only post-processing on existing raw files
python3 sprites/generate_sprites.py --skip-generation --reprocess --name projectile_ciws
```

Resume is automatic through `generation_log.json`: sprites marked `complete`
are skipped. `--force` regenerates anyway. `--reprocess` reruns background
removal; add `--skip-generation` to avoid API calls.

## Retry And Timeout Flags

- `--timeout 600`: HTTP client read timeout in seconds. Image generation often
  takes 30-80 seconds. The pipeline uses `generate_content_stream` so proxy
  keepalive chunks can avoid Cloudflare 524s.
- `--max-retries 5`: retries transient `500`, `502`, `503`, `504`, `520`,
  `521`, `522`, `523`, `524`, and rate-limit failures. Prior confirmation from
  the proxy operator says failed requests are not billed; successful image
  generations are billed by Google.

## Web UI

```bash
python3 sprites/web_ui.py
python3 sprites/web_ui.py --port 9000 --no-browser
python3 sprites/web_ui.py --out sprites/generated
```

Default URL: `http://127.0.0.1:8765/`.

Features:

- Grid of all sprites grouped by category.
- Thumbnails from `processed/`, then `raw/`, then placeholder.
- Status badges: `complete`, `raw-only`, `missing`.
- Category and status filters.
- Side panel with subject, palette, extra text, assembled prompt, refs, raw
  thumbnail, and processed thumbnail.
- Per-sprite actions: force generation and post-process only.
- Bulk multi-select, select all, select missing, and generate selected.
- Live SSE log at `/api/stream`.
- Progress bar with current sprite and ok/fail/skip counts.
- CLI flags exposed in the UI: API key, force, reprocess, skip-generation,
  seed, delay, timeout, and max-retries.
- Russian info tooltips on controls.

## Web UI Architecture

- Single-file server with embedded `HTML_PAGE`.
- Reuses functions from `generate_sprites.py`: `generate_with_retry`,
  `resolve_refs`, `raw_path`, `processed_path`, `load_log`, and `save_log`.
- Reuses `postprocess`, `build_prompt`, and `make_client` from
  `sprite_prompts.py`.
- Generation runs in a daemon thread through `run_job`.
- One global `JOB_STATE` tracks current status.
- Only one job can run at a time; concurrent generation returns HTTP 409.
- Log lines broadcast to connected SSE subscribers through per-connection
  `queue.Queue`s.

## Key Endpoints

| Method | Path | Purpose |
| --- | --- | --- |
| GET | `/` | HTML UI |
| GET | `/api/sprites` | All sprites with status |
| GET | `/api/sprite/<name>` | Full detail including assembled prompt |
| GET | `/api/status` | Current job state |
| GET | `/api/log` | Last 1000 log lines |
| GET | `/api/stream` | SSE log stream |
| GET | `/image/raw/<name>` | Raw PNG |
| GET | `/image/processed/<name>` | Processed PNG |
| POST | `/api/generate` | Start generation job |
| POST | `/api/cancel` | Request graceful cancel before next sprite |

The `/api/generate` body is JSON:

```json
{
  "names": ["drone_shahed"],
  "api_key": "...",
  "force": false,
  "reprocess": false,
  "skip_generation": false,
  "seed": null,
  "delay": 0,
  "timeout": 600,
  "max_retries": 5
}
```

## Output Locations

Default output is `sprites/generated_sprites/`:

- `raw/<category>/<name>.png`: model output, unchanged.
- `processed/<category>/<name>.png`: alpha-keyed final sprite.
- `generation_log.json`: checkpoint and resume log.

There is also a legacy `sprites/generated/` directory with some canonical drone
and tower sprites. Point the UI at it with `--out sprites/generated` when
needed, or manually consolidate old `processed/` and `raw/` files into
`generated_sprites/`.

Installing a finished sprite into the Swift app is manual:

```text
PVOGame/Assets.xcassets/<name>.imageset/<name>.png
```

## Debugging Recipes

- Background not removed or a white box appears around a glow sprite: rerun
  with `--skip-generation --reprocess`. The `white_to_alpha_glow` fallback
  should handle ignored black-background instructions.
- Ripple or noise on the body after background removal: the body color is too
  close to pure white. Use medium gray around `#9A9A9A` instead of cream-white.
- Dark ring at a glow edge: add `NO black outline, NO dark border` to the
  sprite subject.
- Repeated 524 Cloudflare timeouts: retry. The code already uses
  `generate_content_stream`; persistent failures are usually network or
  genuinely slow generations.
