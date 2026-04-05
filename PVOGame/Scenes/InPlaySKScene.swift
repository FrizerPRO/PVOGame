//
//  InPlaySKScene.swift
//  PVOGame
//
//  Tower Defense mode — top-down view, portrait orientation.
//  Drones fly above towers along predefined grid routes.
//

import UIKit
import SpriteKit
import GameplayKit

class InPlaySKScene: SKScene {

    // MARK: - Game Phase

    enum GamePhase {
        case mainMenu
        case build
        case combat
        case waveComplete
        case gameOver
    }

    // MARK: - Properties

    var entities = [GKEntity]()
    var entityIdentifiers = Set<ObjectIdentifier>()
    var lastUpdateTime: TimeInterval = 0
    let collisionDelegate = CollisionDetectedInGame()

    private(set) var gridMap: GridMap!
    var waveManager: WaveManager!
    private(set) var economyManager: EconomyManager!
    private(set) var towerPlacement: TowerPlacementManager!
    var settlementManager: SettlementManager?
    var fireControl = FireControlState()
    let militaryAidManager = MilitaryAidManager()
    let synergyManager = TowerSynergyManager()
    var selectedLevel: LevelDefinition = LevelDefinition.level1
    var selectedCampaignLevelId: String?  // nil = endless mode
    var currentPhase: GamePhase = .mainMenu
    var score = 0
    var lives = Constants.TowerDefense.hqLives
    var dronesDestroyed = 0

    var activeDrones = [AttackDroneEntity]()
    var activeRockets = [RocketEntity]()
    // Per-frame caches (rebuilt once per combat frame in rebuildFrameCaches)
    var aliveDrones = [AttackDroneEntity]()
    var aliveNonMineLayerDrones = [AttackDroneEntity]()
    var aliveMissileCount = 0
    var cachedMissileAlertActive = false
    var activeRadars = [(position: CGPoint, rangeSq: CGFloat)]()
    var radarNightDots = [ObjectIdentifier: SKSpriteNode]()
    var jammedTowerIDs = Set<ObjectIdentifier>()
    var elapsedGameplayTime: TimeInterval = 0
    var interWaveCountdown: TimeInterval = 0
    let firstWaveCountdown: TimeInterval = 15.0
    let normalWaveCountdown: TimeInterval = 3.0
    var gameSpeed: CGFloat = 1.0
    var pendingMissileSpawns = 0
    var pendingHarmSpawns = 0
    var pendingShahedSpawns = 0

    // Wave statistics for summary overlay
    var waveKills = 0
    var waveLeaked = 0
    var waveKillsByType = [String: Int]()
    var waveLeakedByType = [String: Int]()
    var waveTotalSpawned = 0
    var waveSettlementHits = 0
    var waveTowerKills = [ObjectIdentifier: Int]()  // tower ID -> kills
    // Per-game stats for game over recap
    var gameWaveResults = [(wave: Int, kills: Int, leaked: Int, livesLost: Int)]()
    var gameTotalKillsByType = [String: Int]()
    var gameTotalLeakedByType = [String: Int]()
    var waveLivesAtStart = 0

    // Kill combo system
    var comboCount = 0
    var comboTimer: TimeInterval = 0
    let comboWindow: TimeInterval = 1.5  // seconds between kills to maintain combo
    var comboLabel: SKLabelNode?

    // Slow-motion system
    var slowMoTimer: TimeInterval = 0
    var normalSpeed: CGFloat = 1.0

    var activeDroneCount: Int { activeDrones.count }
    var activeDronesForTowers: [AttackDroneEntity] { aliveDrones }
    var isGameOver: Bool { currentPhase == .gameOver }
    var isMissileAlertActive: Bool { cachedMissileAlertActive }

    var waveHasPendingMissiles: Bool {
        guard let wm = waveManager else { return false }
        return wm.hasPendingMissileSalvos || wm.hasPendingHarmSalvos
    }

    // Compatibility stubs for MineLayerDroneEntity AI (no player gun in TD mode)
    var mainGun: GunEntity? { nil }
    var isGunThreatAssessmentActive: Bool { false }

    // HUD
    var hudNode: SKNode?
    var resourceLabel: SKLabelNode?
    var waveLabel: SKLabelNode?
    var livesLabel: SKLabelNode?
    var startWaveButton: SKSpriteNode?
    var startWaveLabel: SKLabelNode?
    var debugWaveInfoLabel: SKLabelNode?
    var debugKillLogLabel: SKLabelNode?
    var debugKillLogLines: [String] = []

    // Tower palette
    let conveyorBelt = ConveyorBeltManager()

    // Grid visuals
    var gridLayer: SKNode?
    var droneLayer: SKNode?
    var shadowLayer: SKNode?

    // Safe area insets (in scene coordinates, bottom-left origin)
    var safeTop: CGFloat = 0
    var safeBottom: CGFloat = 0

    // Settings
    var settingsButton: SettingsButton?
    var settingsMenu: InGameSettingsMenu?

