#!/usr/bin/env python3
"""Generate PVOGame sprites via Nano Banana Pro (gemini-3-pro-image-preview).

All 105 sprites are declared inline as `Sprite` records; shared style/background/
no-junk/view clauses are injected by `sprite_prompts.build_prompt`. Output size is
driven by `aspect_ratio` + `image_size` in the API config — pixel dimensions are not
part of the prompt because the model does not honour arbitrary sizes.

Usage:
    python generate_sprites.py --api-key KEY
    python generate_sprites.py --api-key KEY --name drone_shahed
    python generate_sprites.py --api-key KEY --name 'tower_autocannon_*' --force
    python generate_sprites.py --dry-run
"""

from __future__ import annotations

import argparse
import fnmatch
import json
import sys
import time
from datetime import datetime
from pathlib import Path

from sprite_prompts import (
    API_KEY_CONFIG_FILE,
    Sprite,
    StreamDeadlineExceeded,
    build_prompt,
    ensure_api_key_config_file,
    generate,
    make_client,
    postprocess,
    resolve_api_key,
)
from PIL import Image


SCRIPT_DIR = Path(__file__).parent
DEFAULT_OUT = SCRIPT_DIR / "generated_sprites"
LOG_NAME = "generation_log.json"

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


def category_of(name: str) -> str:
    for prefix, cat in CATEGORY_MAP:
        if name.startswith(prefix):
            return cat
    return "special"


# ---------------------------------------------------------------------------
# Tower families
# ---------------------------------------------------------------------------

TOWERS = [
    Sprite(
        name="tower_autocannon_base",
        view="topdown", bg="white", aspect="1:1",
        subject=(
            "A two-wheeled anti-aircraft gun mount WITHOUT THE GUN — base/chassis only. "
            "Two rubber wheels, cross-shaped stabilizing outriggers deployed in 4 directions, "
            "central support pedestal with a round turret ring (open hole in the center for the "
            "rotating mechanism — the hole should be clearly visible and empty). "
            "Camouflage netting draped around the edges. Olive-green military paint."
        ),
        palette="olive (#4B5320), khaki netting, dark rubber wheels",
    ),
    Sprite(
        name="tower_autocannon_turret",
        view="topdown", bg="white", aspect="1:1",
        refs=("tower_autocannon_base",),
        subject=(
            "ONLY the rotating gun mechanism of a twin-barrel anti-aircraft autocannon. "
            "This is a SEPARATE game sprite — do NOT draw the base, wheels, outriggers, or any "
            "platform. ONLY the gun part that rotates:\n"
            "- Two parallel long barrels pointing straight up toward the top edge\n"
            "- A compact rotating cradle/yoke holding the barrels\n"
            "- Ammo feed belts on both sides\n"
            "- A small gunner seat at the bottom\n"
            "The gun mechanism floats alone with nothing beneath it. "
            "Rotation pivot point at exact center of image."
        ),
        palette="dark steel barrels (#3A3A3A), olive mechanism (#4B5320)",
        extra="IMPORTANT: Do NOT include wheels, outriggers, base platform, or any part of the mount.",
    ),
    Sprite(
        name="tower_autocannon_muzzle",
        view="none", bg="black", aspect="1:1",
        refs=("fx_flame_glow",),
        ref_mode="style",
        subject=(
            "ONLY a muzzle flash effect — no gun, no barrels, no weapon visible. "
            "Two bright white-yellow flame bursts side by side (from twin barrels), pointing upward. "
            "Radial glow falloff from white-hot core to orange edges — same warm-glow palette and "
            "soft falloff as the referenced flame glow. "
            "This is a VFX overlay sprite — ONLY the fire/flash, nothing else. Style-anchor for "
            "the whole muzzle-flash family (ciws and gepard mirror this rendering)."
        ),
        palette="white-hot core (#FFF6D0), bright yellow mid (#FFD700), orange edges (#FF8A1F)",
        extra="No weapon, no gun, no metal parts.",
    ),
    Sprite(
        name="tower_ciws_base",
        view="topdown", bg="white", aspect="1:1",
        subject=(
            "An 8-wheeled military truck chassis (Pantsir-S1 SHORAD system) WITHOUT THE TURRET MODULE. "
            "Long rectangular truck body, 8 wheels of equal size (4 axles), driver cabin at the front "
            "of the truck, engine compartment behind the cabin, flat cargo platform at the rear with "
            "a round turret ring (empty hole for the rotating combat module). NO missile tubes on the "
            "body — missiles are on the turret which is a separate sprite. Sandy-beige camouflage with "
            "olive patches."
        ),
        palette="sandy (#C2B280), olive patches, black wheels",
    ),
    Sprite(
        name="tower_ciws_turret",
        view="topdown", bg="white", aspect="1:1",
        refs=("tower_ciws_base",),
        subject=(
            "ONLY the rotating combat module of a Pantsir-S1 SHORAD system. This is a SEPARATE game "
            "sprite — do NOT draw the truck chassis, wheels, or platform. ONLY the turret module that "
            "rotates: central optoelectronic sensor dome, two 30mm autocannons (parallel barrels "
            "pointing straight up toward the top edge), and 6 missile launch tubes on EACH side of "
            "the turret (12 total, arranged in two rows of 6). The missiles are mounted on this "
            "turret, NOT on the truck body. The turret floats alone with nothing beneath it. "
            "Rotation center at exact center."
        ),
        palette="dark gray (#4A4A4A), steel barrels, olive-gray missile tubes, optic lens glints",
        extra="IMPORTANT: Do NOT include wheels, truck body, or any part of the chassis.",
    ),
    Sprite(
        name="tower_ciws_muzzle",
        view="none", bg="black", aspect="1:1",
        refs=("tower_autocannon_muzzle",),
        ref_mode="style",
        subject=(
            "ONLY a muzzle flash effect — no gun, no barrels, no weapon visible. "
            "Two small bright orange flame bursts SIDE BY SIDE pointing in the SAME direction "
            "(upward toward the top edge) — both barrels fire in one direction, NOT in opposite "
            "directions. Simple 2D cartoon flash. Flat stylized shapes. Same rendering style, "
            "line weight and radial falloff as the autocannon muzzle-flash reference — only the "
            "color leans warmer orange and the bursts are smaller. "
            "This is a VFX overlay sprite — ONLY the fire/flash, nothing else."
        ),
        palette="white-hot core (#FFF4C0), orange mid (#FF8C00), yellow edges (#FFD760)",
        extra="No weapon, no gun, no metal parts.",
    ),
    Sprite(
        name="tower_sam_base",
        view="topdown", bg="white", aspect="1:1",
        subject=(
            "A heavy 8-wheeled military transporter truck (SAM launcher chassis) WITHOUT LAUNCH TUBES. "
            "Long heavy truck, 8 wheels, dark olive paint, driver cabin visible at front, engine "
            "compartment, flat frame platform with mounting brackets for the launcher."
        ),
        palette="dark olive (#3C4A2F), black rubber wheels",
    ),
    Sprite(
        name="tower_sam_launcher",
        view="topdown", bg="white", aspect="1:1",
        refs=("tower_sam_base",),
        subject=(
            "A SAM launch container with 4 large missiles — SEPARATE from the truck chassis, will be "
            "overlaid on the base sprite at runtime. This is a SEPARATE game sprite — do NOT draw the "
            "truck, wheels, or platform. 4 large cylindrical missile tubes arranged in a 2x2 grid, "
            "viewed from directly above — you see 4 large round circles (the end caps of the vertical "
            "tubes). The missiles point straight up, so from above you see circles. Each missile is "
            "noticeably LARGER than the interceptor launcher missiles. Heavy dark mounting frame "
            "holding the tubes. Rotation center at exact center."
        ),
        palette="dark olive (#3C4A2F) canister caps, dark metallic mounting brackets",
        extra="IMPORTANT: Do NOT draw tubes from the side — this is a top-down view showing round circles.",
    ),
    Sprite(
        name="tower_interceptor_base",
        view="topdown", bg="white", aspect="1:1",
        subject=(
            "A semi-trailer launcher platform (Western/NATO style SAM system) WITHOUT LAUNCH TUBES. "
            "Trailer with hydraulic stabilizer legs, tow vehicle, camouflage netting along the sides. "
            "NATO olive-green paint."
        ),
        palette="NATO olive (#4A5028), sandy patches",
    ),
    Sprite(
        name="tower_interceptor_launcher",
        view="topdown", bg="white", aspect="1:1",
        refs=("tower_interceptor_base",),
        subject=(
            "A NATO SAM launcher module with 12 missiles — SEPARATE from the trailer, will be "
            "overlaid on the base sprite at runtime. This is a SEPARATE game sprite — do NOT draw "
            "the trailer, wheels, or platform. 12 cylindrical missile canisters arranged in a grid "
            "(3 rows of 4), viewed from directly above — you see 12 round circles (the end caps of "
            "the vertical tubes). The missiles point straight up, so from above you see circles. "
            "Dark mounting frame holding the tubes together. Rotation center at exact center."
        ),
        palette="silver-gray (#A0A0A0) canister caps, dark (#3A3A3A) mounting frame",
        extra="IMPORTANT: Do NOT draw tubes from the side — this is a top-down view showing round circles.",
    ),
    Sprite(
        name="tower_radar_base",
        view="topdown", bg="white", aspect="1:1",
        subject=(
            "A radar station vehicle — truck with deployed stabilizer outriggers on both sides, "
            "driver cabin, generator unit, cables running along the body. In the center: a round "
            "antenna pedestal (circular metal rotation platform). Olive military paint."
        ),
        palette="olive (#5A6332), dark cabin, cables",
    ),
    Sprite(
        name="tower_radar_antenna",
        view="topdown", bg="white", aspect="3:2",
        refs=("tower_radar_base",),
        subject=(
            "Looking DOWN onto a parabolic radar antenna — SEPARATE from the vehicle chassis, will "
            "be overlaid on the base sprite at runtime. The camera is DIRECTLY ABOVE the antenna. "
            "What you see from above: the thin rectangular OUTLINE/EDGE of the wire-mesh reflector "
            "dish (since the dish faces horizontally, from above you see it as a thin elongated "
            "shape), a feed horn on a support arm pointing into the dish, and the central rotation "
            "mount. The dish does NOT face upward toward the camera — it faces horizontally to the "
            "side, so from above you see its top edge/rim, not its concave face. Rotation axis at "
            "exact center of the image."
        ),
        palette="silver (#C0C0C0) mesh edge, dark gray (#555555) support arm and mount",
    ),
    Sprite(
        name="tower_ew_base",
        view="topdown", bg="white", aspect="1:1",
        subject=(
            "A 6-wheeled military truck chassis (electronic warfare system) WITHOUT ANTENNA ARRAYS. "
            "Truck body, 6 wheels, olive camouflage, cooling units and cable bundles visible on the "
            "flat platform."
        ),
        palette="olive (#4B5320), dark cables, metallic cooling blocks",
    ),
    Sprite(
        name="tower_ew_array",
        view="topdown", bg="white", aspect="1:1",
        refs=("tower_ew_base",),
        subject=(
            "Electronic warfare antenna arrays — SEPARATE from the truck chassis, will be overlaid "
            "on the base sprite at runtime. Multiple directional antenna panels, EW equipment "
            "containers. Teal (#008080) accent indicator stripes on the panels, dark grilles. "
            "Compact form. Rotation center at exact center."
        ),
        palette="dark panels (#333333), teal (#008080) indicator stripes",
    ),
    Sprite(
        name="tower_pzrk_base",
        view="topdown", bg="white", aspect="1:1",
        subject=(
            "A MANPADS firing position — sandbags arranged in a semicircle (bunker/cover), "
            "camouflage netting over the top. Dirt ground with trampled grass inside the cover. "
            "NO SOLDIER — just the empty position."
        ),
        palette="sandy (#C2A86E) sandbags, dark green (#3A5A1E) netting, earth tones",
    ),
    Sprite(
        name="tower_pzrk_soldier",
        view="topdown", bg="white", aspect="1:1",
        refs=("tower_pzrk_base",),
        subject=(
            "A soldier in woodland camouflage uniform with body armor, kneeling with a shoulder-"
            "launched MANPADS tube. The tube points straight up toward the top edge of the image. "
            "Visible helmet, body armor vest, launch tube across the shoulder. SEPARATE from the "
            "bunker — will be overlaid at runtime. Rotation center at exact center."
        ),
        palette="woodland camo (brown #4B3621, green), dark green launch tube",
    ),
    Sprite(
        name="tower_gepard_base",
        view="topdown", bg="white", aspect="1:1",
        subject=(
            "A tracked armored vehicle hull (self-propelled AA gun) WITHOUT THE TURRET. Tank-like "
            "tracks on both sides, engine compartment at rear, open round turret ring (hole) at the "
            "center of the upper hull plate. Three-tone NATO camouflage with MUTED, DESATURATED "
            "colors — not bright green."
        ),
        palette="muted dark olive (#3D4A2F), dark brown (#4A3828), dark gray (#3A3A3A)",
    ),
    Sprite(
        name="tower_gepard_turret",
        view="topdown", bg="white", aspect="1:1",
        refs=("tower_gepard_base",),
        subject=(
            "A self-propelled AA gun turret — SEPARATE from the hull, will be overlaid on the base "
            "sprite at runtime. Compact turret with twin 35mm autocannons — two long barrels pointing "
            "straight up toward the top edge. Small flat tracking radar dome on the turret roof, "
            "small search radar antenna at rear. Steel coloring. Rotation center at exact center."
        ),
        palette="steel (#707070), dark barrels, camo-painted turret sides",
    ),
    Sprite(
        name="tower_gepard_muzzle",
        view="none", bg="black", aspect="1:1",
        refs=("tower_autocannon_muzzle",),
        ref_mode="style",
        subject=(
            "ONLY a muzzle flash effect — no gun, no barrels, no weapon visible. "
            "Two bright yellow flame bursts SIDE BY SIDE pointing in the SAME direction (upward "
            "toward the top edge) — both barrels fire in one direction, NOT in opposite directions. "
            "Simple 2D cartoon flash. Flat stylized shapes. Same rendering style, line weight and "
            "radial falloff as the autocannon muzzle-flash reference — only the color is a purer "
            "bright yellow. "
            "This is a VFX overlay sprite — ONLY the fire/flash, nothing else."
        ),
        palette="white-hot core (#FFFFE0), bright yellow mid (#FFFF00), orange edges (#FF9A2A)",
        extra="No weapon, no gun, no metal parts.",
    ),
]


# ---------------------------------------------------------------------------
# Drones & enemy missiles
# ---------------------------------------------------------------------------

