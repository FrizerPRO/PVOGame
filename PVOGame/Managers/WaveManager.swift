//
//  WaveManager.swift
//  PVOGame
//

import SpriteKit

class WaveManager {
    private(set) var currentWave = 0
    private(set) var isWaveInProgress = false
    private var spawnTimer: TimeInterval = 0
    private var dronesSpawnedThisWave = 0
    private var currentWaveDef: WaveDefinition?
    private weak var scene: InPlaySKScene?
    private let levelDef: LevelDefinition

    // Mine layer spawning
    private var mineLayersSpawnedThisWave = 0
    private var mineLayerTimer: TimeInterval = 0

    // Missile salvo spawning
    private var missileSalvosSpawnedThisWave = 0
    private var missileSalvoTimer: TimeInterval = 0
    private(set) var missileWarningShown = false

    // HARM salvo spawning
    private var harmSalvosSpawnedThisWave = 0
    private var harmSalvoTimer: TimeInterval = 0
    private(set) var harmWarningShown = false

    // Kamikaze spawning
    private var kamikazesSpawnedThisWave = 0
    private var kamikazeTimer: TimeInterval = 0

    // EW drone spawning
    private var ewDronesSpawnedThisWave = 0
    private var ewDroneTimer: TimeInterval = 0

    // Heavy drone spawning
    private var heavyDronesSpawnedThisWave = 0
    private var heavyDroneTimer: TimeInterval = 0

    // Cruise missile spawning
    private var cruiseMissilesSpawnedThisWave = 0
    private var cruiseMissileTimer: TimeInterval = 0

    // Swarm spawning
    private var swarmsSpawnedThisWave = 0
    private var swarmTimer: TimeInterval = 0

    // Shahed-136 spawning
    private var shahedsSpawnedThisWave = 0
    private var shahedTimer: TimeInterval = 0

    // Lancet spawning
    private var lancetsSpawnedThisWave = 0
    private var lancetTimer: TimeInterval = 0

    // Orlan-10 spawning
    private var orlansSpawnedThisWave = 0
    private var orlanTimer: TimeInterval = 0

    // Night wave state
    private(set) var isCurrentWaveNight = false

    init(scene: InPlaySKScene, level: LevelDefinition) {
        self.scene = scene
        self.levelDef = level
    }

    func reset() {
        currentWave = 0
        isWaveInProgress = false
        spawnTimer = 0
        dronesSpawnedThisWave = 0
        currentWaveDef = nil
        mineLayersSpawnedThisWave = 0
        mineLayerTimer = 0
        missileSalvosSpawnedThisWave = 0
        missileSalvoTimer = 0
        missileWarningShown = false
        harmSalvosSpawnedThisWave = 0
        harmSalvoTimer = 0
        harmWarningShown = false
        kamikazesSpawnedThisWave = 0
        kamikazeTimer = 0
        ewDronesSpawnedThisWave = 0
        ewDroneTimer = 0
        heavyDronesSpawnedThisWave = 0
        heavyDroneTimer = 0
        cruiseMissilesSpawnedThisWave = 0
        cruiseMissileTimer = 0
        swarmsSpawnedThisWave = 0
        swarmTimer = 0
        shahedsSpawnedThisWave = 0
        shahedTimer = 0
        lancetsSpawnedThisWave = 0
        lancetTimer = 0
        orlansSpawnedThisWave = 0
        orlanTimer = 0
        isCurrentWaveNight = false
    }

    func nextWaveNumber() -> Int { currentWave + 1 }

    /// True if we've completed all defined waves (campaign victory condition)
    var isCampaignComplete: Bool {
        !isWaveInProgress && currentWave >= levelDef.waves.count && levelDef.waves.count > 0
    }

    var hasPendingMissileSalvos: Bool {
        guard isWaveInProgress, let waveDef = currentWaveDef else { return false }
        return currentWave >= Constants.GameBalance.enemyMissileFirstWave
            && missileSalvosSpawnedThisWave < waveDef.missileSalvoCount
    }

    var hasPendingHarmSalvos: Bool {
        guard isWaveInProgress, let waveDef = currentWaveDef else { return false }
        return currentWave >= Constants.GameBalance.harmMissileFirstWave
            && harmSalvosSpawnedThisWave < waveDef.harmSalvoCount
    }

