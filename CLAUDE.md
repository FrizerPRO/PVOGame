# PVO Tower Defense - AI Assistant Guide

## Project Overview
Ukrainian air defense tower defense game built with iOS SpriteKit and GameplayKit.
The player places anti-air towers on a grid map to defend headquarters (HQ) and
settlements from waves of enemy drones, missiles, and electronic warfare threats.

## Tech Stack
- **Language:** Swift 5.0
- **Frameworks:** SpriteKit, GameplayKit (ECS), UIKit
- **Platform:** iOS 15.5+ (portrait orientation)
- **Architecture:** Entity-Component System (GKEntity/GKComponent)
- **Build:** Xcode project (no SPM/CocoaPods)

## Project Structure
```
PVOGame/
├── Scenes/              # Main game scene and extensions
│   ├── InPlaySKScene.swift              # Core: properties, setup, update loop, entity management
│   ├── InPlaySKScene+HUD.swift          # HUD labels, debug wave/kill info, tower palette
│   ├── InPlaySKScene+Settings.swift     # Settings button, pause menu, restart/exit
│   ├── InPlaySKScene+GameFlow.swift     # Night wave, EW jamming, menus, wave flow, level select
│   ├── InPlaySKScene+DroneSpawning.swift    # All drone/missile spawn methods + formations
│   ├── InPlaySKScene+GameEvents.swift       # Kill/leak handlers, game over, military aid, missiles
│   ├── InPlaySKScene+Effects.swift          # Screen shake, combos, slow-mo, wreckage, cleanup
│   ├── InPlaySKScene+FireControl.swift      # Rocket targeting, frame caches, node pools
│   └── InPlaySKScene+TouchHandling.swift    # Drag-drop towers, touch events, tower/settlement tap
├── Models/              # GKEntity subclasses (drones, projectiles, settlements)
│   ├── AttackDroneEntity.swift          # Base drone class (health, visuals, damage)
│   ├── MineLayerDroneEntity.swift       # Bomber drone (extends AttackDroneEntity)
│   ├── TowerEntity.swift                # Defensive tower entity
│   ├── BulletEntity.swift               # Gun bullet projectile
│   ├── RocketEntity.swift               # Guided missile projectile
│   ├── MineBombEntity.swift             # Mine/bomb dropped by bombers
│   ├── ShahedDroneEntity.swift          # Loitering munition variant
│   ├── HeavyDroneEntity.swift           # Armored drone with bombs
│   ├── CruiseMissileEntity.swift        # Cruise missile with dive behavior
│   ├── LancetDroneEntity.swift          # FPV strike drone
│   ├── KamikazeDroneEntity.swift        # FPV kamikaze drone
│   ├── EWDroneEntity.swift              # Electronic warfare drone
│   ├── OrlanDroneEntity.swift           # Recon drone
│   ├── SwarmCloudEntity.swift           # Swarm formation entity
│   ├── EnemyMissileEntity.swift         # Enemy ballistic missile
│   ├── HarmMissileEntity.swift          # Anti-radiation missile
│   ├── SettlementEntity.swift           # Defended settlement/building
│   ├── FighterEntity.swift              # Fighter jet entity
│   ├── GunEntity.swift                  # Legacy player gun
│   ├── FlyingProjectile.swift           # Protocol for flying entities
│   ├── Shell.swift                      # Protocol for bullet-type projectiles
│   └── FlyingPath.swift                 # Flight path data model
├── Components/          # GKComponent subclasses
│   ├── TowerTargetingComponent.swift    # Tower target acquisition and firing
│   ├── TowerStatsComponent.swift        # Tower stats, durability, magazine system
│   ├── TowerAnimationComponent.swift    # Recoil, muzzle flash, radar spin
│   ├── TowerRotationComponent.swift     # Turret rotation toward target
│   ├── EWTowerComponent.swift           # EW jamming ring visuals
│   ├── AnimationTextureCache.swift      # Shared texture cache (singleton)
│   ├── FlyingProjectileComponent.swift  # GKAgent2D movement for projectiles
│   ├── SpriteComponent.swift            # Basic sprite node wrapper
│   ├── GeometryComponent.swift          # Physics body setup
│   ├── ShadowComponent.swift            # Drone shadow (altitude-based)
│   ├── AltitudeComponent.swift          # Drone altitude level
│   ├── GridPositionComponent.swift      # Grid row/col position
│   ├── RotationComponent.swift          # Legacy gun rotation
│   ├── EWJammingComponent.swift         # Radar jamming effect
│   ├── PlayerControlComponent.swift     # Legacy player input
│   └── ShootComponent.swift             # Legacy projectile impulse
├── Managers/            # Game system managers
│   ├── FireControlState.swift           # Rocket targeting deconfliction algorithm
│   ├── WaveManager.swift                # Wave spawning schedule and progression
│   ├── ConveyorBeltManager.swift        # Tower card conveyor belt UI
│   ├── TowerSynergyManager.swift        # Tower ability synergies
│   ├── AbilityManager.swift             # Special abilities and cooldowns
│   ├── TowerPlacementManager.swift      # Grid placement validation
│   ├── CampaignManager.swift            # Campaign level progression
│   ├── SettlementManager.swift          # Settlement defense system
│   ├── MilitaryAidManager.swift         # Between-wave aid events
│   └── EconomyManager.swift             # Resource/income tracking
├── Grid/                # Grid map and flight paths
│   ├── GridMap.swift                    # 16x10 tile grid, terrain, LOS, occlusion
│   └── DroneFlightPath.swift            # Predefined drone routes, DroneAltitude enum
├── Levels/              # Level/wave definitions
│   └── LevelDefinition.swift            # All campaign levels, WaveDefinition, FormationPattern
├── Enums/               # Shared enumerations
│   ├── TowerType.swift                  # Tower type enum with computed properties
│   └── Direction.swift                  # LEFT/RIGHT direction
├── UI/                  # UIKit overlay views
│   ├── AbilityButton.swift              # In-game ability button
│   ├── InGameSettingsMenu.swift         # Pause/settings menu view
│   └── SettingsButton.swift             # Settings gear button
├── CollisionDetection/  # Physics contact handling
│   └── CollisionDetectedInGame.swift    # SKPhysicsContactDelegate
├── Extensions/          # Swift extensions
│   ├── UIView_Pin.swift                 # Auto Layout constraint helpers
│   ├── UIImage.swift                    # UIImage extensions
│   ├── UIView.swift                     # UIView extensions
│   └── SpriteKitNodeExtension.swift     # SKNode extensions
├── MainMenu/            # Main menu UI
│   ├── WeaponCell.swift                 # Weapon selection cell
│   └── WeaponRow.swift                  # Weapon selection row
├── GameplayViews/       # In-game UIKit overlays
│   ├── ExitMenu.swift                   # Exit confirmation dialog
│   └── MenuButton.swift                 # Menu button component
├── Guns/                # Legacy gun definitions (unused in TD mode)
│   ├── PistolGun.swift
│   ├── MiniGun.swift
│   └── DickGun.swift
├── Constants.swift      # All game balance constants, bitmasks, sizing
├── AppDelegate.swift
└── GameViewController.swift
```