DRONES = [
    Sprite(
        name="drone_regular",
        view="topdown", bg="white", aspect="1:1",
        subject=(
            "A medium fixed-wing military reconnaissance-strike UAV with a V-tail. Nose pointing "
            "straight up toward the top edge of the image. From above you see: the wing planform "
            "(medium gray fuselage, darker swept wings), a dark camera lens circle on the nose, the "
            "V-tail at the bottom, and a small pusher propeller disk at the rear. The drone floats "
            "alone with nothing beneath it. "
            "Medium gray color scheme — NOT white, NOT camouflage, NOT olive. No white highlights, "
            "no specular reflections, no bright spots. All surfaces must be clearly darker than "
            "pure white."
        ),
        palette="medium gray (#909090) fuselage, darker gray (#6E6E6E) wings, dark gray (#555555) outlines, tiny red navigation lights",
    ),
    Sprite(
        name="drone_shahed",
        view="topdown", bg="white", aspect="1:1",
        refs=("drone_regular",),
        subject=(
            "A delta-wing kamikaze drone (Shahed-136 style). Nose pointing straight up toward the "
            "top edge. From above you see: a prominent cylindrical warhead nose section at the top "
            "(clearly larger and distinct from the body), transitioning into a triangular delta "
            "wing — the entire drone looks like an arrowhead pointing up. Short fuselage merged "
            "with the swept wings, no visible tail. NO propeller — the propeller will be added "
            "programmatically. The drone floats alone with nothing beneath it. "
            "Medium gray color scheme — NOT white, NOT camouflage, NOT olive. No white highlights, "
            "no specular reflections, no bright spots. All surfaces must be clearly darker than "
            "pure white."
        ),
        palette="medium gray (#909090) wings, lighter gray (#A8A8A8) warhead nose, dark gray (#555555) outlines",
    ),
    Sprite(
        name="drone_orlan",
        view="topdown", bg="white", aspect="1:1",
        refs=("drone_regular",),
        subject=(
            "A small high-wing reconnaissance UAV with a tractor (puller) propeller at the nose. "
            "Nose with propeller pointing straight up toward the top edge. CLEAN FUSELAGE — straight "
            "tapered wings, twin tail booms with a conventional horizontal stabilizer at the rear. "
            "The body of the plane must be completely plain and uncluttered. Medium gray color "
            "scheme — NOT white, NOT camouflage, NOT olive. No white highlights, no specular "
            "reflections, no bright spots. All surfaces must be clearly darker than pure white."
        ),
        palette="medium gray (#909090) fuselage, lighter gray (#A8A8A8) wings, dark gray (#555555) outlines, gray propeller",
    ),
    Sprite(
        name="drone_kamikaze",
        view="topdown", bg="white", aspect="1:1",
        refs=("drone_regular",),
        subject=(
            "A small FPV kamikaze quadcopter. Front pointing straight up toward the top edge. From "
            "above you see: an X-shaped carbon fiber frame with 4 propeller disks (one at each arm "
            "tip), a small attached munition/payload at the front arm. Matte black, aggressive "
            "compact form. The drone floats alone with nothing beneath it."
        ),
        palette="matte dark gray (#333333), tiny red LED",
    ),
    Sprite(
        name="drone_ew",
        view="topdown", bg="white", aspect="1:1",
        refs=("drone_regular",),
        subject=(
            "An electronic warfare UAV with multiple antenna arrays and EW pods on the wings. Nose "
            "pointing straight up toward the top edge. Medium fixed-wing drone with distinctive "
            "purple/magenta (#8B008B) LED strips along the wings for identification. Dark gray body, "
            "antennas protruding from the fuselage."
        ),
        palette="dark gray body, purple/magenta (#8B008B) accent glow",
    ),
    Sprite(
        name="drone_heavy",
        view="topdown", bg="white", aspect="1:1",
        refs=("drone_regular",),
        subject=(
            "A large hexacopter drone (DJI Matrice 600 style) repurposed for bomb dropping. From "
            "above you see: a central dark body/hub, 6 arms radiating outward (like a star/hexagon), "
            "a bomb payload suspended underneath the center. NO propellers on the sprite — propellers "
            "will be added programmatically as 6 spinning rectangles. The arms should have visible "
            "motor mounts (small circles) at each tip but NO propeller blades. Dark gray industrial "
            "drone body. The drone floats alone with nothing beneath it."
        ),
        palette="dark charcoal (#3A3A3A) body, medium gray (#666666) arms, dark (#444444) motor mounts at arm tips",
    ),
    Sprite(
        name="drone_lancet",
        view="topdown", bg="white", aspect="1:1",
        refs=("drone_regular",),
        subject=(
            "A loitering munition drone (ZALA Lancet style). Nose pointing straight up toward the "
            "top edge. From above you see: a narrow cylindrical GRAY body with a sharp pointed nose "
            "at the top. Cruciform (X-shaped) TAIL FINS at the rear/bottom of the body, and "
            "cruciform (X-shaped) WINGS at the mid-body — both sets in X arrangement. Two YELLOW "
            "accent stripes across the body: one stripe just behind the sharp nose tip, and another "
            "stripe at mid-body just in front of the wings. NO propeller on the sprite — propeller "
            "will be added programmatically at the rear. The drone floats alone with nothing beneath it."
        ),
        palette="medium gray (#808080) body, lighter gray (#999999) wings and tail fins, yellow (#D4A017) accent stripes, dark gray (#555555) outlines",
    ),
    Sprite(
        name="drone_bomber",
        view="topdown", bg="white", aspect="1:1",
        refs=("drone_regular",),
        subject=(
            "A heavy military bomber drone. Nose pointing straight up toward the top edge. From "
            "above you see: a wide fixed-wing planform with a massive center wing section, two "
            "propeller disks on the wings, a short fuselage, and a rectangular bomb bay hatch "
            "visible on the belly centerline. Dark olive military camouflage with gray patches. "
            "The drone floats alone with nothing beneath it. "
            "Muted olive color scheme — NOT white. No white highlights, no specular reflections, "
            "no bright spots. All surfaces must be clearly darker than pure white."
        ),
        palette="dark olive (#3D4B2A), gray (#707070) wing patches, dark propellers",
    ),
    Sprite(
        name="drone_swarm",
        view="topdown", bg="white", aspect="1:1",
        subject=(
            "A tiny micro-drone (nano-UAV). Minimal gray square/diamond shape with 4 barely visible "
            "rotors. Very small and simple, matte dark gray."
        ),
        palette="dark gray (#666666)",
    ),
    Sprite(
        name="bomb_aerial",
        view="side", bg="white", aspect="2:3",
        subject=(
            "A small aerial bomb falling from a drone. Cylindrical body with a streamlined nose "
            "pointing downward and 4 tail stabilizer fins at the top. Dark olive body, dull silver "
            "nose. Compact form. The bomb floats alone with nothing around it. "
            "No specular highlights, no bright white metal, no glossy reflections. All surfaces "
            "clearly darker than pure white."
        ),
        palette="dark olive (#4A5028) body, dull silver (#A8A8A8) nose cone, dark gray (#555555) stabilizers",
    ),
    Sprite(
        name="missile_enemy",
        view="side", bg="white", aspect="9:16",
        subject=(
            "A single 122mm GRAD rocket — elongated cylindrical body with 4 stabilizing fins at the "
            "rear. Bright red body, rocket motor nozzle at the tail. The rocket floats alone with "
            "nothing around it."
        ),
        palette="bright red (#D4251B), silver fin tips",
    ),
    Sprite(
        name="missile_harm",
        view="side", bg="white", aspect="9:16",
        subject=(
            "A single anti-radiation missile (HARM style), pointing upward toward the top edge. "
            "Elongated cylindrical body. Light gray (#A0A0A0) nose cone at the top. Two BLUE "
            "(#2266CC) accent stripes across the body: one just behind the nose, and another at "
            "mid-body. Cruciform (X-shaped) stabilizer fins at mid-body — they taper, getting "
            "thinner (about half thickness) toward the tips. Cruciform (X-shaped) tail fins at the "
            "rear — same shape but HALF the length of the mid-body fins. Gray body, no white areas. "
            "The missile floats alone with nothing around it."
        ),
        palette="medium gray (#888888) body, light gray (#A0A0A0) nose, blue (#2266CC) stripes, darker gray (#666666) fins",
    ),
    Sprite(
        name="missile_cruise",
        view="side", bg="white", aspect="9:16",
        subject=(
            "A single cruise missile, pointing upward toward the top edge. Elongated cylindrical "
            "gray body with a pointed nose at the top. Two small RECTANGULAR wings sticking out to "
            "the left and right at mid-body — short stubby straight wings (not swept). Small tail "
            "control fins at the rear. Neutral gray military paint, no white areas. The missile "
            "floats alone with nothing around it."
        ),
        palette="neutral gray (#808080) body, darker gray (#606060) nose, medium gray (#707070) wings and tail fins",
    ),
]


# ---------------------------------------------------------------------------
# Player projectiles
# ---------------------------------------------------------------------------

PROJECTILES = [
    Sprite(
        name="projectile_autocannon",
        view="none", bg="black", aspect="1:1",
        refs=("fx_flame_glow",),
        ref_mode="style",
        subject=(
            "A small bright yellow-green tracer round — a glowing elongated dot, anti-aircraft "
            "tracer fire effect. Bright white-yellow core with smooth radial falloff into the "
            "black background. Same radial-falloff rendering as the flame-glow reference but "
            "tinted toward yellow-green. Style-anchor for all tracer glows. "
            "Pure soft glow — only light fading into black."
        ),
        palette="bright yellow-white core (#FFF4B0), yellow mid (#FFD700), yellow-green edge (#C8D060)",
        extra="No outlines, no borders, no hard edges — only radial light falloff.",
    ),
    Sprite(
        name="projectile_sam",
        view="side", bg="white", aspect="2:3",
        subject=(
            "A single large SAM interceptor missile — long medium-gray (#9A9A9A) cylindrical body "
            "with darker gray (#7A7A7A) shading along the underside, an olive nose cone (seeker), 4 "
            "folding mid-body fins and 4 tail control surfaces. The missile floats alone with "
            "nothing around it. "
            "Medium-gray surfaces — NOT white, NOT cream, NOT pale. No white highlights, no "
            "specular reflections, no glossy areas. All body surfaces must be clearly darker than "
            "pure white — CLEARLY distinguishable from a white background."
        ),
        palette="medium gray (#9A9A9A) body, darker gray (#7A7A7A) shading, olive (#4B5320) nose, dark gray (#555555) fins, dark gray (#555555) outlines",
    ),
    Sprite(
        name="projectile_interceptor",
        view="side", bg="white", aspect="2:3",
        refs=("projectile_sam",),
        subject=(
            "A single compact guided interceptor missile — shorter than the SAM missile, "
            "medium-gray (#9A9A9A) cylindrical body with darker gray (#7A7A7A) shading along the "
            "underside, a black nose cone (seeker), 4 small tail fins. The missile floats alone "
            "with nothing around it. "
            "Medium-gray surfaces — NOT white, NOT cream, NOT pale. No white highlights, no "
            "specular reflections, no glossy areas. All body surfaces must be clearly darker than "
            "pure white — CLEARLY distinguishable from a white background."
        ),
        palette="medium gray (#9A9A9A) body, darker gray (#7A7A7A) shading, black (#1A1A1A) nose, dark gray (#555555) fins, dark gray (#555555) outlines",
    ),
    Sprite(
        name="projectile_ciws",
        view="none", bg="black", aspect="1:1",
        refs=("projectile_autocannon",),
        ref_mode="style",
        subject=(
            "A small bright orange tracer round — a glowing elongated dot, rapid-fire "
            "anti-aircraft tracer effect. Bright white-yellow core with orange outer glow and "
            "smooth radial falloff into the black background. Same rendering family as the "
            "autocannon tracer reference (shape, falloff, line weight), tinted warm orange. "
            "Pure soft glow — only light fading into black."
        ),
        palette="white core (#FFF4C0), orange mid (#FF8C00), yellow edge glow (#FFD760)",
        extra="No outlines, no borders, no hard edges — only radial light falloff.",
    ),
    Sprite(
        name="projectile_pzrk",
        view="side", bg="white", aspect="2:3",
        refs=("projectile_sam",),
        subject=(
            "A single MANPADS infrared-guided missile — small compact missile with an IR seeker "
            "dome on the nose, olive-green body, 4 pop-out fins. The missile floats alone with "
            "nothing around it. No smoke trail. "
            "No pure white areas, no specular highlights, no glossy reflections."
        ),
        palette="olive-green (#4B5320) body, dark (#2A2A2A) IR dome, gray (#707070) fins",
    ),
    Sprite(
        name="projectile_gepard",
        view="none", bg="black", aspect="1:1",
        refs=("projectile_autocannon",),
        ref_mode="style",
        subject=(
            "A medium-brightness yellow 35mm tracer round — a glowing dot, slightly larger than a "
            "standard tracer. Bright white-yellow core with yellow outer glow and smooth radial "
            "falloff into the black background. Same rendering family as the autocannon tracer "
            "reference, tinted bright yellow and slightly larger. "
            "Pure soft glow — only light fading into black."
        ),
        palette="white-hot core (#FFFFE0), bright yellow mid (#FFFF00), warm yellow edge (#FFC820)",
        extra="No outlines, no borders, no hard edges — only radial light falloff.",
    ),
]


# ---------------------------------------------------------------------------
# Simple VFX
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Simple VFX
#
# Puffs/flames are bg="black" + alpha-from-luminosity: what the model paints as
# "medium gray" composites as ~60% alpha, "dark gray" as ~30%. We write actual
# RGB colors (not "60% opacity") because the model can't render opacity — only
# color — and the post-processor derives alpha from brightness.
#
# Refs weave everything into one visual family:
#   fx_flame_glow        — ref: fx_explosion_medium_f3 (shares fireball palette)
#   fx_smoke_puff        — ref: fx_explosion_medium_f6 (shares dissipating-smoke tone)
#   fx_smoke_puff_gray   — ref: fx_smoke_puff
#   fx_damage_smoke      — ref: fx_smoke_puff
#   fx_rocket_trail_puff — ref: fx_flame_glow (hot exhaust, glows warmer than smoke)
#   fx_ew_bolt_*         — standalone family (jagged is the sub-anchor; the rest
#                          ref jagged for style — magenta/violet electrical palette)
# ---------------------------------------------------------------------------

