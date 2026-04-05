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

    /// Convenience factory for campaign waves with explicit types
    static func campaign(
        drones: Int, speed: CGFloat, interval: TimeInterval, batch: Int,
        altitude: DroneAltitude = .low, health: Int = 1,
        miners: Int = 0, missiles: Int = 0, harms: Int = 0,
        kamikaze: Int = 0, night: Bool = false, ew: Int = 0,
        heavy: Int = 0, cruise: Int = 0, swarm: Int = 0,
        shahed: Int = 0, lancet: Int = 0, orlan: Int = 0,
        formation: FormationPattern = .scattered,
        shahedFormation: ShahedFormation = .scattered
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
            shahedFormation: shahedFormation
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
            shahedFormation: shahedFormation
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

    init(gridLayout: [[Int]], dronePaths: [DronePathDefinition],
         waves: [WaveDefinition], startingResources: Int,
         availableTowers: [TowerType] = TowerType.allCases,
         settlementCount: Int = Constants.Settlement.count,
         guaranteedTowers: [TowerType] = [],
         conveyorSlotCount: Int = 5) {
        self.gridLayout = gridLayout
        self.dronePaths = dronePaths
        self.waves = waves
        self.startingResources = startingResources
        self.availableTowers = availableTowers
        self.settlementCount = settlementCount
        self.guaranteedTowers = guaranteedTowers
        self.conveyorSlotCount = conveyorSlotCount
    }

    // 0 = ground, 1 = highGround (+range), 2 = blocked, 3 = HQ, 5 = concealed (HARM-immune), 6 = valley (drone speed)
    static let level1: LevelDefinition = {
        // 16 rows x 10 cols, portrait orientation
        // Terrain zones replace the old flight path
        let layout: [[Int]] = [
            [0, 0, 0, 0, 6, 6, 0, 0, 0, 0],  // row 0 (top) — valley entry
            [0, 1, 0, 0, 6, 6, 0, 0, 1, 0],  // high ground on flanks
            [0, 0, 0, 0, 6, 0, 0, 0, 0, 0],
            [0, 0, 0, 6, 6, 0, 0, 0, 0, 0],
            [0, 1, 0, 6, 0, 0, 0, 0, 0, 0],  // high ground left
            [0, 0, 0, 6, 0, 0, 0, 0, 0, 0],
            [0, 0, 0, 6, 6, 6, 6, 0, 0, 0],  // valley corridor across
            [0, 0, 0, 0, 0, 0, 6, 0, 1, 0],  // high ground right
            [0, 0, 0, 0, 0, 0, 6, 0, 0, 0],
            [0, 0, 0, 0, 6, 6, 6, 0, 0, 0],
            [0, 0, 0, 0, 6, 0, 0, 0, 0, 0],
            [0, 0, 0, 0, 6, 0, 0, 0, 1, 0],  // high ground right
            [0, 0, 5, 0, 0, 0, 0, 0, 0, 0],  // concealed near HQ
            [0, 0, 0, 0, 0, 0, 0, 5, 0, 0],  // concealed near HQ
            [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
            [0, 0, 0, 0, 3, 3, 0, 0, 0, 0],  // row 15 (bottom) — HQ
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
            .campaign(drones: 0, speed: 55, interval: 1.2, batch: 2, health: 1, shahed: 8),
            .campaign(drones: 0, speed: 58, interval: 1.0, batch: 2, health: 1, shahed: 13, shahedFormation: .chevron),
            .campaign(drones: 0, speed: 61, interval: 0.9, batch: 3, health: 1, shahed: 15, shahedFormation: .triangle),
            .campaign(drones: 0, speed: 64, interval: 0.8, batch: 3, health: 2, shahed: 24, shahedFormation: .tripleTriangle),
        ]
        return LevelDefinition(gridLayout: sharedLayout, dronePaths: sharedPaths,
                               waves: w, startingResources: 300,
                               availableTowers: [.autocannon],
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
                               availableTowers: [.autocannon, .radar],
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
                               availableTowers: [.autocannon, .radar, .interceptor],
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
                               availableTowers: [.autocannon, .radar, .interceptor, .pzrk],
                               settlementCount: 0,
                               guaranteedTowers: [.autocannon, .pzrk, .pzrk])
    }()

    // MARK: - Campaign Level 5: City Defense (6 waves — settlements introduced)
    static let campaignLevel5: LevelDefinition = {
        let w: [WaveDefinition] = [
            .campaign(drones: 20, speed: 58, interval: 1.0, batch: 2, health: 1),
            .campaign(drones: 25, speed: 61, interval: 0.9, batch: 3, health: 1, shahed: 11, shahedFormation: .chevron),
            .campaign(drones: 28, speed: 64, interval: 0.8, batch: 3, health: 2, missiles: 1, shahed: 15, shahedFormation: .triangle),
            .campaign(drones: 30, speed: 67, interval: 0.7, batch: 4, health: 2, kamikaze: 4, night: true),
            .campaign(drones: 33, speed: 70, interval: 0.6, batch: 4, health: 2, missiles: 1, kamikaze: 6, shahed: 21, shahedFormation: .tripleTriangle),
            .campaign(drones: 35, speed: 73, interval: 0.6, batch: 4, health: 3, missiles: 2, kamikaze: 8, shahed: 24, shahedFormation: .tripleTriangle),
        ]
        return LevelDefinition(gridLayout: sharedLayout, dronePaths: sharedPaths,
                               waves: w, startingResources: 350,
                               availableTowers: [.autocannon, .radar, .interceptor, .pzrk],
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
            .campaign(drones: 38, speed: 75, interval: 0.5, batch: 5, health: 3, missiles: 1, kamikaze: 12, ew: 2, shahed: 24, shahedFormation: .tripleTriangle),
        ]
        return LevelDefinition(gridLayout: sharedLayout, dronePaths: sharedPaths,
                               waves: w, startingResources: 400,
                               availableTowers: [.autocannon, .radar, .interceptor, .pzrk, .ewTower],
                               settlementCount: 3,
                               guaranteedTowers: [.autocannon, .radar, .ewTower])
    }()

    // MARK: - Campaign Level 7: Hail (7 waves — + S-300, heavy missiles + HARM)
    static let campaignLevel7: LevelDefinition = {
        let w: [WaveDefinition] = [
            .campaign(drones: 25, speed: 60, interval: 0.9, batch: 3, health: 2),
            .campaign(drones: 28, speed: 63, interval: 0.8, batch: 3, health: 2, missiles: 2, shahed: 13, shahedFormation: .chevron),
            .campaign(drones: 30, speed: 66, interval: 0.7, batch: 4, health: 2, missiles: 2, harms: 1, night: true),
            .campaign(drones: 33, speed: 69, interval: 0.7, batch: 4, health: 3, missiles: 3, kamikaze: 5, ew: 1, shahed: 21, shahedFormation: .tripleTriangle),
            .campaign(drones: 35, speed: 72, interval: 0.6, batch: 5, health: 3, missiles: 3, harms: 1, kamikaze: 7, shahed: 21, shahedFormation: .tripleTriangle),
            .campaign(drones: 38, speed: 75, interval: 0.5, batch: 5, health: 3, missiles: 4, kamikaze: 8, night: true, ew: 1),
            .campaign(drones: 40, speed: 78, interval: 0.5, batch: 5, health: 4, missiles: 4, harms: 2, kamikaze: 10, shahed: 27, shahedFormation: .tripleTriangle),
        ]
        return LevelDefinition(gridLayout: sharedLayout, dronePaths: sharedPaths,
                               waves: w, startingResources: 500,
                               availableTowers: [.autocannon, .radar, .interceptor, .pzrk, .ewTower, .samLauncher],
                               settlementCount: 4,
                               guaranteedTowers: [.radar, .interceptor, .samLauncher])
    }()

    // MARK: - Campaign Level 8: Cruise Missiles (7 waves — + ZRPK, cruise + heavy drones)
    static let campaignLevel8: LevelDefinition = {
        let w: [WaveDefinition] = [
            .campaign(drones: 28, speed: 62, interval: 0.8, batch: 3, health: 2, shahed: 8),
            .campaign(drones: 30, speed: 65, interval: 0.7, batch: 4, health: 2, heavy: 1, cruise: 1),
            .campaign(drones: 33, speed: 68, interval: 0.7, batch: 4, health: 3, missiles: 2, night: true, cruise: 1, shahed: 15, shahedFormation: .triangle),
            .campaign(drones: 35, speed: 71, interval: 0.6, batch: 4, health: 3, miners: 1, kamikaze: 6, heavy: 1, cruise: 2),
            .campaign(drones: 38, speed: 74, interval: 0.5, batch: 5, health: 3, missiles: 2, harms: 1, kamikaze: 8, cruise: 2, shahed: 21, shahedFormation: .tripleTriangle),
            .campaign(drones: 40, speed: 77, interval: 0.5, batch: 5, health: 4, miners: 1, kamikaze: 10, night: true, heavy: 2, cruise: 2),
            .campaign(drones: 42, speed: 80, interval: 0.4, batch: 5, health: 4, missiles: 3, harms: 1, kamikaze: 12, heavy: 2, cruise: 3, shahed: 27, shahedFormation: .tripleTriangle),
        ]
        return LevelDefinition(gridLayout: sharedLayout, dronePaths: sharedPaths,
                               waves: w, startingResources: 500,
                               availableTowers: [.autocannon, .radar, .interceptor, .pzrk, .ewTower, .samLauncher, .ciws],
                               settlementCount: 4,
                               guaranteedTowers: [.radar, .ciws, .interceptor])
    }()

    // MARK: - Campaign Level 9: Lancets (8 waves — Lancets + Orlan recon)
    static let campaignLevel9: LevelDefinition = {
        let w: [WaveDefinition] = [
            .campaign(drones: 25, speed: 60, interval: 0.9, batch: 3, health: 2),
            .campaign(drones: 28, speed: 63, interval: 0.8, batch: 3, health: 2, lancet: 1),
            .campaign(drones: 30, speed: 66, interval: 0.7, batch: 4, health: 2, kamikaze: 5, shahed: 15, lancet: 2, shahedFormation: .triangle),
            .campaign(drones: 33, speed: 69, interval: 0.7, batch: 4, health: 3, missiles: 1, night: true, lancet: 2, orlan: 1),
            .campaign(drones: 35, speed: 72, interval: 0.6, batch: 4, health: 3, kamikaze: 7, ew: 1, shahed: 21, lancet: 3, shahedFormation: .tripleTriangle),
            .campaign(drones: 38, speed: 75, interval: 0.5, batch: 5, health: 3, missiles: 2, harms: 1, kamikaze: 8, lancet: 3, orlan: 1),
            .campaign(drones: 40, speed: 78, interval: 0.5, batch: 5, health: 4, kamikaze: 10, night: true, cruise: 1, shahed: 24, lancet: 4, shahedFormation: .tripleTriangle),
            .campaign(drones: 42, speed: 80, interval: 0.4, batch: 5, health: 4, missiles: 2, kamikaze: 12, ew: 1, heavy: 1, lancet: 4, orlan: 1),
        ]
        return LevelDefinition(gridLayout: sharedLayout, dronePaths: sharedPaths,
                               waves: w, startingResources: 500,
                               availableTowers: [.autocannon, .radar, .interceptor, .pzrk, .ewTower, .samLauncher, .ciws],
                               settlementCount: 4,
                               guaranteedTowers: [.radar, .interceptor, .samLauncher])
    }()

    // MARK: - Campaign Level 10: Iron Swarm (10 waves — all towers, swarms, everything)
    static let campaignLevel10: LevelDefinition = {
        let w: [WaveDefinition] = [
            .campaign(drones: 30, speed: 62, interval: 0.8, batch: 3, health: 2, shahed: 8),
            .campaign(drones: 33, speed: 65, interval: 0.7, batch: 4, health: 2, kamikaze: 6, swarm: 1, shahed: 13, shahedFormation: .chevron),
            .campaign(drones: 35, speed: 68, interval: 0.7, batch: 4, health: 3, missiles: 2, kamikaze: 8, night: true, swarm: 1),
            .campaign(drones: 38, speed: 71, interval: 0.6, batch: 4, health: 3, miners: 1, kamikaze: 10, cruise: 1, swarm: 1, shahed: 21, lancet: 1, shahedFormation: .tripleTriangle),
            .campaign(drones: 40, speed: 74, interval: 0.5, batch: 5, health: 3, missiles: 2, harms: 1, kamikaze: 12, ew: 1, swarm: 2, lancet: 2),
            .campaign(drones: 42, speed: 77, interval: 0.5, batch: 5, health: 4, kamikaze: 14, night: true, heavy: 1, cruise: 2, swarm: 2, shahed: 24, orlan: 1, shahedFormation: .tripleTriangle),
            .campaign(drones: 45, speed: 80, interval: 0.4, batch: 5, health: 4, missiles: 3, harms: 1, kamikaze: 16, ew: 1, cruise: 2, swarm: 2, lancet: 3),
            .campaign(drones: 48, speed: 82, interval: 0.4, batch: 6, health: 4, miners: 1, kamikaze: 18, night: true, heavy: 2, cruise: 3, swarm: 3, shahed: 27, shahedFormation: .tripleTriangle),
            .campaign(drones: 50, speed: 84, interval: 0.35, batch: 6, health: 5, missiles: 3, harms: 2, kamikaze: 20, ew: 2, cruise: 3, swarm: 3, shahed: 30, lancet: 3, orlan: 1, shahedFormation: .tripleTriangle),
            .campaign(drones: 55, speed: 86, interval: 0.35, batch: 6, health: 5, missiles: 4, harms: 2, kamikaze: 24, night: true, heavy: 2, cruise: 3, swarm: 4, shahed: 33, lancet: 4, orlan: 1, shahedFormation: .tripleTriangle),
        ]
        return LevelDefinition(gridLayout: sharedLayout, dronePaths: sharedPaths,
                               waves: w, startingResources: 600,
                               availableTowers: TowerType.allCases,
                               settlementCount: 5,
                               guaranteedTowers: [.radar, .interceptor, .gepard])
    }()

    // MARK: - Test Level: Heavy Drones (debug/sandbox)
    static let testHeavyDrones: LevelDefinition = {
        let w: [WaveDefinition] = [
            // Wave 1: only heavy armored drones, slow, high HP — to test damage visuals
            .campaign(drones: 0, speed: 0, interval: 1.0, batch: 1, health: 1,
                      heavy: 5),
            // Wave 2: more heavy + some regular high-HP
            .campaign(drones: 10, speed: 40, interval: 0.8, batch: 2, health: 8,
                      heavy: 8),
            // Wave 3: heavy + cruise missiles
            .campaign(drones: 5, speed: 45, interval: 0.7, batch: 2, health: 10,
                      heavy: 10, cruise: 3),
        ]
        return LevelDefinition(
            gridLayout: sharedLayout, dronePaths: sharedPaths,
            waves: w, startingResources: 99999,
            availableTowers: TowerType.allCases,
            settlementCount: 0,
            guaranteedTowers: TowerType.allCases,
            conveyorSlotCount: TowerType.allCases.count
        )
    }()
}
