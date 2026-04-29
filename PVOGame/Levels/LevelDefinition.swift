//
//  LevelDefinition.swift
//  PVOGame
//

import Foundation
import CoreGraphics

enum FormationPattern: CaseIterable {
    case scattered    // current random behavior
    case vFormation   // V-shape, 5-7 drones, leader in front
    case column       // single file, tight spacing
    case carpet       // wide horizontal spread
    case escort       // ring of drones protecting center HeavyDrone/EW
}

enum ShahedFormation {
    case scattered       // wave 1: one-by-one random spawning
    case chevron         // V-shape ("галка")
    case triangle        // filled triangle
    case tripleTriangle  // three triangles side by side
}

// MARK: - Composite Formations (M1)

/// A "composite" attack formation that mixes different enemy types and
/// places them at fixed relative positions around a single anchor point.
/// Used by WaveScript to spawn classic combo openers like "EW convoy".
enum CompositeFormationKind {
    /// 1 EW Drone in the centre, 6 Shahed forming a triangular shield around it.
    case ewConvoy
    /// 2 Heavy drones, V-shield of 6 Shahed in front, 2 Kamikaze flanking.
    case bomberRun
    /// 1 Mine-Layer + 1 EW drone escort.
    case mineLayerEscort
    /// Boss-grade combo: 1 Heavy + 1 EW shield + V of 8 Shahed.
    case deathFromAbove
    /// Night raid: 1 EW Drone leader, 12 Shahed in a two-layer escort
    /// (inner ring of 6 + outer triangle of 6). Shaheds stay locked to the
    /// EW until it dies, then peel off toward settlements.
    case ghostBomberEscort
    /// 2 Heavy drones up front as living shields, 1 Mine-Layer following
    /// behind, 4 Shahed flanking. The Heavies soak fire while the Mine-Layer
    /// closes in to drop ordnance on towers.
    case armoredBomberEscort
}

// MARK: - Wave Script (M3)

/// Single typed action a `WaveScript` can perform at a given time.
/// Each action drives a corresponding spawn helper on `InPlaySKScene`.
enum ScriptAction {
    case composite(CompositeFormationKind, side: SpawnEdge)
    /// Micro-staggered Grad/RSZO salvo (M2): one rocket per `micro` second.
    case gradSalvo(count: Int, micro: TimeInterval, scatter: CGFloat, side: SpawnEdge)
    /// Micro-staggered HARM salvo (M2): targets active radar emitters.
    case harmSalvo(count: Int, micro: TimeInterval)
    case cruiseMissile(count: Int, side: SpawnEdge)
    case shahedScattered(count: Int, batch: Int, interval: TimeInterval)
    case shahedFormation(count: Int, formation: ShahedFormation, side: SpawnEdge)
    /// Top-anchored formation positioned at a specific horizontal fraction of the screen.
    /// Used by Pincer-style combos where multiple formations enter the same edge at different X.
    case shahedFormationAt(count: Int, formation: ShahedFormation, xFraction: CGFloat)
    case kamikaze(count: Int, side: SpawnEdge)
    case lancet(count: Int)
    case orlan
    case ewDrone
    case heavyDrone(count: Int)
    case swarmCloud
    case mineLayer
    case missileWarning
    case harmWarning
}

struct ScriptEvent {
    let at: TimeInterval
    let action: ScriptAction

    init(at: TimeInterval, _ action: ScriptAction) {
        self.at = at
        self.action = action
    }
}

/// A timed sequence of `ScriptEvent`s. Played by `WaveManager` on top of
/// the standard wave spawning loop, allowing fixed-timeline "moments".
struct WaveScript {
    let events: [ScriptEvent]

    init(_ events: [ScriptEvent]) {
        // Keep events sorted so the manager can advance with a simple cursor.
        self.events = events.sorted { $0.at < $1.at }
    }

    var totalDuration: TimeInterval { events.last?.at ?? 0 }
}

struct WaveDefinition {
    let droneCount: Int
    let mineLayerCount: Int
    let missileSalvoCount: Int
    let harmSalvoCount: Int
    let speed: CGFloat
    let spawnInterval: TimeInterval
    let spawnBatchSize: Int
    let altitude: DroneAltitude
    let droneHealth: Int
    let kamikazeCount: Int
    let isNight: Bool
    let ewDroneCount: Int
    let heavyDroneCount: Int
    let cruiseMissileCount: Int
    let swarmCount: Int
    let shahedCount: Int
    let lancetCount: Int
    let orlanCount: Int
    let formation: FormationPattern
    let shahedFormation: ShahedFormation
    /// Optional fixed-timeline overlay for this wave (M3). When present,
    /// `WaveManager` plays its events on top of the regular spawning loop.
    let script: WaveScript?

    /// Convenience factory for campaign waves with explicit types
    static func campaign(
        drones: Int, speed: CGFloat, interval: TimeInterval, batch: Int,
        altitude: DroneAltitude = .low, health: Int = 1,
        miners: Int = 0, missiles: Int = 0, harms: Int = 0,
        kamikaze: Int = 0, night: Bool = false, ew: Int = 0,
        heavy: Int = 0, cruise: Int = 0, swarm: Int = 0,
        shahed: Int = 0, lancet: Int = 0, orlan: Int = 0,
        formation: FormationPattern = .scattered,
        shahedFormation: ShahedFormation = .scattered,
        script: WaveScript? = nil
    ) -> WaveDefinition {
        WaveDefinition(
            droneCount: drones, mineLayerCount: miners,
            missileSalvoCount: missiles, harmSalvoCount: harms,
            speed: speed, spawnInterval: interval, spawnBatchSize: batch,
            altitude: altitude, droneHealth: health,
            kamikazeCount: kamikaze, isNight: night, ewDroneCount: ew,
            heavyDroneCount: heavy, cruiseMissileCount: cruise, swarmCount: swarm,
            shahedCount: shahed, lancetCount: lancet, orlanCount: orlan,
            formation: formation,
            shahedFormation: shahedFormation,
            script: script
        )
    }