VFX_SIMPLE = [
    Sprite(
        name="fx_smoke_puff",
        view="none", bg="black", aspect="1:1",
        refs=("fx_explosion_medium_f6",),
        ref_mode="style",
        subject=(
            "A simple 2D cartoon white-gray smoke puff — a soft round fluffy cloud shape with "
            "slightly uneven edges. Bright, near-white core (#F4F4F4) fading smoothly into soft "
            "mid-gray (#A0A0A0) at the outer edge, then into pure black background. "
            "Used for rocket launch smoke and friendly projectile trails — so the core must read "
            "as bright on a dark battlefield. NO black outline, NO dark border, NO dark rim — "
            "the edge is a pure soft radial falloff from gray directly into the black background."
        ),
        palette="near-white core (#F4F4F4), mid-gray mid (#A0A0A0), pure black outside",
    ),
    Sprite(
        name="fx_smoke_puff_gray",
        view="none", bg="black", aspect="1:1",
        refs=("fx_smoke_puff",),
        subject=(
            "A simple 2D cartoon mid-gray smoke puff — same soft round fluffy cloud shape as the "
            "white puff, but painted in medium gray (#B0B0B0) at the core fading to darker gray "
            "(#606060) at the edge. Used for enemy missile exhaust — reads as cooler/darker than "
            "the friendly white puff. NO black outline, NO dark border, NO dark rim — the edge "
            "is a pure soft radial falloff from dark gray directly into the black background."
        ),
        palette="medium gray core (#B0B0B0), darker gray edge (#606060), pure black outside",
    ),
    Sprite(
        name="fx_flame_glow",
        view="none", bg="black", aspect="1:1",
        refs=("fx_explosion_medium_f3",),
        ref_mode="style",
        subject=(
            "A simple 2D cartoon flame glow point — a bright orange-red dot with intense white-hot "
            "core fading to dim orange edges. Pure radial gradient from white-orange center to "
            "black background. Used as missile ignition flash and as a style anchor for every "
            "warm-glow VFX in the game (muzzle flashes, tracers, exhaust). Must carry the same "
            "orange-yellow fireball palette as the explosion anchor."
        ),
        palette="white-hot center (#FFF6D0), bright orange mid (#FF8A1F), deep red edge (#C03010)",
    ),
    Sprite(
        name="fx_damage_smoke",
        view="none", bg="black", aspect="1:1",
        refs=("fx_smoke_puff",),
        subject=(
            "A simple 2D cartoon dark smoke puff — a soft round fluffy cloud shape painted in "
            "dark gray (#606060) at the core fading to very dark gray (#303030) at the edges "
            "(will composite as ~40% alpha after luminosity-based alpha extraction). Used as a "
            "slow-drift emission from a damaged or disabled tower. NO black outline, NO dark "
            "border, NO dark rim — the edge is a pure soft radial falloff from dark gray "
            "directly into the black background."
        ),
        palette="dark gray core (#606060), very dark gray edge (#303030), pure black outside",
    ),
    Sprite(
        name="fx_rocket_trail_puff",
        view="none", bg="black", aspect="1:1",
        refs=("fx_flame_glow",),
        ref_mode="style",
        subject=(
            "A simple 2D cartoon hot-exhaust puff — a small ROUND, RADIALLY SYMMETRIC fluffy "
            "puff with a warm glowing center and a soft warm-gray outer halo, like a glowing "
            "ember or a tiny ball of hot exhaust gas. Bright orange-white core in the middle "
            "fading evenly outward to warm gray with a subtle orange tint, then to pure black "
            "background. Smaller, tighter, and warmer than a regular smoke puff — this is the "
            "ignition-side trail just after a rocket leaves the launcher, not the cold drifting "
            "smoke further back. Single frame, no motion blur. CRITICAL: no tail, no streaks, "
            "no comet-like trail, no elongation in any direction — purely circular blob with "
            "radial falloff. Width and height are equal."
        ),
        palette="orange-white core (#FFD08A), warm gray halo (#8A7060), pure black outside",
    ),
    # ─────────────────────────────────────────────────────────────────────
    # EW jamming lightning bolts (5 variants).
    # Used by EWDroneEntity in place of the procedural SKShapeNode zigzag.
    # Inspired by Vampire Survivors / Hades electric VFX: sharp angular
    # zigzags with a white-hot core and saturated magenta glow on pure black.
    # ─────────────────────────────────────────────────────────────────────
    Sprite(
        name="fx_ew_bolt_jagged",
        view="none", bg="black", aspect="9:16",
        subject=(
            "A single vertical lightning bolt — a sharp angular ZIGZAG running roughly top-to-"
            "bottom of the frame, with 6-8 STRAIGHT segments meeting at SHARP CORNERS (no smooth "
            "curves, no bezier arcs). Each segment is 12-20% of the frame's height; consecutive "
            "segments alternate left/right of the central axis with deflection angles around "
            "35-55° from vertical, so the bolt looks like a real fork-lightning streak frozen in "
            "place. The whole zigzag drifts laterally by no more than ~25% of the frame width. "
            "Stroke construction (cross-section): a 1-2 px WHITE-HOT core (#FFFFFF), a 3-4 px "
            "saturated magenta glow band (#C040FF) hugging the core, then a 2-3 px softer violet "
            "halo (#602080) fading into the pure black background. Floats alone on pure black "
            "with nothing else — no clouds, no drone, no impact, no other sparks. Used as the "
            "base 'crackle' bolt of an EW drone."
        ),
        palette="white-hot core (#FFFFFF), magenta glow (#C040FF), violet halo (#602080), pure black background",
        extra=(
            "CRITICAL: NO black outline, NO dark border around the bolt — the alpha extraction "
            "uses luminosity, so any dark rim becomes a hole. Edges are a pure soft radial "
            "falloff from violet halo into black. The bolt MUST be straight-line segments with "
            "sharp angular corners — no curves, no smoothing, no painterly strokes."
        ),
    ),
    Sprite(
        name="fx_ew_bolt_forked",
        view="none", bg="black", aspect="4:5",
        refs=("fx_ew_bolt_jagged",),
        ref_mode="style",
        subject=(
            "A Y-SHAPED forked lightning bolt. A main TRUNK descends from the top of the frame "
            "as a sharp angular zigzag (5-6 straight segments, each 10-18% of frame height, "
            "meeting at hard corners) down to roughly 55-65% of the frame's height — then "
            "SPLITS into TWO BRANCHES at the fork point: one branch heads down-left at about "
            "30° from vertical (3 segments), the other heads down-right at about 45° from "
            "vertical (4 segments, reaching close to the bottom-right corner). The fork must "
            "look like a NATURAL CONTINUATION of the discharge — at the split point both "
            "branches start with EXACTLY the same stroke thickness as the trunk's last segment "
            "and only taper down toward their tips over the final 1-2 segments. There is NO "
            "ball, NO star burst, NO bright corona, NO accent node at the split point — just "
            "two glowing lines diverging cleanly from one. Stroke construction (uniform along "
            "trunk and branch starts): 2 px white-hot core (#FFFFFF), 4 px magenta glow "
            "(#C040FF), 2-3 px violet halo (#602080) into pure black. The very tips of the "
            "branches narrow to a 1 px core / 2 px glow over the last segment. Pure black "
            "elsewhere. Sharp corners only — no curves, no curls."
        ),
        palette="white-hot core (#FFFFFF), magenta glow (#C040FF), violet halo (#602080), pure black background",
        extra=(
            "CRITICAL: NO black outline or dark border anywhere on the bolt. Trunk and both "
            "branches are made of STRAIGHT SEGMENTS with hard angular corners — no smoothing, "
            "no bezier arcs. NO bright burst, NO star, NO ball, NO corona at the fork point — "
            "the split must look organic, like one bolt becoming two of equal initial "
            "thickness. The fork point is just a sharp angular Y-junction, not a highlight."
        ),
    ),
    Sprite(
        name="fx_ew_bolt_branching",
        view="none", bg="black", aspect="3:4",
        refs=("fx_ew_bolt_jagged",),
        ref_mode="style",
        subject=(
            "A tree-shaped lightning bolt with multiple branches. A long main TRUNK runs the "
            "full height of the frame as a sharp angular zigzag (7-9 straight segments, sharp "
            "corners, alternating left/right around the central axis). Off the trunk THREE "
            "branches break away at three different heights — at about 25%, 55%, and 75% from "
            "the top. The 25% branch goes left, the 55% branch goes right, the 75% branch goes "
            "left again, alternating sides. Each branch is 3-4 straight segments long, "
            "reaching 35-50% of the frame width outward from the trunk, ending in a clean "
            "sharp tip (no spark, no dot, no accent). EVERY segment — trunk and branches alike "
            "— uses the SAME uniform stroke: 2 px white-hot core (#FFFFFF), 4 px magenta glow "
            "(#C040FF), 2-3 px violet halo (#602080) into pure black. Branches are NOT thinner "
            "than the trunk; they are full-thickness bolts diverging from it. Each branch "
            "leaves the trunk as a clean sharp-angle Y-junction — no burst, no star, no ball, "
            "no bright node at the branching point. Floats alone on pure black with nothing "
            "else around it. Sharp angular corners ONLY — no curves, no smoothing."
        ),
        palette="white-hot core (#FFFFFF), magenta glow (#C040FF), violet halo (#602080), pure black background",
        extra=(
            "CRITICAL: NO black outline, NO dark border. The trunk runs continuously from top "
            "to bottom; branches break OFF the trunk and never cross it. Branches MUST be the "
            "same stroke thickness as the trunk — do not taper, do not thin them down. NO "
            "highlights, sparks, bursts, or bright nodes at the branching points or at the "
            "branch tips. All segments are dead-straight lines with hard corners."
        ),
    ),
    Sprite(
        name="fx_ew_bolt_twin",
        view="none", bg="black", aspect="9:16",
        refs=("fx_ew_bolt_jagged",),
        ref_mode="style",
        subject=(
            "A TWIN lightning discharge — two zigzag bolts running top-to-bottom of the frame, "
            "both starting from a single shared point at the top and both ending at separate "
            "points near the bottom. As they descend the two bolts ACTUALLY CROSS EACH OTHER "
            "2-3 times — their paths must visibly INTERSECT and overlap, not run parallel: at "
            "each crossing one bolt's segment passes through the other's segment to form a "
            "clear X-junction. Between crossings they swing left and right of an imaginary "
            "central axis with mirror-ish but not identical jitter, so they look like two real "
            "discharges arguing around the axis (not two parallel copies). Each bolt has 6-7 "
            "sharp angular segments, hard corners, no curves. Each bolt's stroke is uniform "
            "all the way through — including at the crossings: 2 px white-hot core (#FFFFFF), "
            "3 px magenta glow (#C040FF), 2 px violet halo (#602080) into pure black. There "
            "are NO bright nodes, NO corona bursts, NO star shapes, NO ball highlights at the "
            "intersection points — the crossings are simply where the two bolt strokes overlap "
            "naturally. Pure black background, no other elements."
        ),
        palette="white-hot core (#FFFFFF), magenta glow (#C040FF), violet halo (#602080), pure black background",
        extra=(
            "CRITICAL: NO black outline, NO dark border. The two bolts MUST INTERSECT visibly "
            "2-3 times along their length — if they only run parallel without crossing, the "
            "sprite is wrong. The crossings are clean X-overlaps of the two strokes; do NOT "
            "add any bright burst, corona, star, or ball at the intersection points. All "
            "segments are straight lines with sharp angular corners — no curves, no smoothing."
        ),
    ),
    Sprite(
        name="fx_ew_bolt_burst",
        view="none", bg="black", aspect="1:1",
        refs=("fx_ew_bolt_jagged",),
        ref_mode="style",
        subject=(
            "A radial DISCHARGE of lightning bolts emanating OUTWARD from a single shared "
            "central point at the exact center of the frame. FIVE zigzag lightning bolts "
            "ALL begin at the SAME central pixel and shoot outward in different directions, "
            "spaced at roughly 70-75° intervals around the center but slightly irregular — "
            "not a perfectly symmetric snowflake. Each bolt is a 4-5-segment zigzag with "
            "sharp angular corners (no curves), reaching outward to about 90-95% of the "
            "frame's half-width. Each bolt is oriented roughly along its radial direction "
            "but jitters left/right of that axis as it travels outward. Bolt lengths are "
            "uneven — 3 are full length, 2 are about 75% as long — so the silhouette is "
            "asymmetric. Stroke construction (uniform along every bolt): 2 px white-hot "
            "core (#FFFFFF), 3 px magenta glow (#C040FF), 2 px violet halo (#602080) into "
            "pure black. The five bolts share their inner endpoints EXACTLY — they all meet "
            "at the central point with their inner ends, like spokes of a wheel. The "
            "convergence point itself is just where the strokes overlap; do NOT add a "
            "glowing ball, white disc, light orb, halo, corona, star burst, empty hole, or "
            "any other bright or dark artifact at the center — the center is purely the "
            "meeting point of the five bolt strokes, no extra graphic. Each bolt tapers "
            "slightly toward its outer tip (full thickness for the first 70%, narrowing to "
            "1 px core / 2 px glow at the tip). Floats alone on pure black, no other elements."
        ),
        palette="white-hot core (#FFFFFF), magenta glow (#C040FF), violet halo (#602080), pure black background",
        extra=(
            "CRITICAL: the center of the frame is the SHARED ORIGIN of all five bolts — they "
            "ALL start at the same central pixel and shoot outward. NO white disc, NO light "
            "ball, NO glowing orb, NO bright halo, NO corona, NO star burst, NO empty hole, "
            "NO circular gap at the center. The center has NO separate visual element — it "
            "is simply where the five bolt strokes converge and overlap. NO black outline, "
            "NO dark border on the bolts. All segments are dead-straight lines with hard "
            "angular corners — no curves, no smoothing. Bolt angles must be slightly "
            "irregular — not a perfect five-pointed snowflake."
        ),
    ),
]


# ---------------------------------------------------------------------------
# Explosion animation frames
#
# Star-graph refs design (not a linear chain):
#   - fx_explosion_medium_f3 is the GLOBAL VFX ANCHOR (peak fireball, canon
#     palette). It has no refs and is generated first. Everything else pulls
#     its style from this one image (including fx_flame_glow / fx_smoke_puff
#     which ref the anchor / the final smoke frame of the medium sequence).
#   - fx_explosion_{small,large}_f3 are SIZE SUB-ANCHORS. They ref ONLY the
#     global anchor so they inherit palette + fireball style but define their
#     own scale character.
#   - Every other frame `fN` refs (prev_frame, size_anchor_f3): the previous
#     frame carries temporal continuity (position/smoke state), the anchor
#     pins the overall style so drift over 5-7 frames stays bounded.
#
# All frames are sent with ref_mode="temporal" so the model is instructed
# to PRESERVE center/composition/palette (unlike the default style-ref
# preamble which tells the model to intentionally diverge).
#
# Build order in SPRITES: EXPLOSION_ANCHORS first (medium_f3 → small_f3, large_f3),
# then the remaining frames — so every ref is already generated when its
# dependents run.
# ---------------------------------------------------------------------------

_CANVAS_LOCK_CLAUSE = (
    "Canvas bounds and center are IDENTICAL across every frame of this sequence — "
    "the effect grows and decays symmetrically from the exact image center. "
    "Empty regions around the effect are pure black (#000000), nothing else — "
    "no drifting debris outside the effect radius, no off-center wisps, no camera shake."
)


def _explosion_intermediate(name: str, frame_label: str, total_label: str,
                            description: str, prev_frame: str, next_frame: str,
                            anchor: str) -> Sprite:
    """Build a half-step intermediate frame that sits temporally between two
    main frames (e.g. f1_5 between f1 and f2). Refs both neighbors so the
    model sees the before/after state and interpolates. `ref_mode="temporal"`
    preserves center/composition/palette — the intermediate inherits scale
    and position from the neighbors, only the fireball/smoke state differs.
    """
    subject = (
        f"Frame {frame_label} of {total_label} in a cartoon explosion animation sequence — "
        f"a transitional half-step sitting exactly between the previous and next main frames. "
        f"{description} All frames of this animation must share the same center alignment, "
        f"top-down viewing angle, palette, and cartoon style so the sequence plays "
        f"smoothly when animated."
    )
    refs: list[str] = [prev_frame, next_frame]
    if anchor not in refs and anchor != name:
        refs.append(anchor)
    return Sprite(
        name=name,
        view="none", bg="black", aspect="1:1",
        refs=tuple(refs),
        ref_mode="temporal",
        alpha_mode="auto",
        subject=subject,
        extra=_CANVAS_LOCK_CLAUSE,
    )


