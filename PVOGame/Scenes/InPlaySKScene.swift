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
    private var entityIdentifiers = Set<ObjectIdentifier>()
    var lastUpdateTime: TimeInterval = 0
    let collisionDelegate = CollisionDetectedInGame()

    private(set) var gridMap: GridMap!
    private var waveManager: WaveManager!
    private(set) var economyManager: EconomyManager!
    private(set) var towerPlacement: TowerPlacementManager!
    private var fireControl = FireControlState()

    private(set) var currentPhase: GamePhase = .mainMenu
    private(set) var score = 0
    private(set) var lives = Constants.TowerDefense.hqLives
    private(set) var dronesDestroyed = 0

    private var activeDrones = [AttackDroneEntity]()
    private var activeRockets = [RocketEntity]()
    private var elapsedGameplayTime: TimeInterval = 0
    private var interWaveCountdown: TimeInterval = 0
    private let firstWaveCountdown: TimeInterval = 15.0
    private let normalWaveCountdown: TimeInterval = 3.0
    private var gameSpeed: CGFloat = 1.0

    var activeDroneCount: Int { activeDrones.count }
    var activeDronesForTowers: [AttackDroneEntity] { activeDrones }
    var isGameOver: Bool { currentPhase == .gameOver }

    // Compatibility stubs for MineLayerDroneEntity AI (no player gun in TD mode)
    var mainGun: GunEntity? { nil }
    var isGunThreatAssessmentActive: Bool { false }

    // HUD
    private var hudNode: SKNode?
    private var resourceLabel: SKLabelNode?
    private var waveLabel: SKLabelNode?
    private var livesLabel: SKLabelNode?
    private var startWaveButton: SKSpriteNode?
    private var startWaveLabel: SKLabelNode?

    // Tower palette
    private var paletteNode: SKNode?
    private var paletteButtons = [TowerType: SKNode]()
    private var selectedTowerHighlight: SKShapeNode?

    // Grid visuals
    private var gridLayer: SKNode?
    private var droneLayer: SKNode?
    private var shadowLayer: SKNode?

    // Safe area insets (in scene coordinates, bottom-left origin)
    private var safeTop: CGFloat = 0
    private var safeBottom: CGFloat = 0

    // Settings
    private var settingsButton: SettingsButton?
    private var settingsMenu: InGameSettingsMenu?

    // Speed toggle
    private var speedButton: SKSpriteNode?
    private var speedLabel: SKLabelNode?

    // Off-screen miner drone indicator
    private var offscreenIndicator: SKNode?

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

        waveManager = WaveManager(scene: self, level: LevelDefinition.level1)
        economyManager = EconomyManager()
        towerPlacement = TowerPlacementManager(scene: self)

        showMainMenu()
    }

    // MARK: - Grid Setup

    private func setupGrid() {
        let cols = Constants.TowerDefense.gridCols
        let rows = Constants.TowerDefense.gridRows
        let paletteHeight: CGFloat = 70 + safeBottom  // Palette area at bottom
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
        gridMap.loadLevel(LevelDefinition.level1)
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
                    color: colorForTerrain(cell.terrain),
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

    private func colorForTerrain(_ terrain: CellTerrain) -> UIColor {
        switch terrain {
        case .ground:
            return UIColor(red: 0.18, green: 0.22, blue: 0.18, alpha: 1)
        case .flightPath:
            return UIColor(red: 0.30, green: 0.34, blue: 0.26, alpha: 1)
        case .blocked:
            return UIColor(red: 0.15, green: 0.15, blue: 0.15, alpha: 1)
        case .headquarters:
            return UIColor(red: 0.7, green: 0.2, blue: 0.15, alpha: 1)
        }
    }

    // MARK: - HUD

    private func setupHUD() {
        let hud = SKNode()
        hud.zPosition = 95
        addChild(hud)
        hudNode = hud

        let fontSize = Constants.GameBalance.hudFontSize
        let fontName = Constants.GameBalance.hudFontName
        let yPos = frame.height - safeTop - 36

        let rLabel = SKLabelNode(fontNamed: fontName)
        rLabel.fontSize = fontSize
        rLabel.fontColor = .systemGreen
        rLabel.horizontalAlignmentMode = .left
        rLabel.position = CGPoint(x: 28, y: yPos)
        hud.addChild(rLabel)
        resourceLabel = rLabel

        let wLabel = SKLabelNode(fontNamed: fontName)
        wLabel.fontSize = fontSize
        wLabel.fontColor = .white
        wLabel.horizontalAlignmentMode = .center
        wLabel.position = CGPoint(x: frame.width / 2, y: yPos)
        hud.addChild(wLabel)
        waveLabel = wLabel

        let lLabel = SKLabelNode(fontNamed: fontName)
        lLabel.fontSize = fontSize
        lLabel.fontColor = .systemRed
        lLabel.horizontalAlignmentMode = .right
        lLabel.position = CGPoint(x: frame.width - 28, y: yPos)
        hud.addChild(lLabel)
        livesLabel = lLabel

        // Start Wave button
        let btnWidth: CGFloat = 240
        let btnHeight: CGFloat = 40
        let btn = SKSpriteNode(color: UIColor.systemGreen.withAlphaComponent(0.8), size: CGSize(width: btnWidth, height: btnHeight))
        btn.position = CGPoint(x: frame.width / 2, y: yPos - 40)
        btn.zPosition = 96
        btn.name = "startWaveButton"
        btn.isHidden = true
        addChild(btn)
        startWaveButton = btn

        let btnLabel = SKLabelNode(fontNamed: fontName)
        btnLabel.text = "START WAVE"
        btnLabel.fontSize = 16
        btnLabel.fontColor = .white
        btnLabel.verticalAlignmentMode = .center
        btnLabel.name = "startWaveButton"
        btn.addChild(btnLabel)
        startWaveLabel = btnLabel

        // Speed toggle button
        let speedBtnSize: CGFloat = 32
        let speedBtn = SKSpriteNode(color: UIColor.darkGray.withAlphaComponent(0.8), size: CGSize(width: speedBtnSize, height: speedBtnSize))
        speedBtn.position = CGPoint(x: frame.width - 40, y: yPos - 40)
        speedBtn.zPosition = 96
        speedBtn.name = "speedButton"
        speedBtn.isHidden = true
        addChild(speedBtn)
        speedButton = speedBtn

        let spdLabel = SKLabelNode(fontNamed: fontName)
        spdLabel.text = "\u{25B6}"
        spdLabel.fontSize = 14
        spdLabel.fontColor = .white
        spdLabel.verticalAlignmentMode = .center
        spdLabel.name = "speedButton"
        speedBtn.addChild(spdLabel)
        speedLabel = spdLabel
    }

    private func updateHUD() {
        resourceLabel?.text = "DP: \(economyManager?.resources ?? 0)"
        waveLabel?.text = "Wave \(waveManager?.currentWave ?? 0)"
        livesLabel?.text = "HP: \(lives)"
    }

    // MARK: - Tower Palette

    private func setupTowerPalette() {
        let palette = SKNode()
        palette.zPosition = 95
        addChild(palette)
        paletteNode = palette

        let types: [TowerType] = [.autocannon, .ciws, .samLauncher, .interceptor, .radar]
        let btnSize: CGFloat = 50
        let spacing: CGFloat = 12
        let totalWidth = CGFloat(types.count) * btnSize + CGFloat(types.count - 1) * spacing
        let startX = (frame.width - totalWidth) / 2 + btnSize / 2
        let yPos: CGFloat = safeBottom + 42

        for (i, type) in types.enumerated() {
            let x = startX + CGFloat(i) * (btnSize + spacing)

            let bg = SKSpriteNode(color: UIColor.darkGray.withAlphaComponent(0.8), size: CGSize(width: btnSize, height: btnSize))
            bg.position = CGPoint(x: x, y: yPos)
            bg.name = "palette_\(type.rawValue)"

            let icon = SKSpriteNode(color: type.color, size: CGSize(width: btnSize - 16, height: btnSize - 16))
            icon.name = "palette_\(type.rawValue)"
            bg.addChild(icon)

            let costLabel = SKLabelNode(fontNamed: Constants.GameBalance.hudFontName)
            costLabel.text = "\(type.cost)"
            costLabel.fontSize = 10
            costLabel.fontColor = .white
            costLabel.position = CGPoint(x: 0, y: -btnSize / 2 - 8)
            costLabel.name = "palette_\(type.rawValue)"
            bg.addChild(costLabel)

            let nameLabel = SKLabelNode(fontNamed: Constants.GameBalance.hudFontName)
            nameLabel.text = type.displayName
            nameLabel.fontSize = 8
            nameLabel.fontColor = .lightGray
            nameLabel.position = CGPoint(x: 0, y: btnSize / 2 + 4)
            nameLabel.name = "palette_\(type.rawValue)"
            bg.addChild(nameLabel)

            palette.addChild(bg)
            paletteButtons[type] = bg
        }
    }

    private func updatePaletteHighlight() {
        selectedTowerHighlight?.removeFromParent()
        selectedTowerHighlight = nil

        guard let selectedType = towerPlacement?.selectedTowerType,
              let btn = paletteButtons[selectedType] else { return }

        let highlight = SKShapeNode(rectOf: CGSize(width: 54, height: 54), cornerRadius: 4)
        highlight.strokeColor = .white
        highlight.lineWidth = 2
        highlight.fillColor = .clear
        highlight.position = btn.position
        highlight.zPosition = 96
        paletteNode?.addChild(highlight)
        selectedTowerHighlight = highlight
    }

    // MARK: - Settings

    private func setupSettingsButton(_ view: SKView) {
        let buttonSize = Constants.GameBalance.settingsButtonSize
        let button = SettingsButton(frame: CGRect(origin: .zero, size: buttonSize)) { [weak self] in
            self?.presentPauseMenu()
        }
        view.addSubview(button)
        button.pinLeft(to: view, Int(Constants.GameBalance.settingsButtonInsets.x))
        button.pinTop(to: view, Int(Constants.GameBalance.settingsButtonInsets.y))
        button.setWidth(buttonSize.width).isActive = true
        button.setHeight(buttonSize.height).isActive = true
        button.isHidden = true
        settingsButton = button
    }

    private func setupSettingsMenu(_ view: SKView) {
        let width = view.frame.width * Constants.GameBalance.settingsMenuWidthRatio
        let menu = InGameSettingsMenu(
            frame: CGRect(x: 0, y: 0, width: width, height: Constants.GameBalance.settingsMenuHeight),
            onResume: { [weak self] in self?.resumeGame() },
            onExit: { [weak self] in self?.exitToMainMenu() }
        )
        view.addSubview(menu)
        menu.pinCenterX(to: view.centerXAnchor)
        menu.pinCenterY(to: view.centerYAnchor)
        menu.setWidth(width).isActive = true
        menu.setHeight(Constants.GameBalance.settingsMenuHeight).isActive = true
        menu.isHidden = true
        settingsMenu = menu
    }

    private func presentPauseMenu() {
        guard currentPhase == .build || currentPhase == .combat else { return }
        settingsMenu?.isHidden = false
        isPaused = true
    }

    private func resumeGame() {
        settingsMenu?.isHidden = true
        isPaused = false
    }

    private func exitToMainMenu() {
        resumeGame()
        stopGame()
        showMainMenu()
    }

    // MARK: - Game Flow

    private func showMainMenu() {
        currentPhase = .mainMenu
        hudNode?.isHidden = true
        paletteNode?.isHidden = true
        startWaveButton?.isHidden = true
        speedButton?.isHidden = true
        settingsButton?.isHidden = true

        // Show a simple start overlay
        let overlay = SKNode()
        overlay.name = "mainMenuOverlay"
        overlay.zPosition = 100
        addChild(overlay)

        let bg = SKSpriteNode(color: UIColor.black.withAlphaComponent(0.7), size: frame.size)
        bg.position = CGPoint(x: frame.midX, y: frame.midY)
        overlay.addChild(bg)

        let title = SKLabelNode(fontNamed: Constants.GameBalance.hudFontName)
        title.text = "PVO TOWER DEFENSE"
        title.fontSize = 28
        title.fontColor = .white
        title.position = CGPoint(x: frame.midX, y: frame.midY + 60)
        overlay.addChild(title)

        let startBtn = SKSpriteNode(color: .systemGreen, size: CGSize(width: 200, height: 50))
        startBtn.position = CGPoint(x: frame.midX, y: frame.midY - 20)
        startBtn.name = "startGameButton"
        overlay.addChild(startBtn)

        let startLabel = SKLabelNode(fontNamed: Constants.GameBalance.hudFontName)
        startLabel.text = "START GAME"
        startLabel.fontSize = 20
        startLabel.fontColor = .white
        startLabel.verticalAlignmentMode = .center
        startLabel.name = "startGameButton"
        startBtn.addChild(startLabel)
    }

    func startGame() {
        enumerateChildNodes(withName: "//mainMenuOverlay") { node, _ in
            node.removeFromParent()
        }

        currentPhase = .build
        score = 0
        lives = Constants.TowerDefense.hqLives
        dronesDestroyed = 0
        elapsedGameplayTime = 0
        fireControl.reset()

        economyManager.reset(to: Constants.TowerDefense.startingResources)
        waveManager.reset()
        towerPlacement.removeAllTowers()

        // Clear any existing drones
        for drone in activeDrones {
            removeEntity(drone)
        }
        activeDrones.removeAll()
        activeRockets.removeAll()

        hudNode?.isHidden = false
        paletteNode?.isHidden = false
        startWaveButton?.isHidden = false
        speedButton?.isHidden = false
        settingsButton?.isHidden = false

        gameSpeed = 1.0
        speedLabel?.text = "\u{25B6}"
        self.speed = gameSpeed
        physicsWorld.speed = gameSpeed

        interWaveCountdown = firstWaveCountdown
        updateStartWaveButton()
        showWaveAnnouncement(wave: waveManager.nextWaveNumber())
        updateHUD()
    }

    func stopGame() {
        currentPhase = .mainMenu
        cleanupOffscreenIndicator()

        for drone in activeDrones {
            removeEntity(drone)
        }
        activeDrones.removeAll()

        let transientEntities = entities.filter { $0 is BulletEntity || $0 is MineBombEntity }
        for entity in transientEntities {
            removeEntity(entity)
        }
        activeRockets.removeAll()
        entityIdentifiers.removeAll()
        for entity in entities {
            entityIdentifiers.insert(ObjectIdentifier(entity))
        }

        towerPlacement.removeAllTowers()
        fireControl.reset()

        hudNode?.isHidden = true
        paletteNode?.isHidden = true
        startWaveButton?.isHidden = true
        speedButton?.isHidden = true
        settingsButton?.isHidden = true

        gameSpeed = 1.0
        speedLabel?.text = "\u{25B6}"
        self.speed = 1.0
        physicsWorld.speed = 1.0
    }

    private func startCombatPhase() {
        currentPhase = .combat
        startWaveButton?.isHidden = true

        // Repair all towers at wave start
        towerPlacement.towers.forEach { $0.fullRepair() }

        waveManager.startNextWave()
        updateHUD()
    }

    private func onWaveComplete() {
        currentPhase = .build
        cleanupOffscreenIndicator()
        economyManager.earn(Constants.TowerDefense.waveCompletionBonus)
        interWaveCountdown = normalWaveCountdown
        startWaveButton?.isHidden = false
        updateStartWaveButton()
        showWaveAnnouncement(wave: waveManager.nextWaveNumber())
        updateHUD()
    }

    private func updateStartWaveButton() {
        let bonus = Int(interWaveCountdown * 2)
        startWaveLabel?.text = bonus > 0 ? "EARLY START (+\(bonus) DP)" : "START WAVE"
    }

    private func showWaveAnnouncement(wave: Int) {
        let label = SKLabelNode(fontNamed: Constants.GameBalance.hudFontName)
        label.text = "Wave \(wave)"
        label.fontSize = 36
        label.fontColor = .white
        label.position = CGPoint(x: frame.width / 2, y: frame.height / 2)
        label.zPosition = 96
        label.alpha = 0
        addChild(label)

        let fadeIn = SKAction.fadeIn(withDuration: 0.3)
        let wait = SKAction.wait(forDuration: 1.0)
        let fadeOut = SKAction.fadeOut(withDuration: 0.3)
        let remove = SKAction.removeFromParent()
        label.run(SKAction.sequence([fadeIn, wait, fadeOut, remove]))
    }

    private func toggleGameSpeed() {
        switch gameSpeed {
        case 1.0:  gameSpeed = 2.0
        case 2.0:  gameSpeed = 4.0
        default:   gameSpeed = 1.0
        }
        switch gameSpeed {
        case 2.0:  speedLabel?.text = "\u{25B6}\u{25B6}"
        case 4.0:  speedLabel?.text = "\u{25B6}\u{25B6}\u{25B6}"
        default:   speedLabel?.text = "\u{25B6}"
        }
        self.speed = gameSpeed
        physicsWorld.speed = gameSpeed
    }

    // MARK: - Drone Spawning

    func spawnDrone(flightPath: DroneFlightPath, speed: CGFloat, altitude: DroneAltitude, health: Int = 1) {
        let flyingPath = flightPath.toFlyingPath()
        let drone = AttackDroneEntity(
            damage: 1,
            speed: speed,
            imageName: "Drone",
            flyingPath: flyingPath
        )
        drone.configureHealth(health)

        // Add altitude component
        drone.addComponent(AltitudeComponent(altitude: altitude))

        // Add shadow component
        let shadow = ShadowComponent()
        drone.addComponent(shadow)
        shadowLayer?.addChild(shadow.shadowNode)

        // Scale drone based on altitude
        if let spriteNode = drone.component(ofType: SpriteComponent.self)?.spriteNode {
            let scale = altitude.droneVisualScale
            spriteNode.size = CGSize(width: 30 * scale, height: 30 * scale)
            spriteNode.zPosition = 61 + CGFloat(altitude.rawValue) * 5
        }

        activeDrones.append(drone)
        addEntity(drone)
    }

    // MARK: - Game Events

    func onDroneDestroyed(drone: AttackDroneEntity? = nil) {
        guard currentPhase == .combat else { return }
        if let drone, !activeDrones.contains(drone) { return }

        let scoreDelta: Int
        let resourceDelta: Int
        if drone is MineLayerDroneEntity {
            scoreDelta = Constants.GameBalance.scorePerMineLayerDrone
            resourceDelta = Constants.TowerDefense.resourcesPerMineLayerKill
        } else {
            scoreDelta = Constants.GameBalance.scorePerDrone
            resourceDelta = Constants.TowerDefense.resourcesPerDroneKill
        }
        score += scoreDelta
        dronesDestroyed += 1
        economyManager.earn(resourceDelta)
        updateHUD()
    }

    func onDroneReachedHQ(drone: AttackDroneEntity? = nil) {
        guard currentPhase == .combat else { return }
        if let drone {
            if drone.isHit { return }
            if !activeDrones.contains(drone) { return }
        }
        lives -= 1
        updateHUD()
        if lives <= 0 {
            triggerGameOver()
        }
    }

    func onMineReachedGround(_ mine: MineBombEntity) {
        let pos = mine.component(ofType: SpriteComponent.self)?.spriteNode.position ?? .zero
        spawnRocketBlast(at: pos, radius: Constants.GameBalance.mineBombBlastRadius, damage: 1)
        removeEntity(mine)
    }

    func onMineShotInAir(_ mine: MineBombEntity) {
        removeEntity(mine)
    }

    func onMineHitDrone(_ mine: MineBombEntity, drone: AttackDroneEntity) {
        if !drone.isHit {
            drone.takeDamage(1)
            if drone.isHit {
                onDroneDestroyed(drone: drone)
            }
        }
        removeEntity(mine)
    }

    private func triggerGameOver() {
        currentPhase = .gameOver
        cleanupOffscreenIndicator()
        settingsButton?.isHidden = true
        startWaveButton?.isHidden = true
        speedButton?.isHidden = true
        showGameOverOverlay()
    }

    private func showGameOverOverlay() {
        let overlay = SKNode()
        overlay.name = "gameOverOverlay"
        overlay.zPosition = 100
        addChild(overlay)

        let bg = SKSpriteNode(color: UIColor.black.withAlphaComponent(0.75), size: frame.size)
        bg.position = CGPoint(x: frame.midX, y: frame.midY)
        overlay.addChild(bg)

        let title = SKLabelNode(fontNamed: Constants.GameBalance.hudFontName)
        title.text = "GAME OVER"
        title.fontSize = 40
        title.fontColor = .red
        title.position = CGPoint(x: frame.midX, y: frame.midY + 80)
        overlay.addChild(title)

        let stats = [
            "Score: \(score)",
            "Wave: \(waveManager?.currentWave ?? 0)",
            "Drones Destroyed: \(dronesDestroyed)"
        ]
        for (i, text) in stats.enumerated() {
            let label = SKLabelNode(fontNamed: Constants.GameBalance.hudFontName)
            label.text = text
            label.fontSize = 20
            label.fontColor = .white
            label.position = CGPoint(x: frame.midX, y: frame.midY + 20 - CGFloat(i * 30))
            overlay.addChild(label)
        }

        let restartBtn = SKSpriteNode(color: .darkGray, size: CGSize(width: 180, height: 44))
        restartBtn.position = CGPoint(x: frame.midX, y: frame.midY - 80)
        restartBtn.name = "playAgainButton"
        overlay.addChild(restartBtn)

        let restartLabel = SKLabelNode(fontNamed: Constants.GameBalance.hudFontName)
        restartLabel.text = "Play Again"
        restartLabel.fontSize = 18
        restartLabel.fontColor = .green
        restartLabel.verticalAlignmentMode = .center
        restartLabel.name = "playAgainButton"
        restartBtn.addChild(restartLabel)

        let menuBtn = SKSpriteNode(color: .systemRed, size: CGSize(width: 180, height: 44))
        menuBtn.position = CGPoint(x: frame.midX, y: frame.midY - 135)
        menuBtn.name = "menuButton_gameOver"
        overlay.addChild(menuBtn)

        let menuLabel = SKLabelNode(fontNamed: Constants.GameBalance.hudFontName)
        menuLabel.text = "Menu"
        menuLabel.fontSize = 18
        menuLabel.fontColor = .white
        menuLabel.verticalAlignmentMode = .center
        menuLabel.name = "menuButton_gameOver"
        menuBtn.addChild(menuLabel)
    }

    func playAgain() {
        enumerateChildNodes(withName: "//gameOverOverlay") { node, _ in
            node.removeFromParent()
        }
        startGame()
    }

    var hasGameOverOverlay: Bool {
        childNode(withName: "//gameOverOverlay") != nil
    }

    // MARK: - Mine Layer / Bomber Drone

    func spawnMineLayer(health: Int) {
        guard let target = bestBombingTarget() else { return }
        let mineLayer = MineLayerDroneEntity(sceneFrame: frame)
        mineLayer.mineLayerDelegate = self
        mineLayer.configureHealth(health)

        // Set altitude to .micro
        mineLayer.addComponent(AltitudeComponent(altitude: .micro))
        let shadow = ShadowComponent()
        mineLayer.addComponent(shadow)
        shadowLayer?.addChild(shadow.shadowNode)

        // Scale for micro altitude
        if let spriteNode = mineLayer.component(ofType: SpriteComponent.self)?.spriteNode {
            let scale = DroneAltitude.micro.droneVisualScale
            spriteNode.size = CGSize(width: 30 * scale, height: 30 * scale)
            spriteNode.zPosition = 61 + CGFloat(DroneAltitude.micro.rawValue) * 5
        }

        mineLayer.beginCycleTD(in: frame, targetingTower: target)
        activeDrones.append(mineLayer)
        addEntity(mineLayer)
    }

    func bestBombingTarget(from dronePosition: CGPoint? = nil) -> TowerEntity? {
        guard let towerPlacement else { return nil }

        let from = dronePosition ?? CGPoint(x: frame.midX, y: frame.maxY)

        // Anti-micro gun towers: effective close-range defence against mine layers
        let antiMicroTypes: Set<TowerType> = [.autocannon, .ciws]

        // Collect cover zones from active gun towers that counter micro drones
        let coverZones: [(position: CGPoint, rangeSq: CGFloat)] = towerPlacement.towers.compactMap { tower in
            guard let stats = tower.stats,
                  !stats.isDisabled,
                  antiMicroTypes.contains(stats.towerType)
            else { return nil }
            return (position: tower.worldPosition, rangeSq: stats.range * stats.range)
        }

        func isEligible(_ candidate: TowerEntity, ofType type: TowerType) -> Bool {
            guard candidate.towerType == type,
                  !(candidate.stats?.isDisabled ?? true)
            else { return false }

            let pos = candidate.worldPosition
            for zone in coverZones {
                let dx = pos.x - zone.position.x
                let dy = pos.y - zone.position.y
                if dx * dx + dy * dy <= zone.rangeSq {
                    return false
                }
            }
            return true
        }

        let priorityOrder: [TowerType] = [.samLauncher, .interceptor, .radar, .ciws, .autocannon]
        for type in priorityOrder {
            // Skip gun towers that are effective against micro
            guard !antiMicroTypes.contains(type) else { continue }

            let eligible = towerPlacement.towers.filter { isEligible($0, ofType: type) }
            guard !eligible.isEmpty else { continue }

            // Among same-type towers pick the closest to the drone
            return eligible.min(by: { a, b in
                let da = squaredDistance(a.worldPosition, from)
                let db = squaredDistance(b.worldPosition, from)
                return da < db
            })
        }
        return nil
    }

    private func squaredDistance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = a.x - b.x
        let dy = a.y - b.y
        return dx * dx + dy * dy
    }

    func activeTowerThreats() -> [MineLayerDroneEntity.TowerThreatInfo] {
        guard let towerPlacement else { return [] }
        var threats = [MineLayerDroneEntity.TowerThreatInfo]()
        for tower in towerPlacement.towers {
            guard let stats = tower.stats,
                  (stats.towerType == .autocannon || stats.towerType == .ciws),
                  !stats.isDisabled,
                  let targeting = tower.component(ofType: TowerTargetingComponent.self),
                  targeting.currentTarget != nil
            else { continue }
            threats.append(MineLayerDroneEntity.TowerThreatInfo(
                position: tower.worldPosition,
                range: stats.range,
                id: ObjectIdentifier(tower)
            ))
        }
        return threats
    }

    func allTowerThreatZones() -> [MineLayerDroneEntity.TowerThreatInfo] {
        guard let towerPlacement else { return [] }
        var zones = [MineLayerDroneEntity.TowerThreatInfo]()
        for tower in towerPlacement.towers {
            guard let stats = tower.stats,
                  (stats.towerType == .autocannon || stats.towerType == .ciws),
                  !stats.isDisabled
            else { continue }
            zones.append(MineLayerDroneEntity.TowerThreatInfo(
                position: tower.worldPosition,
                range: stats.range,
                id: ObjectIdentifier(tower)
            ))
        }
        return zones
    }

    func onBombHitTower(_ mine: MineBombEntity, tower: TowerEntity) {
        tower.takeBombDamage(1)
        // Small explosion VFX
        let pos = mine.component(ofType: SpriteComponent.self)?.spriteNode.position ?? tower.worldPosition
        spawnBombExplosion(at: pos)
        removeEntity(mine)
    }

    private func spawnBombExplosion(at position: CGPoint) {
        let flash = SKSpriteNode(color: .orange, size: CGSize(width: 16, height: 16))
        flash.position = position
        flash.zPosition = 50
        flash.alpha = 0.8
        addChild(flash)
        let expand = SKAction.scale(to: 2.0, duration: 0.15)
        let fade = SKAction.fadeOut(withDuration: 0.15)
        flash.run(SKAction.sequence([SKAction.group([expand, fade]), SKAction.removeFromParent()]))
    }

    // MARK: - Cleanup

    private func cleanupDrones() {
        guard currentPhase == .combat else { return }
        let snapshot = activeDrones

        for drone in snapshot {
            guard let droneNode = drone.component(ofType: SpriteComponent.self)?.spriteNode else {
                removeEntity(drone)
                continue
            }
            if droneNode.parent == nil {
                removeEntity(drone)
                continue
            }

            // Check if drone reached HQ area (bottom of map)
            let hqThreshold = gridMap.origin.y + gridMap.cellSize.height
            if !drone.isHit && droneNode.position.y < hqThreshold {
                onDroneReachedHQ(drone: drone)
                drone.reachedDestination()
                continue
            }

            // Remove hit drones that fell off screen
            if drone.isHit && droneNode.position.y < -50 {
                removeEntity(drone)
                continue
            }
        }
    }

    private func updateShadows() {
        for drone in activeDrones {
            guard let dronePos = drone.component(ofType: SpriteComponent.self)?.spriteNode.position,
                  let shadow = drone.component(ofType: ShadowComponent.self),
                  let altitude = drone.component(ofType: AltitudeComponent.self)?.altitude
            else { continue }
            shadow.updateShadow(dronePosition: dronePos, altitude: altitude)
        }
    }

    private func updateMineLayerOffscreenIndicator() {
        // Find first active mine layer that is off-screen
        let offscreenMiner = activeDrones.compactMap { $0 as? MineLayerDroneEntity }.first { miner in
            guard !miner.isHit,
                  let pos = miner.component(ofType: SpriteComponent.self)?.spriteNode.position
            else { return false }
            return pos.x < 0 || pos.x > frame.width
        }

        guard let miner = offscreenMiner,
              let dronePos = miner.component(ofType: SpriteComponent.self)?.spriteNode.position
        else {
            offscreenIndicator?.removeFromParent()
            offscreenIndicator = nil
            return
        }

        // Create indicator if needed
        if offscreenIndicator == nil {
            let node = SKNode()
            node.zPosition = 98

            let label = SKLabelNode(fontNamed: Constants.GameBalance.hudFontName)
            label.text = "!"
            label.fontSize = 20
            label.fontColor = .yellow
            label.verticalAlignmentMode = .center
            label.name = "offscreenLabel"
            node.addChild(label)

            // Triangle arrow
            let arrow = SKShapeNode()
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 0, y: 8))
            path.addLine(to: CGPoint(x: -6, y: -4))
            path.addLine(to: CGPoint(x: 6, y: -4))
            path.closeSubpath()
            arrow.path = path
            arrow.fillColor = .yellow
            arrow.strokeColor = .clear
            arrow.name = "offscreenArrow"
            arrow.position = CGPoint(x: 0, y: -16)
            node.addChild(arrow)

            // Pulse animation
            let scaleUp = SKAction.scale(to: 1.15, duration: 0.4)
            let scaleDown = SKAction.scale(to: 0.9, duration: 0.4)
            node.run(SKAction.repeatForever(SKAction.sequence([scaleUp, scaleDown])))

            addChild(node)
            offscreenIndicator = node
        }

        guard let indicator = offscreenIndicator else { return }

        // Position at screen edge, clamped Y
        let edgeMargin: CGFloat = 20
        let clampedY = min(max(dronePos.y, safeBottom + 30), frame.height - safeTop - 30)

        if dronePos.x < 0 {
            indicator.position = CGPoint(x: edgeMargin, y: clampedY)
            // Arrow points left
            if let arrow = indicator.childNode(withName: "offscreenArrow") {
                arrow.zRotation = .pi / 2
            }
        } else {
            indicator.position = CGPoint(x: frame.width - edgeMargin, y: clampedY)
            // Arrow points right
            if let arrow = indicator.childNode(withName: "offscreenArrow") {
                arrow.zRotation = -.pi / 2
            }
        }
    }

    private func cleanupOffscreenIndicator() {
        offscreenIndicator?.removeFromParent()
        offscreenIndicator = nil
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

    // MARK: - Fire Control (for rocket towers)

    func bestRocketTargetPoint(
        preferredPoint: CGPoint? = nil,
        origin: CGPoint? = nil,
        radius: CGFloat? = nil,
        influenceRadius: CGFloat? = nil,
        reservingActiveRocketImpacts: Bool = false,
        excludingRocket: RocketEntity? = nil,
        projectileSpeed: CGFloat? = nil,
        projectileAcceleration: CGFloat? = nil,
        projectileMaxSpeed: CGFloat? = nil
    ) -> CGPoint? {
        syncFireControlState()
        let spec = Constants.GameBalance.standardRocketSpec
        let profile = FireControlState.PlanningProfile(
            blastRadius: max(0, influenceRadius ?? spec.blastRadius),
            maxRange: radius,
            nominalSpeed: max(120, projectileSpeed ?? spec.initialSpeed),
            acceleration: projectileAcceleration ?? spec.acceleration,
            maxSpeed: projectileMaxSpeed ?? spec.maxSpeed
        )
        return fireControl.planLaunch(
            preferredPoint: preferredPoint,
            origin: origin,
            reservingAssignments: reservingActiveRocketImpacts,
            excludingRocketID: excludingRocket.map { ObjectIdentifier($0) },
            profile: profile
        )?.targetPoint
    }

    func updateRocketReservation(for rocket: RocketEntity, targetPoint: CGPoint? = nil) {
        syncFireControlState()
        let rocketID = ObjectIdentifier(rocket)
        let target = targetPoint ?? rocket.guidanceTargetPointForDisplay
        let launchOrigin = rocket.component(ofType: SpriteComponent.self)?.spriteNode.position
        fireControl.upsertAssignment(
            rocketID: rocketID,
            spec: rocket.spec,
            targetPoint: target,
            launchOrigin: launchOrigin,
            currentTime: elapsedGameplayTime
        )
    }

    func isDroneReservedByRocket(_ drone: AttackDroneEntity) -> Bool {
        syncFireControlState()
        return fireControl.isDroneReservedByRocket(ObjectIdentifier(drone))
    }

    func isDroneOverkilled(_ drone: AttackDroneEntity) -> Bool {
        syncFireControlState()
        return fireControl.isDroneOverkilled(ObjectIdentifier(drone))
    }

    func onRocketDetonated(_ rocket: RocketEntity, at position: CGPoint, blastRadius: CGFloat) {
        fireControl.lockAssignmentForImpact(
            rocketID: ObjectIdentifier(rocket),
            impactPoint: position,
            impactRadius: blastRadius,
            currentTime: elapsedGameplayTime,
            lockDuration: 0.25
        )
    }

    func spawnRocketBlast(at position: CGPoint, radius: CGFloat, damage: Int = 1) {
        let blastTexture: SKTexture = {
            let d: CGFloat = 64
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: d, height: d))
            let image = renderer.image { ctx in
                UIColor.white.setFill()
                ctx.cgContext.fillEllipse(in: CGRect(x: 0, y: 0, width: d, height: d))
            }
            return SKTexture(image: image)
        }()

        let blast = SKSpriteNode(texture: blastTexture)
        blast.size = CGSize(width: radius * 2, height: radius * 2)
        blast.name = "rocketBlastNode"
        blast.position = position
        blast.zPosition = 50
        blast.userData = ["damage": damage]
        blast.color = UIColor.orange.withAlphaComponent(0.35)
        blast.colorBlendFactor = 1.0
        blast.physicsBody = SKPhysicsBody(circleOfRadius: radius)
        blast.physicsBody?.isDynamic = false
        blast.physicsBody?.categoryBitMask = Constants.rocketBlastBitMask
        blast.physicsBody?.contactTestBitMask = Constants.droneBitMask
        blast.physicsBody?.collisionBitMask = 0
        addChild(blast)

        let scale = SKAction.scale(to: 1.2, duration: 0.1)
        let fade = SKAction.fadeOut(withDuration: 0.15)
        let remove = SKAction.removeFromParent()
        blast.run(SKAction.sequence([SKAction.group([scale, fade]), remove]))
    }

    private func syncFireControlState() {
        let rocketsInFlightIDs = Set(activeRockets.map { ObjectIdentifier($0) })
        fireControl.syncAssignments(
            withActiveRocketIDs: rocketsInFlightIDs,
            currentTime: elapsedGameplayTime
        )
        fireControl.syncTracks(
            with: activeDrones.filter { !$0.isHit },
            currentTime: elapsedGameplayTime,
            sceneHeight: frame.height
        )
    }

    // MARK: - Touch Handling

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)
        let touchedNode = atPoint(location)

        switch currentPhase {
        case .mainMenu:
            if touchedNode.name == "startGameButton" {
                startGame()
            }

        case .gameOver:
            if touchedNode.name == "playAgainButton" {
                playAgain()
            } else if touchedNode.name == "menuButton_gameOver" {
                enumerateChildNodes(withName: "//gameOverOverlay") { node, _ in
                    node.removeFromParent()
                }
                stopGame()
                showMainMenu()
            }

        case .build:
            // Check start wave button (build phase only)
            if touchedNode.name == "startWaveButton" {
                let earlyBonus = Int(interWaveCountdown * 2)
                if earlyBonus > 0 {
                    economyManager.earn(earlyBonus)
                }
                interWaveCountdown = 0
                startCombatPhase()
                return
            }
            handleTowerInteraction(touchedNode: touchedNode, location: location)

        case .combat:
            handleTowerInteraction(touchedNode: touchedNode, location: location)

        case .waveComplete:
            break
        }
    }

    private var selectedTower: TowerEntity?

    private func handleTowerInteraction(touchedNode: SKNode, location: CGPoint) {
        // Speed button
        if touchedNode.name == "speedButton" || touchedNode.parent?.name == "speedButton" {
            toggleGameSpeed()
            return
        }

        // Upgrade/sell buttons
        if touchedNode.name == "upgradeButton" || touchedNode.parent?.name == "upgradeButton" {
            if let tower = selectedTower {
                if towerPlacement.upgradeTower(tower, economy: economyManager) {
                    tower.hideRangeIndicator()
                    tower.showRangeIndicator()
                    dismissTowerActionPanel()
                    updateHUD()
                }
            }
            return
        }
        if touchedNode.name == "sellButton" || touchedNode.parent?.name == "sellButton" {
            if let tower = selectedTower {
                towerPlacement.sellTower(tower, economy: economyManager)
                selectedTower = nil
                dismissTowerActionPanel()
                updateHUD()
            }
            return
        }

        // Tower palette
        for (type, node) in paletteButtons {
            if touchedNode === node || touchedNode.parent === node || touchedNode.parent?.parent === node {
                if towerPlacement.selectedTowerType == type {
                    towerPlacement.selectTowerType(nil)
                } else {
                    towerPlacement.selectTowerType(type)
                }
                updatePaletteHighlight()
                towerPlacement.clearPreview()
                return
            }
        }

        // Grid tap for tower placement or tower info
        if let gridPos = gridMap.gridPosition(for: location) {
            if towerPlacement.selectedTowerType != nil {
                if gridMap.canPlaceTower(atRow: gridPos.row, col: gridPos.col) {
                    towerPlacement.placeTower(at: gridPos, economy: economyManager)
                    updateHUD()
                }
            } else {
                if let tower = towerPlacement.towerAt(gridPos: gridPos) {
                    handleTowerTap(tower)
                }
            }
        }
    }

    private func handleTowerTap(_ tower: TowerEntity) {
        // Deselect previous
        selectedTower?.hideRangeIndicator()
        dismissTowerActionPanel()

        if selectedTower === tower {
            selectedTower = nil
            return
        }

        selectedTower = tower
        tower.showRangeIndicator()
        showTowerActions(tower)
    }

    private func showTowerActions(_ tower: TowerEntity) {
        // Remove existing action panel
        enumerateChildNodes(withName: "//towerActionPanel") { node, _ in
            node.removeFromParent()
        }

        guard let stats = tower.stats else { return }
        let pos = tower.worldPosition

        let panel = SKNode()
        panel.name = "towerActionPanel"
        panel.zPosition = 97
        panel.position = CGPoint(x: pos.x, y: pos.y + 45)

        if stats.level < 3 {
            let upgradeCost = Int(CGFloat(stats.cost) * Constants.TowerDefense.upgradeCostMultiplier)
            let upgradeBtn = SKSpriteNode(
                color: economyManager.canAfford(upgradeCost) ? .systemBlue : .gray,
                size: CGSize(width: 60, height: 24)
            )
            upgradeBtn.name = "upgradeButton"
            upgradeBtn.position = CGPoint(x: -35, y: 0)
            let upgradeLabel = SKLabelNode(fontNamed: Constants.GameBalance.hudFontName)
            upgradeLabel.text = "UP \(upgradeCost)"
            upgradeLabel.fontSize = 10
            upgradeLabel.fontColor = .white
            upgradeLabel.verticalAlignmentMode = .center
            upgradeLabel.name = "upgradeButton"
            upgradeBtn.addChild(upgradeLabel)
            panel.addChild(upgradeBtn)
        }

        let sellBtn = SKSpriteNode(color: .systemRed, size: CGSize(width: 60, height: 24))
        sellBtn.name = "sellButton"
        sellBtn.position = CGPoint(x: 35, y: 0)
        let sellLabel = SKLabelNode(fontNamed: Constants.GameBalance.hudFontName)
        sellLabel.text = "SELL \(stats.sellValue)"
        sellLabel.fontSize = 10
        sellLabel.fontColor = .white
        sellLabel.verticalAlignmentMode = .center
        sellLabel.name = "sellButton"
        sellBtn.addChild(sellLabel)
        panel.addChild(sellBtn)

        addChild(panel)

        // Auto-dismiss after a delay
        panel.run(SKAction.sequence([
            SKAction.wait(forDuration: 5),
            SKAction.removeFromParent()
        ]))
    }

    private func dismissTowerActionPanel() {
        enumerateChildNodes(withName: "//towerActionPanel") { node, _ in
            node.removeFromParent()
        }
    }

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
        }

        // Update all entities
        for entity in entities {
            entity.update(deltaTime: scaledDt)
        }

        if currentPhase == .combat {
            waveManager.update(deltaTime: scaledDt)
            cleanupDrones()
            updateShadows()
            updateMineLayerOffscreenIndicator()
            syncFireControlState()

            // Check wave completion
            if let waveManager, !waveManager.isWaveInProgress && activeDrones.isEmpty {
                onWaveComplete()
            }
        }

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
