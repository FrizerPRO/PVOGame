# Sprite Generation Prompts for PVOGame

Each block is a self-contained prompt for the image generation model.
No text on sprites — all labels will be added in code.

**Common style**: 2D cartoon style like Plants vs Zombies / Kingdom Rush — bold outlines, simplified shapes, flat colors with soft cel-shading, exaggerated proportions, minimal surface detail.

---

## 1. tower_autocannon_base (128×128px)

Top-down overhead view of a two-wheeled anti-aircraft gun mount WITHOUT THE GUN — base/chassis only. Two rubber wheels, cross-shaped stabilizing outriggers deployed in 4 directions, central support pedestal with a round turret ring (hole for the rotating mechanism). Camouflage netting draped around the edges. Olive-green military paint. Palette: olive (#4B5320), khaki netting, dark rubber wheels. 2D cartoon style like Plants vs Zombies / Kingdom Rush — bold outlines, simplified shapes, flat colors with soft cel-shading, minimal surface detail, top-down view. Solid pure white background (#FFFFFF). No gradients, no ground plane, no shadows on background. No text, no labels, no watermarks, no photorealism, no 3D rendering. Square format, PNG.

---

## 2. tower_autocannon_turret (96×96px)

Top-down overhead view of ONLY the rotating gun mechanism of a twin-barrel anti-aircraft autocannon. This is a SEPARATE game sprite — do NOT draw the base, wheels, outriggers, or any platform. ONLY the gun part that rotates: two parallel long barrels pointing straight up toward the top edge, a compact rotating cradle/yoke holding the barrels, ammo feed belts on both sides, a small gunner seat at the bottom. The gun mechanism floats alone on solid black with nothing beneath it. Rotation pivot point at exact center of image. Palette: dark steel barrels (#3A3A3A), olive mechanism (#4B5320). 2D cartoon style like Plants vs Zombies / Kingdom Rush — bold outlines, simplified shapes, flat colors with soft cel-shading, minimal surface detail, top-down view. Solid pure white background (#FFFFFF). No gradients, no ground plane, no shadows on background. IMPORTANT: Do NOT include wheels, outriggers, base platform, or any part of the mount. No text, no labels, no watermarks, no photorealism, no 3D rendering. Square format, PNG.

---

## 3. tower_autocannon_muzzle (32×32px)

ONLY a muzzle flash effect — no gun, no barrels, no weapon visible. Two bright white-yellow flame bursts side by side (from twin barrels), pointing upward. Radial glow falloff from white-hot core to orange edges. This is a VFX overlay sprite — ONLY the fire/flash, nothing else. Palette: white core, yellow (#FFD700), orange edges. Solid pure black background (#000000). No weapon, no gun, no metal parts. No text, no watermarks. Square format, PNG.

---

## 4. tower_ciws_base (128×128px)

Top-down overhead view of an 8-wheeled military truck chassis (Pantsir-S1 SHORAD system) WITHOUT THE TURRET MODULE. Long rectangular truck body, 8 wheels of equal size (4 axles), driver cabin at the front of the truck, engine compartment behind the cabin, flat cargo platform at the rear with a round turret ring (empty hole for the rotating combat module). NO missile tubes on the body — missiles are on the turret which is a separate sprite. Sandy-beige camouflage with olive patches. Palette: sandy (#C2B280), olive patches, black wheels. 2D cartoon style like Plants vs Zombies / Kingdom Rush — bold outlines, simplified shapes, flat colors with soft cel-shading, minimal surface detail, top-down view. Solid pure white background (#FFFFFF). No gradients, no ground plane, no shadows on background. No text, no labels, no watermarks, no photorealism, no 3D rendering. Square format, PNG.

---

## 5. tower_ciws_turret (80×80px)

Top-down overhead view of ONLY the rotating combat module of a Pantsir-S1 SHORAD system. This is a SEPARATE game sprite — do NOT draw the truck chassis, wheels, or platform. ONLY the turret module that rotates: central optoelectronic sensor dome, two 30mm autocannons (parallel barrels pointing straight up toward the top edge), and 6 missile launch tubes on EACH side of the turret (12 total, arranged in two rows of 6). The missiles are mounted on this turret, NOT on the truck body. The turret floats alone with nothing beneath it. Rotation center at exact center. Palette: dark gray (#4A4A4A), steel barrels, olive-gray missile tubes, optic lens glints. 2D cartoon style like Plants vs Zombies / Kingdom Rush — bold outlines, simplified shapes, flat colors with soft cel-shading, minimal surface detail, top-down view. Solid pure white background (#FFFFFF). No gradients, no ground plane, no shadows on background. IMPORTANT: Do NOT include wheels, truck body, or any part of the chassis. No text, no labels, no watermarks, no photorealism, no 3D rendering. Square format, PNG.

---

## 6. tower_ciws_muzzle (24×24px)

ONLY a muzzle flash effect — no gun, no barrels, no weapon visible. Two small bright orange flame bursts SIDE BY SIDE pointing in the SAME direction (upward toward the top edge) — both barrels fire in one direction, NOT in opposite directions. Simple 2D cartoon flash, NOT photorealistic fire. Flat stylized shapes. This is a VFX overlay sprite — ONLY the fire/flash, nothing else. Palette: orange (#FF8C00) core, yellow edges. Solid pure black background (#000000). No weapon, no gun, no metal parts. No text, no watermarks. Square format, PNG.

---

## 7. tower_sam_base (128×128px)

Top-down overhead view of a heavy 8-wheeled military transporter truck (SAM launcher chassis) WITHOUT LAUNCH TUBES. Long heavy truck, 8 wheels, dark olive paint, driver cabin visible at front, engine compartment, flat frame platform with mounting brackets for the launcher. Palette: dark olive (#3C4A2F), black rubber wheels. 2D cartoon style like Plants vs Zombies / Kingdom Rush — bold outlines, simplified shapes, flat colors with soft cel-shading, minimal surface detail, top-down view. Solid pure white background (#FFFFFF). No gradients, no ground plane, no shadows on background. No text, no labels, no watermarks, no photorealism, no 3D rendering. Square format, PNG.

---

## 8. tower_sam_launcher (88×88px)

Top-down overhead view of a SAM launch container with 4 large missiles — SEPARATE from the truck chassis, will be overlaid on the base sprite at runtime. This is a SEPARATE game sprite — do NOT draw the truck, wheels, or platform. 4 large cylindrical missile tubes arranged in a 2x2 grid, viewed from directly above — you see 4 large round circles (the end caps of the vertical tubes). The missiles point straight up, so from above you see circles. Each missile is noticeably LARGER than the interceptor launcher missiles. Heavy dark mounting frame holding the tubes. Rotation center at exact center. Palette: dark olive (#3C4A2F) canister caps, dark metallic mounting brackets. 2D cartoon style like Plants vs Zombies / Kingdom Rush — bold outlines, simplified shapes, flat colors with soft cel-shading, minimal surface detail, top-down view. Solid pure white background (#FFFFFF). No gradients, no ground plane, no shadows on background. IMPORTANT: Do NOT draw tubes from the side — this is a top-down view showing round circles. No text, no labels, no watermarks, no photorealism, no 3D rendering. Square format, PNG.

---

## 9. tower_interceptor_base (128×128px)

Top-down overhead view of a semi-trailer launcher platform (Western/NATO style SAM system) WITHOUT LAUNCH TUBES. Trailer with hydraulic stabilizer legs, tow vehicle, camouflage netting along the sides. NATO olive-green paint. Palette: NATO olive (#4A5028), sandy patches. 2D cartoon style like Plants vs Zombies / Kingdom Rush — bold outlines, simplified shapes, flat colors with soft cel-shading, minimal surface detail, top-down view. Solid pure white background (#FFFFFF). No gradients, no ground plane, no shadows on background. No text, no labels, no watermarks, no photorealism, no 3D rendering. Square format, PNG.

---

## 10. tower_interceptor_launcher (80×80px)

Top-down overhead view of a NATO SAM launcher module with 12 missiles — SEPARATE from the trailer, will be overlaid on the base sprite at runtime. This is a SEPARATE game sprite — do NOT draw the trailer, wheels, or platform. 12 cylindrical missile canisters arranged in a grid (3 rows of 4), viewed from directly above — you see 12 round circles (the end caps of the vertical tubes). The missiles point straight up, so from above you see circles. Dark mounting frame holding the tubes together. Rotation center at exact center. Palette: silver-gray (#A0A0A0) canister caps, dark (#3A3A3A) mounting frame. 2D cartoon style like Plants vs Zombies / Kingdom Rush — bold outlines, simplified shapes, flat colors with soft cel-shading, minimal surface detail, top-down view. Solid pure white background (#FFFFFF). No gradients, no ground plane, no shadows on background. IMPORTANT: Do NOT draw tubes from the side — this is a top-down view showing round circles. No text, no labels, no watermarks, no photorealism, no 3D rendering. Square format, PNG.

---

## 11. tower_radar_base (128×128px)

Top-down overhead view of a radar station vehicle — truck with deployed stabilizer outriggers on both sides, driver cabin, generator unit, cables running along the body. In the center: a round antenna pedestal (circular metal rotation platform). Olive military paint. Palette: olive (#5A6332), dark cabin, cables. 2D cartoon style like Plants vs Zombies / Kingdom Rush — bold outlines, simplified shapes, flat colors with soft cel-shading, minimal surface detail, top-down view. Solid pure white background (#FFFFFF). No gradients, no ground plane, no shadows on background. No text, no labels, no watermarks, no photorealism, no 3D rendering. Square format, PNG.

---

## 12. tower_radar_antenna (96×64px)

Top-down overhead view looking DOWN onto a parabolic radar antenna — SEPARATE from the vehicle chassis, will be overlaid on the base sprite at runtime. The camera is DIRECTLY ABOVE the antenna. What you see from above: the thin rectangular OUTLINE/EDGE of the wire-mesh reflector dish (since the dish faces horizontally, from above you see it as a thin elongated shape), a feed horn on a support arm pointing into the dish, and the central rotation mount. The dish does NOT face upward toward the camera — it faces horizontally to the side, so from above you see its top edge/rim, not its concave face. Rotation axis at exact center of the image. Palette: silver (#C0C0C0) mesh edge, dark gray (#555555) support arm and mount. 2D cartoon style like Plants vs Zombies / Kingdom Rush — bold outlines, simplified shapes, flat colors with soft cel-shading, minimal surface detail, top-down view. Solid pure white background (#FFFFFF). No gradients, no ground plane, no shadows on background. No text, no labels, no watermarks, no photorealism, no 3D rendering. Wide landscape format (3:2 ratio), PNG.

---

## 13. tower_ew_base (128×128px)

Top-down overhead view of a 6-wheeled military truck chassis (electronic warfare system) WITHOUT ANTENNA ARRAYS. Truck body, 6 wheels, olive camouflage, cooling units and cable bundles visible on the flat platform. Palette: olive (#4B5320), dark cables, metallic cooling blocks. 2D cartoon style like Plants vs Zombies / Kingdom Rush — bold outlines, simplified shapes, flat colors with soft cel-shading, minimal surface detail, top-down view. Solid pure white background (#FFFFFF). No gradients, no ground plane, no shadows on background. No text, no labels, no watermarks, no photorealism, no 3D rendering. Square format, PNG.

---

## 14. tower_ew_array (80×80px)

Top-down overhead view of electronic warfare antenna arrays — SEPARATE from the truck chassis, will be overlaid on the base sprite at runtime. Multiple directional antenna panels, EW equipment containers. Teal (#008080) accent indicator stripes on the panels, dark grilles. Compact form. Rotation center at exact center. Palette: dark panels (#333333), teal (#008080) indicator stripes. 2D cartoon style like Plants vs Zombies / Kingdom Rush — bold outlines, simplified shapes, flat colors with soft cel-shading, minimal surface detail, top-down view. Solid pure white background (#FFFFFF). No gradients, no ground plane, no shadows on background. No text, no labels, no watermarks, no photorealism, no 3D rendering. Square format, PNG.

---

## 15. tower_pzrk_base (128×128px)

Top-down overhead view of a MANPADS firing position — sandbags arranged in a semicircle (bunker/cover), camouflage netting over the top. Dirt ground with trampled grass inside the cover. NO SOLDIER — just the empty position. Palette: sandy (#C2A86E) sandbags, dark green (#3A5A1E) netting, earth tones. 2D cartoon style like Plants vs Zombies / Kingdom Rush — bold outlines, simplified shapes, flat colors with soft cel-shading, minimal surface detail, top-down view. Solid pure white background (#FFFFFF). No gradients, no ground plane, no shadows on background. No text, no labels, no watermarks, no photorealism, no 3D rendering. Square format, PNG.

---

## 16. tower_pzrk_soldier (64×64px)

Top-down overhead view of a soldier in woodland camouflage uniform with body armor, kneeling with a shoulder-launched MANPADS tube. The tube points straight up toward the top edge of the image. Visible helmet, body armor vest, launch tube across the shoulder. SEPARATE from the bunker — will be overlaid at runtime. Rotation center at exact center. Palette: woodland camo (brown #4B3621, green), dark green launch tube. 2D cartoon style like Plants vs Zombies / Kingdom Rush — bold outlines, simplified shapes, flat colors with soft cel-shading, minimal surface detail, top-down view. Solid pure white background (#FFFFFF). No gradients, no ground plane, no shadows on background. No text, no labels, no watermarks, no photorealism, no 3D rendering. Square format, PNG.

---

## 17. tower_gepard_base (128×128px)

Top-down overhead view of a tracked armored vehicle hull (self-propelled AA gun) WITHOUT THE TURRET. Tank-like tracks on both sides, engine compartment at rear, open round turret ring (hole) at the center of the upper hull plate. Three-tone NATO camouflage with MUTED, DESATURATED colors — not bright green. Palette: muted dark olive (#3D4A2F), dark brown (#4A3828), dark gray (#3A3A3A). 2D cartoon style like Plants vs Zombies / Kingdom Rush — bold outlines, simplified shapes, flat colors with soft cel-shading, minimal surface detail, top-down view. Solid pure white background (#FFFFFF). No gradients, no ground plane, no shadows on background. No text, no labels, no watermarks, no photorealism, no 3D rendering. Square format, PNG.

---

## 18. tower_gepard_turret (72×72px)

Top-down overhead view of a self-propelled AA gun turret — SEPARATE from the hull, will be overlaid on the base sprite at runtime. Compact turret with twin 35mm autocannons — two long barrels pointing straight up toward the top edge. Small flat tracking radar dome on the turret roof, small search radar antenna at rear. Steel coloring. Rotation center at exact center. Palette: steel (#707070), dark barrels, camo-painted turret sides. 2D cartoon style like Plants vs Zombies / Kingdom Rush — bold outlines, simplified shapes, flat colors with soft cel-shading, minimal surface detail, top-down view. Solid pure white background (#FFFFFF). No gradients, no ground plane, no shadows on background. No text, no labels, no watermarks, no photorealism, no 3D rendering. Square format, PNG.

---

## 19. tower_gepard_muzzle (28×28px)

ONLY a muzzle flash effect — no gun, no barrels, no weapon visible. Two bright yellow flame bursts SIDE BY SIDE pointing in the SAME direction (upward toward the top edge) — both barrels fire in one direction, NOT in opposite directions. Simple 2D cartoon flash, NOT photorealistic fire. Flat stylized shapes like in Plants vs Zombies. This is a VFX overlay sprite — ONLY the fire/flash, nothing else. Palette: bright yellow (#FFFF00) core, orange edges. Solid pure black background (#000000). No weapon, no gun, no metal parts. No text, no watermarks. Square format, PNG.

---

## 20. drone_regular (120×120px)

Top-down overhead view of a medium fixed-wing military reconnaissance-strike UAV with a V-tail. Nose pointing straight up toward the top edge of the image. From above you see: the wing planform (light gray fuselage, darker swept wings), a dark camera lens circle on the nose, the V-tail at the bottom, and a small pusher propeller disk at the rear. The drone floats alone with nothing beneath it. Palette: light gray (#A0A0A0), dark gray wings, tiny red navigation lights. 2D cartoon style like Plants vs Zombies / Kingdom Rush — bold outlines, simplified shapes, flat colors with soft cel-shading, minimal surface detail, top-down view. Solid pure white background (#FFFFFF). No gradients, no ground plane, no shadows on background. No text, no labels, no watermarks, no photorealism, no 3D rendering. Square format, PNG.

---

## 21. drone_shahed (88×88px)

Top-down overhead view of a delta-wing kamikaze drone (Shahed-136 style). Nose pointing straight up toward the top edge. From above you see: a prominent cylindrical warhead nose section at the top (clearly larger and distinct from the body), transitioning into a triangular delta wing — the entire drone looks like an arrowhead pointing up. Short fuselage merged with the swept wings, no visible tail. NO propeller — the propeller will be added programmatically. The drone floats alone with nothing beneath it. Medium gray color scheme — NOT white, NOT camouflage, NOT olive. No white highlights, no specular reflections, no bright spots. All surfaces must be clearly darker than pure white. Palette: medium gray (#909090) wings, lighter gray (#A8A8A8) warhead nose, dark gray (#555555) outlines. 2D cartoon style like Plants vs Zombies / Kingdom Rush — bold outlines, simplified shapes, flat colors with soft cel-shading, minimal surface detail, top-down view. Solid pure white background (#FFFFFF). No gradients, no ground plane, no shadows on background. No text, no labels, no watermarks, no photorealism, no 3D rendering. Square format, PNG.

---

## 22. drone_orlan (80×80px)

Top-down overhead view of a small high-wing reconnaissance UAV with a pusher propeller at the tail. Nose pointing straight up toward the top edge. White-blue fuselage with a camera pod under the nose, straight tapered wings, V-tail on a tail boom. Palette: white/light blue (#B8D4E3), dark camera lens, gray propeller. 2D cartoon style like Plants vs Zombies / Kingdom Rush — bold outlines, simplified shapes, flat colors with soft cel-shading, minimal surface detail, top-down view. Solid pure white background (#FFFFFF). No gradients, no ground plane, no shadows on background. No text, no labels, no watermarks, no photorealism, no 3D rendering. Square format, PNG.

---

## 23. drone_kamikaze (56×56px)

Top-down overhead view of a small FPV kamikaze quadcopter. Front pointing straight up toward the top edge. From above you see: an X-shaped carbon fiber frame with 4 propeller disks (one at each arm tip), a small attached munition/payload at the front arm. Matte black, aggressive compact form. The drone floats alone with nothing beneath it. Palette: matte dark gray (#333333), tiny red LED. 2D cartoon style like Plants vs Zombies / Kingdom Rush — bold outlines, simplified shapes, flat colors with soft cel-shading, minimal surface detail, top-down view. Solid pure white background (#FFFFFF). No gradients, no ground plane, no shadows on background. No text, no labels, no watermarks, no photorealism, no 3D rendering. Square format, PNG.

---

## 24. drone_ew (96×96px)

Top-down overhead view of an electronic warfare UAV with multiple antenna arrays and EW pods on the wings. Nose pointing straight up toward the top edge. Medium fixed-wing drone with distinctive purple/magenta (#8B008B) LED strips along the wings for identification. Dark gray body, antennas protruding from the fuselage. Palette: dark gray body, purple/magenta (#8B008B) accent glow. 2D cartoon style like Plants vs Zombies / Kingdom Rush — bold outlines, simplified shapes, flat colors with soft cel-shading, minimal surface detail, top-down view. Solid pure white background (#FFFFFF). No gradients, no ground plane, no shadows on background. No text, no labels, no watermarks, no photorealism, no 3D rendering. Square format, PNG.

---

## 25. drone_heavy (168×168px)

Top-down overhead view of a large hexacopter drone (DJI Matrice 600 style) repurposed for bomb dropping. From above you see: a central dark body/hub, 6 arms radiating outward (like a star/hexagon), a bomb payload suspended underneath the center. NO propellers on the sprite — propellers will be added programmatically as 6 spinning rectangles. The arms should have visible motor mounts (small circles) at each tip but NO propeller blades. Dark gray industrial drone body. The drone floats alone with nothing beneath it. Palette: dark charcoal (#3A3A3A) body, medium gray (#666666) arms, dark (#444444) motor mounts at arm tips. 2D cartoon style like Plants vs Zombies / Kingdom Rush — bold outlines, simplified shapes, flat colors with soft cel-shading, minimal surface detail, top-down view. Solid pure white background (#FFFFFF). No gradients, no ground plane, no shadows on background. No text, no labels, no watermarks, no photorealism, no 3D rendering. Square format, PNG.

---

## 26. drone_lancet (64×64px)

Top-down overhead view of a loitering munition drone (ZALA Lancet style). Nose pointing straight up toward the top edge. From above you see: a narrow cylindrical GRAY body with a sharp pointed nose at the top. Cruciform (X-shaped) TAIL FINS at the rear/bottom of the body, and cruciform (X-shaped) WINGS at the mid-body — both sets in X arrangement. Two YELLOW accent stripes across the body: one stripe just behind the sharp nose tip, and another stripe at mid-body just in front of the wings. NO propeller on the sprite — propeller will be added programmatically at the rear. The drone floats alone with nothing beneath it. Palette: medium gray (#808080) body, lighter gray (#999999) wings and tail fins, yellow (#D4A017) accent stripes, dark gray (#555555) outlines. 2D cartoon style like Plants vs Zombies / Kingdom Rush — bold outlines, simplified shapes, flat colors with soft cel-shading, minimal surface detail, top-down view. Solid pure white background (#FFFFFF). No gradients, no ground plane, no shadows on background. No text, no labels, no watermarks, no photorealism, no 3D rendering. Square format, PNG.

---

## 27. drone_bomber (120×120px)

Top-down overhead view of a heavy military bomber drone. Nose pointing straight up toward the top edge. From above you see: a wide fixed-wing planform with a massive center wing section, two propeller disks on the wings, a short fuselage, and a rectangular bomb bay hatch visible on the belly centerline. Dark olive military camouflage with gray patches. The drone floats alone with nothing beneath it. Palette: dark olive (#3D4B2A), gray (#707070) wing patches, dark propellers. 2D cartoon style like Plants vs Zombies / Kingdom Rush — bold outlines, simplified shapes, flat colors with soft cel-shading, minimal surface detail, top-down view. Solid pure white background (#FFFFFF). No gradients, no ground plane, no shadows on background. No text, no labels, no watermarks, no photorealism, no 3D rendering. Square format, PNG.

---

## 28. bomb_aerial (48×48px)

Side view of a small aerial bomb falling from a drone. Cylindrical body with a streamlined nose pointing downward and 4 tail stabilizer fins at the top. Dark olive body, silver nose. Compact form. The bomb floats alone with nothing around it. Palette: dark olive (#4A5028), silver (#B0B0B0) nose cone, dark stabilizers. 2D cartoon style like Plants vs Zombies / Kingdom Rush — simplified shapes, flat colors with soft cel-shading. Solid pure white background (#FFFFFF). No text, no watermarks, no photorealism. Square format, PNG.

---

## 29. missile_enemy (24×72px)

Side view of a single 122mm GRAD rocket — elongated cylindrical body with 4 stabilizing fins at the rear. Bright red body, rocket motor nozzle at the tail. The rocket floats alone with nothing around it. Simple 2D cartoon style, NOT photorealistic. Palette: bright red (#D4251B), silver fin tips. 2D cartoon style like Plants vs Zombies / Kingdom Rush — simplified shapes, flat colors with soft cel-shading. Solid pure white background (#FFFFFF). No text, no watermarks, no photorealism. Tall narrow format (1:3 ratio), PNG.

---

## 30. missile_harm (28×80px)

Side view of a single anti-radiation missile (HARM style), pointing upward toward the top edge. Elongated cylindrical body. Light gray (#A0A0A0) nose cone at the top. Two BLUE (#2266CC) accent stripes across the body: one just behind the nose, and another at mid-body. Cruciform (X-shaped) stabilizer fins at mid-body — they taper, getting thinner (about half thickness) toward the tips. Cruciform (X-shaped) tail fins at the rear — same shape but HALF the length of the mid-body fins. Gray body, no white areas. The missile floats alone with nothing around it. Simple 2D cartoon style, NOT photorealistic. Palette: medium gray (#888888) body, light gray (#A0A0A0) nose, blue (#2266CC) stripes, darker gray (#666666) fins. 2D cartoon style like Plants vs Zombies / Kingdom Rush — simplified shapes, flat colors with soft cel-shading. Solid pure white background (#FFFFFF). No text, no watermarks, no photorealism. Tall narrow format (roughly 1:3 ratio), PNG.

---

## 31. missile_cruise (32×88px)

Side view of a single cruise missile, pointing upward toward the top edge. Elongated cylindrical gray body with a pointed nose at the top. Two small RECTANGULAR wings sticking out to the left and right at mid-body — short stubby straight wings (not swept). Small tail control fins at the rear. Neutral gray military paint, no white areas. The missile floats alone with nothing around it. Simple 2D cartoon style, NOT photorealistic. Palette: neutral gray (#808080) body, darker gray (#606060) nose, medium gray (#707070) wings and tail fins. 2D cartoon style like Plants vs Zombies / Kingdom Rush — simplified shapes, flat colors with soft cel-shading. Solid pure white background (#FFFFFF). No text, no watermarks, no photorealism. Tall narrow format (roughly 1:3 ratio), PNG.

---

## 32. drone_swarm (16×16px)

Top-down view of a tiny micro-drone (nano-UAV). Minimal gray square/diamond shape with 4 barely visible rotors. Very small and simple, matte dark gray. Palette: dark gray (#666666). Solid pure white background (#FFFFFF). No text. Square format, PNG.

---

## 33. projectile_autocannon (16×16px)

Small bright yellow-green tracer round — a glowing elongated dot, anti-aircraft tracer fire effect. Bright core with falloff to edges. Palette: bright yellow (#FFD700) center, yellow-green glow. Solid pure black background (#000000). No text. Square format, PNG.

---

## Important: Damage Visual Effects (applied to all drone sprites at runtime)

All drone sprites (drone_shahed, drone_kamikaze, drone_ew, drone_heavy, drone_lancet, drone_orlan, drone_swarm, drone_bomber) receive **programmatic damage effects** when hit. The sprite artist should be aware that the base sprite will be modified at runtime:

### Light damage
- **Color tint**: sprite gets a gray overlay via `colorBlendFactor: 0.15` blended with gray
- **Smoke**: a small particle emitter is attached to the sprite — light gray (#B3B3B3) circular smoke puffs, birthRate 8, rising upward from the drone body, alpha 0.3, particles expand from 0.15 to ~0.27 scale

### Medium damage
- **Color tint**: darker gray overlay, `colorBlendFactor: 0.35`, color darkens to (#595959)
- **Smoke**: heavier dark smoke emitter, birthRate 20, alpha 0.5, same upward-rising gray particles but denser and more opaque

### Critical damage (drone is burning)
- **Color tint**: red-brown tint (`color: rgb(153, 38, 26)`, `colorBlendFactor: 0.45`)
- **Fire**: orange-yellow flame particle emitter, birthRate 40, alpha 0.9, particles start orange (#FF9900) and fade through red to dark. Particles rise upward with wider angular spread than smoke. Emitter position covers 30% of the sprite size

### Design implications for sprite artists
- Use **medium-toned colors** (not too bright, not too dark) so both the gray tint (damage) and the orange/red fire effect remain visible against the drone body
- Avoid large pure-white areas on drones — they would conflict with the smoke particles and make the gray tint look unnatural
- The smoke/fire particles appear as children of the sprite node at zPosition 30, so they render above the drone body
- Navigation lights (small red/green dots) are added programmatically at the wing tips — do NOT include them in the sprite
- Propellers are added programmatically — do NOT include spinning propellers in the sprite

---

## 34. projectile_sam (48×72px)

Side view of a single large SAM interceptor missile — long white cylindrical body with an olive nose cone (seeker), 4 folding mid-body fins and 4 tail control surfaces. The missile floats alone with nothing around it. Simple 2D cartoon style, NOT photorealistic. Palette: white body, olive nose, gray fins. 2D cartoon style like Plants vs Zombies / Kingdom Rush — simplified shapes, flat colors with soft cel-shading. Solid pure white background (#FFFFFF). No text, no watermarks, no photorealism. Tall format (2:3 ratio), PNG.

---

## 35. projectile_interceptor (30×45px)

Side view of a single compact guided interceptor missile — shorter than the SAM missile, white body with a black nose cone (seeker), 4 small tail fins. The missile floats alone with nothing around it. Simple 2D cartoon style, NOT photorealistic. Palette: white body, black nose, silver fins. 2D cartoon style like Plants vs Zombies / Kingdom Rush — simplified shapes, flat colors with soft cel-shading. Solid pure white background (#FFFFFF). No text, no watermarks, no photorealism. Tall format (2:3 ratio), PNG.

---

## 36. projectile_ciws (16×16px)

Small bright orange tracer round — a glowing elongated dot, rapid-fire anti-aircraft tracer effect. Orange-yellow glow. Palette: orange (#FF8C00) center, yellow glow at edges. Solid pure black background (#000000). No text. Square format, PNG.

---

## 37. projectile_pzrk (30×45px)

Side view of a single MANPADS infrared-guided missile — small compact missile with an IR seeker dome on the nose, olive-green body, 4 pop-out fins. The missile floats alone with nothing around it. Simple 2D cartoon style, NOT photorealistic. No smoke trail. Palette: olive-green body, dark IR dome, small fins. 2D cartoon style like Plants vs Zombies / Kingdom Rush — simplified shapes, flat colors with soft cel-shading. Solid pure white background (#FFFFFF). No text, no watermarks, no photorealism. Tall format (2:3 ratio), PNG.

---

## 38. projectile_gepard (16×16px)

Medium-brightness yellow 35mm tracer round — a glowing dot, slightly larger than a standard tracer. Bright yellow glow. Palette: bright yellow (#FFFF00) center. Solid pure black background (#000000). No text. Square format, PNG.

---

## 39. fx_smoke_puff (56×56px)

Simple 2D cartoon white smoke puff — a soft round fluffy cloud shape with slightly uneven edges, white center fading to edges. Flat stylized shapes like in Plants vs Zombies, NOT photorealistic smoke. For rocket/projectile smoke trails. Solid pure black background (#000000). No text. Square format, PNG.

---

## 40. fx_smoke_puff_gray (56×56px)

Simple 2D cartoon gray smoke puff — a soft round fluffy cloud shape, slightly darker than white smoke. Flat stylized shapes like in Plants vs Zombies, NOT photorealistic smoke. For enemy missile exhaust. Palette: gray (#B0B0B0) center at 60% opacity. Solid pure black background (#000000). No text. Square format, PNG.

---

## 41. fx_flame_glow (32×32px)

Simple 2D cartoon flame point — a bright orange-red dot with intense hot core fading to dim orange edges. Flat stylized shapes like in Plants vs Zombies, NOT photorealistic fire. Radial gradient from white-orange center to edges. Palette: white-hot center, orange (#FF5A0D), red edges. Solid pure black background (#000000). No text. Square format, PNG.

---

## FRAME-BY-FRAME EXPLOSION ANIMATIONS

Replace 3 static sprites. Each frame is a separate sprite for SKAction.animate().
All frames within one animation must be in the same style, same viewing angle, on black background.

### Small Explosion (5 frames, 64×64px) — drone destruction

## 42a. fx_explosion_small_f1 (64×64px)

Frame 1 of 5 in a cartoon small explosion animation sequence. A bright white-hot point at center, just the beginning of the flash, size ~20% of final explosion radius. This is the initial detonation flash — next frames will show an expanding orange fireball, then fading to smoke. 2D cartoon style like Plants vs Zombies / Kingdom Rush. Solid pure black background (#000000). No text. Square format, PNG.

---

## 42b. fx_explosion_small_f2 (64×64px)

Frame 2 of 5 in a cartoon small explosion animation sequence. The white core is expanding, surrounded by a yellow-orange fireball, size ~40% of final explosion radius. Previous frame was a small white flash. Next frames will show peak fireball, then fading flames and smoke. 2D cartoon style like Plants vs Zombies / Kingdom Rush. Solid pure black background (#000000). No text. Square format, PNG.

---

## 42c. fx_explosion_small_f3 (64×64px)

Frame 3 of 5 in a cartoon small explosion animation sequence. Orange fireball at maximum brightness, dark smoke beginning at edges, size ~65% of final explosion radius. Previous frames showed a white flash expanding into a fireball. Next frames: flames fade, gray smoke expands. 2D cartoon style like Plants vs Zombies / Kingdom Rush. Solid pure black background (#000000). No text. Square format, PNG.

---

## 42d. fx_explosion_small_f4 (64×64px)

Frame 4 of 5 in a cartoon small explosion animation sequence. Flames fading to orange-red, gray smoke expanding outward, size ~85% of final explosion radius. Previous frames showed a fireball at peak intensity. Next frame: thin dissipating gray smoke only. 2D cartoon style like Plants vs Zombies / Kingdom Rush. Solid pure black background (#000000). No text. Square format, PNG.

---

## 42e. fx_explosion_small_f5 (64×64px)

Frame 5 of 5 (final) in a cartoon small explosion animation sequence. Thin gray wisps of smoke, nearly fully transparent, no flames remaining, size 100% of final radius. Previous frames showed a fireball fading through orange-red to smoke. This is the last dissipating frame. 2D cartoon style like Plants vs Zombies / Kingdom Rush. Solid pure black background (#000000). No text. Square format, PNG.

---

### Medium Explosion (6 frames, 96×96px) — missile hit

## 43a. fx_explosion_medium_f1 (96×96px)

Frame 1 of 6 in a cartoon medium explosion animation sequence. A bright white-hot point at center, just the beginning of detonation, size ~20% of final radius. This is a medium-sized explosion (missile impact). Next frames: expanding fireball, peak flame, then smoke. 2D cartoon style like Plants vs Zombies / Kingdom Rush. Solid pure black background (#000000). No text. Square format, PNG.

---

## 43b. fx_explosion_medium_f2 (96×96px)

Frame 2 of 6 in a cartoon medium explosion animation sequence. White core expanding, surrounded by an intense yellow-orange fireball, size ~40% of final radius. Previous: white flash. Next: peak fireball with smoke edges. 2D cartoon style like Plants vs Zombies / Kingdom Rush. Solid pure black background (#000000). No text. Square format, PNG.

---

## 43c. fx_explosion_medium_f3 (96×96px)

Frame 3 of 6 in a cartoon medium explosion animation sequence. Orange fireball at maximum intensity, a faint dark smoke ring starting at edges, size ~60% of final radius. Previous: expanding fireball. Next: flames begin fading, debris visible. 2D cartoon style like Plants vs Zombies / Kingdom Rush. Solid pure black background (#000000). No text. Square format, PNG.

---

## 43d. fx_explosion_medium_f4 (96×96px)

Frame 4 of 6 in a cartoon medium explosion animation sequence. Flames fading to orange-red, dark smoke expanding outward, small debris fragments visible, size ~80% of final radius. Previous: peak fireball. Next: mostly smoke. 2D cartoon style like Plants vs Zombies / Kingdom Rush. Solid pure black background (#000000). No text. Square format, PNG.

---

## 43e. fx_explosion_medium_f5 (96×96px)

Frame 5 of 6 in a cartoon medium explosion animation sequence. Red-brown remnants, gray-black smoke dominates, center clearing, size ~95% of final radius. Previous: fading flames with debris. Next: thin dissipating smoke. 2D cartoon style like Plants vs Zombies / Kingdom Rush. Solid pure black background (#000000). No text. Square format, PNG.

---

## 43f. fx_explosion_medium_f6 (96×96px)

Frame 6 of 6 (final) in a cartoon medium explosion animation sequence. Thin gray wisps of smoke dissipating, nearly fully transparent, size 100% of final radius. Previous frames showed a full explosion sequence from flash to smoke. This is the last frame. 2D cartoon style like Plants vs Zombies / Kingdom Rush. Solid pure black background (#000000). No text. Square format, PNG.

---

### Large Explosion (7 frames, 128×128px) — airstrike / heavy drone

## 44a. fx_explosion_large_f1 (128×128px)

Frame 1 of 7 in a cartoon large explosion animation sequence. A bright white-hot detonation point at center, a small blinding sphere, size ~15% of final radius. This is a large explosion (heavy drone/airstrike). Next: massive expanding fireball. 2D cartoon style like Plants vs Zombies / Kingdom Rush. Solid pure black background (#000000). No text. Square format, PNG.

---

## 44b. fx_explosion_large_f2 (128×128px)

Frame 2 of 7 in a cartoon large explosion animation sequence. White core expanding, powerful yellow-orange fireball, size ~30% of final radius. Previous: initial white flash. Next: peak intensity fireball. 2D cartoon style like Plants vs Zombies / Kingdom Rush. Solid pure black background (#000000). No text. Square format, PNG.

---

## 44c. fx_explosion_large_f3 (128×128px)

Frame 3 of 7 in a cartoon large explosion animation sequence. Intense orange fireball at peak brightness, yellow-white center, smoke beginning at edges, size ~50% of final radius. Previous: expanding fireball. Next: flames start fading. 2D cartoon style like Plants vs Zombies / Kingdom Rush. Solid pure black background (#000000). No text. Square format, PNG.

---

## 44d. fx_explosion_large_f4 (128×128px)

Frame 4 of 7 in a cartoon large explosion animation sequence. Orange-red fireball starting to fade, dark smoke ring expanding, flying debris fragments visible, size ~65% of final radius. Previous: peak fireball. Next: more smoke, less flame. 2D cartoon style like Plants vs Zombies / Kingdom Rush. Solid pure black background (#000000). No text. Square format, PNG.

---

## 44e. fx_explosion_large_f5 (128×128px)

Frame 5 of 7 in a cartoon large explosion animation sequence. Red-brown flames, massive black-gray smoke cloud, debris fragments, size ~80% of final radius. Previous: fading fireball. Next: smoke dominates. 2D cartoon style like Plants vs Zombies / Kingdom Rush. Solid pure black background (#000000). No text. Square format, PNG.

---

## 44f. fx_explosion_large_f6 (128×128px)

Frame 6 of 7 in a cartoon large explosion animation sequence. Flames nearly extinguished, dark gray smoke dominates, center clearing, size ~95% of final radius. Previous: red-brown flames with heavy smoke. Next: final dissipating wisps. 2D cartoon style like Plants vs Zombies / Kingdom Rush. Solid pure black background (#000000). No text. Square format, PNG.

---

## 44g. fx_explosion_large_f7 (128×128px)

Frame 7 of 7 (final) in a cartoon large explosion animation sequence. Dissipating gray wisps of smoke, nearly fully transparent, last particles, size 100% of final radius. This is the last frame of the sequence. 2D cartoon style like Plants vs Zombies / Kingdom Rush. Solid pure black background (#000000). No text. Square format, PNG.

---

## 45. fx_armor_spark (24×24px)

Simple 2D cartoon ricochet spark — a bright yellow glint with 4-6 tiny radiating lines from the center. Flat stylized shapes like in Plants vs Zombies. Bullet-hitting-armor impact effect. Palette: bright yellow (#FFD700), white center. Solid pure black background (#000000). No text. Square format, PNG.

---

## 46. fx_damage_smoke (32×32px)

Simple 2D cartoon dark gray smoke puff, semi-transparent. Flat stylized shapes like in Plants vs Zombies, NOT photorealistic. For showing a damaged/disabled tower emitting smoke. Palette: dark gray (#606060) at 50% opacity. Solid pure black background (#000000). No text. Square format, PNG.

---

## 47. fx_shadow_ellipse (128×64px)

Soft dark elliptical shadow — black at 35% opacity in the center, fading to transparent edges. For drone ground shadow. Solid pure black background (#000000). No text. Wide format (2:1 ratio), PNG.

---

## 48. settlement_village (112×112px)

Top-down overhead view of a small rural hamlet. From above you see: 3-4 tiny cottage ROOFTOPS (brown/straw colored rectangles), thin dirt paths between them, small green vegetable garden patches. Warm brown and white tones. The settlement floats alone on the background with nothing around it. 2D cartoon style like Plants vs Zombies / Kingdom Rush — simplified shapes, minimal texture, flat colors with soft cel-shading, top-down view. Solid pure white background (#FFFFFF). No gradients, no ground plane beyond the settlement. No text, no labels, no watermarks, no photorealism, no 3D rendering. Square format, PNG.

---

## 49. settlement_town (112×112px)

Top-down overhead view of a small urban block. From above you see: 4-6 flat ROOFTOPS of multi-story apartment buildings (gray-beige rectangles), paved roads between them, a small park with round tree canopies. Light beige and gray tones. The block floats alone on the background. 2D cartoon style like Plants vs Zombies / Kingdom Rush — simplified shapes, minimal texture, flat colors with soft cel-shading, top-down view. Solid pure white background (#FFFFFF). No gradients, no ground plane beyond the settlement. No text, no labels, no watermarks, no photorealism, no 3D rendering. Square format, PNG.

---

## 50. settlement_factory (112×112px)

Top-down overhead view of a small industrial complex. From above you see: a main workshop with a zigzag/sawtooth ROOFTOP pattern, round smokestack circles, cylindrical storage tank circles, a loading ramp. Gray-blue metal roofs, concrete yard. The complex floats alone on the background. 2D cartoon style like Plants vs Zombies / Kingdom Rush — simplified shapes, minimal texture, flat colors with soft cel-shading, top-down view. Solid pure white background (#FFFFFF). No gradients, no ground plane beyond the settlement. No text, no labels, no watermarks, no photorealism, no 3D rendering. Square format, PNG.

---

## 51. settlement_farm (112×112px)

Top-down overhead view of a farm. From above you see: a farmhouse ROOFTOP, a barn with a red-brown ROOFTOP, a round grain silo circle, neat rows of green crop lines around the buildings, a thin dirt road. The farm floats alone on the background. 2D cartoon style like Plants vs Zombies / Kingdom Rush — simplified shapes, minimal texture, flat colors with soft cel-shading, top-down view. Solid pure white background (#FFFFFF). No gradients, no ground plane beyond the settlement. No text, no labels, no watermarks, no photorealism, no 3D rendering. Square format, PNG.

---

## 52. settlement_depot (112×112px)

Top-down overhead view of a military supply depot. From above you see: 2 long warehouse hangar ROOFTOPS, rows of small crate and container rectangles in the yard, parked military truck shapes, a thin perimeter fence outline. Olive and orange-brown tones. The depot floats alone on the background. 2D cartoon style like Plants vs Zombies / Kingdom Rush — simplified shapes, minimal texture, flat colors with soft cel-shading, top-down view. Solid pure white background (#FFFFFF). No gradients, no ground plane beyond the settlement. No text, no labels, no watermarks, no photorealism, no 3D rendering. Square format, PNG.

---

## 53. tile_ground (128×128px)

Square landscape tile — flat dark green-gray ground with sparse tufts of grass, slight dirt texture. Dark muted olive tones, military field. MUST be seamless tileable — edges must match perfectly when placed side by side. 2D cartoon style, flat colors. No objects, no structures — just terrain. 128×128px, PNG.

---

## 54. tile_highGround (128×128px)

Square landscape tile — elevated sandy-brown terrain, packed earth with small rocks and dry grass patches. Tan/khaki military hilltop feel, noticeably warmer and lighter than the dark olive ground tile. Towers placed here get elevated line-of-sight. MUST be seamless tileable — edges must match perfectly. 2D cartoon style, flat colors. 128×128px, PNG.

---

## 55. tile_blocked (128×128px)

Square landscape tile — dark gray rocky ground or concrete rubble, darker than the regular ground tile. Zone where building is not allowed. MUST be seamless tileable — edges must match perfectly. 2D cartoon style, flat colors. 128×128px, PNG.

---

## 56. tile_headquarters (128×128px)

Square tile — top-down view of a military bunker/command post entrance, reinforced concrete with camouflage netting, red-brown earth around an armored door. 128×128px, PNG.

---

## 57. tile_settlement (128×128px)

Square landscape tile — slightly brighter green zone with neat grass, cleaner and lighter than the military ground tile. Zone where settlements can be placed. MUST be seamless tileable — edges must match perfectly. 2D cartoon style, flat colors. 128×128px, PNG.

---

## 58. tile_concealed (128×128px)

Square landscape tile — very dark green terrain with dense low bushes and camouflage netting patches. Darker than the regular ground tile, feels hidden and covered. Towers placed here are immune to anti-radiation missiles. MUST be seamless tileable — edges must match perfectly. 2D cartoon style, flat colors. 128×128px, PNG.

---

## 59. tile_valley (128×128px)

Square landscape tile — muted olive-brown lowland terrain with worn footpaths and slight depression feel. Slightly different tone from regular ground — more brown, less green. Drones speed up when flying over this zone. MUST be seamless tileable — edges must match perfectly. 2D cartoon style, flat colors. 128×128px, PNG.

---

## 60. ui_hud_bar (1170×240px)

Horizontal dark military CRT panel — very dark green-black background with barely visible scanline texture, a thin green phosphor border line at the bottom, matte dark metal look. Soviet Cold War-era air defense console aesthetic. For the top HUD bar. No text. Wide format, 1170×240px, PNG.

---

## 61. ui_btn_start_wave_normal (720×120px)

Military illuminated button — dark metallic frame around a glowing green button surface, beveled edges, LED indicator on the left. Cold War air defense console button style. No text — text will be added separately in code. Solid pure white background (#FFFFFF). Wide format, 720×120px, PNG.

---

## 62. ui_btn_start_wave_pressed (720×120px)

Military illuminated button in PRESSED state — same style as the normal state button (dark metallic frame, beveled edges, LED indicator) but the button surface is brighter (intense green glow), beveled edges appear depressed, LED indicator is brightly lit. Cold War air defense console style. No text. Solid pure white background (#FFFFFF). Wide format, 720×120px, PNG.

---

## 63. ui_btn_start_wave_disabled (720×120px)

Military button in DISABLED state — same style as the normal state button (dark metallic frame, beveled edges, LED indicator) but the button surface is dim (muted dark gray with faint greenish tint), beveled edges flat, LED indicator is off/dark. Cold War air defense console style. No text. Solid pure white background (#FFFFFF). Wide format, 720×120px, PNG.

---

## 64. ui_btn_speed_1x (96×96px)

Small military toggle switch/button — dark metallic frame with a lit green indicator, a single chevron symbol "▶" drawn in green phosphor at center. Cold War console switch style. Solid pure white background (#FFFFFF). No text other than the chevron symbol. Square format, 96×96px, PNG.

---

## 65. ui_btn_speed_2x (96×96px)

Small military toggle switch/button — dark metallic frame with a lit amber-orange indicator, a double chevron symbol "▶▶" drawn in amber phosphor at center. Cold War console switch style. Solid pure white background (#FFFFFF). No text other than the chevron symbol. Square format, 96×96px, PNG.

---

## 66. ui_btn_settings (120×120px)

Military settings button — dark matte metallic circle with a gear/cog symbol drawn in green phosphor, beveled edge. Cold War console aesthetic. Solid pure white background (#FFFFFF). Square format, 120×120px, PNG.

---

## 67. ui_conveyor_slot (168×168px)

Square military equipment slot/compartment — dark recessed panel with a thin green phosphor border, faint CRT grid pattern inside. For placing tower cards. Air defense console style. No text. Solid pure white background (#FFFFFF). Square format, 168×168px, PNG.

---

## 68. ui_tower_card (120×120px)

Square military equipment selection card — slightly raised dark metallic panel with a faint green phosphor edge glow. For placing tower icons on top. Cold War console style. No text. Solid pure white background (#FFFFFF). Square format, 120×120px, PNG.

---

## 69. ui_ability_fighter (150×150px)

Military ability button with a fighter jet silhouette — dark metallic frame, round button, green phosphor silhouette of a jet aircraft. Air defense console style. For calling in air support. No text. Solid pure white background (#FFFFFF). Square format, 150×150px, PNG.

---

## 70. ui_ability_barrage (150×150px)

Military ability button with an explosion icon — dark metallic frame, round button, amber-orange phosphor explosion/burst symbol. Air defense console style. For artillery strike ability. No text. Solid pure white background (#FFFFFF). Square format, 150×150px, PNG.

---

## 71. ui_ability_reload (150×150px)

Military ability button with a circular reload arrow — dark metallic frame, round button, green phosphor circular arrow symbol. Air defense console style. For emergency reload ability. No text. Solid pure white background (#FFFFFF). Square format, 150×150px, PNG.

---

## 72. ui_menu_background (1170×2532px)

Full-screen dark military CRT console background — very dark green-black with faint phosphor scanlines, a pale radar sweep arc in the background, military coordinate grid lines. Soviet S-300 air defense command post aesthetic. Military stencil test patterns at edges. No text. Portrait format, 1170×2532px, PNG.

---

## 73. ui_title_background (900×180px)

Dark panel with CRT green phosphor bloom effect — rectangular area with intense green bloom glow, scanlines, slight CRT distortion. Background for the game title, text will be overlaid separately. Solid pure white background (#FFFFFF). Wide format, 900×180px, PNG.

---

## 74. ui_btn_campaign (600×150px)

Military button — dark metallic frame with a blue-lit button surface. Soviet military console style, blue illuminated indicator. No text — text will be added separately. Solid pure white background (#FFFFFF). Wide format, 600×150px, PNG.

---

## 75. ui_btn_endless (600×150px)

Military button — dark metallic frame with a green-lit button surface. Soviet military console style, green illuminated indicator. No text — text will be added separately. Solid pure white background (#FFFFFF). Wide format, 600×150px, PNG.

---

## 76. ui_level_card (1080×144px)

Horizontal military mission card — dark matte metallic rectangle with green phosphor border, faint CRT texture, recessed panel. For the level selection list. Cold War console style. No text. Wide format, 1080×144px, PNG.

---

## 77. ui_btn_back (360×120px)

Military button — dark metallic frame, red-lit button surface. Cold War emergency/warning button aesthetic. No text — text will be added separately. Solid pure white background (#FFFFFF). Wide format, 360×120px, PNG.

---

## 78. ui_gameover_background (900×240px)

Dark panel with CRT red phosphor bloom effect — rectangular area with pulsing red bloom glow, CRT distortion, military warning display style. Background for "GAME OVER" text, which will be overlaid separately. Solid pure white background (#FFFFFF). Wide format, 900×240px, PNG.

---

## 77. ui_btn_playagain (540×132px)

Military button — dark gray metallic surface with beveled edges, faint green border glow. Cold War console button style. No text — text will be added separately. Solid pure white background (#FFFFFF). Wide format, 540×132px, PNG.

---

## 78. ui_btn_menu (540×132px)

Military button — dark metallic frame, red-lit button surface. Cold War emergency button style. No text — text will be added separately. Solid pure white background (#FFFFFF). Wide format, 540×132px, PNG.

---

## 79. ui_pause_panel (900×810px)

Rectangular dark military CRT panel with a thick green phosphor border. Black interior with faint scanlines. Air defense console pause screen style. No text. 900×810px, PNG.

---

## 80. ui_btn_resume (540×150px)

Military button — dark gray surface with a green LED indicator, metallic frame. Cold War console button. No text — text will be added separately. Solid pure white background (#FFFFFF). Wide format, 540×150px, PNG.

---

## 81. ui_btn_restart (540×150px)

Military button — dark gray surface with an amber LED indicator, metallic frame. Cold War console button. No text — text will be added separately. Solid pure white background (#FFFFFF). Wide format, 540×150px, PNG.

---

## 82. ui_btn_exit (540×150px)

Military button — red-lit button surface, metallic frame. Cold War emergency/warning button style. No text — text will be added separately. Solid pure white background (#FFFFFF). Wide format, 540×150px, PNG.

---

## 83. ui_aid_card (330×480px)

Vertical military equipment/upgrade selection card — dark matte metallic rectangle with an amber phosphor border, CRT texture inside, space for an icon and description text. Cold War console upgrade card style. No text. Solid pure white background (#FFFFFF). Portrait format, 330×480px, PNG.

---

## 84. ui_warning_background (600×120px)

Dark panel with bright red CRT phosphor bloom effect — rectangular area with pulsing red bloom, warning display style. Background for alert text, which will be overlaid separately. Solid pure white background (#FFFFFF). Wide format, 600×120px, PNG.

---

## 85. ui_target_marker (90×90px)

Military targeting reticle/crosshair — a thin red circle with crosshair lines, military aiming sight. For designating artillery strike targets. Solid pure white background (#FFFFFF). Square format, 90×90px, PNG.

---

## 86. ui_offscreen_arrow (60×60px)

Bright yellow military directional arrow — a filled triangle/chevron pointing to the right, with a faint glow. For indicating enemy drones off-screen. Solid pure white background (#FFFFFF). Square format, 60×60px, PNG.

---

## 87. ui_star_filled (60×60px)

Bright yellow military 5-pointed star — metallic golden finish with slight bevel. For campaign level completion rating. Solid pure white background (#FFFFFF). Square format, 60×60px, PNG.

---

## 88. ui_star_empty (60×60px)

Outline-only 5-pointed star in dim gray — thin line, empty star for unfilled rating slot. Solid pure white background (#FFFFFF). Square format, 60×60px, PNG.

---

## 89. sprite_fighter_jet (160×80px)

Top-down overhead view of a military fighter jet in a banking turn. From above you see: the wing planform of a twin-engine fighter, gray-blue camouflage, afterburner glow circles at the rear. The jet floats alone with nothing beneath it. 2D cartoon style like Plants vs Zombies / Kingdom Rush — simplified shapes, flat colors with soft cel-shading. Solid pure white background (#FFFFFF). No text, no watermarks. Wide format (2:1 ratio), 160×80px, PNG.

---

## 90. AppIcon (1024×1024px)

iOS app icon — dark military green-black background with faint CRT scanlines, a bright green phosphor radar display with a sweep arc at the center, a simplified silhouette of a SAM launcher in the foreground. 2D cartoon style like Plants vs Zombies / Kingdom Rush — simplified shapes, flat colors, minimal texture. No text — text will be added separately. Square format, 1024×1024px, PNG.

---

## Summary: 105 individual sprites

| Category | Count |
|----------|-------|
| Towers (base + turret + muzzle) | 19 |
| Enemy drones and missiles | 13 |
| Player projectiles | 6 |
| VFX effects (incl. 18 explosion frames) | 24 |
| Settlements | 5 |
| Landscape tiles | 5 |
| UI elements (with button state variants) | 31 |
| Special sprites | 2 |
| **Total** | **105** |