def _explosion_frame(name: str, frame_no: int, total: int, description: str,
                     prev_frame: str | None, anchor: str | None = None) -> Sprite:
    """Build one explosion frame. `prev_frame` is temporal continuity, `anchor`
    is the size sub-anchor that pins style across the whole sequence. Both go
    into refs (deduplicated, prev_frame first so the model sees the most
    recent state earliest). ref_mode="temporal" so the preamble tells the
    model to PRESERVE center/composition/palette, not diverge like style refs.

    Late frames (the second-to-last and last of each sequence) are dominated
    by DARK smoke on a black background. Luminosity-to-alpha would fade that
    smoke to ~30% opacity — we override with alpha_mode="keyed" (chroma-key
    against the black corners) so the smoke keeps its intended opacity.
    """
    subject = (
        f"Frame {frame_no} of {total} in a cartoon explosion animation sequence. "
        f"{description} All frames of this animation must share the same center alignment, "
        f"top-down viewing angle, palette, and cartoon style so the sequence plays "
        f"smoothly when animated."
    )
    refs: list[str] = []
    if prev_frame:
        refs.append(prev_frame)
    if anchor and anchor != prev_frame and anchor != name:
        refs.append(anchor)
    # The last 2 frames of every size are the smoke-dominated ones.
    alpha_mode = "keyed" if frame_no >= total - 1 else "auto"
    return Sprite(
        name=name,
        view="none", bg="black", aspect="1:1",
        refs=tuple(refs),
        ref_mode="temporal",
        alpha_mode=alpha_mode,
        subject=subject,
        extra=_CANVAS_LOCK_CLAUSE,
    )


EXPLOSION_ANCHORS = [
    # Global anchor — the canon fireball for the whole game.
    _explosion_frame("fx_explosion_medium_f3", 3, 6,
        "Orange fireball at maximum intensity, a faint dark smoke ring just starting at the "
        "edges, size ~60% of final radius. Cartoon-stylized bright yellow-orange body with a "
        "white-hot center point, soft radial falloff into black. This frame is the CANON "
        "VFX fireball — it defines the palette, line weight, and smoke-fringe style for every "
        "explosion frame in the game. No debris, no flying fragments.",
        prev_frame=None, anchor=None),
    # Small sub-anchor
    _explosion_frame("fx_explosion_small_f3", 3, 5,
        "Orange fireball at maximum brightness, dark smoke beginning at edges, size ~65% of "
        "final radius. Palette, line weight, and smoke style matched exactly to the medium "
        "fireball anchor — only the overall scale character differs (tighter core, sharper "
        "falloff). Small-explosion peak.",
        prev_frame=None, anchor="fx_explosion_medium_f3"),
    # Large sub-anchor
    _explosion_frame("fx_explosion_large_f3", 3, 7,
        "Intense orange fireball at peak brightness with a yellow-white hot center, a soft "
        "smoke ring starting to form at the edges, size ~50% of final radius. Palette and "
        "cartoon style matched to the medium fireball anchor, but with a brighter white-hot "
        "core and a larger nascent smoke ring. Large-explosion peak.",
        prev_frame=None, anchor="fx_explosion_medium_f3"),
]

EXPLOSION_SMALL = [
    _explosion_frame("fx_explosion_small_f1", 1, 5,
        "A bright white-hot point at center, just the beginning of the flash, "
        "size ~20% of final radius. This is a small explosion (bullet burst / drone hit).",
        prev_frame=None, anchor="fx_explosion_small_f3"),
    _explosion_intermediate("fx_explosion_small_f1_5", "1.5", "5",
        "Halfway between the initial white flash and the expanding fireball — white-hot "
        "core beginning to bloom, faintest hint of yellow-orange just starting to form "
        "around it, size ~19% of final radius.",
        prev_frame="fx_explosion_small_f1", next_frame="fx_explosion_small_f2",
        anchor="fx_explosion_small_f3"),
    _explosion_frame("fx_explosion_small_f2", 2, 5,
        "White core expanding, surrounded by a yellow-orange fireball, "
        "size ~18% of final radius.",
        prev_frame="fx_explosion_small_f1", anchor="fx_explosion_small_f3"),
    _explosion_intermediate("fx_explosion_small_f2_5", "2.5", "5",
        "Halfway between the young fireball and the peak fireball — white core shrinking "
        "as the yellow-orange fireball brightens and expands toward maximum intensity, "
        "faintest dark smoke fringe beginning at outer edge, size ~40% of final radius.",
        prev_frame="fx_explosion_small_f2", next_frame="fx_explosion_small_f3",
        anchor="fx_explosion_small_f3"),
    _explosion_intermediate("fx_explosion_small_f3_5", "3.5", "5",
        "Halfway between the peak fireball and the decaying fireball — bright orange body "
        "still dominant but the white-hot center is fading into yellow, smoke ring growing "
        "noticeably thicker around the edges, a hint of red at the outer flames, "
        "size ~75% of final radius.",
        prev_frame="fx_explosion_small_f3", next_frame="fx_explosion_small_f4",
        anchor="fx_explosion_small_f3"),
    _explosion_frame("fx_explosion_small_f4", 4, 5,
        "Flames fading to orange-red, gray smoke expanding outward, tiny debris fragments "
        "visible, size ~85% of final radius.",
        prev_frame="fx_explosion_small_f3", anchor="fx_explosion_small_f3"),
    _explosion_frame("fx_explosion_small_f5", 5, 5,
        "Thin gray wisps of smoke, nearly fully transparent, no flames remaining, "
        "size 100% of final radius. This is the last frame.",
        prev_frame="fx_explosion_small_f4", anchor="fx_explosion_small_f3"),
]

EXPLOSION_MEDIUM = [
    _explosion_frame("fx_explosion_medium_f1", 1, 6,
        "A bright white-hot point at center, just the beginning of detonation, "
        "size ~20% of final radius. This is a medium-sized explosion (missile impact).",
        prev_frame=None, anchor="fx_explosion_medium_f3"),
    _explosion_intermediate("fx_explosion_medium_f1_5", "1.5", "6",
        "Halfway between the initial white flash and the expanding fireball — white-hot "
        "core beginning to bloom, faint yellow-orange just starting to form around it, "
        "size ~19% of final radius.",
        prev_frame="fx_explosion_medium_f1", next_frame="fx_explosion_medium_f2",
        anchor="fx_explosion_medium_f3"),
    _explosion_frame("fx_explosion_medium_f2", 2, 6,
        "White core expanding, surrounded by an intense yellow-orange fireball, "
        "size ~18% of final radius.",
        prev_frame="fx_explosion_medium_f1", anchor="fx_explosion_medium_f3"),
    _explosion_intermediate("fx_explosion_medium_f2_5", "2.5", "6",
        "Halfway between the young fireball and the peak fireball — white core shrinking "
        "as the yellow-orange fireball brightens and expands toward maximum intensity, "
        "faintest dark smoke fringe beginning at outer edge, size ~38% of final radius.",
        prev_frame="fx_explosion_medium_f2", next_frame="fx_explosion_medium_f3",
        anchor="fx_explosion_medium_f3"),
    _explosion_intermediate("fx_explosion_medium_f3_5", "3.5", "6",
        "Halfway between the peak fireball and the decaying fireball — bright orange body "
        "still dominant but the white-hot center is fading into yellow, dark smoke ring "
        "growing thicker around the edges, a hint of red at the outer flames, "
        "size ~70% of final radius.",
        prev_frame="fx_explosion_medium_f3", next_frame="fx_explosion_medium_f4",
        anchor="fx_explosion_medium_f3"),
    _explosion_frame("fx_explosion_medium_f4", 4, 6,
        "Large fireball still dominating the frame, half yellow and half red with a smooth "
        "gradient from the yellow hot core into the red outer flames — no sharp boundary. "
        "Dark smoke expanding outward, small debris fragments visible, size ~80% of final radius.",
        prev_frame="fx_explosion_medium_f3", anchor="fx_explosion_medium_f3"),
    _explosion_frame("fx_explosion_medium_f5", 5, 6,
        "Red-brown remnants, gray-black smoke dominates, center clearing, "
        "size ~95% of final radius.",
        prev_frame="fx_explosion_medium_f4", anchor="fx_explosion_medium_f3"),
    _explosion_frame("fx_explosion_medium_f6", 6, 6,
        "Thin gray wisps of smoke dissipating, nearly fully transparent, "
        "size 100% of final radius. This is the last frame.",
        prev_frame="fx_explosion_medium_f5", anchor="fx_explosion_medium_f3"),
]

EXPLOSION_LARGE = [
    _explosion_frame("fx_explosion_large_f1", 1, 7,
        "A bright white-hot detonation point at center, a small blinding sphere, "
        "size ~15% of final radius. This is a large explosion (heavy drone/airstrike).",
        prev_frame=None, anchor="fx_explosion_large_f3"),
    _explosion_intermediate("fx_explosion_large_f1_5", "1.5", "7",
        "Halfway between the initial white detonation and the expanding fireball — "
        "blinding white-hot core beginning to bloom outward, faintest yellow-orange halo "
        "just forming around it, size ~16% of final radius.",
        prev_frame="fx_explosion_large_f1", next_frame="fx_explosion_large_f2",
        anchor="fx_explosion_large_f3"),
    _explosion_frame("fx_explosion_large_f2", 2, 7,
        "White core expanding, powerful yellow-orange fireball, size ~18% of final radius.",
        prev_frame="fx_explosion_large_f1", anchor="fx_explosion_large_f3"),
    _explosion_intermediate("fx_explosion_large_f2_5", "2.5", "7",
        "Halfway between the young fireball and the peak fireball — white core shrinking "
        "as the yellow-orange fireball brightens and swells toward maximum intensity, a "
        "very faint dark smoke fringe beginning at the outer edge, size ~34% of final radius.",
        prev_frame="fx_explosion_large_f2", next_frame="fx_explosion_large_f3",
        anchor="fx_explosion_large_f3"),
    _explosion_intermediate("fx_explosion_large_f3_5", "3.5", "7",
        "Halfway between the peak fireball and the decaying fireball — bright orange body "
        "still dominant but the white-hot center is fading into yellow, smoke ring around "
        "the edges thickening visibly, early orange-red tones forming at the outer flames, "
        "size ~58% of final radius.",
        prev_frame="fx_explosion_large_f3", next_frame="fx_explosion_large_f4",
        anchor="fx_explosion_large_f3"),
    _explosion_frame("fx_explosion_large_f4", 4, 7,
        "Orange-red fireball starting to fade, dark smoke ring expanding, flying debris "
        "fragments visible, size ~65% of final radius.",
        prev_frame="fx_explosion_large_f3", anchor="fx_explosion_large_f3"),
    _explosion_frame("fx_explosion_large_f5", 5, 7,
        "Red-brown flames, massive black-gray smoke cloud, debris fragments, "
        "size ~80% of final radius.",
        prev_frame="fx_explosion_large_f4", anchor="fx_explosion_large_f3"),
    _explosion_frame("fx_explosion_large_f6", 6, 7,
        "Flames nearly extinguished, dark gray smoke dominates, center clearing, "
        "size ~95% of final radius.",
        prev_frame="fx_explosion_large_f5", anchor="fx_explosion_large_f3"),
    _explosion_frame("fx_explosion_large_f7", 7, 7,
        "Dissipating gray wisps of smoke, nearly fully transparent, last particles, "
        "size 100% of final radius. This is the last frame of the sequence.",
        prev_frame="fx_explosion_large_f6", anchor="fx_explosion_large_f3"),
]


# ---------------------------------------------------------------------------
# Settlements
# ---------------------------------------------------------------------------

