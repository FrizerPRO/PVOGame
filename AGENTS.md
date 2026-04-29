# PVOGame - Codex Project Guide

This is the Codex-formatted copy of `CLAUDE.md`. Codex reads `AGENTS.md`
as repository guidance. Keep the Claude files intact for Claude Code users.

## Project Overview

Ukrainian air defense tower defense game built with iOS SpriteKit and
GameplayKit. The player places anti-air towers on a grid map to defend
headquarters (HQ) and settlements from waves of enemy drones, missiles, and
electronic warfare threats.

## Tech Stack

- Language: Swift 5.0
- Frameworks: SpriteKit, GameplayKit (ECS), UIKit
- Platform: iOS 15.5+ in portrait orientation
- Architecture: Entity-Component System (GKEntity/GKComponent)
- Build: Xcode project, no SPM or CocoaPods

## Codex Working Rules

- Protect user changes. This worktree is often dirty, so inspect diffs before
  editing and never revert unrelated changes.
- Open and build the outer `PVOGame.xcodeproj`. Ignore the nested legacy
  project under `PVOGame/PVOGame.xcodeproj`.
- Ignore the nested `PVOGame/PVOGame/PVOGame/` directory unless a task
  explicitly targets legacy code.
- Prefer existing SpriteKit/GameplayKit ECS patterns over new abstractions.
- Keep gameplay constants in `PVOGame/Constants.swift` under nested structs.
- When adding files through the `xcodeproj` Ruby gem, use just the filename
  for groups that already have `path` set.
- Claude settings and hooks under `.claude/` are not consumed by Codex. The
  equivalent manual scripts live under `codex/hooks/`; see `codex/README.md`.

## Build And Run

```bash
# Open in Xcode
open PVOGame.xcodeproj

# CLI build. Prefer iPhone 17 Pro when available.
xcodebuild -project PVOGame.xcodeproj -scheme PVOGame \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build

# Rebuild, install, and relaunch on the simulator.
codex/hooks/rebuild-sim.sh
```

## Project Structure

```text
PVOGame/
├── Scenes/              # Main game scene and extensions
│   ├── InPlaySKScene.swift
│   ├── InPlaySKScene+HUD.swift
│   ├── InPlaySKScene+Settings.swift
│   ├── InPlaySKScene+GameFlow.swift
│   ├── InPlaySKScene+DroneSpawning.swift
│   ├── InPlaySKScene+GameEvents.swift
│   ├── InPlaySKScene+Effects.swift
│   ├── InPlaySKScene+FireControl.swift
│   └── InPlaySKScene+TouchHandling.swift
├── Models/              # GKEntity subclasses
├── Components/          # GKComponent subclasses
├── Managers/            # Wave, economy, placement, fire control, campaign
├── Grid/                # Grid map and flight paths
├── Levels/              # Level and wave definitions
├── Enums/               # Shared enumerations
├── UI/                  # UIKit overlay views
├── CollisionDetection/  # Physics contact handling
├── Extensions/          # Swift extensions
├── MainMenu/            # Main menu UI
├── GameplayViews/       # In-game UIKit overlays
├── Guns/                # Legacy gun definitions, unused in TD mode
├── Constants.swift
├── AppDelegate.swift
└── GameViewController.swift
```

## Architecture

Entities are GKEntity subclasses for drones, towers, projectiles, settlements,
and legacy objects. Components add behavior such as targeting, stats, rotation,
sprites, geometry, altitude, and shadows. Managers own larger gameplay systems
such as waves, economy, placement, campaign progress, settlements, synergies,
abilities, and fire-control deconfliction.

`InPlaySKScene` is the central SKScene coordinator split across extension
files. It owns managers and game state, runs the update loop, handles tower
drag/drop and interactions, and manages entity lifecycle through
`addEntity`/`removeEntity`.

## Key Data Flow

```text
InPlaySKScene
  ├─ WaveManager
  ├─ GridMap
  ├─ TowerPlacementManager
  ├─ FireControlState
  ├─ ConveyorBeltManager
  ├─ TowerSynergyManager
  ├─ SettlementManager
  ├─ CollisionDetectedInGame
  └─ Entities with components
```

## Game Flow

1. Main menu to campaign level or endless mode.
2. Build phase: drag towers from the conveyor belt onto the grid.
3. Combat phase: WaveManager spawns enemies and towers auto-engage.
4. Wave complete: settlements generate income and military aid choices appear.
5. Repeat until HQ lives reach zero or all campaign waves are cleared.

## Key Types

| Type | Role |
| --- | --- |
| `InPlaySKScene` | Main game scene coordinator |
| `AttackDroneEntity` | Base class for all enemy air targets |
| `TowerEntity` | Placed defensive tower |
| `TowerType` | Tower enum: autocannon, ciws, samLauncher, interceptor, radar, ewTower, pzrk, gepard |
| `RocketEntity` | Guided missile projectile |
| `FireControlState` | Rocket targeting deconfliction |
| `WaveManager` | Wave spawning schedule |
| `GridMap` | 16x10 tile grid with terrain and line of sight |
| `Constants` | Balance values, bitmasks, and sizing |

## Conventions

- File naming: `TypeName.swift`; extensions: `TypeName+Feature.swift`.
- Collision bitmasks live in `Constants` (`droneBitMask`, `bulletBitMask`,
  and related masks).
- Entity visuals normally use `SpriteComponent`; physics uses
  `GeometryComponent`.
- zPosition layers: ground 0-10, shadows 5, towers 21-40, projectiles 41-60,
  drones 61+, HUD 95-100.
- UI text is Ukrainian/Russian.

## Tower Types

| Enum case | Real-world analogue | Role |
| --- | --- | --- |
| `autocannon` | ZU-23-2 | Anti-air gun |
| `ciws` | Zenit ZRPK | Close-in weapon system |
| `samLauncher` | S-300 | Long-range SAM |
| `interceptor` | PRCH | Interceptor |
| `radar` | RLS | Radar station |
| `ewTower` | EW system | Electronic warfare |
| `pzrk` | MANPADS | Man-portable SAM |
| `gepard` | Gepard | AA tank |

## Sprite Generation Pipeline

Sprite generation lives under `sprites/` and uses Python plus Gemini 3 Pro
Image (`gemini-3-pro-image-preview`, "Nano Banana Pro"). The app target does
not include these scripts.

```bash
# CLI
python3 sprites/generate_sprites.py --api-key "$KEY" --name '<glob>'

# Local web UI
python3 sprites/web_ui.py
# http://127.0.0.1:8765/
```

Detailed sprite registry, prompt, post-processing, retry, timeout, and web UI
instructions live in `sprites/AGENTS.md`. Output defaults to
`sprites/generated_sprites/processed/<category>/<name>.png`. Installing a
finished sprite into the app is a manual copy into
`PVOGame/Assets.xcassets/<name>.imageset/`.

## Important Notes

- Open the outer `PVOGame.xcodeproj`.
- Ignore the nested legacy project and nested legacy app directories unless
  explicitly asked to work there.
- `xcodeproj` Ruby gem is installed for programmatic project updates.
- Legacy gun entities (`Guns/`, `GunEntity`, `PlayerControlComponent`) still
  compile but are unused in tower-defense mode.