    // Speed toggle
    var speedButton: SKSpriteNode?
    var speedLabel: SKLabelNode?

    // Off-screen miner drone indicator
    var offscreenIndicator: SKNode?

    // Night overlay
    var nightOverlay: SKSpriteNode?
    var isNightWave = false

    // Ability manager
    var abilityManager = AbilityManager()

    // Active swarm clouds (for update loop)
    var activeSwarmClouds = [SwarmCloudEntity]()

    // Node pools for recycling frequently created/destroyed nodes
    var tracerPool = [SKSpriteNode]()
    var smokePuffPool = [SKSpriteNode]()
    var explosionPool = [SKSpriteNode]()
    let nodePoolCapacity = 100

    // Fire control sync guard — ensures sync runs at most once per frame
    var fireControlSyncedThisFrame = false
    // Rocket retarget budget — limits expensive planLaunch() calls per frame
    var rocketRetargetBudget = 0
    let maxRetargetsPerFrame = 3

    // MARK: - Scene Setup

    override func didMove(to view: SKView) {
        super.didMove(to: view)
        size = view.frame.size
        backgroundColor = UIColor(red: 0.12, green: 0.14, blue: 0.12, alpha: 1)
        physicsWorld.contactDelegate = collisionDelegate
        physicsWorld.gravity = .zero
        collisionDelegate.gameScene = self

        // Safe area: view.safeAreaInsets.top = notch/Dynamic Island, bottom = home indicator
        let insets = view.safeAreaInsets
        safeTop = insets.top
        safeBottom = insets.bottom

        setupGrid()
        setupGridVisuals()
        setupHUD()
        setupTowerPalette()
        setupSettingsButton(view)
        setupSettingsMenu(view)

        waveManager = WaveManager(scene: self, level: selectedLevel)
        economyManager = EconomyManager()
        towerPlacement = TowerPlacementManager(scene: self)

        showMainMenu()
    }

    // MARK: - Grid Setup

    private func setupGrid() {
        let cols = Constants.TowerDefense.gridCols
        let rows = Constants.TowerDefense.gridRows
        let paletteHeight: CGFloat = 130 + safeBottom  // Palette + ability bar at bottom
        let hudHeight: CGFloat = 80 + safeTop          // HUD area at top
        let cellWidth = frame.width / CGFloat(cols)
        let cellHeight = (frame.height - paletteHeight - hudHeight) / CGFloat(rows)
        let cellSize = min(cellWidth, cellHeight)
        let totalWidth = cellSize * CGFloat(cols)
        let originX = (frame.width - totalWidth) / 2
        let originY = paletteHeight  // Grid starts above palette

        gridMap = GridMap(
            rows: rows,
            cols: cols,
            cellSize: CGSize(width: cellSize, height: cellSize),
            origin: CGPoint(x: originX, y: originY)
        )
        gridMap.loadLevel(selectedLevel)
    }

    private func setupGridVisuals() {
        let layer = SKNode()
        layer.zPosition = 1
        addChild(layer)
        gridLayer = layer

        let cellSize = gridMap.cellSize

        for row in 0..<gridMap.rows {
            for col in 0..<gridMap.cols {
                guard let cell = gridMap.cell(atRow: row, col: col) else { continue }
                let pos = gridMap.worldPosition(forRow: row, col: col)

                let tile = SKSpriteNode(
                    color: colorForTerrain(cell.terrain, row: row, col: col),
                    size: CGSize(width: cellSize.width - 1, height: cellSize.height - 1)
                )
                tile.position = pos
                tile.zPosition = 1
                layer.addChild(tile)

                // Grid lines
                let border = SKShapeNode(rectOf: CGSize(width: cellSize.width, height: cellSize.height))
                border.strokeColor = UIColor.white.withAlphaComponent(0.08)
                border.fillColor = .clear
                border.lineWidth = 0.5
                border.position = pos
                border.zPosition = 2
                layer.addChild(border)
            }
        }

        // Shadow layer for drone shadows
        let shadows = SKNode()
        shadows.zPosition = 5
        addChild(shadows)
        shadowLayer = shadows

        // Drone layer
        let drones = SKNode()
        drones.zPosition = 61
        addChild(drones)
        droneLayer = drones
    }

    private func colorForTerrain(_ terrain: CellTerrain, row: Int = 0, col: Int = 0) -> UIColor {
        switch terrain {
        case .ground:
            // Subtle checkerboard variation
            let base: CGFloat = (row + col) % 2 == 0 ? 0.18 : 0.19
            return UIColor(red: base, green: base + 0.04, blue: base, alpha: 1)
        case .highGround:
            return UIColor(red: 0.28, green: 0.24, blue: 0.16, alpha: 1)
        case .blocked:
            return UIColor(red: 0.15, green: 0.15, blue: 0.15, alpha: 1)
        case .headquarters:
            return UIColor(red: 0.7, green: 0.2, blue: 0.15, alpha: 1)
        case .settlement:
            return UIColor(red: 0.25, green: 0.35, blue: 0.25, alpha: 1)
        case .concealed:
            return UIColor(red: 0.12, green: 0.20, blue: 0.12, alpha: 1)
        case .valley:
            return UIColor(red: 0.22, green: 0.26, blue: 0.20, alpha: 1)
        }
    }