## Architecture

### Entity-Component System
- **Entities** (GKEntity subclasses) are game objects: drones, towers, projectiles
- **Components** (GKComponent subclasses) add behavior: targeting, stats, rotation, sprites
- **Managers** handle game subsystems: waves, economy, placement, fire control

### InPlaySKScene (coordinator)
The single SKScene, split across 9 files via extensions. It:
- Owns all managers and game state
- Runs the update loop (calls manager updates, fire control, entity updates)
- Handles touch input (tower drag-drop, upgrades)
- Manages entity lifecycle (addEntity/removeEntity)

### Key Data Flow
```
InPlaySKScene (coordinator)
  ├→ WaveManager (spawns drones per wave definitions)
  ├→ GridMap (validates tower placement, terrain, LOS)
  ├→ TowerPlacementManager (places towers on grid)
  ├→ FireControlState (deconflicts rocket targeting)
  ├→ ConveyorBeltManager (tower cards for placement)
  ├→ TowerSynergyManager (tower buff interactions)
  ├→ SettlementManager (settlement defense/income)
  ├→ CollisionDetectedInGame (physics contacts)
  └→ Entities (towers, drones, rockets with components)
```

## Game Flow
1. Main menu → select campaign level or endless mode
2. Build phase: drag towers from conveyor belt onto grid
3. Combat phase: WaveManager spawns enemies, towers auto-engage
4. Wave complete → settlement income, military aid choice
5. Repeat until HQ lives reach 0 or all campaign waves cleared