    func startNextWave() {
        currentWave += 1
        isWaveInProgress = true
        dronesSpawnedThisWave = 0
        spawnTimer = 0
        mineLayersSpawnedThisWave = 0
        mineLayerTimer = Constants.GameBalance.mineLayerSpawnDelay
        missileSalvosSpawnedThisWave = 0
        missileSalvoTimer = Constants.GameBalance.enemyMissileSalvoSpawnDelay
        missileWarningShown = false
        harmSalvosSpawnedThisWave = 0
        harmSalvoTimer = Constants.GameBalance.harmMissileSalvoSpawnDelay
        harmWarningShown = false
        kamikazesSpawnedThisWave = 0
        kamikazeTimer = Constants.Kamikaze.spawnDelay
        ewDronesSpawnedThisWave = 0
        ewDroneTimer = 6.0
        heavyDronesSpawnedThisWave = 0
        heavyDroneTimer = 8.0
        cruiseMissilesSpawnedThisWave = 0
        cruiseMissileTimer = 5.0
        swarmsSpawnedThisWave = 0
        swarmTimer = 10.0
        shahedsSpawnedThisWave = 0
        shahedTimer = Constants.Shahed.batchDelay
        lancetsSpawnedThisWave = 0
        lancetTimer = Constants.Lancet.spawnDelay
        orlansSpawnedThisWave = 0
        orlanTimer = Constants.Orlan.spawnDelay

        let waveDef: WaveDefinition
        if currentWave <= levelDef.waves.count {
            waveDef = levelDef.waves[currentWave - 1]
        } else {
            waveDef = WaveDefinition.defaultWave(number: currentWave)
        }
        currentWaveDef = waveDef
        isCurrentWaveNight = waveDef.isNight
    }

