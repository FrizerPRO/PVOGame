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
    }

    func nextWaveNumber() -> Int { currentWave + 1 }

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

        let waveDef: WaveDefinition
        if currentWave <= levelDef.waves.count {
            waveDef = levelDef.waves[currentWave - 1]
        } else {
            waveDef = WaveDefinition.defaultWave(number: currentWave)
        }
        currentWaveDef = waveDef
        print("[WAVE] ===== WAVE \(currentWave) START ===== salvos=\(waveDef.missileSalvoCount) harmSalvos=\(waveDef.harmSalvoCount) drones=\(waveDef.droneCount)")
    }

    func update(deltaTime: TimeInterval) {
        guard isWaveInProgress, let waveDef = currentWaveDef, let scene else { return }

        // Mine layer spawning
        if Constants.GameBalance.isMineLayerEnabled && mineLayersSpawnedThisWave < waveDef.mineLayerCount {
            mineLayerTimer -= deltaTime
            if mineLayerTimer <= 0 {
                scene.spawnMineLayer(health: waveDef.droneHealth * 2)
                mineLayersSpawnedThisWave += 1
                mineLayerTimer = Constants.GameBalance.mineLayerSpawnInterval
            }
        }

        // Missile salvo spawning
        if Constants.GameBalance.isEnemyMissileEnabled &&
            currentWave >= Constants.GameBalance.enemyMissileFirstWave &&
            missileSalvosSpawnedThisWave < waveDef.missileSalvoCount {
            missileSalvoTimer -= deltaTime
            if missileSalvoTimer <= 0 && !missileWarningShown {
                // Show warning first
                print("[WAVE] Missile warning shown, wave=\(currentWave), salvoTimer will reset")
                scene.showMissileWarning()
                missileWarningShown = true
                missileSalvoTimer = Constants.GameBalance.enemyMissileWarningTime
            } else if missileSalvoTimer <= 0 && missileWarningShown {
                // Spawn the salvo after warning delay
                print("[WAVE] Spawning missile salvo \(missileSalvosSpawnedThisWave+1)/\(waveDef.missileSalvoCount), wave=\(currentWave)")
                scene.spawnMissileSalvo(waveNumber: currentWave)
                missileSalvosSpawnedThisWave += 1
                missileWarningShown = false
                missileSalvoTimer = Constants.GameBalance.enemyMissileSalvoInterval
            }
        }

        // HARM salvo spawning
        if Constants.GameBalance.isHarmMissileEnabled &&
            currentWave >= Constants.GameBalance.harmMissileFirstWave &&
            harmSalvosSpawnedThisWave < waveDef.harmSalvoCount {
            harmSalvoTimer -= deltaTime
            if harmSalvoTimer <= 0 && !harmWarningShown {
                print("[WAVE] HARM warning shown, wave=\(currentWave)")
                scene.showHarmWarning()
                harmWarningShown = true
                harmSalvoTimer = Constants.GameBalance.harmMissileWarningTime
            } else if harmSalvoTimer <= 0 && harmWarningShown {
                print("[WAVE] Spawning HARM salvo \(harmSalvosSpawnedThisWave+1)/\(waveDef.harmSalvoCount), wave=\(currentWave)")
                scene.spawnHarmSalvo(waveNumber: currentWave)
                harmSalvosSpawnedThisWave += 1
                harmWarningShown = false
                harmSalvoTimer = Constants.GameBalance.harmMissileSalvoInterval
            }
        }

        if dronesSpawnedThisWave >= waveDef.droneCount {
            let allMineLayersDone = mineLayersSpawnedThisWave >= waveDef.mineLayerCount
            let allSalvosDone = missileSalvosSpawnedThisWave >= waveDef.missileSalvoCount
            let allHarmSalvosDone = harmSalvosSpawnedThisWave >= waveDef.harmSalvoCount
            if scene.activeDronesForTowers.isEmpty && allMineLayersDone && allSalvosDone && allHarmSalvosDone && scene.pendingMissileSpawns == 0 && scene.pendingHarmSpawns == 0 {
                isWaveInProgress = false
                print("[WAVE] ===== WAVE \(currentWave) END ===== activeDrones=\(scene.activeDroneCount)")
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
        let pathDefs = levelDef.dronePaths
        guard !pathDefs.isEmpty else { return }

        let pathDef = pathDefs[dronesSpawnedThisWave % pathDefs.count]
        guard let gridMap = scene.gridMap else { return }

        // Build waypoints from grid path definition
        let waypoints = pathDef.gridWaypoints.map { wp in
            gridMap.worldPosition(forRow: wp.row, col: wp.col)
        }

        // Randomize altitude based on wave (exclude .micro — only for bomber drones)
        let altitude: DroneAltitude
        if currentWave <= 2 {
            altitude = .low
        } else if currentWave <= 4 {
            altitude = Bool.random() ? .low : .medium
        } else {
            altitude = DroneAltitude.regularCases.randomElement() ?? .low
        }

        guard !waypoints.isEmpty else { return }

        // Add random offset to each waypoint for path variety
        let spawnWaypoints = waypoints.enumerated().map { index, wp -> CGPoint in
            if index == 0 {
                // Spawn point: offset + start above screen
                return CGPoint(
                    x: wp.x + CGFloat.random(in: -20...20),
                    y: wp.y + 40
                )
            }
            if index == waypoints.count - 1 {
                // Final point (HQ): small offset only
                return CGPoint(
                    x: wp.x + CGFloat.random(in: -5...5),
                    y: wp.y
                )
            }
            // Intermediate waypoints: random jitter
            return CGPoint(
                x: wp.x + CGFloat.random(in: -12...12),
                y: wp.y + CGFloat.random(in: -8...8)
            )
        }

        let flightPath = DroneFlightPath(
            waypoints: spawnWaypoints,
            altitude: altitude,
            spawnEdge: pathDef.spawnEdge
        )

        scene.spawnDrone(flightPath: flightPath, speed: waveDef.speed, altitude: altitude, health: waveDef.droneHealth)
        dronesSpawnedThisWave += 1
    }

}