SETTLEMENTS = [
    Sprite(
        name="settlement_village",
        view="topdown", bg="white", aspect="1:1",
        subject=(
            "A small rural hamlet. From above you see: 3-4 tiny cottage ROOFTOPS (brown/straw "
            "colored rectangles), thin dirt paths between them, small green vegetable garden "
            "patches. Warm brown and white tones. The settlement floats alone on the background "
            "with nothing around it."
        ),
        palette="warm brown (#8B5A3C) rooftops, tan (#C9A67A) dirt paths, green (#5A7A3A) garden patches",
    ),
    Sprite(
        name="settlement_town",
        view="topdown", bg="white", aspect="1:1",
        refs=("settlement_village",),
        subject=(
            "A small urban block. From above you see: 4-6 flat ROOFTOPS of multi-story apartment "
            "buildings (gray-beige rectangles), paved roads between them, a small park with round "
            "tree canopies. Light beige and gray tones. The block floats alone on the background."
        ),
        palette="light beige (#D9C7A0) rooftops, gray (#8A8A8A) roads, green (#5A7A3A) park canopies",
    ),
    Sprite(
        name="settlement_factory",
        view="topdown", bg="white", aspect="1:1",
        refs=("settlement_village",),
        subject=(
            "A small industrial complex. From above you see: a main workshop with a zigzag/sawtooth "
            "ROOFTOP pattern, round smokestack circles, cylindrical storage tank circles, a loading "
            "ramp. Gray-blue metal roofs, concrete yard. The complex floats alone on the background."
        ),
        palette="gray-blue (#6A7888) metal roofs, concrete (#A8A49A) yard tones, dark (#3A3A3A) smokestack outlines",
    ),
    Sprite(
        name="settlement_farm",
        view="topdown", bg="white", aspect="1:1",
        refs=("settlement_village",),
        subject=(
            "A farm. From above you see: a farmhouse ROOFTOP, a barn with a red-brown ROOFTOP, a "
            "round grain silo circle, neat rows of green crop lines around the buildings, a thin "
            "dirt road. The farm floats alone on the background."
        ),
        palette="red-brown (#8B3A2A) barn rooftop, beige (#C9A67A) farmhouse, green (#5A7A3A) crop rows, tan (#B8956A) silo",
    ),
    Sprite(
        name="settlement_depot",
        view="topdown", bg="white", aspect="1:1",
        refs=("settlement_village",),
        subject=(
            "A military supply depot. From above you see: 2 long warehouse hangar ROOFTOPS, rows "
            "of small crate and container rectangles in the yard, parked military truck shapes, a "
            "thin perimeter fence outline. Olive and orange-brown tones. The depot floats alone on "
            "the background. "
            "CRITICAL: strict orthographic top-down — buildings are seen as FLAT ROOF SHAPES only. "
            "NO visible side walls, NO light-gray wall highlights on the bottom/right of rooftops, "
            "NO pseudo-3D depth, NO axonometric tilt. Each building is a flat rectangular patch of "
            "roof colour bordered by a dark outline — nothing on any side of that outline."
        ),
        palette="olive (#4B5320) warehouse roofs, orange-brown (#A85A2A) crates, dark gray (#555555) trucks",
    ),
    Sprite(
        name="settlement_refinery",
        view="topdown", bg="white", aspect="1:1",
        refs=("settlement_factory",),
        subject=(
            "An oil refinery / petrochemical plant. STRICT ORTHOGRAPHIC TOP-DOWN view — "
            "buildings are seen as FLAT ROOF SHAPES only. NO visible side walls, NO light-gray "
            "wall highlights, NO pseudo-3D depth, NO axonometric tilt.\n\n"
            "CENTRAL FEATURE — at the EXACT geometric CENTER of the tile (50%, 50%), draw a "
            "circular oil collection basin: an outer concrete ring (#A8A49A) ~18% of the tile "
            "width in outer diameter, ~3% ring thickness, surrounding an inner pool of dark "
            "crude oil (#1E1612) ~14% of the tile width. At the exact center of the basin, a "
            "small dark metal spout/wellhead nub (#3A3A3A) ~3% of tile width — this is where "
            "an oil-fountain animation overlay will be attached at runtime, so the basin and "
            "spout MUST be clearly visible and unobstructed. The basin reads as DELIBERATE "
            "INDUSTRIAL INFRASTRUCTURE, NOT a spill: the concrete ring is clean, no oil "
            "stains outside the ring, no smudges on the surrounding concrete pad, the inner "
            "pool surface is uniformly dark and flat.\n\n"
            "AROUND THE BASIN (none of these may overlap or cover the basin):\n"
            "- 2-3 large cylindrical crude-oil storage TANK ROOFTOPS (dark metal #5A6068 "
            "circles with thin radial seam lines and a central darker dot for the manhole, "
            "outer diameter ~22% of tile width each), placed in the corners of the tile\n"
            "- 1 tall narrow rectangular distillation column footprint (#6A7888) on one edge\n"
            "- A pipe rack — thin parallel lines of orange-brown pipe (#A85A2A) running "
            "between the tanks and the central basin in a clean radial / orthogonal pattern\n"
            "- A small flare-stack circle (#3A3A3A) on the opposite edge from the column\n"
            "- A concrete yard (#A8A49A) covering the empty space, with thin darker "
            "expansion-joint lines for industrial texture\n"
            "- A thin dark perimeter outline marking the facility boundary\n\n"
            "Each building is a flat rectangular or circular patch of roof colour bordered by "
            "a thin dark outline — nothing on any side of that outline. The whole refinery "
            "floats alone on a pure white background with nothing around it.\n\n"
            "OVERLAY ANCHOR (for game integration, NOT visible on the sprite): the oil "
            "fountain animation will be drawn on top of this sprite, centered at 50%, 50% of "
            "the tile, scaled to roughly the basin's outer diameter (~18% of tile width)."
        ),
        palette=(
            "dark metal tank roofs (#5A6068), gray-blue distillation column (#6A7888), "
            "concrete yard and basin ring (#A8A49A), orange-brown pipes (#A85A2A), "
            "dark crude oil pool (#1E1612), wellhead nub (#3A3A3A), thin dark outlines (#2E2A28)"
        ),
    ),
]


# ---------------------------------------------------------------------------
# Oil fountain animation frames (settlement_refinery overlay)
#
# Loopable 6-frame cycle layered on top of settlement_refinery's central
# basin. STRICT TOP-DOWN view of a vertical geyser shooting UP toward the
# camera, so we look down the axis of the column. From this angle a real
# crude-oil burst is NOT a clean circle — it has the messy fluid-dynamics
# look of a high-speed splash photograph: a dense irregular core where the
# jet's axis is, a ragged break-up zone of ligaments / tendrils tearing
# off the rim, and scattered satellite droplets thrown out asymmetrically
# in clumps and gaps. Photo-real fluid chaos, just rendered in cartoon
# flat color.
#
# The basin lives in the BASE sprite (always visible underneath); the
# overlay renders ONLY the splash on pure white. The f6→f1 seam is
# bounded because both endpoints are minimum-energy frames (small dense
# core, almost no break-up) — even with random asymmetry the silhouettes
# are similar enough that the loop reads as continuous.
#
# Anchor: f3 (peak burst, no refs — defines the canonical look).
# Generation order: f3 → f2/f4 → f1/f5 → f6. Every non-anchor frame refs
# (closer-to-anchor neighbour, f3 anchor) under ref_mode="temporal" so
# the model preserves center alignment, scale, and palette across the
# loop while letting the chaotic detail vary per frame.
# ---------------------------------------------------------------------------

_OIL_FOUNTAIN_SMALL_RENDER_CLAUSE = (
    "CRITICAL — RENDER SIZE: this sprite is composited into the game at SMALL "
    "size (roughly 64-96 pixels on screen). At that size, dozens of tiny "
    "droplets become visual NOISE / RIPPLE that hurts the eye. Therefore: "
    "keep the splash composed of a SMALL NUMBER of LARGE, BOLD, CLEAR shapes. "
    "It is FAR BETTER to have 3-5 well-defined droplets than 15 tiny ones. "
    "A few big chunky drops, each clearly visible, beats a cloud of pixel-"
    "size specks every single time. The CORE silhouette is the dominant "
    "readable shape — invest detail there, not in surrounding mist."
)

_OIL_FOUNTAIN_REFERENCE_CLAUSE = (
    "REFERENCE LOOK: think of a high-speed photograph of a water/liquid splash — "
    "but viewed from STRAIGHT ABOVE looking down the axis of the jet, rendered "
    "in opaque crude-oil tones instead of clear water, and SIMPLIFIED to a few "
    "bold shapes for small-sprite readability. A top-down splash at this scale "
    "has TWO main zones:\n"
    "  1. CORE — a dense dark blob where the jet's column meets the air. The "
    "     outline is RAGGED and ORGANIC, never a clean circle: it has lobes, "
    "     bulges, and a few concave bites. Inside, the oil is opaque and "
    "     uniform. The core dominates the silhouette and is what reads at "
    "     small sprite size.\n"
    "  2. A FEW LARGE SATELLITE DROPLETS — only a handful of airborne drops "
    "     scattered ASYMMETRICALLY around the core. Each drop is CHUNKY and "
    "     CLEARLY VISIBLE on its own (think: ink-splatter dots, not a cloud "
    "     of pixels). Drops vary in size and distance, and they cluster on "
    "     ONE OR TWO sides of the core — the other sides have NO drops at "
    "     all. NEVER an even ring around the center.\n"
    "Optionally 1-2 short SHORT THICK ligaments / fingers may extend from the "
    "core's rim toward an outer drop, but only a couple — they should not "
    "cover the rim. Asymmetry is the whole point: real fluid is never tidy."
)

_OIL_FOUNTAIN_LOCK_CLAUSE = (
    "Canvas bounds and approximate center are stable across every frame of "
    "this loop — the wellhead spout is roughly at the GEOMETRIC CENTER of "
    "the square frame so the splash builds up from the same point. Empty "
    "regions are pure white (#FFFFFF). "
    "SEPARATE game sprite — do NOT draw the refinery, do NOT draw the basin, "
    "do NOT draw any concrete ring, do NOT draw the ground, do NOT draw any "
    "buildings, pipes, or any kind of structure. Output ONLY the splash "
    "itself (core + a few scattered droplets), floating alone on pure white. "
    "NO vertical oil column visible, NO sideways spray, NO horizontal spill — "
    "this is a top-down view of a geyser shooting straight UP toward the "
    "camera. NO blue, cyan, or teal tones — this is opaque dark crude oil, "
    "not water. NO motion-blur streaks, NO comet tails — drops are dense "
    "oil blobs frozen in mid-air."
)

_OIL_FOUNTAIN_ANTI_PERFECTION_CLAUSE = (
    "DO NOT draw a clean circle for the core. DO NOT draw a ring of droplets "
    "of any kind. DO NOT distribute droplets symmetrically. DO NOT space "
    "droplets at equal angles. DO NOT cover the rim with droplets evenly. "
    "DO NOT render fine spray, mist, micro-droplets, fog, or any cloud of "
    "tiny particles — they will look like noise at small sprite size. "
    "DO NOT add motion-blur streaks or trailing dots. The splash is composed "
    "of a SMALL handful of CHUNKY clearly-visible shapes, scattered "
    "asymmetrically. It is good and desirable for one side of the splash to "
    "have a couple of drops while the other side has none."
)


def _oil_fountain_frame(name: str, frame_no: int, energy: str, description: str,
                        refs: tuple[str, ...]) -> Sprite:
    """Build one frame of the oil fountain loop.

    `energy` is a high-level label ("minimum", "rising", "peak", "decaying", etc.) —
    the per-frame `description` carries the specific look. We deliberately AVOID
    pinning down precise blob diameters, droplet counts, or ring radii in the
    helper, because over-specifying numbers pushes the model to render a clean
    geometric pattern. Frame-level descriptions use words like "small / medium /
    large", "few / many", "tight / wide" so the model has room to render natural
    fluid chaos.

    aspect="1:1" because the splash spreads radially. bg="white" + auto alpha
    (remove_bg_by_color) — crude oil is dark enough that corner-keying handles
    the edges cleanly even with thin ligaments.
    """
    subject = (
        f"Frame {frame_no} of 6 in a SEAMLESSLY LOOPING oil-fountain animation, "
        f"viewed STRICTLY FROM ABOVE. The fountain shoots straight up toward the "
        f"camera, so we look down the axis of the geyser. Energy level for this "
        f"frame: **{energy}**. {description}\n\n"
        f"Style: 2D cartoon flat-color (the same family as the game's other VFX), "
        f"BUT with the organic ragged silhouette of a real high-speed splash photo. "
        f"The oil reads as opaque dense liquid — dark, slightly thicker than water, "
        f"with no transparency, no glassy refraction, no specular highlights. "
        f"Treat the brushwork like an INK SPLATTER more than a vector illustration."
    )
    return Sprite(
        name=name,
        view="topdown", bg="white", aspect="1:1",
        refs=refs,
        ref_mode="temporal",
        alpha_mode="auto",
        subject=subject,
        palette=(
            "deep crude oil core (#0E0A08), mid crude tendrils and droplets (#1E1612), "
            "small warm-brown wet highlight (#3A2418) only at the densest spot of the "
            "core, pure white (#FFFFFF) background"
        ),
        extra=(
            _OIL_FOUNTAIN_SMALL_RENDER_CLAUSE
            + "\n\n" + _OIL_FOUNTAIN_REFERENCE_CLAUSE
            + "\n\n" + _OIL_FOUNTAIN_LOCK_CLAUSE
            + "\n\n" + _OIL_FOUNTAIN_ANTI_PERFECTION_CLAUSE
        ),
    )


OIL_FOUNTAIN = [
    # Anchor: peak burst. No refs — this frame defines the canon look for the loop.
    _oil_fountain_frame(
        "fx_oil_fountain_f3", 3, energy="PEAK — full violent burst",
        description=(
            "The most energetic frame in the loop. The dense oil CORE is the "
            "dominant shape — large and irregular, occupying roughly a quarter of "
            "the frame's width with a ragged lobed outline (never a clean circle). "
            "Around the core, just FOUR TO FIVE chunky satellite droplets, "
            "scattered ASYMMETRICALLY — clustered on one or two sides of the core, "
            "with most of the surrounding white area completely EMPTY. Each "
            "droplet is large enough to read clearly at small sprite size. "
            "Optionally one short thick ligament/finger of oil reaching from the "
            "core toward one of the satellite drops. NO mist, NO fine spray, NO "
            "tiny specks. The image reads as a few big bold shapes scattered on "
            "white, not a cloud of detail. This frame defines the canonical look "
            "of the entire loop — later frames inherit its palette and brushwork."
        ),
        refs=(),
    ),
    # Rising and falling neighbours — both ref the anchor only.
    _oil_fountain_frame(
        "fx_oil_fountain_f2", 2, energy="RISING — building up to peak",
        description=(
            "The pulse is climbing toward the peak. Core is medium-sized, smaller "
            "than at the peak, with a less ragged outline (only one or two bulges "
            "starting to form). Only TWO TO THREE chunky satellite droplets close "
            "to the core, all clumped on the SAME side (the rest of the frame "
            "around the core is empty white). No tendrils yet, or at most one "
            "short thick bump on the rim. Reads as 'the burst is building up — "
            "first big drops just left the core'."
        ),
        refs=("fx_oil_fountain_f3",),
    ),
    _oil_fountain_frame(
        "fx_oil_fountain_f4", 4, energy="DECAYING — just past peak",
        description=(
            "Just after the peak. Core has shrunk noticeably and its outline is "
            "still ragged but losing energy. Around it, exactly FOUR chunky "
            "satellite droplets at a wider spread than at the peak (further from "
            "the core) — these are the same drops as at the peak, just travelling "
            "outward on their arc. Asymmetry is even more pronounced: drops are "
            "all on one or two sides, the other sides are completely empty. "
            "No tendrils, no fine spray. Reads as 'the burst is collapsing — big "
            "drops are flying outward and back down'."
        ),
        refs=("fx_oil_fountain_f3",),
    ),
    # Low-energy neighbours.
    _oil_fountain_frame(
        "fx_oil_fountain_f1", 1, energy="LOW — pulse just starting",
        description=(
            "The pulse is just beginning to rise from the calm minimum. The core "
            "is SMALL and almost rounded (slightly uneven edge, but no big lobes "
            "yet). Only ONE chunky satellite droplet visible, hugging close to the "
            "core on one side. The rest of the frame is empty white. No tendrils. "
            "Reads as 'the well is starting to push oil up — first big bubble has "
            "just broken'."
        ),
        refs=("fx_oil_fountain_f2", "fx_oil_fountain_f3"),
    ),
    _oil_fountain_frame(
        "fx_oil_fountain_f5", 5, energy="LATE DECAY — settling toward minimum",
        description=(
            "The burst is collapsing. Core is small, outline almost smooth (the "
            "ragged-rim energy is mostly gone). Exactly TWO chunky satellite "
            "droplets remain, scattered ASYMMETRICALLY and far out on the same "
            "side — the last big drops in the air before they fall out of frame. "
            "The rest of the frame is empty white. No tendrils, no spray."
        ),
        refs=("fx_oil_fountain_f4", "fx_oil_fountain_f3"),
    ),
    # Minimum — closes the loop back to f1.
    _oil_fountain_frame(
        "fx_oil_fountain_f6", 6, energy="MINIMUM — calm between pulses",
        description=(
            "The lowest-energy frame in the loop. JUST a small dense oil blob at "
            "the center, slightly irregular outline. ZERO satellite droplets, "
            "ZERO tendrils, NO spray. The rest of the frame is empty white. This "
            "frame is visually similar to frame 1 (which has just one drop) so "
            "that when the animation cycles f6→f1 the seam is barely noticeable. "
            "Reads as 'the well is calm, oil is barely moving'. Then the pulse "
            "rises again into f1, f2, f3..."
        ),
        refs=("fx_oil_fountain_f5", "fx_oil_fountain_f3"),
    ),
]


