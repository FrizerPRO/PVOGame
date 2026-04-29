# Sprite Generation Prompts for PVOGame

This is a human-readable index of the 107 sprite specifications used by
`generate_sprites.py`. The **source of truth is the `SPRITES` list in
`generate_sprites.py`** — this document mirrors those entries.

Common boilerplate (style / background / "no text" / top-down reminder) is
injected by `sprite_prompts.build_prompt`, so each entry below lists only
the unique **subject** + **palette** + **metadata** (aspect, refs, image_size).

The model is **Gemini 3 Pro Image** (Nano Banana Pro). It does **not** support
arbitrary pixel sizes — output size is driven by `aspect_ratio` + `image_size`
(`1K` / `2K` / `4K`) in the API config. It does **not** produce transparent
backgrounds, so sprites are generated on a solid colour and post-processed.

---

## Shared clauses (applied by `sprite_prompts.py`)

The generator prepends/appends the following verbatim, based on per-sprite
fields (`view`, `bg`, plus a universal `extra` slot):

### View — `VIEW_TOPDOWN`  (applied when `view == "topdown"`)

> CRITICAL REQUIREMENT: This sprite MUST be drawn in a STRICT TOP-DOWN /
> BIRD'S-EYE VIEW (camera looking straight down from above). No isometric,
> no 3/4 view, no side view, no perspective — purely overhead as if
> photographed by a satellite.

Closing reminder (`VIEW_TOPDOWN_REMINDER`):

> REMINDER: Strictly top-down overhead view. The camera is directly above
> looking straight down. No tilted perspective.

### View — `VIEW_SIDE`  (applied when `view == "side"`)

> Side view. The subject is drawn in strict side profile, pointing upward
> toward the top edge of the image. The subject floats alone with nothing
> around it.

### Style — `STYLE_CARTOON`

> 2D cartoon style like Plants vs Zombies / Kingdom Rush — bold outlines,
> simplified shapes, flat colors with soft cel-shading, minimal surface
> detail. Not photorealistic.

### Background