    static func defaultWave(number: Int) -> WaveDefinition {
        let baseCount = 50 + number * 4
        let speed: CGFloat = Constants.GameBalance.droneBaseSpeed
            + Constants.GameBalance.droneMaxSpeedBonus
            * (1 - exp(-CGFloat(number) * Constants.GameBalance.droneSpeedGrowthRate))
        let altitude: DroneAltitude = .low
        let health = 2 + (number - 1) / 2
        let batch = min(3 + number / 2, 6)
        let firstMissileWave = Constants.GameBalance.enemyMissileFirstWave
        let salvos: Int
        if number < firstMissileWave {
            salvos = 0
        } else {
            salvos = 1 + (number - firstMissileWave) / 3
        }
        let firstHarmWave = Constants.GameBalance.harmMissileFirstWave
        let harmSalvos: Int
        if number < firstHarmWave {
            harmSalvos = 0
        } else {
            harmSalvos = 1 + (number - firstHarmWave) / 2
        }
        // Kamikaze: wave 5+, count grows with wave
        let kamikazeCount: Int
        if number >= Constants.Kamikaze.firstWave {
            kamikazeCount = Constants.Kamikaze.spawnBatchMin + (number - Constants.Kamikaze.firstWave)
        } else {
            kamikazeCount = 0
        }
        // Night: every 4th wave starting at 3
        let isNight = number >= Constants.NightWave.firstNightWave
            && (number - Constants.NightWave.firstNightWave) % Constants.NightWave.nightWaveInterval == 0
        // EW drone: wave 6+
        let ewDroneCount: Int
        if number >= Constants.EW.ewDroneFirstWave {
            ewDroneCount = number >= 10 ? 2 : 1
        } else {
            ewDroneCount = 0
        }
        // Heavy drone: wave 7+
        let heavyDroneCount: Int
        if number >= Constants.AdvancedEnemies.heavyDroneFirstWave {
            heavyDroneCount = number >= 12 ? min(3, 1 + (number - 12) / 2) : 1
        } else {
            heavyDroneCount = 0
        }
        // Cruise missile: wave 8+
        let cruiseMissileCount: Int
        if number >= Constants.AdvancedEnemies.cruiseMissileFirstWave {
            cruiseMissileCount = 1 + (number - Constants.AdvancedEnemies.cruiseMissileFirstWave) / 3
        } else {
            cruiseMissileCount = 0
        }
        // Swarm: wave 10+
        let swarmCount: Int
        if number >= Constants.AdvancedEnemies.swarmFirstWave {
            swarmCount = 1 + (number - Constants.AdvancedEnemies.swarmFirstWave) / 4
        } else {
            swarmCount = 0
        }
        // Shahed-136: wave 6+, large batches that grow
        let shahedCount: Int
        let shahedFormation: ShahedFormation
        if number >= Constants.Shahed.firstWave {
            shahedCount = max(13, Constants.Shahed.batchSize + (number - Constants.Shahed.firstWave) * 2)
            // Cycle formations in infinite mode
            let cycle = (number - Constants.Shahed.firstWave) % 3
            switch cycle {
            case 0: shahedFormation = .chevron
            case 1: shahedFormation = .triangle
            default: shahedFormation = .tripleTriangle
            }
        } else {
            shahedCount = 0
            shahedFormation = .scattered
        }
        // Lancet: wave 8+
        let lancetCount: Int
        if number >= Constants.Lancet.firstWave {
            lancetCount = 1 + (number - Constants.Lancet.firstWave) / 3
        } else {
            lancetCount = 0
        }
        // Orlan-10: wave 9+
        let orlanCount: Int
        if number >= Constants.Orlan.firstWave {
            orlanCount = 1
        } else {
            orlanCount = 0
        }
        // Formation: waves 1-2 scattered, 3-6 scattered/V, 7+ any
        let formation: FormationPattern
        if number <= 2 {
            formation = .scattered
        } else if number <= 6 {
            formation = [.scattered, .vFormation].randomElement()!
        } else {
            let options: [FormationPattern] = heavyDroneCount > 0 || ewDroneCount > 0
                ? [.scattered, .vFormation, .column, .carpet, .escort]
                : [.scattered, .vFormation, .column, .carpet]
            formation = options.randomElement()!
        }

        return WaveDefinition(
            droneCount: baseCount,
            mineLayerCount: number >= 3 ? 1 : 0,
            missileSalvoCount: salvos,
            harmSalvoCount: harmSalvos,
            speed: speed,
            spawnInterval: max(0.35, 1.2 - Double(number) * 0.07),
            spawnBatchSize: batch,
            altitude: altitude,
            droneHealth: health,
            kamikazeCount: kamikazeCount,
            isNight: isNight,
            ewDroneCount: ewDroneCount,
            heavyDroneCount: heavyDroneCount,
            cruiseMissileCount: cruiseMissileCount,
            swarmCount: swarmCount,
            shahedCount: shahedCount,
            lancetCount: lancetCount,
            orlanCount: orlanCount,
            formation: formation,
            shahedFormation: shahedFormation,
            script: ComboLibrary.endlessScript(forWave: number)
        )
    }
}

struct LevelDefinition {
    let gridLayout: [[Int]]
    let dronePaths: [DronePathDefinition]
    let waves: [WaveDefinition]
    let startingResources: Int
    let availableTowers: [TowerType]
    let settlementCount: Int
    let guaranteedTowers: [TowerType]
    let conveyorSlotCount: Int
    let instantConveyor: Bool
    let infiniteLives: Bool
    let prePlacedTowers: [(row: Int, col: Int, type: TowerType)]

    init(gridLayout: [[Int]], dronePaths: [DronePathDefinition],
         waves: [WaveDefinition], startingResources: Int,
         availableTowers: [TowerType] = TowerType.allCases,
         settlementCount: Int = Constants.Settlement.count,
         guaranteedTowers: [TowerType] = [],
         conveyorSlotCount: Int = 5,
         instantConveyor: Bool = false,
         infiniteLives: Bool = false,
         prePlacedTowers: [(row: Int, col: Int, type: TowerType)] = []) {
        self.gridLayout = gridLayout
        self.dronePaths = dronePaths
        self.waves = waves
        self.startingResources = startingResources
        self.availableTowers = availableTowers
        self.settlementCount = settlementCount
        self.guaranteedTowers = guaranteedTowers
        self.conveyorSlotCount = conveyorSlotCount
        self.instantConveyor = instantConveyor
        self.infiniteLives = infiniteLives
        self.prePlacedTowers = prePlacedTowers
    }

