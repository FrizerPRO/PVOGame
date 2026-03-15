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
    }

    func startNextWave() {
        currentWave += 1
        isWaveInProgress = true
        dronesSpawnedThisWave = 0
        spawnTimer = 0
        mineLayersSpawnedThisWave = 0
        mineLayerTimer = Constants.GameBalance.mineLayerSpawnDelay

        let waveDef: WaveDefinition
        if currentWave <= levelDef.waves.count {
            waveDef = levelDef.waves[currentWave - 1]
        } else {
            waveDef = WaveDefinition.defaultWave(number: currentWave)
        }
        currentWaveDef = waveDef

        showWaveAnnouncement(wave: currentWave)
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

        if dronesSpawnedThisWave >= waveDef.droneCount {
            if scene.activeDronesForTowers.isEmpty && mineLayersSpawnedThisWave >= waveDef.mineLayerCount {
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

    private func showWaveAnnouncement(wave: Int) {
        guard let scene else { return }
        let label = SKLabelNode(fontNamed: Constants.GameBalance.hudFontName)
        label.text = "Wave \(wave)"
        label.fontSize = 36
        label.fontColor = .white
        label.position = CGPoint(x: scene.frame.width / 2, y: scene.frame.height / 2)
        label.zPosition = 96
        label.alpha = 0
        scene.addChild(label)

        let fadeIn = SKAction.fadeIn(withDuration: 0.3)
        let wait = SKAction.wait(forDuration: 1.0)
        let fadeOut = SKAction.fadeOut(withDuration: 0.3)
        let remove = SKAction.removeFromParent()
        label.run(SKAction.sequence([fadeIn, wait, fadeOut, remove]))
    }
}