## Key Types
| Type | Role |
|------|------|
| `InPlaySKScene` | Main game scene coordinator |
| `AttackDroneEntity` | Base class for all enemy air targets |
| `TowerEntity` | Placed defensive tower |
| `TowerType` | Enum: autocannon, ciws, samLauncher, interceptor, radar, ewTower, pzrk, gepard |
| `RocketEntity` | Guided missile projectile (extends BulletEntity) |
| `FireControlState` | Rocket targeting deconfliction |
| `WaveManager` | Wave spawning schedule |
| `GridMap` | 16x10 tile grid with terrain and LOS |
| `Constants` | All game balance values in nested structs |

## Conventions
- File naming: `TypeName.swift`, extensions: `TypeName+Feature.swift`
- Constants in `Constants.swift` nested structs (e.g., `Constants.Kamikaze.speed`)
- Collision bitmasks: `Constants.droneBitMask`, `Constants.bulletBitMask`, etc.
- Entity sprites via `SpriteComponent`, physics via `GeometryComponent`
- zPosition layers: ground 0-10, shadows 5, towers 21-40, projectiles 41-60, drones 61+, HUD 95-100
- UI text in Ukrainian/Russian (game themed around Ukrainian air defense)

## Tower Types
| Enum case | Real-world analogue | Role |
|-----------|-------------------|------|
| autocannon | ZU-23-2 | Anti-air gun |
| ciws | Zenit ZRPK | Close-in weapon system |
| samLauncher | S-300 | Long-range SAM |
| interceptor | PRCH | Interceptor |
| radar | RLS | Radar station |
| ewTower | EW system | Electronic warfare |
| pzrk | MANPADS | Man-portable SAM |
| gepard | Gepard | AA tank |

## Build & Run
```bash
# Open in Xcode
open PVOGame.xcodeproj

# CLI build (use iPhone 16 Pro or iPhone 17 Pro simulator)
xcodebuild -project PVOGame.xcodeproj -scheme PVOGame \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

## Sprite Generation Pipeline

All sprite generation lives under `sprites/` (Python, Gemini 3 Pro Image /
"Nano Banana Pro"). Two entry points:

- **CLI:** `python3 sprites/generate_sprites.py --api-key $KEY --name <glob>`
- **Web UI:** `python3 sprites/web_ui.py` → `http://127.0.0.1:8765/`
  (grid of all 107 sprites with status badges, per-sprite prompt inspector,
  bulk-select + generate, live SSE log, info tooltips)

Full pipeline docs — sprite registry structure, background modes, prompt
style conventions, post-processing algorithms (`remove_bg_by_color`,
`luminosity_to_alpha`, `white_to_alpha_glow`), retry/timeout flags, and
debugging recipes — live in **[`sprites/CLAUDE.md`](sprites/CLAUDE.md)**,
which Claude Code auto-loads when working in that directory.

Output: `sprites/generated_sprites/processed/<category>/<name>.png`.
Copying into `PVOGame/Assets.xcassets/<name>.imageset/` is manual.

## Important Notes
- Open the **outer** `PVOGame.xcodeproj`, NOT the nested legacy one at `PVOGame/PVOGame.xcodeproj`
- The nested `PVOGame/PVOGame/PVOGame/` directory is a legacy remnant — ignore it
- `xcodeproj` Ruby gem is installed for programmatic project file updates
- When adding files via xcodeproj gem, use just the filename (not relative path) for groups with `path` set
- Legacy gun entities (Guns/, GunEntity, PlayerControlComponent) still compile but are unused in TD mode