# ---------------------------------------------------------------------------
# Terrain tiles — seamless, no background removal needed
# ---------------------------------------------------------------------------

# NB: tiles are drawn on white just so the bg-removal pipeline stays uniform;
# at runtime the sprite is used as-is (seamless), so `bg_removal` should be "none"
# — handled by NO_REMOVAL_PREFIXES below.

TILES = [
    Sprite(
        name="tile_ground",
        view="topdown", bg="fill", aspect="1:1",
        refs=("settlement_village",),
        subject=(
            "A square landscape tile — flat medium-green ground (#5A7A3A) with a light dirt-and-"
            "grass texture. Color and rendering style MUST match the green background under the "
            "cottages in settlement_village (medium saturation, not dark-olive, not military-"
            "drab). Grass detail is TINY and SPARSE — small scattered sprigs / tufts each no "
            "larger than ~3% of the tile's side (think single small clumps of leaves, not big "
            "V-shaped grass blades). Every grass mark has a thin dark outline, same line weight "
            "as in settlement_village. A few faint brown dirt patches for variation. "
            "MUST be seamless tileable — edges must match perfectly when placed side by side. "
            "No objects, no structures, no buildings — just terrain."
        ),
        palette="medium green (#5A7A3A) base, darker green (#3E5E27) shading, muted brown (#7A5A3A) dirt patches",
    ),
    Sprite(
        name="tile_highGround",
        view="topdown", bg="fill", aspect="1:1",
        refs=("tile_ground",),
        subject=(
            "A square landscape tile, STRICT ORTHOGRAPHIC TOP-DOWN view of a "
            "ROCKY CLIFF / MESA SCARP with a flat plateau on top — a chunk of "
            "layered bedrock whose flat top is where AA towers will be placed. "
            "Strictly bird's-eye, no isometric tilt, no 3/4 angle, no side-view "
            "of the cliff wall. NOT a boulder, NOT a stone slab — it is a piece "
            "of geological scarp with a clearly higher plateau on top."
            "\n\n"
            "FRAMING (output 1024x1024): the cliff bounding box covers ~92-96% "
            "of the tile in BOTH width and height. Leftmost point at x≈30-50 px, "
            "rightmost at x≈975-995 px, topmost at y≈30-50 px, bottommost at "
            "y≈975-995 px. Geometric centroid sits exactly on the tile's center "
            "with NO drift toward any corner. The cliff has roughly equal extent "
            "on all four sides — the four tile corners each contain only a small "
            "triangular grass area (≤10% of tile area each). Anti-patterns: "
            "(a) a small boulder floating in the middle with a wide grass frame; "
            "(b) a cliff hugging the top-left with the bottom-right empty."
            "\n\n"
            "SILHOUETTE — craggy, rectilinear, jagged like a coastal scarp from "
            "the air. 3-5 promontories jutting out, 2-3 notches/inlets cutting "
            "in. Add 1-2 smaller stepped ledges (a lower secondary rock shelf "
            "6-12 px wide along part of one rim, beveled the same way) so the "
            "cliff has multiple elevation tiers — NOT a smooth blob outline. "
            "Interior is FLAT-TOPPED (not a dome, not a mound). Cliff body "
            "never touches any tile edge but comes very close on all four "
            "sides equally."
            "\n\n"
            "STRATIFIED RIM — a CONCENTRIC STEPPED RING around the ENTIRE "
            "plateau, fully SYMMETRIC: top, bottom, left, right all look the "
            "same. A dark stone band (~3-4% of tile width, an ABSOLUTE thickness "
            "that does NOT grow when the plateau grows) hugs the rim on the "
            "plateau's own surface, broken into 2-3 concentric sub-bands that "
            "follow the silhouette like topographic contour lines, separated by "
            "darker hairline cracks (#2E2A28). Tone gradient outermost→innermost: "
            "#5A554F → #4A4642 → #3A3632. Read as sedimentary rock LAYERS seen "
            "from above, NOT a side-view wall, NOT a directional bevel."
            "\n\n"
            "PLATEAU TOP SURFACE — flat light warm gray stone (#B0AAA0), VERY "
            "OPEN, very clean, very uniform — towers will be placed here and "
            "must not visually compete. Minimal texture: a few short faint "
            "cracks (#7A7670, 1-2 px) from random rim points, optional 1-2 "
            "tiny pebbles. No heavy patterns, no grass tufts, no buildings. "
            "Reads as 'helipad-flat stone plate'. The plateau interior takes "
            "up 80%+ of the cliff's area; the rim band is a thin sliver."
            "\n\n"
            "DROP SHADOW — a hard cast shadow (#2E3A24, sharp edge, flat color, "
            "NOT a gradient) sits on the GRASS immediately south and east of "
            "the cliff, offset ~6-10% of tile width from the cliff body so it "
            "clearly reads as a cast shadow on the ground next to the cliff. "
            "Traces the silhouette only on the south/east arc — no shadow on "
            "north/west. This is the only directional cue and it lives on the "
            "GRASS, not on the cliff itself."
            "\n\n"
            "GRASS BORDER — all four tile edges carry a continuous grass strip "
            "IDENTICAL to tile_ground (same #5A7A3A base, same sparse sprigs, "
            "same dirt patches, same outline weight #1A2812) so adjacent tiles "
            "seam invisibly. Strip is ~30-60 px wide on every side, never more "
            "than ~70 px on any side. Optionally 2-3 small scree pebble "
            "clusters (3-5 pebbles each, #A8A39B) on the grass at the cliff's "
            "foot."
            "\n\n"
            "Style: classic flat-color cartoon top-down pixel-art. Crisp edges, "
            "no soft gradients, no photographic 3D, no isometric perspective. "
            "Detail scale and outline weight match tile_ground exactly. Must be "
            "seamless tileable on the grass edges. Goal: a player must instantly "
            "recognize this as a CLIFF with a flat plateau on top, viewed from "
            "straight above."
        ),
        palette="grass border IDENTICAL to tile_ground — medium green (#5A7A3A) base, darker green (#3E5E27) shading, muted brown (#7A5A3A) dirt; plateau rim bevel light-to-dark: lit lip (#C8C2B6) top-left, mid stone (#8A837A) sides, dark cliff face (#4A4642) bottom-right; plateau top FLAT light warm gray stone (#B0AAA0) with faint cracks (#7A7670); BOLD drop shadow (#2E3A24) on the grass to the bottom-right of the plateau; optional inner contour ring (#9A938A); scree pebbles (#A8A39B); bold thick dark outline (#1A2812)",
    ),
    Sprite(
        name="tile_blocked",
        view="topdown", bg="fill", aspect="1:1",
        refs=("tile_ground",),
        subject=(
            "A square landscape tile — dark gray rocky ground / concrete rubble, noticeably darker "
            "and cooler than the green ground tile. Scattered debris fragments but no distinct "
            "objects. Zone where building is not allowed. Detail scale and outline weight must "
            "match tile_ground exactly. MUST be seamless tileable — edges must match perfectly."
        ),
        palette="dark gray (#4E4E4E) rubble base, lighter concrete fragments (#6A6A6A), darkest cracks (#333333)",
    ),
    Sprite(
        name="tile_headquarters",
        view="topdown", bg="fill", aspect="1:1",
        refs=("tile_ground",),
        subject=(
            "A square tile — top-down view of a military bunker / command post entrance: "
            "reinforced concrete pad, camouflage netting, red-brown earth around an armored door. "
            "Centered composition. Detail scale and outline weight must match tile_ground exactly."
        ),
        palette="concrete (#7A7466) pad, camouflage green (#4B5320) netting, red-brown (#7A4A28) earth, dark gray (#3A3A3A) armored door",
    ),
    Sprite(
        name="tile_settlement",
        view="topdown", bg="fill", aspect="1:1",
        refs=("tile_ground",),
        subject=(
            "A square landscape tile, top-down view: a tile_ground patch with a CLEAN "
            "UNIFORM CENTER reserved for a settlement sprite that will be drawn on top. "
            "The palette is IDENTICAL to tile_ground — same medium green (#5A7A3A) base, "
            "same darker green (#3E5E27) shading, same muted brown (#7A5A3A) dirt, same "
            "outline color (#1A2812) and weight. The difference from tile_ground is NOT "
            "color — it is CONTENT / layout. "
            "\n\n"
            "Three non-negotiable goals: "
            "(A) The OUTER BORDER of the tile — a thin strip roughly 10-15% of the tile "
            "side along each edge — is IDENTICAL to tile_ground: same sprigs, same small "
            "brown dirt patches, same density and outline weight. Every dirt blob or sprig "
            "from tile_ground that would flow across a tile boundary must continue into "
            "this border identically, so when a tile_settlement is placed next to a "
            "tile_ground / tile_concealed / tile_highGround the grass is INDISTINGUISHABLE "
            "at the seam. No visible boundary line between them. "
            "(B) The CENTER of the tile (roughly the inner 70-75% circle/rounded-square) "
            "is deliberately CLEAN and UNIFORM — a flat field of the exact same medium "
            "green (#5A7A3A) as the border, with essentially NO sprigs, NO dirt patches, "
            "NO tufts, NO flowers, NO decorations of any kind. This zone will be almost "
            "fully covered by a settlement/cottage sprite, so it must be quiet and not "
            "compete visually. Any sprigs or dirt from tile_ground that would normally "
            "land in this zone are REMOVED / COVERED — they do NOT bleed inward from the "
            "border. "
            "(C) The transition from the textured border to the clean center is "
            "unobtrusive and organic — a soft irregular inner boundary where the density "
            "of sprigs / dirt simply fades to zero. NO drawn ring, NO circle outline, NO "
            "marked lawn edge, NO fence, NO path, NO cultivation pattern. It should read "
            "as 'this is where the house sits — just bare grass' not as a designed yard. "
            "\n\n"
            "DO NOT draw the settlement / cottage / building itself — that is a separate "
            "sprite placed on top. DO NOT draw fences, flowerbeds, garden borders, "
            "picket lines, mowing stripes, hedge rows, footpaths, wells, or any man-made "
            "markers. DO NOT shift the base color brighter, yellower, darker, or more "
            "saturated than tile_ground — it is the SAME grass. DO NOT add shadows, 3D "
            "depth, shading gradients, or painterly highlights. "
            "\n\n"
            "Flat top-down pixel-art style, crisp thin dark outlines, detail scale and "
            "outline weight of the bordering sprigs/dirt match tile_ground EXACTLY. "
            "MUST be seamless tileable on all four edges with tile_ground and with "
            "another tile_settlement — the outer 10-15% strip is the seam-matching zone."
        ),
        palette="IDENTICAL to tile_ground — medium green (#5A7A3A) base, darker green (#3E5E27) shading, muted brown (#7A5A3A) dirt patches, thin dark outline (#1A2812) same weight. NO new colors. The tile differs only in CONTENT/LAYOUT (clean uniform center), not palette.",
    ),
    Sprite(
        name="tile_concealed",
        view="topdown", bg="white", aspect="1:1",
        refs=("tile_ground", "tile_settlement"),
        subject=(
            "SEPARATE game sprite — a square OVERLAY the size of one map tile, showing ONLY a "
            "ring of large trees and bushes viewed from directly above. This will be drawn on "
            "top of a base tile (tile_settlement) and on top of an air-defense launcher "
            "sprite, so the foliage partially covers the launcher's edges from above while "
            "the launcher remains clearly visible through the open center. "
            "\n\n"
            "Three non-negotiable goals: "
            "(A) The background is PURE solid white (#FFFFFF) everywhere there is no tree or "
            "bush — the post-process will key this white to full transparency. Do NOT draw "
            "any grass, sprigs, dirt, ground, soil, shadow cast on ground, or any terrain "
            "texture. Foliage only, nothing else. NO background color, NO faint tint, NO "
            "grass hints peeking through — just bright pure white between the crowns. "
            "(B) The CENTER of the tile (roughly the inner 55-60% circle) stays EMPTY — pure "
            "white, zero foliage, zero twigs, zero leaves overhanging into it. An air-defense "
            "launcher sprite will sit here and must remain fully readable. The foliage lives "
            "only on the outer ring of the tile. "
            "(C) Trees are LARGER than an air-defense launcher sprite. Each tree crown is "
            "roughly 28-38% of the tile side (noticeably bigger than a PVO launcher placed "
            "in the same tile). Around 5-8 tree crowns total, arranged IRREGULARLY on the "
            "perimeter — varying sizes, not symmetric, not evenly spaced, clusters of 2-3 "
            "touching crowns are fine. Small bush clumps (roughly 12-18% of tile side) may "
            "fill the gaps between trees. Some crowns may extend slightly past the tile edge "
            "so that adjacent tile_concealed overlays can visually merge into a grove — but "
            "foliage never crosses into the empty center. "
            "\n\n"
            "Tree rendering — TRUE TOP-DOWN view as if photographed by a drone camera "
            "straight down: a tree is a roughly circular/organic CROWN of leaves, NOT a "
            "silhouette with a trunk showing to the side. Each crown is built from two or "
            "three flat-color layers to sell volume: "
            "  • Base canopy layer: medium forest green (#3E5E27), irregular lobed outline "
            "    (not a smooth circle — bumpy, broccoli-like clusters of leaf bunches). "
            "  • Shadow-side accent: a darker green (#2E4220) crescent or wedge on one side "
            "    of the crown (pick the SAME light direction for every crown in the tile — "
            "    e.g. all shadows on the lower-right). Small, maybe 15-25% of the crown. "
            "  • Highlight dappling: a few light-green (#6E8A3A) small rounded specks on "
            "    the opposite side of each crown, suggesting sunlit leaves catching light. "
            "    Tiny — each spec 3-6 px, a handful per crown. "
            "  • A pinpoint trunk dot (#3A2A18, 2-3 px) is just barely visible at the "
            "    geometric centre of each crown when looking straight down. Optional — some "
            "    crowns can omit it if the canopy is fully closed. "
            "A thin dark outline (#1A2812, SAME line weight as tile_ground) traces the "
            "outside of every crown and bush. "
            "\n\n"
            "Bushes: smaller, less organised lumpy blobs in the same green family "
            "(#2E4220 body, #3E5E27 highlights), thin dark outline. Use them to fill awkward "
            "gaps between tree crowns on the perimeter. "
            "\n\n"
            "DO NOT draw: tree trunks shown from the side, ground, grass, sprigs, dirt, "
            "stones, paths, cast shadows on terrain, camouflage netting, tarps, fences, "
            "buildings, any human-made cover. DO NOT shade the crowns with smooth painterly "
            "gradients — use flat color layers only. DO NOT add a global drop shadow under "
            "the tile. DO NOT fill the center with leaves. "
            "\n\n"
            "Flat top-down pixel-art style, crisp thin dark outlines, detail scale and "
            "outline weight match tile_ground EXACTLY. The sprite must work as a "
            "transparent-background OVERLAY: everything non-foliage is pure white and will "
            "be keyed out. Adjacent tile_concealed overlays should merge into a continuous "
            "tree line at their shared edges."
        ),
        palette="pure white (#FFFFFF) background (keyed to alpha in post-process) — NOT a color in the art; tree canopy base medium forest green (#3E5E27), shadow-side dark green (#2E4220), sunlit dappling light green (#6E8A3A), bush body #2E4220 with #3E5E27 highlights, tiny central trunk dot #3A2A18, thin dark outline (#1A2812) same weight as tile_ground",
    ),
    Sprite(
        name="tile_valley",
        view="topdown", bg="fill", aspect="1:1",
        refs=("tile_ground",),
        subject=(
            "A square landscape tile, top-down view: a tile_ground patch with a shallow "
            "DEPRESSION carved through it — the same grass field as tile_ground, but with "
            "a worn footpath / erosion gully winding across the tile. Drones fly faster "
            "over this zone. The palette is IDENTICAL to tile_ground — same medium green "
            "(#5A7A3A) base, same darker green (#3E5E27) shading, same muted brown "
            "(#7A5A3A) dirt, same outline color (#1A2812) and weight. The difference from "
            "tile_ground is NOT color — it is CONTENT / SHAPE. "
            "\n\n"
            "Three non-negotiable goals: "
            "(A) The OUTER BORDER of the tile — a thin strip roughly 8-12% of the tile "
            "side along each edge — is IDENTICAL to tile_ground: same sprigs, same "
            "scattered small brown dirt patches, same density and outline weight, same "
            "color. Every dirt blob or sprig from tile_ground that would flow across a "
            "tile boundary must continue into this border identically, so a tile_valley "
            "placed next to tile_ground / tile_concealed / tile_highGround is "
            "INDISTINGUISHABLE at the seam. No visible boundary line between tiles. "
            "(B) The valley itself is an IRREGULAR WORN TRACK that crosses the tile from "
            "one edge to another (pick an asymmetric diagonal path — e.g. enters on one "
            "side and exits on an adjacent side, NOT a straight line down the middle, "
            "NOT corner-to-corner symmetric). The track reads as a shallow trodden "
            "depression — an ORGANIC irregular blob shape, varying in width along its "
            "length (narrower in places, wider in others), with bulges and pinches like "
            "a real footpath worn over time. Render the track as expanded brown exposed "
            "earth in the SAME tones tile_ground already uses for its dirt patches "
            "(#7A5A3A base, slightly darker #5C4428 shading along the deeper middle of "
            "the track to suggest mild concavity). Scatter a handful of tile_ground's "
            "normal sprigs along the track edges where grass is fraying into dirt — same "
            "sprig vocabulary, just thinning out. "
            "(C) The track entrance and exit at the tile edges MUST align continuously "
            "with the same track from a neighboring tile_valley — i.e. a track piece "
            "that exits at the midpoint of one edge is wide enough to flow into any "
            "neighboring tile_valley without a stepped seam. Everywhere else on the tile "
            "edge (outside the track opening) is ordinary tile_ground grass. "
            "\n\n"
            "DO NOT shift the base color browner, darker, grayer, yellower, or more "
            "saturated than tile_ground — the 'valley' read comes ENTIRELY from the "
            "worn-earth track shape, not from a palette shift. DO NOT draw rivers, "
            "streams, paved roads, tire tracks, stone borders, fences, topo contour "
            "lines, cast shadows, 3D depth, gradients, or painterly highlights. DO NOT "
            "make the track a straight ruler-like line, a grid, or a symmetric cross. "
            "\n\n"
            "Flat top-down pixel-art style, crisp thin dark outlines. Detail scale and "
            "outline weight of the grass border + dirt track match tile_ground EXACTLY. "
            "MUST be seamless tileable on all four edges with tile_ground (grass-only "
            "sections) and with another tile_valley (where tracks meet, they continue)."
        ),
        palette="IDENTICAL to tile_ground — medium green (#5A7A3A) base, darker green (#3E5E27) shading, muted brown (#7A5A3A) dirt (expanded into the worn track), slightly darker brown (#5C4428) along the track's deeper middle for very subtle concavity, thin dark outline (#1A2812) same weight. NO new hues. The tile differs only in CONTENT/SHAPE (a winding worn track), not palette.",
    ),
]