    func update(deltaTime: TimeInterval) {
        guard isWaveInProgress, let waveDef = currentWaveDef, let scene else { return }

        // Mine layer spawning
        if mineLayersSpawnedThisWave < waveDef.mineLayerCount {
            mineLayerTimer -= deltaTime
            if mineLayerTimer <= 0 {
                scene.spawnMineLayer(health: waveDef.droneHealth * 2)
                mineLayersSpawnedThisWave += 1
                mineLayerTimer = Constants.GameBalance.mineLayerSpawnInterval
            }
        }

        // Missile salvo spawning
        if Constants.GameBalance.isEnemyMissileEnabled &&
            missileSalvosSpawnedThisWave < waveDef.missileSalvoCount {
            missileSalvoTimer -= deltaTime
            if missileSalvoTimer <= 0 && !missileWarningShown {
                scene.showMissileWarning()
                missileWarningShown = true
                missileSalvoTimer = Constants.GameBalance.enemyMissileWarningTime
            } else if missileSalvoTimer <= 0 && missileWarningShown {
                scene.spawnMissileSalvo(waveNumber: currentWave)
                missileSalvosSpawnedThisWave += 1
                missileWarningShown = false
                let baseInterval = Constants.GameBalance.enemyMissileSalvoInterval
                missileSalvoTimer = scene.isOrlanActive ? baseInterval * Constants.Orlan.salvoIntervalMultiplier : baseInterval
            }
        }

        // HARM salvo spawning
        if Constants.GameBalance.isHarmMissileEnabled &&
            harmSalvosSpawnedThisWave < waveDef.harmSalvoCount {
            harmSalvoTimer -= deltaTime
            if harmSalvoTimer <= 0 && !harmWarningShown {
                scene.showHarmWarning()
                harmWarningShown = true
                harmSalvoTimer = Constants.GameBalance.harmMissileWarningTime
            } else if harmSalvoTimer <= 0 && harmWarningShown {
                scene.spawnHarmSalvo(waveNumber: currentWave)
                harmSalvosSpawnedThisWave += 1
                harmWarningShown = false
                let baseInterval = Constants.GameBalance.harmMissileSalvoInterval
                harmSalvoTimer = scene.isOrlanActive ? baseInterval * Constants.Orlan.salvoIntervalMultiplier : baseInterval
            }
        }

        // Kamikaze spawning
        if kamikazesSpawnedThisWave < waveDef.kamikazeCount {
            kamikazeTimer -= deltaTime
            if kamikazeTimer <= 0 {
                let batchSize = min(
                    Int.random(in: Constants.Kamikaze.spawnBatchMin...Constants.Kamikaze.spawnBatchMax),
                    waveDef.kamikazeCount - kamikazesSpawnedThisWave
                )
                for i in 0..<batchSize {
                    let delay = TimeInterval(i) * Constants.Kamikaze.spawnInterval
                    scene.run(SKAction.sequence([
                        SKAction.wait(forDuration: delay),
                        SKAction.run { [weak scene] in
                            scene?.spawnKamikaze()
                        }
                    ]))
                }
                kamikazesSpawnedThisWave += batchSize
                kamikazeTimer = 4.0  // delay between batches
            }
        }

        // EW drone spawning
        if ewDronesSpawnedThisWave < waveDef.ewDroneCount {
            ewDroneTimer -= deltaTime
            if ewDroneTimer <= 0 {
                scene.spawnEWDrone()
                ewDronesSpawnedThisWave += 1
                ewDroneTimer = 12.0
            }
        }

        // Heavy drone spawning
        if heavyDronesSpawnedThisWave < waveDef.heavyDroneCount {
            heavyDroneTimer -= deltaTime
            if heavyDroneTimer <= 0 {
                scene.spawnHeavyDrone()
                heavyDronesSpawnedThisWave += 1
                heavyDroneTimer = 10.0
            }
        }

        // Cruise missile spawning
        if cruiseMissilesSpawnedThisWave < waveDef.cruiseMissileCount {
            cruiseMissileTimer -= deltaTime
            if cruiseMissileTimer <= 0 {
                scene.spawnCruiseMissile()
                cruiseMissilesSpawnedThisWave += 1
                cruiseMissileTimer = 8.0
            }
        }

        // Swarm spawning
        if swarmsSpawnedThisWave < waveDef.swarmCount {
            swarmTimer -= deltaTime
            if swarmTimer <= 0 {
                scene.spawnSwarmCloud()
                swarmsSpawnedThisWave += 1
                swarmTimer = 15.0
            }
        }

        // Shahed-136 spawning — large staggered batches
        if shahedsSpawnedThisWave < waveDef.shahedCount {
            shahedTimer -= deltaTime
            if shahedTimer <= 0 {
                let remaining = waveDef.shahedCount - shahedsSpawnedThisWave
                let batch = min(Constants.Shahed.batchSize, remaining)
                for i in 0..<batch {
                    let delay = TimeInterval(i) * Constants.Shahed.spawnInterval
                    scene.run(SKAction.sequence([
                        SKAction.wait(forDuration: delay),
                        SKAction.run { [weak scene] in
                            scene?.spawnShahed()
                        }
                    ]))
                }
                shahedsSpawnedThisWave += batch
                shahedTimer = Constants.Shahed.batchDelay
            }
        }

        // Lancet spawning
        if lancetsSpawnedThisWave < waveDef.lancetCount {
            lancetTimer -= deltaTime
            if lancetTimer <= 0 {
                scene.spawnLancet()
                lancetsSpawnedThisWave += 1
                lancetTimer = Constants.Lancet.spawnDelay
            }
        }

        // Orlan-10 spawning
        if orlansSpawnedThisWave < waveDef.orlanCount {
            orlanTimer -= deltaTime
            if orlanTimer <= 0 {
                scene.spawnOrlan()
                orlansSpawnedThisWave += 1
                orlanTimer = Constants.Orlan.spawnDelay
            }
        }

        if dronesSpawnedThisWave >= waveDef.droneCount {
            let allMineLayersDone = mineLayersSpawnedThisWave >= waveDef.mineLayerCount
            let allSalvosDone = missileSalvosSpawnedThisWave >= waveDef.missileSalvoCount
            let allHarmSalvosDone = harmSalvosSpawnedThisWave >= waveDef.harmSalvoCount
            let allKamikazeDone = kamikazesSpawnedThisWave >= waveDef.kamikazeCount
            let allEWDone = ewDronesSpawnedThisWave >= waveDef.ewDroneCount
            let allHeavyDone = heavyDronesSpawnedThisWave >= waveDef.heavyDroneCount
            let allCruiseDone = cruiseMissilesSpawnedThisWave >= waveDef.cruiseMissileCount
            let allSwarmDone = swarmsSpawnedThisWave >= waveDef.swarmCount
            let allShahedDone = shahedsSpawnedThisWave >= waveDef.shahedCount
            let allLancetDone = lancetsSpawnedThisWave >= waveDef.lancetCount
            let allOrlanDone = orlansSpawnedThisWave >= waveDef.orlanCount
            if scene.activeDronesForTowers.isEmpty && allMineLayersDone && allSalvosDone && allHarmSalvosDone && allKamikazeDone && allEWDone && allHeavyDone && allCruiseDone && allSwarmDone && allShahedDone && allLancetDone && allOrlanDone && scene.pendingMissileSpawns == 0 && scene.pendingHarmSpawns == 0 {
                isWaveInProgress = false
            }
            return
        }

        spawnTimer -= deltaTime
        if spawnTimer <= 0 {
            spawnTimer = waveDef.spawnInterval
            let batch = min(waveDef.spawnBatchSize, waveDef.droneCount - dronesSpawnedThisWave)
            for _ in 0..<batch {
                spawnDrone(waveDef: waveDef)
            }
        }
    }