    // MARK: - Entity Management

    public func addEntity(_ entity: GKEntity) {
        let id = ObjectIdentifier(entity)
        guard !entityIdentifiers.contains(id) else { return }
        entities.append(entity)
        entityIdentifiers.insert(id)
        if let rocket = entity as? RocketEntity {
            activeRockets.append(rocket)
        }
        if let node = entity.component(ofType: SpriteComponent.self)?.spriteNode, node.parent == nil {
            addChild(node)
        }
    }

    public func removeEntity(_ entity: GKEntity) {
        entityIdentifiers.remove(ObjectIdentifier(entity))
        if let rocket = entity as? RocketEntity {
            fireControl.handleRocketRemoved(ObjectIdentifier(rocket))
            if let idx = activeRockets.firstIndex(where: { $0 === rocket }) {
                activeRockets.remove(at: idx)
            }
        }
        if let node = entity.component(ofType: SpriteComponent.self)?.spriteNode {
            node.removeFromParent()
        }
        // Remove shadow
        if let shadow = entity.component(ofType: ShadowComponent.self) {
            shadow.shadowNode.removeFromParent()
        }
        if let index = entities.firstIndex(of: entity) {
            entities.remove(at: index)
        }
        if let drone = entity as? AttackDroneEntity,
           let activeIndex = activeDrones.firstIndex(of: drone) {
            activeDrones.remove(at: activeIndex)
        }
    }


    // MARK: - Touch Handling State (methods in InPlaySKScene+TouchHandling.swift)

    var dragState: DragState?
    let dragThreshold: CGFloat = 10
    let cellSnapDuration: TimeInterval = 0.08
    var selectedTower: TowerEntity?
    var selectedSettlement: SettlementEntity?

    // MARK: - Update Loop

    override func update(_ currentTime: TimeInterval) {
        super.update(currentTime)
        if lastUpdateTime == 0 {
            lastUpdateTime = currentTime
            return
        }
        let dt = currentTime - lastUpdateTime
        lastUpdateTime = currentTime

        guard currentPhase == .combat || currentPhase == .build else { return }

        let scaledDt = dt * Double(gameSpeed)

        // Update conveyor belt
        conveyorBelt.update(deltaTime: dt, isBuildPhase: currentPhase == .build)

        // Inter-wave countdown (always real-time, not affected by speed)
        if currentPhase == .build && interWaveCountdown > 0 {
            interWaveCountdown -= dt
            if interWaveCountdown <= 0 {
                interWaveCountdown = 0
                startCombatPhase()
            } else {
                updateStartWaveButton()
            }
        }

        if currentPhase == .combat {
            elapsedGameplayTime += scaledDt
            // Rebuild per-frame caches (alive drones, radar coverage, EW jamming, missile alert)
            rebuildFrameCaches()
            // Sync fire control ONCE before entity updates so towers/rockets see fresh data
            fireControlSyncedThisFrame = false
            rocketRetargetBudget = 0
            syncFireControlState()
        }

        // Update all entities
        for entity in entities {
            entity.update(deltaTime: scaledDt)
        }

        if currentPhase == .combat {
            waveManager.update(deltaTime: scaledDt)
            applyValleySpeedBoost(deltaTime: scaledDt)
            cleanupDrones()
            updateMineLayerOffscreenIndicator()

            // Update swarm clouds
            for swarm in activeSwarmClouds {
                swarm.update(deltaTime: scaledDt)
            }

            // Update radar dots at night
            if isNightWave {
                updateRadarNightDots()
            }

            // Update combo and slow-mo timers
            updateComboTimer(deltaTime: scaledDt)
            updateSlowMo(deltaTime: dt) // slow-mo uses real time, not scaled

            // Check wave completion
            if let waveManager, !waveManager.isWaveInProgress && activeDrones.isEmpty {
                onWaveComplete()
            }
        }

        // Update ability cooldowns (always, even in build phase)
        abilityManager.update(deltaTime: scaledDt)

        updateHUD()
    }
}

// MARK: - MineLayerDroneDelegate

extension InPlaySKScene: MineLayerDroneDelegate {
    func mineLayer(
        _ mineLayer: MineLayerDroneEntity,
        spawnBombAt position: CGPoint,
        isFromCrashedDrone: Bool
    ) {
        let bomb = MineBombEntity()
        bomb.place(at: position)
        bomb.configureForTDBombing(target: mineLayer.targetTower)
        bomb.configureOrigin(isFromCrashedDrone: isFromCrashedDrone, sourceDrone: mineLayer)
        addEntity(bomb)
    }

    func mineLayerDidExitForRearm(_ mineLayer: MineLayerDroneEntity) {
        removeEntity(mineLayer)
    }
}