# ---------------------------------------------------------------------------
# UI
# ---------------------------------------------------------------------------

_UI_STYLE = "Cold War Soviet air defense console aesthetic. "

UI = [
    Sprite(
        name="ui_hud_bar",
        view="none", bg="fill", aspect="21:9",
        subject=(
            _UI_STYLE +
            "A horizontal dark military CRT panel — very dark green-black background with barely "
            "visible scanline texture, a thin green phosphor border line at the bottom, matte dark "
            "metal look. For the top HUD bar."
        ),
        palette="dark green-black, green phosphor border, matte metal",
    ),
    Sprite(
        name="ui_btn_start_wave_normal",
        view="none", bg="white", aspect="21:9",
        subject=(
            _UI_STYLE +
            "A military illuminated button — dark metallic frame around a glowing green button "
            "surface, beveled edges, LED indicator on the left. No text — text will be added "
            "separately in code."
        ),
        palette="dark metallic frame, glowing green surface, green LED",
    ),
    Sprite(
        name="ui_btn_start_wave_pressed",
        view="none", bg="white", aspect="21:9",
        refs=("ui_btn_start_wave_normal",),
        subject=(
            _UI_STYLE +
            "A military illuminated button in PRESSED state — same style as the normal state button "
            "(dark metallic frame, beveled edges, LED indicator) but the button surface is brighter "
            "(intense green glow), beveled edges appear depressed, LED indicator is brightly lit. "
            "No text."
        ),
        palette="dark metallic frame, intense green surface, brightly lit LED",
    ),
    Sprite(
        name="ui_btn_start_wave_disabled",
        view="none", bg="white", aspect="21:9",
        refs=("ui_btn_start_wave_normal",),
        subject=(
            _UI_STYLE +
            "A military button in DISABLED state — same style as the normal state button (dark "
            "metallic frame, beveled edges, LED indicator) but the button surface is dim (muted "
            "dark gray with faint greenish tint), beveled edges flat, LED indicator is off/dark. "
            "No text."
        ),
        palette="dark metallic frame, dim gray-green surface, dark LED",
    ),
    Sprite(
        name="ui_btn_speed_1x",
        view="none", bg="white", aspect="1:1",
        subject=(
            _UI_STYLE +
            "A small military toggle switch/button — dark metallic frame with a lit green "
            "indicator, a single chevron symbol \"▶\" drawn in green phosphor at center. "
            "No text other than the chevron symbol."
        ),
        palette="dark metallic frame, green phosphor chevron",
    ),
    Sprite(
        name="ui_btn_speed_2x",
        view="none", bg="white", aspect="1:1",
        refs=("ui_btn_speed_1x",),
        subject=(
            _UI_STYLE +
            "A small military toggle switch/button — dark metallic frame with a lit amber-orange "
            "indicator, a double chevron symbol \"▶▶\" drawn in amber phosphor at center. "
            "No text other than the chevron symbols."
        ),
        palette="dark metallic frame, amber phosphor chevrons",
    ),
    Sprite(
        name="ui_btn_settings",
        view="none", bg="white", aspect="1:1",
        subject=(
            _UI_STYLE +
            "A military settings button — dark matte metallic circle with a gear/cog symbol drawn "
            "in green phosphor, beveled edge."
        ),
        palette="dark matte circle, green phosphor gear",
    ),
    Sprite(
        name="ui_conveyor_slot",
        view="none", bg="white", aspect="1:1",
        subject=(
            _UI_STYLE +
            "A square military equipment slot/compartment — dark recessed panel with a thin green "
            "phosphor border, faint CRT grid pattern inside. For placing tower cards. No text."
        ),
        palette="dark recessed panel, green phosphor border, faint CRT grid",
    ),
    Sprite(
        name="ui_tower_card",
        view="none", bg="white", aspect="1:1",
        refs=("ui_conveyor_slot",),
        subject=(
            _UI_STYLE +
            "A square military equipment selection card — slightly raised dark metallic panel with "
            "a faint green phosphor edge glow. For placing tower icons on top. No text."
        ),
        palette="dark metallic panel, green phosphor edge glow",
    ),
    Sprite(
        name="ui_ability_fighter",
        view="none", bg="white", aspect="1:1",
        subject=(
            _UI_STYLE +
            "A military ability button with a fighter jet silhouette — dark metallic frame, round "
            "button, green phosphor silhouette of a jet aircraft. For calling in air support. "
            "No text."
        ),
        palette="dark metallic frame, green phosphor jet silhouette",
    ),
    Sprite(
        name="ui_ability_barrage",
        view="none", bg="white", aspect="1:1",
        refs=("ui_ability_fighter",),
        subject=(
            _UI_STYLE +
            "A military ability button with an explosion icon — dark metallic frame, round button, "
            "amber-orange phosphor explosion/burst symbol. For artillery strike ability. No text."
        ),
        palette="dark metallic frame, amber phosphor explosion symbol",
    ),
    Sprite(
        name="ui_ability_reload",
        view="none", bg="white", aspect="1:1",
        refs=("ui_ability_fighter",),
        subject=(
            _UI_STYLE +
            "A military ability button with a circular reload arrow — dark metallic frame, round "
            "button, green phosphor circular arrow symbol. For emergency reload ability. No text."
        ),
        palette="dark metallic frame, green phosphor circular arrow",
    ),
    Sprite(
        name="ui_menu_background",
        view="none", bg="fill", aspect="9:16",
        subject=(
            _UI_STYLE +
            "A full-screen dark military CRT console background — very dark green-black with faint "
            "phosphor scanlines, a pale radar sweep arc in the background, military coordinate "
            "grid lines. Soviet S-300 air defense command post aesthetic. Military stencil test "
            "patterns at edges. No text."
        ),
        palette="dark green-black, pale green radar sweep, faint grid lines",
    ),
    Sprite(
        name="ui_title_background",
        view="none", bg="white", aspect="21:9",
        subject=(
            _UI_STYLE +
            "A dark panel with CRT green phosphor bloom effect — rectangular area with intense "
            "green bloom glow, scanlines, slight CRT distortion. Background for the game title, "
            "text will be overlaid separately."
        ),
        palette="dark panel, intense green bloom",
    ),
    Sprite(
        name="ui_btn_campaign",
        view="none", bg="white", aspect="21:9",
        subject=(
            _UI_STYLE +
            "A military button — dark metallic frame with a blue-lit button surface. "
            "Blue illuminated indicator. No text — text will be added separately."
        ),
        palette="dark metallic frame, blue-lit surface",
    ),
    Sprite(
        name="ui_btn_endless",
        view="none", bg="white", aspect="21:9",
        refs=("ui_btn_campaign",),
        subject=(
            _UI_STYLE +
            "A military button — dark metallic frame with a green-lit button surface. "
            "Green illuminated indicator. No text — text will be added separately."
        ),
        palette="dark metallic frame, green-lit surface",
    ),
    Sprite(
        name="ui_level_card",
        view="none", bg="white", aspect="21:9",
        subject=(
            _UI_STYLE +
            "A horizontal military mission card — dark matte metallic rectangle with green "
            "phosphor border, faint CRT texture, recessed panel. For the level selection list. "
            "No text."
        ),
        palette="dark matte metal, green phosphor border, CRT texture",
    ),
    Sprite(
        name="ui_btn_back",
        view="none", bg="white", aspect="21:9",
        subject=(
            _UI_STYLE +
            "A military button — dark metallic frame, red-lit button surface. Emergency/warning "
            "button aesthetic. No text — text will be added separately."
        ),
        palette="dark metallic frame, red-lit surface",
    ),
    Sprite(
        name="ui_gameover_background",
        view="none", bg="white", aspect="21:9",
        subject=(
            _UI_STYLE +
            "A dark panel with CRT red phosphor bloom effect — rectangular area with pulsing red "
            "bloom glow, CRT distortion, military warning display style. Background for "
            "\"GAME OVER\" text, which will be overlaid separately."
        ),
        palette="dark panel, pulsing red bloom",
    ),
    Sprite(
        name="ui_btn_playagain",
        view="none", bg="white", aspect="21:9",
        subject=(
            _UI_STYLE +
            "A military button — dark gray metallic surface with beveled edges, faint green border "
            "glow. No text — text will be added separately."
        ),
        palette="dark gray metal, green border glow",
    ),
    Sprite(
        name="ui_btn_menu",
        view="none", bg="white", aspect="21:9",
        refs=("ui_btn_back",),
        subject=(
            _UI_STYLE +
            "A military button — dark metallic frame, red-lit button surface. Emergency button "
            "style. No text — text will be added separately."
        ),
        palette="dark metallic frame, red-lit surface",
    ),
    Sprite(
        name="ui_pause_panel",
        view="none", bg="fill", aspect="5:4",
        subject=(
            _UI_STYLE +
            "A rectangular dark military CRT panel with a thick green phosphor border. Black "
            "interior with faint scanlines. Pause screen style. No text."
        ),
        palette="black interior, thick green phosphor border",
    ),
    Sprite(
        name="ui_btn_resume",
        view="none", bg="white", aspect="21:9",
        refs=("ui_btn_playagain",),
        subject=(
            _UI_STYLE +
            "A military button — dark gray surface with a green LED indicator, metallic frame. "
            "No text — text will be added separately."
        ),
        palette="dark gray surface, green LED, metallic frame",
    ),
    Sprite(
        name="ui_btn_restart",
        view="none", bg="white", aspect="21:9",
        refs=("ui_btn_playagain",),
        subject=(
            _UI_STYLE +
            "A military button — dark gray surface with an amber LED indicator, metallic frame. "
            "No text — text will be added separately."
        ),
        palette="dark gray surface, amber LED, metallic frame",
    ),
    Sprite(
        name="ui_btn_exit",
        view="none", bg="white", aspect="21:9",
        refs=("ui_btn_back",),
        subject=(
            _UI_STYLE +
            "A military button — red-lit button surface, metallic frame. Emergency/warning button "
            "style. No text — text will be added separately."
        ),
        palette="red-lit surface, metallic frame",
    ),
    Sprite(
        name="ui_aid_card",
        view="none", bg="white", aspect="9:16",
        subject=(
            _UI_STYLE +
            "A vertical military equipment/upgrade selection card — dark matte metallic rectangle "
            "with an amber phosphor border, CRT texture inside, space for an icon and description "
            "text. No text."
        ),
        palette="dark matte metal, amber phosphor border, CRT texture",
    ),
    Sprite(
        name="ui_warning_background",
        view="none", bg="white", aspect="21:9",
        subject=(
            _UI_STYLE +
            "A dark panel with bright red CRT phosphor bloom effect — rectangular area with "
            "pulsing red bloom, warning display style. Background for alert text, which will be "
            "overlaid separately."
        ),
        palette="dark panel, pulsing red bloom",
    ),
    Sprite(
        name="ui_target_marker",
        view="none", bg="white", aspect="1:1",
        subject=(
            "A military targeting reticle/crosshair — a thin red circle with crosshair lines, "
            "military aiming sight. For designating artillery strike targets."
        ),
        palette="thin red circle, red crosshair lines",
    ),
    Sprite(
        name="ui_offscreen_arrow",
        view="none", bg="white", aspect="1:1",
        subject=(
            "A bright yellow military directional arrow — a filled triangle/chevron pointing to "
            "the right, with a faint glow. For indicating enemy drones off-screen."
        ),
        palette="bright yellow fill, faint glow",
    ),
    Sprite(
        name="ui_star_filled",
        view="none", bg="white", aspect="1:1",
        subject=(
            "A bright yellow military 5-pointed star — metallic golden finish with slight bevel. "
            "For campaign level completion rating."
        ),
        palette="metallic golden yellow, slight bevel",
    ),
    Sprite(
        name="ui_star_empty",
        view="none", bg="white", aspect="1:1",
        refs=("ui_star_filled",),
        subject=(
            "An outline-only 5-pointed star in dim gray — thin line, empty star for unfilled "
            "rating slot."
        ),
        palette="dim gray thin outline",
    ),
]