    // 0 = ground, 1 = highGround (+range), 2 = blocked, 3 = HQ, 5 = concealed (HARM-immune)
    static let level1: LevelDefinition = {
        // 16 rows x 10 cols, portrait orientation
        // Terrain zones replace the old flight path
        let layout: [[Int]] = [
            [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],  // row 0 (top)
            [0, 1, 0, 0, 0, 0, 0, 0, 1, 0],  // high ground on flanks
            [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
            [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
            [0, 1, 0, 0, 0, 0, 0, 0, 0, 0],  // high ground left
            [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
            [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
            [0, 0, 0, 0, 0, 0, 0, 0, 1, 0],  // high ground right
            [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
            [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
            [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
            [0, 0, 0, 0, 0, 0, 0, 0, 1, 0],  // high ground right
            [0, 0, 5, 0, 0, 0, 0, 0, 0, 0],  // concealed near HQ
            [0, 0, 0, 0, 0, 0, 0, 5, 0, 0],  // concealed near HQ
            [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
            [3, 3, 3, 3, 3, 3, 3, 3, 3, 3],  // row 15 (bottom) — entire row is HQ
        ]

        let pathA = DronePathDefinition(
            gridWaypoints: [
                .init(row: 0, col: 4),
                .init(row: 2, col: 4),
                .init(row: 3, col: 2),
                .init(row: 5, col: 2),
                .init(row: 6, col: 4),
                .init(row: 6, col: 7),
                .init(row: 8, col: 7),
                .init(row: 9, col: 5),
                .init(row: 9, col: 3),
                .init(row: 11, col: 3),
                .init(row: 12, col: 4),
                .init(row: 13, col: 5),
                .init(row: 14, col: 5),
                .init(row: 15, col: 4),
            ],
            altitude: .low,
            spawnEdge: .top
        )

        let pathB = DronePathDefinition(
            gridWaypoints: [
                .init(row: 0, col: 5),
                .init(row: 2, col: 5),
                .init(row: 3, col: 3),
                .init(row: 5, col: 2),
                .init(row: 6, col: 5),
                .init(row: 6, col: 7),
                .init(row: 8, col: 7),
                .init(row: 9, col: 6),
                .init(row: 9, col: 3),
                .init(row: 11, col: 3),
                .init(row: 12, col: 3),
                .init(row: 13, col: 5),
                .init(row: 14, col: 5),
                .init(row: 15, col: 5),
            ],
            altitude: .low,
            spawnEdge: .top
        )

        let pathC = DronePathDefinition(
            gridWaypoints: [
                .init(row: 0, col: 4),
                .init(row: 1, col: 5),
                .init(row: 3, col: 2),
                .init(row: 4, col: 2),
                .init(row: 6, col: 3),
                .init(row: 6, col: 7),
                .init(row: 7, col: 7),
                .init(row: 9, col: 4),
                .init(row: 10, col: 3),
                .init(row: 12, col: 4),
                .init(row: 12, col: 5),
                .init(row: 14, col: 5),
                .init(row: 15, col: 4),
            ],
            altitude: .low,
            spawnEdge: .top
        )

        let waves = (1...20).map { WaveDefinition.defaultWave(number: $0) }

        return LevelDefinition(
            gridLayout: layout,
            dronePaths: [pathA, pathB, pathC],
            waves: waves,
            startingResources: Constants.TowerDefense.startingResources
        )
    }()

    // Shared paths/layout (reused by campaign levels)
    private static var sharedPaths: [DronePathDefinition] { level1.dronePaths }
    private static var sharedLayout: [[Int]] { level1.gridLayout }

    // MARK: - Campaign Level 1: First Contact (4 waves — ZU only, Shaheds)
    static let campaignLevel1: LevelDefinition = {
        let w: [WaveDefinition] = [
            .campaign(drones: 0, speed: 55, interval: 1.2, batch: 2, health: 1, shahed: 32),
            .campaign(drones: 0, speed: 58, interval: 1.0, batch: 2, health: 1, shahed: 78, shahedFormation: .chevron),
            .campaign(drones: 0, speed: 61, interval: 0.9, batch: 3, health: 1, shahed: 90, shahedFormation: .triangle),
            .campaign(drones: 0, speed: 64, interval: 0.8, batch: 3, health: 2, shahed: 384, shahedFormation: .tripleTriangle),
        ]
        return LevelDefinition(gridLayout: sharedLayout, dronePaths: sharedPaths,
                               waves: w, startingResources: 300,
                               availableTowers: [.autocannon, .oilRefinery],
                               settlementCount: 0,
                               guaranteedTowers: [.autocannon, .autocannon, .autocannon])
    }()

    // MARK: - Campaign Level 2: Night Alarm (5 waves — ZU + RLS, night drones)
    static let campaignLevel2: LevelDefinition = {
        let w: [WaveDefinition] = [
            .campaign(drones: 18, speed: 56, interval: 1.1, batch: 2, health: 1),
            .campaign(drones: 22, speed: 59, interval: 1.0, batch: 2, health: 1, night: true),
            .campaign(drones: 25, speed: 62, interval: 0.9, batch: 3, health: 1, night: true),
            .campaign(drones: 28, speed: 65, interval: 0.8, batch: 3, health: 2),
            .campaign(drones: 30, speed: 68, interval: 0.7, batch: 3, health: 2, night: true),
        ]
        return LevelDefinition(gridLayout: sharedLayout, dronePaths: sharedPaths,
                               waves: w, startingResources: 350,
                               availableTowers: [.autocannon, .radar, .oilRefinery],
                               settlementCount: 0,
                               guaranteedTowers: [.autocannon, .autocannon, .radar])
    }()

    // MARK: - Campaign Level 3: Missile Strike (5 waves — + Interceptor, Grad missiles)
    static let campaignLevel3: LevelDefinition = {
        let w: [WaveDefinition] = [
            .campaign(drones: 20, speed: 58, interval: 1.0, batch: 2, health: 1),
            .campaign(drones: 22, speed: 61, interval: 0.9, batch: 3, health: 1, missiles: 1),
            .campaign(drones: 25, speed: 64, interval: 0.8, batch: 3, health: 2, missiles: 1),
            .campaign(drones: 28, speed: 67, interval: 0.7, batch: 3, health: 2, missiles: 2, night: true),
            .campaign(drones: 30, speed: 70, interval: 0.7, batch: 4, health: 2, missiles: 2),
        ]
        return LevelDefinition(gridLayout: sharedLayout, dronePaths: sharedPaths,
                               waves: w, startingResources: 400,
                               availableTowers: [.autocannon, .radar, .interceptor, .oilRefinery],
                               settlementCount: 0,
                               guaranteedTowers: [.autocannon, .radar, .interceptor])
    }()

    // MARK: - Campaign Level 4: People's Defense (5 waves — + PZRK, Shaheds + FPV)
    static let campaignLevel4: LevelDefinition = {
        let w: [WaveDefinition] = [
            .campaign(drones: 22, speed: 58, interval: 1.0, batch: 2, health: 1),
            .campaign(drones: 25, speed: 61, interval: 0.9, batch: 3, health: 1, shahed: 13, shahedFormation: .chevron),
            .campaign(drones: 28, speed: 64, interval: 0.8, batch: 3, health: 2, kamikaze: 4, shahed: 15, shahedFormation: .triangle),
            .campaign(drones: 30, speed: 67, interval: 0.7, batch: 4, health: 2, kamikaze: 6, shahed: 24, shahedFormation: .tripleTriangle),
            .campaign(drones: 35, speed: 70, interval: 0.6, batch: 4, health: 2, kamikaze: 8, night: true, shahed: 27, shahedFormation: .tripleTriangle),
        ]
        return LevelDefinition(gridLayout: sharedLayout, dronePaths: sharedPaths,
                               waves: w, startingResources: 400,
                               availableTowers: [.autocannon, .radar, .interceptor, .pzrk, .oilRefinery],
                               settlementCount: 0,
                               guaranteedTowers: [.autocannon, .pzrk, .pzrk])
    }()

    // MARK: - Campaign Level 5: City Defense (6 waves — settlements introduced)
    static let campaignLevel5: LevelDefinition = {
        let w: [WaveDefinition] = [
            .campaign(drones: 20, speed: 58, interval: 1.0, batch: 2, health: 1),
            .campaign(drones: 25, speed: 61, interval: 0.9, batch: 3, health: 1, shahed: 11, shahedFormation: .chevron),
            .campaign(drones: 28, speed: 64, interval: 0.8, batch: 3, health: 2, missiles: 1, shahed: 15, shahedFormation: .triangle),
            .campaign(drones: 30, speed: 67, interval: 0.7, batch: 4, health: 2, kamikaze: 4, night: true,
                      script: ComboLibrary.pincerMovement()),
            .campaign(drones: 33, speed: 70, interval: 0.6, batch: 4, health: 2, missiles: 1, kamikaze: 6, shahed: 21, shahedFormation: .tripleTriangle),
            .campaign(drones: 35, speed: 73, interval: 0.6, batch: 4, health: 3, missiles: 2, kamikaze: 8, shahed: 24, shahedFormation: .tripleTriangle),
        ]
        return LevelDefinition(gridLayout: sharedLayout, dronePaths: sharedPaths,
                               waves: w, startingResources: 350,
                               availableTowers: [.autocannon, .radar, .interceptor, .pzrk, .oilRefinery],
                               settlementCount: 3,
                               guaranteedTowers: [.autocannon, .radar, .pzrk])
    }()

    // MARK: - Campaign Level 6: FPV Attack (6 waves — + EW Tower, EW drones)
    static let campaignLevel6: LevelDefinition = {
        let w: [WaveDefinition] = [
            .campaign(drones: 25, speed: 60, interval: 0.9, batch: 3, health: 2),
            .campaign(drones: 28, speed: 63, interval: 0.8, batch: 3, health: 2, kamikaze: 5, ew: 1),
            .campaign(drones: 30, speed: 66, interval: 0.7, batch: 4, health: 2, kamikaze: 7, night: true, ew: 1, shahed: 15, shahedFormation: .triangle),
            .campaign(drones: 33, speed: 69, interval: 0.7, batch: 4, health: 3, missiles: 1, kamikaze: 8, ew: 1),
            .campaign(drones: 35, speed: 72, interval: 0.6, batch: 4, health: 3, kamikaze: 10, night: true, ew: 2, shahed: 21, shahedFormation: .tripleTriangle),
            .campaign(drones: 38, speed: 75, interval: 0.5, batch: 5, health: 3, missiles: 1, kamikaze: 12, ew: 2, shahed: 24, shahedFormation: .tripleTriangle,
                      script: ComboLibrary.jammerConvoy()),
        ]
        return LevelDefinition(gridLayout: sharedLayout, dronePaths: sharedPaths,
                               waves: w, startingResources: 400,
                               availableTowers: [.autocannon, .radar, .interceptor, .pzrk, .ewTower, .oilRefinery],
                               settlementCount: 3,
                               guaranteedTowers: [.autocannon, .radar, .ewTower])
    }()

    // MARK: - Campaign Level 7: Hail (7 waves — + S-300, heavy missiles + HARM)
    static let campaignLevel7: LevelDefinition = {
        let w: [WaveDefinition] = [
            .campaign(drones: 25, speed: 60, interval: 0.9, batch: 3, health: 2,
                      script: ComboLibrary.hailStormShort()),
            .campaign(drones: 28, speed: 63, interval: 0.8, batch: 3, health: 2, missiles: 2, shahed: 13, shahedFormation: .chevron),
            .campaign(drones: 30, speed: 66, interval: 0.7, batch: 4, health: 2, missiles: 2, harms: 1, night: true),
            .campaign(drones: 33, speed: 69, interval: 0.7, batch: 4, health: 3, missiles: 3, kamikaze: 5, ew: 1, shahed: 21, shahedFormation: .tripleTriangle),
            .campaign(drones: 35, speed: 72, interval: 0.6, batch: 5, health: 3, missiles: 3, harms: 1, kamikaze: 7, shahed: 21, shahedFormation: .tripleTriangle),
            .campaign(drones: 38, speed: 75, interval: 0.5, batch: 5, health: 3, missiles: 4, kamikaze: 8, night: true, ew: 1,
                      script: ComboLibrary.hailStorm()),
            .campaign(drones: 40, speed: 78, interval: 0.5, batch: 5, health: 4, missiles: 4, harms: 2, kamikaze: 10, shahed: 27, shahedFormation: .tripleTriangle,
                      script: ComboLibrary.seadStrike()),
        ]
        return LevelDefinition(gridLayout: sharedLayout, dronePaths: sharedPaths,
                               waves: w, startingResources: 500,
                               availableTowers: [.autocannon, .radar, .interceptor, .pzrk, .ewTower, .samLauncher, .oilRefinery],
                               settlementCount: 4,
                               guaranteedTowers: [.radar, .interceptor, .samLauncher])
    }()

    // MARK: - Campaign Level 8: Cruise Missiles (7 waves — + ZRPK, cruise + heavy drones)
    static let campaignLevel8: LevelDefinition = {
        let w: [WaveDefinition] = [
            .campaign(drones: 28, speed: 62, interval: 0.8, batch: 3, health: 2, shahed: 8),
            .campaign(drones: 30, speed: 65, interval: 0.7, batch: 4, health: 2, heavy: 1, cruise: 1),
            .campaign(drones: 33, speed: 68, interval: 0.7, batch: 4, health: 3, missiles: 2, night: true, cruise: 1, shahed: 15, shahedFormation: .triangle),
            .campaign(drones: 35, speed: 71, interval: 0.6, batch: 4, health: 3, miners: 1, kamikaze: 6, heavy: 1, cruise: 2,
                      script: ComboLibrary.decoyAndDagger()),
            .campaign(drones: 38, speed: 74, interval: 0.5, batch: 5, health: 3, missiles: 2, harms: 1, kamikaze: 8, cruise: 2, shahed: 21, shahedFormation: .tripleTriangle),
            .campaign(drones: 40, speed: 77, interval: 0.5, batch: 5, health: 4, miners: 1, kamikaze: 10, night: true, heavy: 2, cruise: 2,
                      script: ComboLibrary.mineField()),
            .campaign(drones: 42, speed: 80, interval: 0.4, batch: 5, health: 4, missiles: 3, harms: 1, kamikaze: 12, heavy: 2, cruise: 3, shahed: 27, shahedFormation: .tripleTriangle),
        ]
        return LevelDefinition(gridLayout: sharedLayout, dronePaths: sharedPaths,
                               waves: w, startingResources: 500,
                               availableTowers: [.autocannon, .radar, .interceptor, .pzrk, .ewTower, .samLauncher, .ciws, .oilRefinery],
                               settlementCount: 4,
                               guaranteedTowers: [.radar, .ciws, .interceptor])
    }()

    // MARK: - Campaign Level 9: Lancets (8 waves — Lancets + Orlan recon)
    static let campaignLevel9: LevelDefinition = {
        let w: [WaveDefinition] = [
            .campaign(drones: 25, speed: 60, interval: 0.9, batch: 3, health: 2),
            .campaign(drones: 28, speed: 63, interval: 0.8, batch: 3, health: 2, lancet: 1),
            .campaign(drones: 30, speed: 66, interval: 0.7, batch: 4, health: 2, kamikaze: 5, shahed: 15, lancet: 2, shahedFormation: .triangle),
            .campaign(drones: 33, speed: 69, interval: 0.7, batch: 4, health: 3, missiles: 1, night: true, lancet: 2, orlan: 1,
                      script: ComboLibrary.hunterKiller()),
            .campaign(drones: 35, speed: 72, interval: 0.6, batch: 4, health: 3, kamikaze: 7, ew: 1, shahed: 21, lancet: 3, shahedFormation: .tripleTriangle),
            .campaign(drones: 38, speed: 75, interval: 0.5, batch: 5, health: 3, missiles: 2, harms: 1, kamikaze: 8, lancet: 3, orlan: 1,
                      script: ComboLibrary.reconInForce()),
            .campaign(drones: 40, speed: 78, interval: 0.5, batch: 5, health: 4, kamikaze: 10, night: true, cruise: 1, shahed: 24, lancet: 4, shahedFormation: .tripleTriangle),
            .campaign(drones: 42, speed: 80, interval: 0.4, batch: 5, health: 4, missiles: 2, kamikaze: 12, ew: 1, heavy: 1, lancet: 4, orlan: 1),
        ]
        return LevelDefinition(gridLayout: sharedLayout, dronePaths: sharedPaths,
                               waves: w, startingResources: 500,
                               availableTowers: [.autocannon, .radar, .interceptor, .pzrk, .ewTower, .samLauncher, .ciws, .oilRefinery],
                               settlementCount: 4,
                               guaranteedTowers: [.radar, .interceptor, .samLauncher])
    }()

    // MARK: - Campaign Level 10: Iron Swarm (10 waves — all towers, swarms, everything)
    static let campaignLevel10: LevelDefinition = {
        let w: [WaveDefinition] = [
            .campaign(drones: 30, speed: 62, interval: 0.8, batch: 3, health: 2, shahed: 8),
            .campaign(drones: 33, speed: 65, interval: 0.7, batch: 4, health: 2, kamikaze: 6, swarm: 1, shahed: 13, shahedFormation: .chevron,
                      script: ComboLibrary.swarmBreach()),
            .campaign(drones: 35, speed: 68, interval: 0.7, batch: 4, health: 3, missiles: 2, kamikaze: 8, night: true, swarm: 1),
            .campaign(drones: 38, speed: 71, interval: 0.6, batch: 4, health: 3, miners: 1, kamikaze: 10, cruise: 1, swarm: 1, shahed: 21, lancet: 1, shahedFormation: .tripleTriangle),
            .campaign(drones: 40, speed: 74, interval: 0.5, batch: 5, health: 3, missiles: 2, harms: 1, kamikaze: 12, ew: 1, swarm: 2, lancet: 2),
            .campaign(drones: 42, speed: 77, interval: 0.5, batch: 5, health: 4, kamikaze: 14, night: true, heavy: 1, cruise: 2, swarm: 2, shahed: 24, orlan: 1, shahedFormation: .tripleTriangle),
            .campaign(drones: 45, speed: 80, interval: 0.4, batch: 5, health: 4, missiles: 3, harms: 1, kamikaze: 16, ew: 1, cruise: 2, swarm: 2, lancet: 3),
            .campaign(drones: 48, speed: 82, interval: 0.4, batch: 6, health: 4, miners: 1, kamikaze: 18, night: true, heavy: 2, cruise: 3, swarm: 3, shahed: 27, shahedFormation: .tripleTriangle),
            .campaign(drones: 50, speed: 84, interval: 0.35, batch: 6, health: 5, missiles: 3, harms: 2, kamikaze: 20, ew: 2, cruise: 3, swarm: 3, shahed: 30, lancet: 3, orlan: 1, shahedFormation: .tripleTriangle),
            .campaign(drones: 55, speed: 86, interval: 0.35, batch: 6, health: 5, missiles: 4, harms: 2, kamikaze: 24, night: true, heavy: 2, cruise: 3, swarm: 4, shahed: 33, lancet: 4, orlan: 1, shahedFormation: .tripleTriangle,
                      script: ComboLibrary.ironFist()),
        ]
        return LevelDefinition(gridLayout: sharedLayout, dronePaths: sharedPaths,
                               waves: w, startingResources: 600,
                               availableTowers: TowerType.allCases,
                               settlementCount: 5,
                               guaranteedTowers: [.radar, .interceptor, .gepard])
    }()

    // MARK: - Campaign Level 11: Iranian Night (combos #1 + #14)
    static let campaignLevel11: LevelDefinition = {
        let w: [WaveDefinition] = [
            .campaign(drones: 35, speed: 65, interval: 0.7, batch: 4, health: 3, night: true,
                      script: ComboLibrary.saturationStrike()),
            .campaign(drones: 30, speed: 68, interval: 0.7, batch: 4, health: 3, night: true, ew: 1,
                      script: ComboLibrary.jammerConvoy()),
            .campaign(drones: 32, speed: 70, interval: 0.6, batch: 5, health: 3, kamikaze: 6, night: true,
                      script: ComboLibrary.ghostBombers()),
            .campaign(drones: 38, speed: 72, interval: 0.6, batch: 5, health: 4, kamikaze: 8, night: true,
                      script: ComboLibrary.saturationStrike()),
            .campaign(drones: 40, speed: 75, interval: 0.5, batch: 5, health: 4, kamikaze: 10, night: true,
                      script: ComboLibrary.deathFromAbove()),
        ]
        return LevelDefinition(gridLayout: sharedLayout, dronePaths: sharedPaths,
                               waves: w, startingResources: 600,
                               availableTowers: TowerType.allCases,
                               settlementCount: 5,
                               guaranteedTowers: [.radar, .samLauncher, .interceptor])
    }()

    // MARK: - Test Level: Combo Showcase (debug/sandbox)
    //
    // One wave per combo from `ComboLibrary`, in the design-doc order.
    // Used to visually verify every scripted scenario in isolation.
    // All towers unlocked, unlimited resources.
    static let testExplosions: LevelDefinition = {
        func gradWave(salvos: Int, perSalvo: Int, interval: TimeInterval, night: Bool = false) -> WaveDefinition {
            var events = [ScriptEvent]()
            for i in 0..<salvos {
                let t = Double(i) * interval
                events.append(ScriptEvent(at: t, .gradSalvo(count: perSalvo, micro: 0.08, scatter: 60, side: .top)))
            }
            return .campaign(drones: 0, speed: 0, interval: 1.0, batch: 1, health: 1, night: night,
                             script: WaveScript(events))
        }
        let w: [WaveDefinition] = [
            gradWave(salvos: 15, perSalvo: 25, interval: 2.0),
            gradWave(salvos: 20, perSalvo: 30, interval: 1.5),
            gradWave(salvos: 20, perSalvo: 25, interval: 1.5, night: true),
            gradWave(salvos: 25, perSalvo: 30, interval: 1.2, night: true),
        ]
        // Fill bottom 3 rows (12, 13, 14) with alternating S-300 and interceptors
        var towers: [(row: Int, col: Int, type: TowerType)] = []
        for row in 12...14 {
            for col in 0...9 {
                let type: TowerType = (row + col) % 2 == 0 ? .samLauncher : .interceptor
                towers.append((row: row, col: col, type: type))
            }
        }
        return LevelDefinition(
            gridLayout: sharedLayout, dronePaths: sharedPaths,
            waves: w, startingResources: 99999,
            availableTowers: [.interceptor, .samLauncher],
            settlementCount: 0,
            guaranteedTowers: [.interceptor, .samLauncher, .interceptor, .samLauncher, .interceptor],
            conveyorSlotCount: 5,
            instantConveyor: true,
            infiniteLives: true,
            prePlacedTowers: towers
        )
    }()

    static let testHeavyDrones: LevelDefinition = {
        // Empty shell wave — only the script produces spawns. `drones: 0`
        // skips the regular spawning loop, so the WaveScript is all there is.
        func comboWave(_ script: WaveScript) -> WaveDefinition {
            .campaign(drones: 0, speed: 0, interval: 1.0, batch: 1, health: 1,
                      script: script)
        }
        let w: [WaveDefinition] = [
            comboWave(ComboLibrary.layeredStrike()),       // 15
            comboWave(ComboLibrary.spotterHarm()),         // 16
            comboWave(ComboLibrary.lancetStorm()),         // 17
            comboWave(ComboLibrary.falseAlarm()),          // 18
            comboWave(ComboLibrary.blindingStrike()),      // 19
            comboWave(ComboLibrary.armoredBomberRun()),    // 20
            comboWave(ComboLibrary.silentCruise()),        // 21
            comboWave(ComboLibrary.decapitationStrike()),  // 22
            comboWave(ComboLibrary.twinRecon()),           // 23
            comboWave(ComboLibrary.totalSaturation()),     // 24
        ]
        return LevelDefinition(
            gridLayout: sharedLayout, dronePaths: sharedPaths,
            waves: w, startingResources: 99999,
            availableTowers: TowerType.allCases,
            settlementCount: 0,
            guaranteedTowers: TowerType.allCases,
            conveyorSlotCount: TowerType.allCases.count,
            infiniteLives: true
        )
    }()

    // MARK: - Test: EW Drone

    /// Test level for EW (electronic warfare) drone visuals and jamming.
    /// - 99999 resources, infinite lives, instant conveyor, all towers.
    /// - Wave 1: 3 Heavy drones, no other enemies — clean look at the
    ///           Bayraktar-style cruise → strike → egress profile.
    /// - Wave 2: 2 Heavy drones + regular drones — verify gun towers vs
    ///           medium-altitude stand-off bombers.
    /// - Wave 3: 3 Heavy drones + mixed combat (lancets, kamikaze, shaheds) —
    ///           stress test: multiple stand-off strikes during real engagement.
    static let testEWDrone: LevelDefinition = {
        let w: [WaveDefinition] = [
            // Wave 1: pure Heavy — slow trickle, easy to read each strike.
            .campaign(drones: 0, speed: 45, interval: 2.0, batch: 1, health: 4,
                      heavy: 3),
            // Wave 2: Heavy under combat — Heavy + drones, watch towers split
            // between low-altitude targets and medium-altitude bombers.
            .campaign(drones: 8, speed: 55, interval: 1.0, batch: 2, health: 2,
                      heavy: 2),
            // Wave 3: full mix — multiple Heavies + lancets/kamikaze/shaheds.
            .campaign(drones: 6, speed: 55, interval: 0.9, batch: 2, altitude: .medium, health: 3,
                      kamikaze: 4, heavy: 3, shahed: 12, lancet: 3, shahedFormation: .chevron),
        ]
        return LevelDefinition(
            gridLayout: sharedLayout, dronePaths: sharedPaths,
            waves: w, startingResources: 99999,
            availableTowers: TowerType.allCases,
            settlementCount: 0,
            guaranteedTowers: TowerType.allCases,
            conveyorSlotCount: TowerType.allCases.count,
            instantConveyor: true,
            infiniteLives: true
        )
    }()
}

// MARK: - Combo Library
//
// Pre-built `WaveScript`s for the 14 combo scenarios in the design doc.
// Each static method returns a fresh `WaveScript`. Used by both campaign
// levels (attached to specific waves) and `defaultWave` (endless mode).
enum ComboLibrary {

    // 1 — Saturation Strike (Iran-Israel 14 Apr 2024)
    static func saturationStrike() -> WaveScript {
        WaveScript([
            ScriptEvent(at: 0.0,  .shahedScattered(count: 15, batch: 5, interval: 0.4)),
            ScriptEvent(at: 8.0,  .missileWarning),
            ScriptEvent(at: 9.5,  .gradSalvo(count: 6, micro: 0.2, scatter: 80, side: .top)),
            ScriptEvent(at: 14.0, .cruiseMissile(count: 3, side: .top)),
        ])
    }

    // 2 — Jammer Convoy (Russian Shahed + Krasukha tactic)
    // EW drone leads a hex ring of 6 shaheds. Shaheds stay locked to the leader
    // until it is destroyed, then peel off toward the nearest settlements.
    static func jammerConvoy() -> WaveScript {
        WaveScript([
            ScriptEvent(at: 0.0,  .composite(.ewConvoy, side: .top)),
            ScriptEvent(at: 10.0, .composite(.ewConvoy, side: .top)),
        ])
    }

    // 3 — Hunter-Killer Pair (Orlan + Lancet)
    static func hunterKiller() -> WaveScript {
        WaveScript([
            ScriptEvent(at: 0.0,  .orlan),
            ScriptEvent(at: 4.0,  .lancet(count: 1)),
            ScriptEvent(at: 10.0, .lancet(count: 1)),
            ScriptEvent(at: 12.0, .missileWarning),
            ScriptEvent(at: 13.5, .gradSalvo(count: 3, micro: 0.3, scatter: 70, side: .top)),
        ])
    }

    // 4 — Hail Storm (BM-21 Grad)
    // Two salvos fired from two separate launchers at the top edge. Each launcher
    // fires its 8 rockets in rapid succession from nearly the same point, so the
    // salvo reads as one БМ-21 volley rather than a scattered barrage.
    static func hailStorm() -> WaveScript {
        WaveScript([
            ScriptEvent(at: 0.0,  .missileWarning),
            ScriptEvent(at: 2.0,  .gradSalvo(count: 8, micro: 0.12, scatter: 25, side: .top)),
            ScriptEvent(at: 12.0, .gradSalvo(count: 8, micro: 0.12, scatter: 25, side: .top)),
        ])
    }

    /// Lighter "training" version of #4 used early in level 7.
    static func hailStormShort() -> WaveScript {
        WaveScript([
            ScriptEvent(at: 0.0, .missileWarning),
            ScriptEvent(at: 2.0, .gradSalvo(count: 6, micro: 0.14, scatter: 25, side: .top)),
        ])
    }

    // 5 — Decoy and Dagger (Shahed cover for cruise missiles)
    // Two shahed formations from the top saturate the sky, then cruise missiles
    // slip through from the same edge. All top-spawned so the player reads it
    // as one coherent northern attack.
    static func decoyAndDagger() -> WaveScript {
        WaveScript([
            ScriptEvent(at: 0.0, .shahedFormation(count: 10, formation: .chevron, side: .top)),
            ScriptEvent(at: 4.0, .shahedFormation(count: 12, formation: .triangle, side: .top)),
            ScriptEvent(at: 7.0, .cruiseMissile(count: 3, side: .top)),
        ])
    }

    // 6 — SEAD Strike (Wild Weasel HARM)
    static func seadStrike() -> WaveScript {
        WaveScript([
            ScriptEvent(at: 0.0, .shahedScattered(count: 8, batch: 4, interval: 0.4)),
            ScriptEvent(at: 5.0, .harmWarning),
            ScriptEvent(at: 7.0, .harmSalvo(count: 3, micro: 0.1)),
            ScriptEvent(at: 7.3, .harmSalvo(count: 3, micro: 0.1)),
            ScriptEvent(at: 7.6, .harmSalvo(count: 3, micro: 0.1)),
        ])
    }

    // 7 — Bomber Run (MineLayer bombers → shahed overload)
    // Two mine-laying bombers arrive first to blow a hole in the AA coverage,
    // then a tripleTriangle of shaheds rolls through the softened defense and a
    // scattered tail exploits any remaining gaps.
    static func bomberRun() -> WaveScript {
        WaveScript([
            ScriptEvent(at: 0.0,  .composite(.mineLayerEscort, side: .top)),
            ScriptEvent(at: 4.0,  .composite(.mineLayerEscort, side: .top)),
            ScriptEvent(at: 14.0, .shahedFormation(count: 18, formation: .tripleTriangle, side: .top)),
            ScriptEvent(at: 18.0, .shahedScattered(count: 10, batch: 5, interval: 0.4)),
        ])
    }

    // 8 — Swarm Breach
    static func swarmBreach() -> WaveScript {
        WaveScript([
            ScriptEvent(at: 0.0, .swarmCloud),
            ScriptEvent(at: 2.0, .kamikaze(count: 2, side: .top)),
            ScriptEvent(at: 2.0, .kamikaze(count: 2, side: .top)),
            ScriptEvent(at: 8.0, .swarmCloud),
        ])
    }

    // 9 — Iron Fist (Iran 1 Oct 2024)
    static func ironFist() -> WaveScript {
        WaveScript([
            ScriptEvent(at: 0.0,  .shahedFormation(count: 20, formation: .tripleTriangle, side: .top)),
            ScriptEvent(at: 6.0,  .missileWarning),
            ScriptEvent(at: 7.5,  .gradSalvo(count: 4, micro: 0.25, scatter: 35, side: .top)),
            ScriptEvent(at: 10.0, .gradSalvo(count: 4, micro: 0.25, scatter: 35, side: .top)),
            ScriptEvent(at: 14.0, .cruiseMissile(count: 2, side: .top)),
        ])
    }

    // 10 — Ghost Bombers (night raid)
    // EW drone leads a 12-shahed double escort (ring + triangle). Shaheds stay
    // locked to the leader until it's killed, then scatter. Kamikaze tail from
    // the top reinforces the assault.
    static func ghostBombers() -> WaveScript {
        WaveScript([
            ScriptEvent(at: 0.5, .composite(.ghostBomberEscort, side: .top)),
            ScriptEvent(at: 8.0, .kamikaze(count: 3, side: .top)),
        ])
    }

    // 11 — Pincer Movement
    // Three top-edge formations at different screen X's form the pincer — all
    // enemies still enter from above, but fan out across the width to close in.
    static func pincerMovement() -> WaveScript {
        WaveScript([
            ScriptEvent(at: 0.0,  .shahedFormationAt(count: 7, formation: .chevron, xFraction: 0.2)),
            ScriptEvent(at: 0.0,  .shahedFormationAt(count: 7, formation: .chevron, xFraction: 0.8)),
            ScriptEvent(at: 6.0,  .cruiseMissile(count: 1, side: .top)),
            ScriptEvent(at: 12.0, .shahedFormationAt(count: 6, formation: .chevron, xFraction: 0.5)),
        ])
    }

    // 12 — Reconnaissance in Force
    static func reconInForce() -> WaveScript {
        WaveScript([
            ScriptEvent(at: 0.0, .orlan),
            ScriptEvent(at: 3.0, .lancet(count: 1)),
            ScriptEvent(at: 3.0, .lancet(count: 1)),
            ScriptEvent(at: 5.0, .shahedFormation(count: 6, formation: .chevron, side: .top)),
        ])
    }

    // 13 — Mine Field
    static func mineField() -> WaveScript {
        WaveScript([
            ScriptEvent(at: 0.0, .composite(.mineLayerEscort, side: .top)),
            ScriptEvent(at: 8.0, .composite(.mineLayerEscort, side: .top)),
        ])
    }

    // 14 — Death from Above (BOSS)
    static func deathFromAbove() -> WaveScript {
        WaveScript([
            ScriptEvent(at: 0.0,  .composite(.deathFromAbove, side: .top)),
            ScriptEvent(at: 4.0,  .lancet(count: 1)),
            ScriptEvent(at: 4.0,  .lancet(count: 1)),
            ScriptEvent(at: 8.0,  .missileWarning),
            ScriptEvent(at: 9.5,  .gradSalvo(count: 4, micro: 0.3, scatter: 60, side: .top)),
        ])
    }

    // 15 — Layered Strike (multi-altitude saturation)
    // Hits three altitude bands at once: Shaheds at standard, Heavy at medium,
    // HARM at micro, Cruise at cruise. No single tower covers all bands, so the
    // player has to stretch coverage and inevitably leaves a gap.
    static func layeredStrike() -> WaveScript {
        WaveScript([
            ScriptEvent(at: 0.0,  .shahedFormation(count: 6, formation: .chevron, side: .top)),
            ScriptEvent(at: 4.0,  .heavyDrone(count: 1)),
            ScriptEvent(at: 7.0,  .harmWarning),
            ScriptEvent(at: 9.0,  .harmSalvo(count: 3, micro: 0.15)),
            ScriptEvent(at: 11.0, .cruiseMissile(count: 2, side: .top)),
        ])
    }

    // 16 — Spotter HARM (Orlan + HARM follow-up)
    // Orlan loiters first as the "spotter" — the HARM salvo arrives ~10s later
    // as if cued by it. Shahed cover muddies the picture; one cruise tail
    // exploits any radar damage.
    static func spotterHarm() -> WaveScript {
        WaveScript([
            ScriptEvent(at: 0.0,  .orlan),
            ScriptEvent(at: 5.0,  .shahedScattered(count: 6, batch: 3, interval: 0.5)),
            ScriptEvent(at: 9.0,  .harmWarning),
            ScriptEvent(at: 11.0, .harmSalvo(count: 4, micro: 0.12)),
            ScriptEvent(at: 16.0, .cruiseMissile(count: 1, side: .top)),
        ])
    }

    // 17 — Lancet Storm (PZRK magazine overload)
    // Four simultaneous Lancets exceed any single PZRK battery (1 round / 12s
    // reload) and saturate the rocket fire-control deconfliction. A second
    // wave of three more arrives before the magazines refill.
    static func lancetStorm() -> WaveScript {
        WaveScript([
            ScriptEvent(at: 0.0, .lancet(count: 1)),
            ScriptEvent(at: 0.0, .lancet(count: 1)),
            ScriptEvent(at: 0.0, .lancet(count: 1)),
            ScriptEvent(at: 0.0, .lancet(count: 1)),
            ScriptEvent(at: 6.0, .lancet(count: 1)),
            ScriptEvent(at: 6.0, .lancet(count: 1)),
            ScriptEvent(at: 6.0, .lancet(count: 1)),
        ])
    }

    // 18 — False Alarm (SAM ammo reservation drain)
    // Triggers a missile warning followed by only a token salvo, baiting SAMs
    // to reserve magazine. The real strike (Heavy + Cruise) lands ~9s later
    // before the reload window completes.
    static func falseAlarm() -> WaveScript {
        WaveScript([
            ScriptEvent(at: 0.0,  .missileWarning),
            ScriptEvent(at: 1.5,  .gradSalvo(count: 2, micro: 0.3, scatter: 30, side: .top)),
            ScriptEvent(at: 9.0,  .heavyDrone(count: 1)),
            ScriptEvent(at: 11.0, .cruiseMissile(count: 3, side: .top)),
        ])
    }

    // 19 — Blinding Strike (EW jam → HARM → Cruise)
    // EW convoy degrades tower accuracy/turn-rate first; HARM salvo arrives
    // while jamming is active so radars can't track it well; cruise tail
    // exploits the surviving radar damage.
    static func blindingStrike() -> WaveScript {
        WaveScript([
            ScriptEvent(at: 0.0,  .composite(.ewConvoy, side: .top)),
            ScriptEvent(at: 8.0,  .harmWarning),
            ScriptEvent(at: 10.0, .harmSalvo(count: 3, micro: 0.12)),
            ScriptEvent(at: 14.0, .cruiseMissile(count: 2, side: .top)),
        ])
    }

    // 20 — Armored Bomber Escort (Heavies as living shields for a Mine-Layer)
    // 2 Heavy drones (12 HP each) soak the gun towers' fire while the
    // Mine-Layer closes in unmolested. Triangle of Shaheds follows up after
    // the bombs have been laid.
    static func armoredBomberRun() -> WaveScript {
        WaveScript([
            ScriptEvent(at: 0.0, .composite(.armoredBomberEscort, side: .top)),
            ScriptEvent(at: 8.0, .shahedFormation(count: 8, formation: .triangle, side: .top)),
        ])
    }

    // 21 — Silent Cruise (swarm cover for cruise missiles)
    // A Swarm Cloud overloads CIWS/Gepard with 15 micro targets while three
    // Cruise missiles slip through the chaos. Second swarm reinforces the
    // cover so the cruise volley isn't isolated.
    static func silentCruise() -> WaveScript {
        WaveScript([
            ScriptEvent(at: 0.0, .swarmCloud),
            ScriptEvent(at: 5.0, .cruiseMissile(count: 3, side: .top)),
            ScriptEvent(at: 8.0, .swarmCloud),
        ])
    }

    // 22 — Decapitation Strike (HARM kills radar, then mass attack)
    // Concentrated double HARM salvo aims to take out the radar tower; once
    // the gun towers are blind (esp. at night) the Cruise + Shahed mass
    // formation walks in.
    static func decapitationStrike() -> WaveScript {
        WaveScript([
            ScriptEvent(at: 0.0,  .harmWarning),
            ScriptEvent(at: 1.5,  .harmSalvo(count: 4, micro: 0.1)),
            ScriptEvent(at: 6.0,  .harmSalvo(count: 2, micro: 0.1)),
            ScriptEvent(at: 10.0, .cruiseMissile(count: 4, side: .top)),
            ScriptEvent(at: 14.0, .shahedFormation(count: 12, formation: .tripleTriangle, side: .top)),
        ])
    }

    // 23 — Twin Recon (paired Orlan + dual Lancet streams)
    // Two Orlans 1.5s apart create overlapping speed-boost zones; their
    // Lancets arrive in two waves spaced 3s apart so PZRK never catches up.
    // Shahed chevron exploits the chaos at the back end.
    static func twinRecon() -> WaveScript {
        WaveScript([
            ScriptEvent(at: 0.0,  .orlan),
            ScriptEvent(at: 1.5,  .orlan),
            ScriptEvent(at: 5.0,  .lancet(count: 1)),
            ScriptEvent(at: 5.0,  .lancet(count: 1)),
            ScriptEvent(at: 8.0,  .lancet(count: 1)),
            ScriptEvent(at: 8.0,  .lancet(count: 1)),
            ScriptEvent(at: 12.0, .shahedFormation(count: 8, formation: .chevron, side: .top)),
        ])
    }

    // 24 — Total Saturation (BOSS-tier "everything at once")
    // Final exam: jamming + multi-altitude + magazine drain + tower-killers +
    // swarm cover, all overlapping. Designed for late endless / final boss.
    static func totalSaturation() -> WaveScript {
        WaveScript([
            ScriptEvent(at: 0.0,  .composite(.ewConvoy, side: .top)),
            ScriptEvent(at: 4.0,  .shahedFormation(count: 14, formation: .tripleTriangle, side: .top)),
            ScriptEvent(at: 7.0,  .heavyDrone(count: 2)),
            ScriptEvent(at: 9.0,  .harmWarning),
            ScriptEvent(at: 10.0, .harmSalvo(count: 3, micro: 0.12)),
            ScriptEvent(at: 12.0, .lancet(count: 1)),
            ScriptEvent(at: 12.0, .lancet(count: 1)),
            ScriptEvent(at: 15.0, .cruiseMissile(count: 3, side: .top)),
            ScriptEvent(at: 18.0, .swarmCloud),
        ])
    }

    // MARK: - Endless mode lookup

    /// Returns a deterministic combo script for the given endless wave
    /// number, or nil if this wave gets no script. Specific wave numbers
    /// are picked so each combo first appears at its design-doc cadence
    /// and then repeats roughly every 6 waves.
    static func endlessScript(forWave number: Int) -> WaveScript? {
        switch number {
        case 6, 18:  return hailStorm()
        case 8:      return pincerMovement()
        case 9, 21:  return decoyAndDagger()
        case 10:     return jammerConvoy()
        case 11:     return hunterKiller()
        case 12:     return saturationStrike()
        case 13:     return seadStrike()
        case 14:     return bomberRun()
        case 15:     return swarmBreach()
        case 16:     return reconInForce()
        case 17:     return mineField()
        case 19:     return ironFist()
        case 22:     return layeredStrike()
        case 23:     return spotterHarm()
        case 24:     return falseAlarm()
        case 26:     return silentCruise()
        case 27:     return blindingStrike()
        case 28:     return decapitationStrike()
        case 29:     return lancetStorm()
        case 31:     return twinRecon()
        case 32:     return armoredBomberRun()
        case 20:     return deathFromAbove()
        case let n where n >= 25 && (n - 25) % 10 == 0:
            return totalSaturation()  // Boss every 10 waves: 25, 35, 45...
        case let n where n >= 30 && (n - 30) % 10 == 0:
            return deathFromAbove()   // Original boss every 10 waves: 30, 40, 50...
        default:
            return nil
        }
    }
}