- `bg == "white"` → **`BG_WHITE`**:
  Solid pure white background (#FFFFFF). No gradients, no ground plane, no
  shadows on background. The object floats on perfectly flat white.
  Post-processing: chromakey the detected corner colour to alpha=0.
- `bg == "black"` → **`BG_BLACK`**:
  Solid pure black background (#000000). No gradients, no ground plane, no
  shadows on background.
  Post-processing: `alpha := max(R,G,B)` so bright VFX pixels stay, black goes transparent.
- `bg == "fill"` → **`BG_FILL`**:
  The sprite MUST fill the entire frame edge-to-edge — there is NO
  surrounding background. The subject occupies the full image.
  Post-processing: none (kept as-is). Used for seamless tiles and opaque
  full-frame UI panels / AppIcon.

### Trailer — `NO_JUNK`

> No text, no labels, no watermarks, no photorealism, no 3D rendering.

### Style-reference preamble  (when `refs` is non-empty)

When the sprite has a non-empty `refs = [...]`, the previously generated
raw image of each named sprite is attached to the API request as a style
reference. The model is told:

> Below is a STYLE REFERENCE ONLY — a different sprite from the same game.
> Copy ONLY the rendering style: cartoon line weight, flat cel-shading,
> color saturation level. Do NOT copy the shape, layout, composition,
> perspective, or subject matter from it. The sprite you generate must look
> completely different — it is a different object.

---

## Damage visual effects (runtime)

All drone sprites (`drone_shahed`, `drone_kamikaze`, `drone_ew`, `drone_heavy`,
`drone_lancet`, `drone_orlan`, `drone_swarm`, `drone_bomber`) receive
programmatic damage effects when hit. Sprite artists should be aware:

### Light damage
- Color tint: gray overlay at `colorBlendFactor: 0.15`
- Smoke: light gray (#B3B3B3) circular puffs, birthRate 8, alpha 0.3, rising

### Medium damage
- Color tint: darker gray (#595959) at `colorBlendFactor: 0.35`
- Smoke: heavier, birthRate 20, alpha 0.5

### Critical damage (burning)
- Color tint: red-brown (rgb 153, 38, 26) at `colorBlendFactor: 0.45`
- Fire: orange-yellow emitter, birthRate 40, alpha 0.9, wider angular spread

### Design implications
- Use medium-toned colors so tint and fire effect remain visible
- Avoid large pure-white areas on drones (conflict with smoke particles)
- Navigation lights and propellers are added programmatically — **do NOT**
  include them in the sprite

---

## Enemy-kill explosion tier mapping

Triggered by `spawnKillExplosion` in `InPlaySKScene+Effects.swift`, selected
by enemy class:

| Tier   | Frames                        | Enemies                                                                  |
|--------|-------------------------------|--------------------------------------------------------------------------|
| none   | —                             | `SwarmDroneEntity`, plain `AttackDroneEntity` — silent                   |
| small  | `fx_explosion_small_f1..f5`   | `KamikazeDroneEntity`, `LancetDroneEntity`, `HarmMissileEntity`          |
| medium | `fx_explosion_medium_f1..f6`  | `ShahedDroneEntity`, `OrlanDroneEntity`, `EWDroneEntity`, `EnemyMissileEntity`, `MineLayerDroneEntity` |
| large  | `fx_explosion_large_f1..f7`   | `HeavyDroneEntity`, `CruiseMissileEntity` — airstrike-grade              |

Animation notes:
- Each animation plays ONCE at the kill position (no looping)
- Final frame should already be ~fully transparent smoke
- Viewing angle: top-down (matches the game's camera)
- Frames must share center alignment so the sequence doesn't jitter
- At night the explosion illuminates nearby terrain via a soft circular hole
  in the night overlay — ensure a bright hot core that reads against dark terrain

---

## Sprite catalogue

Each entry shows: `name — aspect — refs → subject / palette`.

### Towers

| name                          | aspect | refs                        |
|-------------------------------|--------|-----------------------------|
| tower_autocannon_base         | 1:1    | —                           |
| tower_autocannon_turret       | 1:1    | tower_autocannon_base       |
| tower_autocannon_muzzle       | 1:1    | — (bg=black, VFX)           |
| tower_ciws_base               | 1:1    | —                           |
| tower_ciws_turret             | 1:1    | tower_ciws_base             |
| tower_ciws_muzzle             | 1:1    | — (bg=black, VFX)           |
| tower_sam_base                | 1:1    | —                           |
| tower_sam_launcher            | 1:1    | tower_sam_base              |
| tower_interceptor_base        | 1:1    | —                           |
| tower_interceptor_launcher    | 1:1    | tower_interceptor_base      |
| tower_radar_base              | 1:1    | —                           |
| tower_radar_antenna           | 3:2    | tower_radar_base            |
| tower_ew_base                 | 1:1    | —                           |
| tower_ew_array                | 1:1    | tower_ew_base               |
| tower_pzrk_base               | 1:1    | —                           |
| tower_pzrk_soldier            | 1:1    | tower_pzrk_base             |
| tower_gepard_base             | 1:1    | —                           |
| tower_gepard_turret           | 1:1    | tower_gepard_base           |
| tower_gepard_muzzle           | 1:1    | — (bg=black, VFX)           |

Per-sprite subject/palette lives in `generate_sprites.py :: TOWERS`.

### Drones and enemy missiles

| name                          | aspect | refs                        |
|-------------------------------|--------|-----------------------------|
| drone_regular                 | 1:1    | —                           |
| drone_shahed                  | 1:1    | drone_regular               |
| drone_orlan                   | 1:1    | drone_regular               |
| drone_kamikaze                | 1:1    | drone_regular               |
| drone_ew                      | 1:1    | drone_regular               |
| drone_heavy                   | 1:1    | drone_regular               |
| drone_lancet                  | 1:1    | drone_regular               |
| drone_bomber                  | 1:1    | drone_regular               |
| drone_swarm                   | 1:1    | —                           |
| bomb_aerial                   | 2:3    | — (side view)               |
| missile_enemy                 | 9:16   | — (side view)               |
| missile_harm                  | 9:16   | — (side view)               |
| missile_cruise                | 9:16   | — (side view)               |

Definitions: `generate_sprites.py :: DRONES`.

### Player projectiles

| name                          | aspect | refs              |
|-------------------------------|--------|-------------------|
| projectile_autocannon         | 1:1    | — (bg=black)      |
| projectile_sam                | 2:3    | — (side view)     |
| projectile_interceptor        | 2:3    | projectile_sam    |
| projectile_ciws               | 1:1    | — (bg=black)      |
| projectile_pzrk               | 2:3    | projectile_sam    |
| projectile_gepard             | 1:1    | — (bg=black)      |

Definitions: `generate_sprites.py :: PROJECTILES`.

### Simple VFX (bg=black)

| name                          | aspect | refs                  |
|-------------------------------|--------|-----------------------|
| fx_smoke_puff                 | 1:1    | —                     |
| fx_smoke_puff_gray            | 1:1    | fx_smoke_puff         |
| fx_flame_glow                 | 1:1    | —                     |
| fx_armor_spark                | 1:1    | —                     |
| fx_damage_smoke               | 1:1    | fx_smoke_puff         |
| fx_shadow_ellipse             | 16:9   | —                     |

Definitions: `generate_sprites.py :: VFX_SIMPLE`.

### Explosion animation frames (all 1:1, bg=black)

Each frame `N` references frame `N-1` for temporal consistency.

- **Small (5 frames)**: `fx_explosion_small_f1` → … → `fx_explosion_small_f5`
- **Medium (6 frames)**: `fx_explosion_medium_f1` → … → `fx_explosion_medium_f6`
- **Large (7 frames)**: `fx_explosion_large_f1` → … → `fx_explosion_large_f7`

Definitions: `generate_sprites.py :: EXPLOSION_{SMALL,MEDIUM,LARGE}`.

### Settlements (all 1:1, top-down)

| name                  | refs                  |
|-----------------------|-----------------------|
| settlement_village    | —                     |
| settlement_town       | settlement_village    |
| settlement_factory    | settlement_village    |
| settlement_farm       | settlement_village    |
| settlement_depot      | settlement_village    |

Definitions: `generate_sprites.py :: SETTLEMENTS`.

### Terrain tiles (all 1:1, top-down, seamless)

All tiles use `bg="fill"` — the tile content fills the entire frame,
post-processing is skipped so the seamless texture is preserved.

- `tile_ground` (style anchor)
- `tile_highGround`, `tile_blocked`, `tile_headquarters`, `tile_settlement`,
  `tile_concealed`, `tile_valley` — all reference `tile_ground` for style

Definitions: `generate_sprites.py :: TILES`.

### UI elements

| name                          | aspect | refs                        |
|-------------------------------|--------|-----------------------------|
| ui_hud_bar                    | 21:9   | — (`bg=fill`)               |
| ui_btn_start_wave_normal      | 21:9   | —                           |
| ui_btn_start_wave_pressed     | 21:9   | ui_btn_start_wave_normal    |
| ui_btn_start_wave_disabled    | 21:9   | ui_btn_start_wave_normal    |
| ui_btn_speed_1x               | 1:1    | —                           |
| ui_btn_speed_2x               | 1:1    | ui_btn_speed_1x             |
| ui_btn_settings               | 1:1    | —                           |
| ui_conveyor_slot              | 1:1    | —                           |
| ui_tower_card                 | 1:1    | ui_conveyor_slot            |
| ui_ability_fighter            | 1:1    | —                           |
| ui_ability_barrage            | 1:1    | ui_ability_fighter          |
| ui_ability_reload             | 1:1    | ui_ability_fighter          |
| ui_menu_background            | 9:16   | — (`bg=fill`)               |
| ui_title_background           | 21:9   | —                           |
| ui_btn_campaign               | 21:9   | —                           |
| ui_btn_endless                | 21:9   | ui_btn_campaign             |
| ui_level_card                 | 21:9   | —                           |
| ui_btn_back                   | 21:9   | —                           |
| ui_gameover_background        | 21:9   | —                           |
| ui_btn_playagain              | 21:9   | —                           |
| ui_btn_menu                   | 21:9   | ui_btn_back                 |
| ui_pause_panel                | 5:4    | — (`bg=fill`)               |
| ui_btn_resume                 | 21:9   | ui_btn_playagain            |
| ui_btn_restart                | 21:9   | ui_btn_playagain            |
| ui_btn_exit                   | 21:9   | ui_btn_back                 |
| ui_aid_card                   | 9:16   | —                           |
| ui_warning_background         | 21:9   | —                           |
| ui_target_marker              | 1:1    | —                           |
| ui_offscreen_arrow            | 1:1    | —                           |
| ui_star_filled                | 1:1    | —                           |
| ui_star_empty                 | 1:1    | ui_star_filled              |

Definitions: `generate_sprites.py :: UI`. The `_UI_STYLE` prefix ("Cold War
Soviet air defense console aesthetic") is applied in code.

### Special

| name                | aspect | image_size | refs |
|---------------------|--------|------------|------|
| sprite_fighter_jet  | 16:9   | 1K         | —    |
| AppIcon             | 1:1    | 2K         | — (`bg=fill`) |

Definitions: `generate_sprites.py :: SPECIAL`.

---

## Summary

| Category                | Count |
|-------------------------|-------|
| Towers (base + part + muzzle) | 19 |
| Drones and enemy missiles     | 13 |
| Player projectiles            | 6  |
| Simple VFX                    | 6  |
| Explosion frames (5 + 6 + 7)  | 18 |
| Settlements                   | 5  |
| Terrain tiles                 | 7  |
| UI elements                   | 31 |
| Special (fighter jet, AppIcon)| 2  |
| **Total**                     | **107** |

---

## Regenerating

```bash
# One sprite
python generate_sprites.py --api-key $KEY --name drone_shahed --force

# A family
python generate_sprites.py --api-key $KEY --name 'tower_autocannon_*' --force

# A category (towers/drones/projectiles/vfx/settlements/tiles/ui/special)
python generate_sprites.py --api-key $KEY --category ui

# Preview assembled prompts without hitting the API
python generate_sprites.py --dry-run --name drone_shahed --print-prompt
```

Resume is automatic — a `generation_log.json` in the output directory tracks
which sprites have been `generated` / `complete`. Use `--force` to regenerate
anyway, or `--reprocess` to re-run post-processing only.