    private func spawnDrone(waveDef: WaveDefinition) {
        guard let scene else { return }
        guard let gridMap = scene.gridMap else { return }

        // Randomize altitude based on wave (exclude .micro — only for bomber drones)
        let altitude: DroneAltitude
        if currentWave <= 2 {
            altitude = .low
        } else if currentWave <= 4 {
            altitude = Bool.random() ? .low : .medium
        } else {
            altitude = DroneAltitude.regularCases.randomElement() ?? .low
        }

        // Assign target settlement (drone flies THROUGH it on the way to HQ)
        let targetSettlement = scene.settlementManager?.assignTarget(
            towers: scene.towerPlacement?.towers ?? []
        )

        // HQ center — always the final destination
        let hqRow = Constants.TowerDefense.gridRows - 1
        let hqCol = Constants.TowerDefense.gridCols / 2
        let hqPoint = gridMap.worldPosition(forRow: hqRow, col: hqCol)

        // Random spawn from top (simpler, more reliable for path-following)
        let spawnPoint = CGPoint(
            x: CGFloat.random(in: 20...(scene.frame.width - 20)),
            y: scene.frame.height + CGFloat.random(in: 20...50)
        )

        // Build path: spawn → jitter → settlement → jitter → HQ
        let waypoints: [CGPoint]
        if let settlement = targetSettlement {
            let settlementPoint = settlement.worldPosition
            waypoints = buildPathThroughSettlement(
                from: spawnPoint, through: settlementPoint, to: hqPoint
            )
        } else {
            // No settlement — fly straight to HQ with jitter (like old behavior)
            waypoints = buildDirectPath(from: spawnPoint, to: hqPoint)
        }

        let flightPath = DroneFlightPath(
            waypoints: waypoints,
            altitude: altitude,
            spawnEdge: .top
        )

        scene.spawnDrone(flightPath: flightPath, speed: waveDef.speed, altitude: altitude, health: waveDef.droneHealth, targetSettlement: targetSettlement)
        dronesSpawnedThisWave += 1
    }

    /// Path: spawn → 2 jitter → settlement → 2 jitter → HQ
    private func buildPathThroughSettlement(from start: CGPoint, through mid: CGPoint, to end: CGPoint) -> [CGPoint] {
        var points = [start]

        // 2 jitter waypoints between spawn and settlement
        for i in 1...2 {
            let t = CGFloat(i) / 3.0
            points.append(CGPoint(
                x: lerp(start.x, mid.x, t) + CGFloat.random(in: -20...20),
                y: lerp(start.y, mid.y, t) + CGFloat.random(in: -10...10)
            ))
        }

        // Settlement waypoint (the target)
        points.append(mid)

        // 2 jitter waypoints between settlement and HQ
        for i in 1...2 {
            let t = CGFloat(i) / 3.0
            points.append(CGPoint(
                x: lerp(mid.x, end.x, t) + CGFloat.random(in: -15...15),
                y: lerp(mid.y, end.y, t) + CGFloat.random(in: -8...8)
            ))
        }

        // HQ endpoint
        points.append(CGPoint(
            x: end.x + CGFloat.random(in: -5...5),
            y: end.y
        ))

        return points
    }

    /// Direct path to HQ with jitter (no settlement)
    private func buildDirectPath(from start: CGPoint, to end: CGPoint) -> [CGPoint] {
        var points = [start]
        for i in 1...3 {
            let t = CGFloat(i) / 4.0
            points.append(CGPoint(
                x: lerp(start.x, end.x, t) + CGFloat.random(in: -15...15),
                y: lerp(start.y, end.y, t) + CGFloat.random(in: -8...8)
            ))
        }
        points.append(CGPoint(
            x: end.x + CGFloat.random(in: -5...5),
            y: end.y
        ))
        return points
    }

    private func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat {
        a + (b - a) * t
    }

}