# ---------------------------------------------------------------------------
# Special sprites
# ---------------------------------------------------------------------------

SPECIAL = [
    Sprite(
        name="sprite_fighter_jet",
        view="topdown", bg="white", aspect="16:9",
        subject=(
            "A military fighter jet in a banking turn. From above you see: the wing planform of a "
            "twin-engine fighter, gray-blue camouflage airframe with darker shading on the wing "
            "undersides, a central fuselage with a bubble canopy, and two afterburner glow circles "
            "at the rear. The jet floats alone with nothing beneath it. "
            "Medium gray-blue surfaces — NOT white, no specular highlights, no bright metal. All "
            "airframe surfaces clearly darker than pure white (the afterburner glow is the only "
            "bright element)."
        ),
        palette="gray-blue (#6A7A8A) airframe, darker (#4A5868) wing shadows, dark gray (#555555) outlines, red-orange (#FF6A1A) afterburner glow",
    ),
    Sprite(
        name="AppIcon",
        view="none", bg="fill", aspect="1:1", image_size="2K",
        subject=(
            "iOS app icon — dark military green-black background with faint CRT scanlines, a "
            "bright green phosphor radar display with a sweep arc at the center, a simplified "
            "silhouette of a SAM launcher in the foreground. Simplified shapes, flat colors, "
            "minimal texture. No text — text will be added separately."
        ),
        palette="dark green-black, bright green phosphor radar, dark SAM silhouette",
    ),
]


# Generation order matters for refs — every sprite referenced by another must
# be generated FIRST (or the ref image file must already exist on disk). We
# front-load the VFX family so their anchors are available when TOWERS/PROJECTILES
# generate (muzzle flashes and tracers style-ref into fx_flame_glow, which
# itself refs fx_explosion_medium_f3).
#
# Dependency chain:
#   EXPLOSION_ANCHORS        # medium_f3 = GLOBAL VFX ANCHOR (no refs)
#     └─ VFX_SIMPLE          # fx_flame_glow refs anchor; fx_smoke_puff refs medium_f6
#        └─ TOWERS           # muzzle flashes ref fx_flame_glow
#        └─ PROJECTILES      # tracers ref fx_flame_glow
#     └─ EXPLOSION_{S,M,L}   # frame Nth refs (frame N-1, size sub-anchor)
#
# Note: fx_smoke_puff refs fx_explosion_medium_f6, which is generated AFTER
# VFX_SIMPLE. That's resolved lazily — process_sprite reads the raw PNG from
# disk if it exists — but on a fresh first run fx_smoke_puff will be generated
# without the medium_f6 ref. Acceptable tradeoff: the dependency is a style
# hint, not temporal continuity. After medium_f6 exists, --force regenerate
# fx_smoke_puff to get the proper style transfer.
SPRITES: list[Sprite] = (
    EXPLOSION_ANCHORS
    + VFX_SIMPLE
    + TOWERS
    + DRONES
    + PROJECTILES
    + EXPLOSION_SMALL
    + EXPLOSION_MEDIUM
    + EXPLOSION_LARGE
    + SETTLEMENTS
    + OIL_FOUNTAIN
    + TILES
    + UI
    + SPECIAL
)

BY_NAME: dict[str, Sprite] = {sp.name: sp for sp in SPRITES}
assert len(BY_NAME) == len(SPRITES), "duplicate sprite name in registry"


# ---------------------------------------------------------------------------
# File layout + log
# ---------------------------------------------------------------------------

def raw_path(out: Path, sp: Sprite) -> Path:
    return out / "raw" / category_of(sp.name) / f"{sp.name}.png"


def processed_path(out: Path, sp: Sprite) -> Path:
    return out / "processed" / category_of(sp.name) / f"{sp.name}.png"


def load_log(out: Path) -> dict:
    p = out / LOG_NAME
    if p.exists():
        return json.loads(p.read_text(encoding="utf-8"))
    return {}


def save_log(out: Path, log: dict) -> None:
    p = out / LOG_NAME
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(json.dumps(log, indent=2, ensure_ascii=False), encoding="utf-8")


# ---------------------------------------------------------------------------
# Generation with retry
# ---------------------------------------------------------------------------

TRANSIENT_HTTP_CODES = ("500", "502", "503", "504", "520", "521", "522", "523", "524")


def _short_err(e: Exception, limit: int = 200) -> str:
    s = str(e).replace("\n", " ")
    return s if len(s) <= limit else s[:limit] + "... [truncated]"


def generate_with_retry(client, sp: Sprite, ref_bytes: list[bytes],
                        seed: int | None, max_retries: int = 8) -> bytes | None:
    prompt = build_prompt(sp)
    for attempt in range(max_retries):
        try:
            data = generate(
                client,
                prompt,
                ref_images=ref_bytes,
                aspect_ratio=sp.aspect,
                image_size=sp.image_size,
                seed=seed,
                ref_mode=sp.ref_mode,
            )
            if data is None:
                print("  [WARN] no image in response")
                return None
            return data
        except StreamDeadlineExceeded as e:
            wait = 15 * (2 ** attempt)
            print(f"  [STREAM DEADLINE] waiting {wait}s ({attempt + 1}/{max_retries}): {e}")
            time.sleep(wait)
        except Exception as e:
            err = str(e)
            if "429" in err or "rate" in err.lower():
                wait = 30 * (2 ** attempt)
                print(f"  [RATE LIMIT] waiting {wait}s ({attempt + 1}/{max_retries})")
                time.sleep(wait)
            elif any(code in err for code in TRANSIENT_HTTP_CODES):
                code = next((c for c in TRANSIENT_HTTP_CODES if c in err), "5xx")
                wait = 15 * (2 ** attempt)
                print(f"  [SERVER {code}] waiting {wait}s ({attempt + 1}/{max_retries}): "
                      f"{_short_err(e)}")
                time.sleep(wait)
            else:
                print(f"  [ERROR] {_short_err(e)}")
                return None
    print("  [FAIL] max retries exceeded")
    return None


def missing_refs(sp: Sprite, out: Path, raw_cache: dict[str, bytes]) -> list[str]:
    """Return the names of refs that have no raw bytes available.

    A ref is considered satisfied if either its raw PNG exists on disk or its
    bytes sit in `raw_cache` (freshly generated earlier in the same job).
    Unknown refs (not in BY_NAME) are reported as missing so the caller can
    log something useful — but in practice the registry dedups names at load
    time so this shouldn't happen.
    """
    out_list: list[str] = []
    for ref_name in sp.refs:
        if ref_name in raw_cache:
            continue
        ref_sprite = BY_NAME.get(ref_name)
        if ref_sprite is None:
            out_list.append(ref_name)
            continue
        if not raw_path(out, ref_sprite).exists():
            out_list.append(ref_name)
    return out_list


def resolve_refs(sp: Sprite, out: Path, raw_cache: dict[str, bytes]) -> list[bytes]:
    """Load every ref's raw bytes. Assumes callers have already verified
    `missing_refs(sp, out, raw_cache)` is empty — the strict policy is
    enforced in the job runner, not here."""
    refs: list[bytes] = []
    for ref_name in sp.refs:
        if ref_name in raw_cache:
            refs.append(raw_cache[ref_name])
            continue
        ref_sprite = BY_NAME.get(ref_name)
        if ref_sprite is None:
            print(f"  [REF] unknown reference: {ref_name}")
            continue
        rp = raw_path(out, ref_sprite)
        if rp.exists():
            blob = rp.read_bytes()
            raw_cache[ref_name] = blob
            refs.append(blob)
            print(f"  [REF] loaded {ref_name}")
        else:
            print(f"  [REF] {ref_name} not yet generated, skipping")
    return refs


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--api-key", help="Gemini API key (required unless --dry-run)")
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT,
                        help=f"Output directory (default: {DEFAULT_OUT})")
    parser.add_argument("--name", action="append", default=[],
                        help="Glob filter on sprite names; can be repeated")
    parser.add_argument("--category", choices=sorted({c for _, c in CATEGORY_MAP}),
                        help="Limit to one category")
    parser.add_argument("--force", action="store_true",
                        help="Regenerate even if raw/output files exist")
    parser.add_argument("--reprocess", action="store_true",
                        help="Re-run post-processing on existing raw files")
    parser.add_argument("--skip-generation", action="store_true",
                        help="Only post-process existing raw files, don't hit the API")
    parser.add_argument("--dry-run", action="store_true",
                        help="Print the plan without calling the API")
    parser.add_argument("--print-prompt", action="store_true",
                        help="With --dry-run: also print each assembled prompt")
    parser.add_argument("--seed", type=int, default=None,
                        help="Seed forwarded to the model for reproducibility")
    parser.add_argument("--delay", type=float, default=2.0,
                        help="Seconds between API calls (default: 2.0)")
    parser.add_argument("--timeout", type=float, default=600.0,
                        help="HTTP client read timeout in seconds (default: 600). "
                             "Streaming mode keeps the connection alive so Cloudflare's 100s "
                             "cap is rarely hit.")
    parser.add_argument("--max-retries", type=int, default=8,
                        help="Max retries per sprite on transient errors (default: 8). "
                             "Safe to raise — proxy confirmed failed requests are not billed. "
                             "Kept low by default so a genuinely stuck sprite fails in a few "
                             "minutes instead of 15-50 (deadline 180s × retries).")
    args = parser.parse_args()

    selected: list[Sprite] = []
    for sp in SPRITES:
        if args.category and category_of(sp.name) != args.category:
            continue
        if args.name and not any(fnmatch.fnmatch(sp.name, pat) for pat in args.name):
            continue
        selected.append(sp)

    if not selected:
        print("No sprites match the given filters.", file=sys.stderr)
        return 1

    print(f"Sprites selected: {len(selected)} / {len(SPRITES)} total")

    if args.dry_run:
        for sp in selected:
            print(
                f"[{sp.name}]  aspect={sp.aspect}  size={sp.image_size}  "
                f"view={sp.view}  bg={sp.bg}  cat={category_of(sp.name)}  "
                f"refs={list(sp.refs)}"
            )
            if args.print_prompt:
                print("  PROMPT:")
                for line in build_prompt(sp).splitlines():
                    print("    " + line)
                print()
        return 0

    api_key = resolve_api_key(args.api_key)
    if not api_key and not args.skip_generation:
        ensure_api_key_config_file()
        print(
            "No Gemini API key found. Options (first match wins):\n"
            "  1. pass --api-key on the command line\n"
            "  2. export GEMINI_API_KEY=<key>\n"
            f"  3. edit {API_KEY_CONFIG_FILE} and paste the key there\n"
            "(the config file has been created with a template if it did not exist)",
            file=sys.stderr,
        )
        return 1

    args.out.mkdir(parents=True, exist_ok=True)
    client = (
        make_client(api_key, timeout_ms=int(args.timeout * 1000))
        if not args.skip_generation else None
    )

    # Warm the raw cache from disk so refs can resolve across partial runs.
    raw_cache: dict[str, bytes] = {}
    # Batch-local failure tracking — see web_ui.run_job for rationale.
    batch_failed: set[str] = set()

    log = load_log(args.out)
    done = failed = skipped = 0

    for i, sp in enumerate(selected, 1):
        print(f"\n[{i}/{len(selected)}] {sp.name}  (aspect={sp.aspect}, size={sp.image_size})")

        rp = raw_path(args.out, sp)
        pp = processed_path(args.out, sp)
        status = log.get(sp.name, {}).get("status", "")

        if status == "complete" and not (args.force or args.reprocess):
            print("  [SKIP] already complete")
            skipped += 1
            continue

        need_gen = not args.skip_generation and (args.force or not rp.exists())

        if args.skip_generation and not rp.exists():
            print(f"  [SKIP] no raw file at {rp}")
            skipped += 1
            continue

        if need_gen:
            # Strict refs policy — see web_ui.run_job for full rationale.
            # A ref is satisfied iff it's in raw_cache (just generated) or on
            # disk AND NOT in batch_failed. The batch_failed overlay is what
            # propagates a parent's failure downstream when the on-disk file
            # is stale from an earlier run.
            missing = missing_refs(sp, args.out, raw_cache)
            stale = [r for r in sp.refs if r in batch_failed]
            blocked = list(dict.fromkeys(missing + stale))
            if blocked:
                reason = "refs not generated" if missing else "refs failed earlier in this batch"
                print(f"  [BLOCKED] {reason}: {', '.join(blocked)}")
                print(f"            generate them first — skipping {sp.name}")
                batch_failed.add(sp.name)
                skipped += 1
                continue

            refs = resolve_refs(sp, args.out, raw_cache)
            print("  generating...")
            data = generate_with_retry(client, sp, refs, args.seed, max_retries=args.max_retries)
            if data is None:
                batch_failed.add(sp.name)
                failed += 1
                continue
            rp.parent.mkdir(parents=True, exist_ok=True)
            rp.write_bytes(data)
            raw_cache[sp.name] = data
            log[sp.name] = {"status": "generated", "timestamp": datetime.now().isoformat()}
            save_log(args.out, log)
            print(f"  raw -> {rp}")
            if i < len(selected) and args.delay > 0:
                time.sleep(args.delay)
        else:
            print(f"  raw exists: {rp}")

        print(f"  post-processing (bg={sp.bg})...")
        try:
            img = Image.open(rp).convert("RGBA")
            img = postprocess(img, sp.bg, sp.alpha_mode)
            pp.parent.mkdir(parents=True, exist_ok=True)
            img.save(pp, "PNG")
        except Exception as e:
            print(f"  [FAIL] post-process: {e}")
            failed += 1
            continue

        log[sp.name] = {"status": "complete", "timestamp": datetime.now().isoformat()}
        save_log(args.out, log)
        print(f"  processed -> {pp}")
        done += 1

    print(f"\nDone. completed={done} skipped={skipped} failed={failed}")
    print(f"raw:       {args.out / 'raw'}")
    print(f"processed: {args.out / 'processed'}")
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
