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
    private(set) var settlementManager: SettlementManager?
    private var fireControl = FireControlState()
    let militaryAidManager = MilitaryAidManager()
    private let synergyManager = TowerSynergyManager()
    private var selectedLevel: LevelDefinition = LevelDefinition.level1
    private var selectedCampaignLevelId: String?  // nil = endless mode
    private(set) var currentPhase: GamePhase = .mainMenu
    private(set) var score = 0
    private(set) var lives = Constants.TowerDefense.hqLives
    private(set) var dronesDestroyed = 0

    private var activeDrones = [AttackDroneEntity]()
    private var activeRockets = [RocketEntity]()
    // Per-frame caches (rebuilt once per combat frame in rebuildFrameCaches)
    private var aliveDrones = [AttackDroneEntity]()
    private var aliveNonMineLayerDrones = [AttackDroneEntity]()
    private var aliveMissileCount = 0
    private var cachedMissileAlertActive = false
    private var activeRadars = [(position: CGPoint, rangeSq: CGFloat)]()
    private var radarNightDots = [ObjectIdentifier: SKSpriteNode]()
    private var jammedTowerIDs = Set<ObjectIdentifier>()
    private var elapsedGameplayTime: TimeInterval = 0
    private var interWaveCountdown: TimeInterval = 0
    private let firstWaveCountdown: TimeInterval = 15.0
    private let normalWaveCountdown: TimeInterval = 3.0
    private var gameSpeed: CGFloat = 1.0
    private(set) var pendingMissileSpawns = 0
    private(set) var pendingHarmSpawns = 0

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
    private var hudNode: SKNode?
    private var resourceLabel: SKLabelNode?
    private var waveLabel: SKLabelNode?
    private var livesLabel: SKLabelNode?
    private var startWaveButton: SKSpriteNode?
    private var startWaveLabel: SKLabelNode?

    // Tower palette
    private let conveyorBelt = ConveyorBeltManager()

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

    // Night overlay
    private var nightOverlay: SKSpriteNode?
    private(set) var isNightWave = false

    // Ability manager
    private var abilityManager = AbilityManager()

    // Active swarm clouds (for update loop)
    private var activeSwarmClouds = [SwarmCloudEntity]()

    // Node pools for recycling frequently created/destroyed nodes
    private var tracerPool = [SKSpriteNode]()
    private var smokePuffPool = [SKSpriteNode]()
    private let nodePoolCapacity = 100

    // Fire control sync guard — ensures sync runs at most once per frame
    private var fireControlSyncedThisFrame = false
    // Rocket retarget budget — limits expensive planLaunch() calls per frame
    private(set) var rocketRetargetBudget = 0
    private let maxRetargetsPerFrame = 3

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
        case .settlement:
            return UIColor(red: 0.25, green: 0.35, blue: 0.25, alpha: 1)
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
        conveyorBelt.setup(in: self, safeBottom: safeBottom)
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
            onRestart: { [weak self] in self?.restartGame() },
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
        // Reset lastUpdateTime so the next frame doesn't see a huge dt
        lastUpdateTime = 0
        isPaused = false
    }

    private func restartGame() {
        resumeGame()
        stopGame()
        startGame()
    }

    private func exitToMainMenu() {
        resumeGame()
        stopGame()
        showMainMenu()
    }

    // MARK: - Night Wave

    private func transitionToNight() {
        guard !isNightWave else { return }
        isNightWave = true

        let overlay = SKSpriteNode(color: .black, size: frame.size)
        overlay.alpha = 0
        overlay.position = CGPoint(x: frame.midX, y: frame.midY)
        overlay.zPosition = 90  // under HUD
        overlay.name = "nightOverlay"
        addChild(overlay)
        nightOverlay = overlay

        overlay.run(SKAction.fadeAlpha(to: Constants.NightWave.overlayAlpha, duration: Constants.NightWave.transitionDuration))

        // Block tower placement
        towerPlacement?.selectTowerType(nil)
        conveyorBelt.deselect()
        conveyorBelt.setNightMode(true)

        // Create radar indicator dots
        updateRadarNightDots()
    }

    private func transitionToDay() {
        guard isNightWave else { return }
        isNightWave = false

        if let overlay = nightOverlay {
            overlay.run(SKAction.sequence([
                SKAction.fadeOut(withDuration: Constants.NightWave.transitionDuration),
                SKAction.removeFromParent()
            ]))
            nightOverlay = nil
        }

        // Restore tower placement
        conveyorBelt.setNightMode(false)

        // Remove radar dots
        for (_, dot) in radarNightDots {
            dot.removeFromParent()
        }
        radarNightDots.removeAll()
    }

    /// Returns whether the given world-space point is within any active radar's coverage zone.
    /// Only meaningful during night waves; returns true during day.
    func isPositionInRadarCoverage(_ point: CGPoint) -> Bool {
        guard isNightWave else { return true }
        for (radarPos, rangeSq) in activeRadars {
            let dx = point.x - radarPos.x
            let dy = point.y - radarPos.y
            if dx * dx + dy * dy <= rangeSq {
                return true
            }
        }
        return false
    }

    /// Update blinking green dots at radar positions during night.
    private func updateRadarNightDots() {
        guard isNightWave, let towerPlacement else { return }

        var currentIDs = Set<ObjectIdentifier>()
        for tower in towerPlacement.towers {
            guard let stats = tower.stats, stats.towerType == .radar, !stats.isDisabled else { continue }
            let id = ObjectIdentifier(tower)
            currentIDs.insert(id)

            if radarNightDots[id] == nil {
                let dot = SKSpriteNode(color: .green, size: CGSize(width: 6, height: 6))
                dot.position = tower.worldPosition
                dot.zPosition = Constants.NightWave.nightEffectZPosition
                dot.alpha = 0.2
                addChild(dot)

                let pulse = SKAction.sequence([
                    SKAction.fadeAlpha(to: 1.0, duration: 1.0),
                    SKAction.fadeAlpha(to: 0.2, duration: 1.0)
                ])
                dot.run(SKAction.repeatForever(pulse))
                radarNightDots[id] = dot
            }
        }

        // Remove dots for destroyed/disabled radars
        for (id, dot) in radarNightDots where !currentIDs.contains(id) {
            dot.removeFromParent()
            radarNightDots.removeValue(forKey: id)
        }
    }

    // MARK: - EW Jamming

    /// Returns the jamming accuracy multiplier for a tower (1.0 if not jammed).
    /// Uses per-frame cached jamming set for O(1) lookup.
    func ewJammingMultiplier(for tower: TowerEntity) -> CGFloat {
        jammedTowerIDs.contains(ObjectIdentifier(tower))
            ? Constants.EW.ewDroneAccuracyMultiplier : 1.0
    }

    // MARK: - Game Flow

    private func showMainMenu() {
        currentPhase = .mainMenu
        hudNode?.isHidden = true
        conveyorBelt.removeUI()
        startWaveButton?.isHidden = true
        speedButton?.isHidden = true
        settingsButton?.isHidden = true

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
        title.position = CGPoint(x: frame.midX, y: frame.midY + 100)
        overlay.addChild(title)

        // Campaign button
        let campaignBtn = SKSpriteNode(color: .systemBlue, size: CGSize(width: 200, height: 50))
        campaignBtn.position = CGPoint(x: frame.midX, y: frame.midY + 10)
        campaignBtn.name = "campaignButton"
        overlay.addChild(campaignBtn)

        let campaignLabel = SKLabelNode(fontNamed: Constants.GameBalance.hudFontName)
        campaignLabel.text = "КАМПАНИЯ"
        campaignLabel.fontSize = 20
        campaignLabel.fontColor = .white
        campaignLabel.verticalAlignmentMode = .center
        campaignLabel.name = "campaignButton"
        campaignBtn.addChild(campaignLabel)

        // Stars counter
        let stars = CampaignManager.shared.totalStars()
        if stars > 0 {
            let starsLabel = SKLabelNode(fontNamed: Constants.GameBalance.hudFontName)
            starsLabel.text = "\(stars) \u{2605}"
            starsLabel.fontSize = 14
            starsLabel.fontColor = .systemYellow
            starsLabel.position = CGPoint(x: frame.midX, y: frame.midY - 20)
            overlay.addChild(starsLabel)
        }

        // Endless button
        let endlessBtn = SKSpriteNode(color: .systemGreen, size: CGSize(width: 200, height: 50))
        endlessBtn.position = CGPoint(x: frame.midX, y: frame.midY - 60)
        endlessBtn.name = "startGameButton"
        overlay.addChild(endlessBtn)

        let endlessLabel = SKLabelNode(fontNamed: Constants.GameBalance.hudFontName)
        endlessLabel.text = "ENDLESS"
        endlessLabel.fontSize = 20
        endlessLabel.fontColor = .white
        endlessLabel.verticalAlignmentMode = .center
        endlessLabel.name = "startGameButton"
        endlessBtn.addChild(endlessLabel)

    }

    // MARK: - Level Selection

    private func showLevelSelect() {
        enumerateChildNodes(withName: "//mainMenuOverlay") { node, _ in
            node.removeFromParent()
        }

        let overlay = SKNode()
        overlay.name = "levelSelectOverlay"
        overlay.zPosition = 100
        addChild(overlay)

        let bg = SKSpriteNode(color: UIColor.black.withAlphaComponent(0.8), size: frame.size)
        bg.position = CGPoint(x: frame.midX, y: frame.midY)
        overlay.addChild(bg)

        let title = SKLabelNode(fontNamed: Constants.GameBalance.hudFontName)
        title.text = "CAMPAIGN"
        title.fontSize = 24
        title.fontColor = .white
        title.position = CGPoint(x: frame.midX, y: frame.height - 80 - safeTop)
        overlay.addChild(title)

        let campaign = CampaignManager.shared
        let levels = campaign.levels
        let cardHeight: CGFloat = 48
        let spacing: CGFloat = 8
        let startY = frame.height - 120 - safeTop

        for (i, level) in levels.enumerated() {
            let y = startY - CGFloat(i) * (cardHeight + spacing)
            let unlocked = campaign.isUnlocked(level.id)
            let completed = campaign.isCompleted(level.id)
            let stars = campaign.stars(for: level.id)

            let card = SKSpriteNode(
                color: unlocked ? UIColor.darkGray.withAlphaComponent(0.85) : UIColor.darkGray.withAlphaComponent(0.35),
                size: CGSize(width: frame.width - 40, height: cardHeight)
            )
            card.position = CGPoint(x: frame.midX, y: y)
            card.name = unlocked ? "levelCard_\(i)" : nil
            overlay.addChild(card)

            // Level number
            let numLabel = SKLabelNode(fontNamed: Constants.GameBalance.hudFontName)
            numLabel.text = "\(i + 1)."
            numLabel.fontSize = 14
            numLabel.fontColor = unlocked ? .white : .gray
            numLabel.position = CGPoint(x: -card.size.width / 2 + 20, y: 6)
            numLabel.horizontalAlignmentMode = .left
            numLabel.verticalAlignmentMode = .center
            numLabel.name = card.name
            card.addChild(numLabel)

            // Level name
            let nameLabel = SKLabelNode(fontNamed: Constants.GameBalance.hudFontName)
            nameLabel.text = unlocked ? level.name : "???"
            nameLabel.fontSize = 12
            nameLabel.fontColor = unlocked ? .white : .gray
            nameLabel.position = CGPoint(x: -card.size.width / 2 + 44, y: 6)
            nameLabel.horizontalAlignmentMode = .left
            nameLabel.verticalAlignmentMode = .center
            nameLabel.name = card.name
            card.addChild(nameLabel)

            // Subtitle
            let subLabel = SKLabelNode(fontNamed: Constants.GameBalance.hudFontName)
            subLabel.text = unlocked ? level.subtitle : ""
            subLabel.fontSize = 9
            subLabel.fontColor = UIColor.white.withAlphaComponent(0.5)
            subLabel.position = CGPoint(x: -card.size.width / 2 + 44, y: -8)
            subLabel.horizontalAlignmentMode = .left
            subLabel.verticalAlignmentMode = .center
            card.addChild(subLabel)

            // Stars
            if completed {
                let starsText = String(repeating: "\u{2605}", count: stars) + String(repeating: "\u{2606}", count: 3 - stars)
                let starsLabel = SKLabelNode(fontNamed: Constants.GameBalance.hudFontName)
                starsLabel.text = starsText
                starsLabel.fontSize = 14
                starsLabel.fontColor = .systemYellow
                starsLabel.position = CGPoint(x: card.size.width / 2 - 40, y: 0)
                starsLabel.verticalAlignmentMode = .center
                starsLabel.name = card.name
                card.addChild(starsLabel)
            } else if !unlocked {
                let lockLabel = SKLabelNode(fontNamed: Constants.GameBalance.hudFontName)
                lockLabel.text = "LOCKED"
                lockLabel.fontSize = 10
                lockLabel.fontColor = .gray
                lockLabel.position = CGPoint(x: card.size.width / 2 - 40, y: 0)
                lockLabel.verticalAlignmentMode = .center
                card.addChild(lockLabel)
            }
        }

        // Back button
        let backBtn = SKSpriteNode(color: .systemRed, size: CGSize(width: 120, height: 40))
        backBtn.position = CGPoint(x: frame.midX, y: startY - CGFloat(levels.count) * (cardHeight + spacing) - 20)
        backBtn.name = "levelSelectBack"
        overlay.addChild(backBtn)

        let backLabel = SKLabelNode(fontNamed: Constants.GameBalance.hudFontName)
        backLabel.text = "BACK"
        backLabel.fontSize = 16
        backLabel.fontColor = .white
        backLabel.verticalAlignmentMode = .center
        backLabel.name = "levelSelectBack"
        backBtn.addChild(backLabel)
    }

    func startGame() {
        enumerateChildNodes(withName: "//mainMenuOverlay") { node, _ in
            node.removeFromParent()
        }
        enumerateChildNodes(withName: "//levelSelectOverlay") { node, _ in
            node.removeFromParent()
        }

        currentPhase = .build
        score = 0
        dronesDestroyed = 0
        elapsedGameplayTime = 0
        fireControl.reset()

        // Force-remove night overlay (may still be fading from previous game)
        isNightWave = false
        nightOverlay?.removeAllActions()
        nightOverlay?.removeFromParent()
        nightOverlay = nil
        for (_, dot) in radarNightDots { dot.removeFromParent() }
        radarNightDots.removeAll()

        lives = Constants.TowerDefense.hqLives

        // Reload grid with selected level
        gridMap.loadLevel(selectedLevel)

        // Generate and place settlements
        settlementManager?.removeAll()
        settlementManager = SettlementManager(scene: self)
        if let gridLayer {
            settlementManager?.generateAndPlace(
                on: gridMap,
                gridLayer: gridLayer,
                count: selectedLevel.settlementCount
            )
        }

        economyManager.reset(to: selectedLevel.startingResources)
        waveManager = WaveManager(scene: self, level: selectedLevel)
        towerPlacement.removeAllTowers()
        militaryAidManager.reset()
        synergyManager.reset()

        // Remove any lingering aid overlay
        enumerateChildNodes(withName: "//militaryAidOverlay") { node, _ in
            node.removeFromParent()
        }

        // Clear any existing drones
        for drone in activeDrones {
            removeEntity(drone)
        }
        activeDrones.removeAll()
        activeRockets.removeAll()

        hudNode?.isHidden = false
        conveyorBelt.setAvailableTowers(selectedLevel.availableTowers)
        conveyorBelt.setGuaranteedTowers(selectedLevel.guaranteedTowers)
        conveyorBelt.setup(in: self, safeBottom: safeBottom)
        startWaveButton?.isHidden = false
        speedButton?.isHidden = false
        settingsButton?.isHidden = false

        // Setup ability buttons
        abilityManager.removeButtons()
        abilityManager.setup(in: self)

        gameSpeed = 1.0
        speedLabel?.text = "\u{25B6}"
        self.speed = gameSpeed
        physicsWorld.speed = gameSpeed

        interWaveCountdown = firstWaveCountdown
        updateStartWaveButton()

        // Show level name for campaign levels, then wave announcement
        if let levelId = selectedCampaignLevelId,
           let campaignLevel = CampaignManager.shared.levels.first(where: { $0.id == levelId }) {
            showLevelNameAnnouncement(name: campaignLevel.name) {
                self.showWaveAnnouncement(wave: self.waveManager.nextWaveNumber())
            }
        } else {
            showWaveAnnouncement(wave: waveManager.nextWaveNumber())
        }
        updateHUD()
    }

    func stopGame() {
        currentPhase = .mainMenu
        cleanupOffscreenIndicator()
        transitionToDay()

        for drone in activeDrones {
            removeEntity(drone)
        }
        activeDrones.removeAll()
        activeSwarmClouds.removeAll()

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
        settlementManager?.removeAll()
        fireControl.reset()

        hudNode?.isHidden = true
        conveyorBelt.removeUI()
        startWaveButton?.isHidden = true
        speedButton?.isHidden = true
        settingsButton?.isHidden = true
        abilityManager.removeButtons()

        gameSpeed = 1.0
        speedLabel?.text = "\u{25B6}"
        self.speed = 1.0
        physicsWorld.speed = 1.0
    }

    private func startCombatPhase() {
        currentPhase = .combat
        startWaveButton?.isHidden = true
        fireControl.reset()
        pendingMissileSpawns = 0
        pendingHarmSpawns = 0

        // Repair all towers and replenish magazines at wave start
        towerPlacement.towers.forEach {
            $0.fullRepair()
            $0.stats?.replenishMagazine()
        }

        waveManager.startNextWave()

        // Night wave transition
        if waveManager.isCurrentWaveNight {
            transitionToNight()
        } else {
            transitionToDay()
        }

        updateHUD()
    }

    private func onWaveComplete() {
        currentPhase = .build
        cleanupOffscreenIndicator()
        transitionToDay()
        activeSwarmClouds.removeAll()
        let waveBonus = Constants.TowerDefense.waveCompletionBonus
        let settlementIncome = settlementManager?.totalWaveIncome() ?? 0
        economyManager.earn(waveBonus + settlementIncome)

        // Deactivate shield if it was active
        if militaryAidManager.isShieldActive {
            militaryAidManager.deactivateShield()
            enumerateChildNodes(withName: "//hqShield") { node, _ in
                node.run(SKAction.sequence([
                    SKAction.fadeOut(withDuration: 0.5),
                    SKAction.removeFromParent()
                ]))
            }
        }

        // Check campaign victory
        if waveManager.isCampaignComplete && selectedCampaignLevelId != nil {
            showCampaignVictory()
            return
        }

        interWaveCountdown = normalWaveCountdown
        startWaveButton?.isHidden = false
        updateStartWaveButton()

        showWaveAnnouncement(wave: waveManager.nextWaveNumber())
        updateHUD()
    }

    private func showCampaignVictory() {
        currentPhase = .gameOver  // reuse gameOver phase for blocking input

        // Award stars
        if let levelId = selectedCampaignLevelId {
            CampaignManager.shared.completeLevel(levelId, remainingHP: lives, maxHP: Constants.TowerDefense.hqLives)
        }
        let stars = CampaignManager.shared.stars(for: selectedCampaignLevelId ?? "")
        let starsText = String(repeating: "\u{2605}", count: stars) + String(repeating: "\u{2606}", count: 3 - stars)

        let overlay = SKNode()
        overlay.name = "victoryOverlay"
        overlay.zPosition = 100
        addChild(overlay)

        let bg = SKSpriteNode(color: UIColor.black.withAlphaComponent(0.75), size: frame.size)
        bg.position = CGPoint(x: frame.midX, y: frame.midY)
        overlay.addChild(bg)

        let title = SKLabelNode(fontNamed: Constants.GameBalance.hudFontName)
        title.text = "ПОБЕДА!"
        title.fontSize = 40
        title.fontColor = .systemGreen
        title.position = CGPoint(x: frame.midX, y: frame.midY + 80)
        overlay.addChild(title)

        let starsLabel = SKLabelNode(fontNamed: Constants.GameBalance.hudFontName)
        starsLabel.text = starsText
        starsLabel.fontSize = 36
        starsLabel.fontColor = .systemYellow
        starsLabel.position = CGPoint(x: frame.midX, y: frame.midY + 30)
        overlay.addChild(starsLabel)

        let stats = [
            "Score: \(score)",
            "HP: \(lives)/\(Constants.TowerDefense.hqLives)",
            "Drones: \(dronesDestroyed)"
        ]
        for (i, text) in stats.enumerated() {
            let label = SKLabelNode(fontNamed: Constants.GameBalance.hudFontName)
            label.text = text
            label.fontSize = 18
            label.fontColor = .white
            label.position = CGPoint(x: frame.midX, y: frame.midY - 20 - CGFloat(i * 28))
            overlay.addChild(label)
        }

        // Next level button (only if there IS a next level)
        if let currentId = selectedCampaignLevelId,
           let currentIdx = CampaignManager.shared.levels.firstIndex(where: { $0.id == currentId }),
           currentIdx + 1 < CampaignManager.shared.levels.count {
            let nextBtn = SKSpriteNode(color: .systemGreen, size: CGSize(width: 180, height: 44))
            nextBtn.position = CGPoint(x: frame.midX, y: frame.midY - 110)
            nextBtn.name = "victoryNextButton"
            overlay.addChild(nextBtn)

            let nextLabel = SKLabelNode(fontNamed: Constants.GameBalance.hudFontName)
            nextLabel.text = "NEXT"
            nextLabel.fontSize = 18
            nextLabel.fontColor = .white
            nextLabel.verticalAlignmentMode = .center
            nextLabel.name = "victoryNextButton"
            nextBtn.addChild(nextLabel)
        }

        let menuBtn = SKSpriteNode(color: .systemBlue, size: CGSize(width: 180, height: 44))
        menuBtn.position = CGPoint(x: frame.midX, y: frame.midY - 165)
        menuBtn.name = "victoryMenuButton"
        overlay.addChild(menuBtn)

        let menuLabel = SKLabelNode(fontNamed: Constants.GameBalance.hudFontName)
        menuLabel.text = "CAMPAIGN"
        menuLabel.fontSize = 18
        menuLabel.fontColor = .white
        menuLabel.verticalAlignmentMode = .center
        menuLabel.name = "victoryMenuButton"
        menuBtn.addChild(menuLabel)
    }

    private func updateStartWaveButton() {
        let bonus = Int(interWaveCountdown * 2)
        startWaveLabel?.text = bonus > 0 ? "EARLY START (+\(bonus) DP)" : "START WAVE"
    }

    private func showLevelNameAnnouncement(name: String, completion: @escaping () -> Void) {
        let label = SKLabelNode(fontNamed: Constants.GameBalance.hudFontName)
        label.text = name
        label.fontSize = 30
        label.fontColor = .systemYellow
        label.position = CGPoint(x: frame.width / 2, y: frame.height / 2)
        label.zPosition = 96
        label.alpha = 0
        addChild(label)

        let fadeIn = SKAction.fadeIn(withDuration: 0.4)
        let wait = SKAction.wait(forDuration: 1.5)
        let fadeOut = SKAction.fadeOut(withDuration: 0.4)
        let remove = SKAction.removeFromParent()
        label.run(SKAction.sequence([fadeIn, wait, fadeOut, remove])) {
            completion()
        }
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

    func spawnDrone(flightPath: DroneFlightPath, speed: CGFloat, altitude: DroneAltitude, health: Int = 1, targetSettlement: SettlementEntity? = nil) {
        let flyingPath = flightPath.toFlyingPath()
        let drone = AttackDroneEntity(
            damage: 1,
            speed: speed,
            imageName: "Drone",
            flyingPath: flyingPath
        )
        drone.configureHealth(health)
        drone.targetSettlement = targetSettlement

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

    // MARK: - Shahed-136 Spawn

    func spawnShahed() {
        guard let gridMap else { return }

        // Assign target settlement
        let target = settlementManager?.assignTarget(
            towers: towerPlacement?.towers ?? []
        )

        // HQ is always the final destination
        let hqRow = Constants.TowerDefense.gridRows - 1
        let hqCol = Constants.TowerDefense.gridCols / 2
        let hqPoint = gridMap.worldPosition(forRow: hqRow, col: hqCol)

        // Random spawn from top
        let spawnPoint = CGPoint(
            x: CGFloat.random(in: 20...(frame.width - 20)),
            y: frame.height + CGFloat.random(in: 20...50)
        )

        // Path: spawn → through settlement → HQ
        let waypoints: [CGPoint]
        if let target {
            waypoints = generateSettlementPath(from: spawnPoint, through: target.worldPosition, to: hqPoint)
        } else {
            waypoints = generateSettlementPath(from: spawnPoint, to: hqPoint)
        }

        let altitude: DroneAltitude = .low
        let flightPath = DroneFlightPath(waypoints: waypoints, altitude: altitude, spawnEdge: .top)
        let flyingPath = flightPath.toFlyingPath()
        let drone = ShahedDroneEntity.create(flyingPath: flyingPath)
        drone.targetSettlement = target

        drone.addComponent(AltitudeComponent(altitude: altitude))
        let shadow = ShadowComponent()
        drone.addComponent(shadow)
        shadowLayer?.addChild(shadow.shadowNode)

        if let spriteNode = drone.component(ofType: SpriteComponent.self)?.spriteNode {
            spriteNode.zPosition = 61 + CGFloat(altitude.rawValue) * 5
        }

        activeDrones.append(drone)
        addEntity(drone)
    }

    // MARK: - Settlement Path Helpers

    /// Path: spawn → jitter → through settlement → jitter → HQ
    func generateSettlementPath(from start: CGPoint, through mid: CGPoint, to end: CGPoint) -> [CGPoint] {
        var points = [start]

        // 2 jitter waypoints: spawn → settlement
        for i in 1...2 {
            let t = CGFloat(i) / 3.0
            points.append(CGPoint(
                x: start.x + (mid.x - start.x) * t + CGFloat.random(in: -20...20),
                y: start.y + (mid.y - start.y) * t + CGFloat.random(in: -10...10)
            ))
        }

        // Settlement waypoint
        points.append(mid)

        // 2 jitter waypoints: settlement → HQ
        for i in 1...2 {
            let t = CGFloat(i) / 3.0
            points.append(CGPoint(
                x: mid.x + (end.x - mid.x) * t + CGFloat.random(in: -15...15),
                y: mid.y + (end.y - mid.y) * t + CGFloat.random(in: -8...8)
            ))
        }

        // HQ endpoint
        points.append(CGPoint(x: end.x + CGFloat.random(in: -5...5), y: end.y))
        return points
    }

    /// Direct path: spawn → jitter → HQ (no settlement target)
    func generateSettlementPath(from start: CGPoint, to end: CGPoint) -> [CGPoint] {
        var points = [start]
        for i in 1...3 {
            let t = CGFloat(i) / 4.0
            points.append(CGPoint(
                x: start.x + (end.x - start.x) * t + CGFloat.random(in: -15...15),
                y: start.y + (end.y - start.y) * t + CGFloat.random(in: -8...8)
            ))
        }
        points.append(CGPoint(x: end.x + CGFloat.random(in: -5...5), y: end.y))
        return points
    }

    // MARK: - Lancet Spawn

    func spawnLancet() {
        let spawnX = CGFloat.random(in: 40...(frame.width - 40))
        let spawnY = frame.height + CGFloat.random(in: 20...50)
        let spawnPoint = CGPoint(x: spawnX, y: spawnY)

        // Loiter above the tower cluster (mid-screen)
        let loiterY = frame.height * 0.55 + CGFloat.random(in: -40...40)
        let loiterX = CGFloat.random(in: 60...(frame.width - 60))
        let loiterCenter = CGPoint(x: loiterX, y: loiterY)

        let lancet = LancetDroneEntity(sceneFrame: frame, scene: self)

        let altitude: DroneAltitude = .medium
        lancet.addComponent(AltitudeComponent(altitude: altitude))
        let shadow = ShadowComponent()
        lancet.addComponent(shadow)
        shadowLayer?.addChild(shadow.shadowNode)

        if let spriteNode = lancet.component(ofType: SpriteComponent.self)?.spriteNode {
            let scale = altitude.droneVisualScale
            spriteNode.size = CGSize(width: 14 * scale, height: 16 * scale)
            spriteNode.zPosition = 61 + CGFloat(altitude.rawValue) * 5
        }

        lancet.configureFlight(from: spawnPoint, loiterAt: loiterCenter)

        activeDrones.append(lancet)
        addEntity(lancet)
    }

    // MARK: - Orlan-10 Spawn

    func spawnOrlan() {
        let spawnX = CGFloat.random(in: 60...(frame.width - 60))
        let spawnY = frame.height + 30
        let spawnPoint = CGPoint(x: spawnX, y: spawnY)

        let orlan = OrlanDroneEntity.create(sceneFrame: frame)

        let altitude: DroneAltitude = .high
        orlan.addComponent(AltitudeComponent(altitude: altitude))
        let shadow = ShadowComponent()
        orlan.addComponent(shadow)
        shadowLayer?.addChild(shadow.shadowNode)

        if let spriteNode = orlan.component(ofType: SpriteComponent.self)?.spriteNode {
            let scale = altitude.droneVisualScale
            spriteNode.size = CGSize(width: 20 * scale, height: 20 * scale)
            spriteNode.zPosition = 61 + CGFloat(altitude.rawValue) * 5
        }

        orlan.configureSpawn(at: spawnPoint)

        activeDrones.append(orlan)
        addEntity(orlan)
    }

    /// Returns true if any Orlan-10 recon drone is alive (used by WaveManager for salvo timing)
    var isOrlanActive: Bool {
        activeDrones.contains { $0 is OrlanDroneEntity && !$0.isHit }
    }

    // MARK: - Kamikaze Spawn

    func spawnKamikaze() {
        let spawnX = CGFloat.random(in: 20...(frame.width - 20))
        let spawnY = frame.height + CGFloat.random(in: 20...50)
        let spawnPoint = CGPoint(x: spawnX, y: spawnY)

        // 50% chance to target a settlement, 50% HQ
        var targetSettlementRef: SettlementEntity?
        let target: CGPoint

        if Bool.random(), let settlement = settlementManager?.aliveSettlements().randomElement() {
            targetSettlementRef = settlement
            let scatterAngle = CGFloat.random(in: 0...(2 * .pi))
            let scatterDist = CGFloat.random(in: 0...15)
            target = CGPoint(
                x: settlement.worldPosition.x + cos(scatterAngle) * scatterDist,
                y: settlement.worldPosition.y + sin(scatterAngle) * scatterDist
            )
        } else {
            // Target HQ center with scatter
            let hqCenter: CGPoint
            if let gridMap {
                let hqRow = Constants.TowerDefense.gridRows - 1
                let hqCol = Constants.TowerDefense.gridCols / 2
                hqCenter = gridMap.worldPosition(forRow: hqRow, col: hqCol)
            } else {
                hqCenter = CGPoint(x: frame.midX, y: 60)
            }
            let scatterAngle = CGFloat.random(in: 0...(2 * .pi))
            let scatterDist = CGFloat.random(in: 0...40)
            target = CGPoint(
                x: hqCenter.x + cos(scatterAngle) * scatterDist,
                y: hqCenter.y + sin(scatterAngle) * scatterDist
            )
        }

        let kamikaze = KamikazeDroneEntity(sceneFrame: frame)
        kamikaze.targetSettlement = targetSettlementRef

        let altitude: DroneAltitude = Bool.random() ? .low : .micro
        kamikaze.addComponent(AltitudeComponent(altitude: altitude))
        let shadow = ShadowComponent()
        kamikaze.addComponent(shadow)
        shadowLayer?.addChild(shadow.shadowNode)

        if let spriteNode = kamikaze.component(ofType: SpriteComponent.self)?.spriteNode {
            let scale = Constants.Kamikaze.spriteScale * altitude.droneVisualScale
            spriteNode.size = CGSize(width: 12 * scale, height: 14 * scale)
            spriteNode.zPosition = 61 + CGFloat(altitude.rawValue) * 5
        }

        kamikaze.configureFlight(from: spawnPoint, to: target, speed: Constants.Kamikaze.speed)

        activeDrones.append(kamikaze)
        addEntity(kamikaze)
    }

    // MARK: - EW Drone Spawn

    func spawnEWDrone() {
        let spawnX = CGFloat.random(in: 20...(frame.width - 20))
        let spawnY = frame.height + CGFloat.random(in: 30...50)
        let spawnPoint = CGPoint(x: spawnX, y: spawnY)

        let hqCenter: CGPoint
        if let gridMap {
            let hqRow = Constants.TowerDefense.gridRows - 1
            let hqCol = Constants.TowerDefense.gridCols / 2
            hqCenter = gridMap.worldPosition(forRow: hqRow, col: hqCol)
        } else {
            hqCenter = CGPoint(x: frame.midX, y: 60)
        }

        let ewDrone = EWDroneEntity(sceneFrame: frame)
        let altitude: DroneAltitude = .high
        ewDrone.addComponent(AltitudeComponent(altitude: altitude))
        let shadow = ShadowComponent()
        ewDrone.addComponent(shadow)
        shadowLayer?.addChild(shadow.shadowNode)

        if let spriteNode = ewDrone.component(ofType: SpriteComponent.self)?.spriteNode {
            let scale = altitude.droneVisualScale
            spriteNode.size = CGSize(width: 24 * scale, height: 24 * scale)
            spriteNode.zPosition = 61 + CGFloat(altitude.rawValue) * 5
        }

        ewDrone.configureFlight(from: spawnPoint, to: hqCenter, speed: Constants.EW.ewDroneSpeed)

        activeDrones.append(ewDrone)
        addEntity(ewDrone)
    }

    // MARK: - Heavy Drone Spawn

    func spawnHeavyDrone() {
        guard let gridMap else { return }
        let pathDefs = selectedLevel.dronePaths
        guard !pathDefs.isEmpty else { return }

        let pathDef = pathDefs.randomElement()!
        let waypoints = pathDef.gridWaypoints.map { wp in
            gridMap.worldPosition(forRow: wp.row, col: wp.col)
        }
        guard !waypoints.isEmpty else { return }

        let spawnWaypoints = waypoints.enumerated().map { index, wp -> CGPoint in
            if index == 0 {
                return CGPoint(x: wp.x + CGFloat.random(in: -15...15), y: wp.y + 40)
            }
            if index == waypoints.count - 1 {
                return CGPoint(x: wp.x + CGFloat.random(in: -5...5), y: wp.y)
            }
            return CGPoint(x: wp.x + CGFloat.random(in: -10...10), y: wp.y + CGFloat.random(in: -6...6))
        }

        let flightPath = DroneFlightPath(waypoints: spawnWaypoints, altitude: .medium, spawnEdge: pathDef.spawnEdge)
        let heavyDrone = HeavyDroneEntity(sceneFrame: frame, flightPath: flightPath)

        let altitude: DroneAltitude = .medium
        heavyDrone.addComponent(AltitudeComponent(altitude: altitude))
        let shadow = ShadowComponent()
        heavyDrone.addComponent(shadow)
        shadowLayer?.addChild(shadow.shadowNode)

        if let spriteNode = heavyDrone.component(ofType: SpriteComponent.self)?.spriteNode {
            let scale = Constants.AdvancedEnemies.heavyDroneSpriteScale * altitude.droneVisualScale
            spriteNode.size = CGSize(width: 30 * scale, height: 30 * scale)
            spriteNode.zPosition = 61 + CGFloat(altitude.rawValue) * 5
        }

        activeDrones.append(heavyDrone)
        addEntity(heavyDrone)
    }

    // MARK: - Cruise Missile Spawn

    func spawnCruiseMissile() {
        let spawnEdge = Bool.random() // true = left, false = right
        let spawnX: CGFloat = spawnEdge ? -20 : frame.width + 20
        let spawnY = CGFloat.random(in: frame.height * 0.4...frame.height * 0.8)
        let spawnPoint = CGPoint(x: spawnX, y: spawnY)

        let hqCenter: CGPoint
        if let gridMap {
            let hqRow = Constants.TowerDefense.gridRows - 1
            let hqCol = Constants.TowerDefense.gridCols / 2
            hqCenter = gridMap.worldPosition(forRow: hqRow, col: hqCol)
        } else {
            hqCenter = CGPoint(x: frame.midX, y: 60)
        }

        let cruise = CruiseMissileEntity(sceneFrame: frame)
        let altitude: DroneAltitude = .cruise
        cruise.addComponent(AltitudeComponent(altitude: altitude))
        let shadow = ShadowComponent()
        cruise.addComponent(shadow)
        shadowLayer?.addChild(shadow.shadowNode)

        if let spriteNode = cruise.component(ofType: SpriteComponent.self)?.spriteNode {
            let scale = altitude.droneVisualScale
            spriteNode.size = CGSize(width: 8 * scale, height: 22 * scale)
            spriteNode.zPosition = 61 + CGFloat(altitude.rawValue) * 5
        }

        let speed = CGFloat.random(in: Constants.AdvancedEnemies.cruiseMissileMinSpeed...Constants.AdvancedEnemies.cruiseMissileMaxSpeed)
        cruise.configureFlight(from: spawnPoint, to: hqCenter, speed: speed)

        activeDrones.append(cruise)
        addEntity(cruise)
    }

    // MARK: - Swarm Cloud Spawn

    func spawnSwarmCloud() {
        let spawnX = CGFloat.random(in: 40...(frame.width - 40))
        let spawnY = frame.height + 30

        let hqCenter: CGPoint
        if let gridMap {
            let hqRow = Constants.TowerDefense.gridRows - 1
            let hqCol = Constants.TowerDefense.gridCols / 2
            hqCenter = gridMap.worldPosition(forRow: hqRow, col: hqCol)
        } else {
            hqCenter = CGPoint(x: frame.midX, y: 60)
        }

        let swarm = SwarmCloudEntity(
            sceneFrame: frame,
            spawnCenter: CGPoint(x: spawnX, y: spawnY),
            target: hqCenter
        )

        for drone in swarm.swarmDrones {
            drone.addComponent(AltitudeComponent(altitude: .micro))
            let shadow = ShadowComponent(baseSize: CGSize(width: 8, height: 4))
            drone.addComponent(shadow)
            shadowLayer?.addChild(shadow.shadowNode)

            activeDrones.append(drone)
            addEntity(drone)
        }
        activeSwarmClouds.append(swarm)
    }

    // MARK: - Game Events

    func onDroneDestroyed(drone: AttackDroneEntity? = nil) {
        guard currentPhase == .combat else { return }
        if let drone, !activeDrones.contains(drone) { return }

        let scoreDelta: Int
        let resourceDelta: Int
        if drone is OrlanDroneEntity {
            scoreDelta = Constants.Orlan.scorePerKill
            resourceDelta = Constants.Orlan.reward
        } else if drone is LancetDroneEntity {
            scoreDelta = Constants.Lancet.scorePerKill
            resourceDelta = Constants.Lancet.reward
        } else if drone is ShahedDroneEntity {
            scoreDelta = Constants.Shahed.scorePerKill
            resourceDelta = Constants.Shahed.reward
        } else if drone is KamikazeDroneEntity {
            scoreDelta = Constants.Kamikaze.scorePerKill
            resourceDelta = Constants.Kamikaze.reward
        } else if drone is EWDroneEntity {
            scoreDelta = Constants.EW.ewDroneScore
            resourceDelta = Constants.EW.ewDroneReward
        } else if drone is HeavyDroneEntity {
            scoreDelta = Constants.AdvancedEnemies.heavyDroneScore
            resourceDelta = Constants.AdvancedEnemies.heavyDroneReward
        } else if drone is CruiseMissileEntity {
            scoreDelta = Constants.AdvancedEnemies.cruiseMissileScore
            resourceDelta = Constants.AdvancedEnemies.cruiseMissileReward
        } else if drone is HarmMissileEntity {
            scoreDelta = Constants.GameBalance.scorePerHarmMissile
            resourceDelta = Constants.GameBalance.resourcesPerHarmMissileKill
        } else if drone is EnemyMissileEntity {
            scoreDelta = Constants.GameBalance.scorePerMissile
            resourceDelta = Constants.GameBalance.resourcesPerMissileKill
        } else if drone is MineLayerDroneEntity {
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
        // Shield blocks all HQ damage
        if militaryAidManager.isShieldActive {
            // Visual: shield flash on absorb
            if let shieldNode = childNode(withName: "//hqShield") {
                shieldNode.run(SKAction.sequence([
                    SKAction.scale(to: 1.4, duration: 0.1),
                    SKAction.scale(to: 1.0, duration: 0.2)
                ]))
            }
            return
        }
        if drone is KamikazeDroneEntity {
            lives -= Constants.Kamikaze.hqDamage
            if let pos = drone?.component(ofType: SpriteComponent.self)?.spriteNode.position {
                spawnBombExplosion(at: pos)
            }
        } else if drone is CruiseMissileEntity {
            lives -= Constants.AdvancedEnemies.cruiseMissileHQDamage
            if let pos = drone?.component(ofType: SpriteComponent.self)?.spriteNode.position {
                spawnBombExplosion(at: pos)
            }
        } else if drone is EnemyMissileEntity {
            lives -= Constants.GameBalance.enemyMissileHQDamage
            if let pos = drone?.component(ofType: SpriteComponent.self)?.spriteNode.position {
                spawnBombExplosion(at: pos)
            }
        } else {
            lives -= 1
        }
        updateHUD()
        if lives <= 0 {
            triggerGameOver()
        }
    }

    func onDroneReachedSettlement(drone: AttackDroneEntity, settlement: SettlementEntity) {
        guard currentPhase == .combat else { return }
        guard !drone.isHit else { return }

        // Shield blocks all damage
        if militaryAidManager.isShieldActive {
            if let shieldNode = childNode(withName: "//hqShield") {
                shieldNode.run(SKAction.sequence([
                    SKAction.scale(to: 1.4, duration: 0.1),
                    SKAction.scale(to: 1.0, duration: 0.2)
                ]))
            }
            return
        }

        // Damage settlement
        let wasDestroyed = settlementManager?.damageSettlement(settlement, amount: 1) ?? false

        // Reduce global lives based on drone type
        if drone is KamikazeDroneEntity {
            lives -= Constants.Settlement.kamikazeDamageToLives
        } else if drone is CruiseMissileEntity {
            lives -= Constants.Settlement.cruiseMissileDamageToLives
        } else {
            lives -= Constants.Settlement.droneDamageToLives
        }

        spawnBombExplosion(at: settlement.worldPosition)

        if wasDestroyed {
            onSettlementDestroyed(settlement)
        }

        updateHUD()
        if lives <= 0 {
            triggerGameOver()
        }
    }

    private func onSettlementDestroyed(_ settlement: SettlementEntity) {
        // Retarget all drones that were heading to this settlement
        retargetDronesFrom(destroyedSettlement: settlement)
    }

    private func retargetDronesFrom(destroyedSettlement: SettlementEntity) {
        guard let gridMap else { return }
        let hqRow = Constants.TowerDefense.gridRows - 1
        let hqCol = Constants.TowerDefense.gridCols / 2
        let hqPoint = gridMap.worldPosition(forRow: hqRow, col: hqCol)

        let aliveSettlements = settlementManager?.aliveSettlements() ?? []

        for drone in activeDrones {
            guard !drone.isHit, drone.targetSettlement === destroyedSettlement else { continue }
            guard let dronePos = drone.component(ofType: SpriteComponent.self)?.spriteNode.position else { continue }

            // Find nearest alive settlement
            let nearest = aliveSettlements.min(by: { a, b in
                let distA = hypot(dronePos.x - a.worldPosition.x, dronePos.y - a.worldPosition.y)
                let distB = hypot(dronePos.x - b.worldPosition.x, dronePos.y - b.worldPosition.y)
                return distA < distB
            })

            if let newTarget = nearest {
                drone.targetSettlement = newTarget
                // Rebuild path: current position → new settlement → HQ
                let waypoints = generateSettlementPath(
                    from: dronePos, through: newTarget.worldPosition, to: hqPoint
                )
                drone.retargetPath(waypoints: waypoints)
            } else {
                // No alive settlements — fly straight to HQ
                drone.targetSettlement = nil
                let waypoints = generateSettlementPath(from: dronePos, to: hqPoint)
                drone.retargetPath(waypoints: waypoints)
            }
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

    // MARK: - Military Aid Overlay

    private func showMilitaryAidOverlay() {
        let options = militaryAidManager.generateOptions()
        guard options.count == 3 else { return }

        let overlay = SKNode()
        overlay.name = "militaryAidOverlay"
        overlay.zPosition = 100
        addChild(overlay)

        // Semi-transparent background
        let bg = SKSpriteNode(color: UIColor.black.withAlphaComponent(0.7), size: frame.size)
        bg.position = CGPoint(x: frame.midX, y: frame.midY)
        overlay.addChild(bg)

        // Title
        let title = SKLabelNode(fontNamed: Constants.GameBalance.hudFontName)
        title.text = "ВОЕННАЯ ПОМОЩЬ"
        title.fontSize = 28
        title.fontColor = .systemYellow
        title.position = CGPoint(x: frame.midX, y: frame.midY + 180)
        overlay.addChild(title)

        let subtitle = SKLabelNode(fontNamed: Constants.GameBalance.hudFontName)
        subtitle.text = "Выберите усиление"
        subtitle.fontSize = 16
        subtitle.fontColor = UIColor.white.withAlphaComponent(0.7)
        subtitle.position = CGPoint(x: frame.midX, y: frame.midY + 152)
        overlay.addChild(subtitle)

        // 3 upgrade cards
        let cardWidth: CGFloat = min(frame.width * 0.28, 110)
        let cardHeight: CGFloat = 160
        let spacing: CGFloat = 10
        let totalWidth = cardWidth * 3 + spacing * 2
        let startX = frame.midX - totalWidth / 2 + cardWidth / 2

        for (i, upgrade) in options.enumerated() {
            let cardX = startX + CGFloat(i) * (cardWidth + spacing)
            let cardY = frame.midY - 10

            // Card background
            let card = SKSpriteNode(color: UIColor.darkGray.withAlphaComponent(0.85),
                                    size: CGSize(width: cardWidth, height: cardHeight))
            card.position = CGPoint(x: cardX, y: cardY)
            card.name = "aidCard_\(i)"
            overlay.addChild(card)

            // Color accent bar at top
            let accent = SKSpriteNode(color: upgrade.color,
                                      size: CGSize(width: cardWidth, height: 6))
            accent.position = CGPoint(x: 0, y: cardHeight / 2 - 3)
            accent.name = "aidCard_\(i)"
            card.addChild(accent)

            // Title
            let titleLabel = SKLabelNode(fontNamed: Constants.GameBalance.hudFontName)
            titleLabel.text = upgrade.title
            titleLabel.fontSize = 12
            titleLabel.fontColor = upgrade.color
            titleLabel.position = CGPoint(x: 0, y: cardHeight / 2 - 30)
            titleLabel.verticalAlignmentMode = .center
            titleLabel.name = "aidCard_\(i)"
            card.addChild(titleLabel)

            // Description (word-wrapped manually)
            let desc = upgrade.description
            let descLines = wrapText(desc, maxChars: 14)
            for (lineIdx, line) in descLines.enumerated() {
                let descLabel = SKLabelNode(fontNamed: Constants.GameBalance.hudFontName)
                descLabel.text = line
                descLabel.fontSize = 11
                descLabel.fontColor = .white
                descLabel.position = CGPoint(x: 0, y: 10 - CGFloat(lineIdx) * 16)
                descLabel.verticalAlignmentMode = .center
                descLabel.name = "aidCard_\(i)"
                card.addChild(descLabel)
            }

            // Appear animation
            card.setScale(0.5)
            card.alpha = 0
            let delay = SKAction.wait(forDuration: Double(i) * 0.12)
            let appear = SKAction.group([
                SKAction.scale(to: 1.0, duration: 0.25),
                SKAction.fadeIn(withDuration: 0.2)
            ])
            appear.timingMode = .easeOut
            card.run(SKAction.sequence([delay, appear]))
        }
    }

    private func wrapText(_ text: String, maxChars: Int) -> [String] {
        let words = text.split(separator: " ")
        var lines: [String] = []
        var currentLine = ""
        for word in words {
            if currentLine.isEmpty {
                currentLine = String(word)
            } else if currentLine.count + 1 + word.count <= maxChars {
                currentLine += " " + word
            } else {
                lines.append(currentLine)
                currentLine = String(word)
            }
        }
        if !currentLine.isEmpty { lines.append(currentLine) }
        return lines
    }

    private func handleMilitaryAidSelection(cardIndex: Int) {
        let options = militaryAidManager.currentOptions
        guard cardIndex >= 0 && cardIndex < options.count else { return }

        let selected = options[cardIndex]
        applyMilitaryAid(selected)

        // Flash selected card, then dismiss overlay
        enumerateChildNodes(withName: "//militaryAidOverlay") { overlay, _ in
            overlay.enumerateChildNodes(withName: "aidCard_\(cardIndex)") { card, _ in
                if card is SKSpriteNode && card.parent === overlay {
                    card.run(SKAction.colorize(with: .white, colorBlendFactor: 0.5, duration: 0.15))
                }
            }
            let dismiss = SKAction.sequence([
                SKAction.wait(forDuration: 0.4),
                SKAction.fadeOut(withDuration: 0.2),
                SKAction.removeFromParent()
            ])
            overlay.run(dismiss) { [weak self] in
                self?.resumeAfterMilitaryAid()
            }
        }
        militaryAidManager.currentOptions = []
        updateHUD()
    }

    private func applyMilitaryAid(_ type: MilitaryAidType) {
        switch type {
        case .funding:
            economyManager.earn(200)
            showAidFloatingText("+200 DP", color: .systemYellow)

        case .fortification:
            lives += 5
            showAidFloatingText("+5 HP", color: .systemBlue)

        case .airstrike:
            let targets = activeDrones.filter { !$0.isHit }.prefix(8)
            for drone in targets {
                drone.takeDamage(999)
                if let pos = drone.component(ofType: SpriteComponent.self)?.spriteNode.position {
                    spawnAirstrikeExplosion(at: pos)
                }
                onDroneDestroyed(drone: drone)
            }
            if targets.isEmpty {
                showAidFloatingText("НЕТ ЦЕЛЕЙ", color: .gray)
            }

        case .repairAll:
            for tower in towerPlacement.towers {
                guard let stats = tower.stats, stats.isDisabled else { continue }
                tower.fullRepair()
                // White flash on repaired tower
                if let sprite = tower.component(ofType: SpriteComponent.self)?.spriteNode {
                    let flash = SKSpriteNode(color: .white, size: CGSize(width: 36, height: 36))
                    flash.position = sprite.position
                    flash.zPosition = 40
                    addChild(flash)
                    flash.run(SKAction.sequence([
                        SKAction.fadeOut(withDuration: 0.5),
                        SKAction.removeFromParent()
                    ]))
                }
            }

        case .shieldHQ:
            militaryAidManager.activateShield()
            showShieldEffect()

        case .reloadAll:
            for tower in towerPlacement.towers {
                guard let stats = tower.stats else { continue }
                stats.replenishMagazine()
            }
            showAidFloatingText("ЗРК ПЕРЕЗАРЯЖЕНЫ", color: .systemOrange)

        case .slowField:
            for drone in activeDrones where !drone.isHit {
                drone.speed *= 0.4
                // Visual: blue tint on slowed drones
                if let sprite = drone.component(ofType: SpriteComponent.self)?.spriteNode {
                    sprite.run(SKAction.colorize(with: .cyan, colorBlendFactor: 0.4, duration: 0.2))
                }
            }
            // Revert after 10 seconds
            run(SKAction.sequence([
                SKAction.wait(forDuration: 10.0),
                SKAction.run { [weak self] in
                    guard let self else { return }
                    for drone in self.activeDrones where !drone.isHit {
                        drone.speed /= 0.4
                        if let sprite = drone.component(ofType: SpriteComponent.self)?.spriteNode {
                            sprite.run(SKAction.colorize(withColorBlendFactor: 0, duration: 0.3))
                        }
                    }
                }
            ]))
            showAidFloatingText("РЭБ АКТИВИРОВАНО", color: .systemPurple)

        case .bonusWave:
            for i in 0..<5 {
                run(SKAction.sequence([
                    SKAction.wait(forDuration: Double(i) * 0.5),
                    SKAction.run { [weak self] in self?.spawnBonusDrone() }
                ]))
            }
        }
    }

    private func showAidFloatingText(_ text: String, color: UIColor) {
        let label = SKLabelNode(fontNamed: Constants.GameBalance.hudFontName)
        label.text = text
        label.fontSize = 24
        label.fontColor = color
        label.position = CGPoint(x: frame.midX, y: frame.midY - 60)
        label.zPosition = 99
        addChild(label)
        label.run(SKAction.sequence([
            SKAction.group([
                SKAction.moveBy(x: 0, y: 60, duration: 1.2),
                SKAction.sequence([
                    SKAction.wait(forDuration: 0.8),
                    SKAction.fadeOut(withDuration: 0.4)
                ])
            ]),
            SKAction.removeFromParent()
        ]))
    }

    private func spawnAirstrikeExplosion(at pos: CGPoint) {
        let flash = SKSpriteNode(color: .orange, size: CGSize(width: 30, height: 30))
        flash.position = pos
        flash.zPosition = 80
        addChild(flash)
        flash.run(SKAction.sequence([
            SKAction.group([
                SKAction.scale(to: 3.0, duration: 0.25),
                SKAction.fadeOut(withDuration: 0.3)
            ]),
            SKAction.removeFromParent()
        ]))
    }

    private func showShieldEffect() {
        guard let gridMap else { return }
        let hqPos = gridMap.worldPosition(
            forRow: Constants.TowerDefense.gridRows - 1,
            col: Constants.TowerDefense.gridCols / 2
        )
        let shield = SKShapeNode(circleOfRadius: 40)
        shield.strokeColor = .cyan
        shield.fillColor = UIColor.cyan.withAlphaComponent(0.15)
        shield.lineWidth = 2
        shield.position = hqPos
        shield.zPosition = 90
        shield.name = "hqShield"
        addChild(shield)
        // Pulse animation
        shield.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.scale(to: 1.1, duration: 0.8),
            SKAction.scale(to: 0.95, duration: 0.8),
        ])))
    }

    /// Spawn a slow, visible bonus drone worth extra DP
    private func spawnBonusDrone() {
        guard let gridMap else { return }
        let pathDefs = selectedLevel.dronePaths
        guard let pathDef = pathDefs.randomElement() else { return }
        let waypoints = pathDef.gridWaypoints.map { wp in
            gridMap.worldPosition(forRow: wp.row, col: wp.col)
        }
        guard !waypoints.isEmpty else { return }
        let jittered = waypoints.enumerated().map { i, wp -> CGPoint in
            if i == 0 { return CGPoint(x: wp.x + .random(in: -15...15), y: wp.y + 40) }
            if i == waypoints.count - 1 { return CGPoint(x: wp.x, y: wp.y) }
            return CGPoint(x: wp.x + .random(in: -10...10), y: wp.y + .random(in: -8...8))
        }
        let flightPath = DroneFlightPath(waypoints: jittered, altitude: .low, spawnEdge: pathDef.spawnEdge)
        let drone = AttackDroneEntity(damage: 1, speed: 30, imageName: "Drone", flyingPath: flightPath.toFlyingPath())
        drone.configureHealth(1)
        drone.addComponent(AltitudeComponent(altitude: .low))
        let shadow = ShadowComponent()
        drone.addComponent(shadow)
        shadowLayer?.addChild(shadow.shadowNode)
        // Gold color — bonus target
        if let sprite = drone.component(ofType: SpriteComponent.self)?.spriteNode {
            sprite.color = .systemYellow
            sprite.colorBlendFactor = 1.0
            sprite.size = CGSize(width: 26, height: 26)
            sprite.zPosition = 62
        }
        activeDrones.append(drone)
        addEntity(drone)
    }

    private func resumeAfterMilitaryAid() {
        interWaveCountdown = normalWaveCountdown
        startWaveButton?.isHidden = false
        updateStartWaveButton()
    }

    private var hasMilitaryAidOverlay: Bool {
        childNode(withName: "//militaryAidOverlay") != nil
    }

    // MARK: - Enemy Missile Salvo

    func showMissileWarning() {
        let warning = SKLabelNode(fontNamed: Constants.GameBalance.hudFontName)
        warning.text = "INCOMING"
        warning.fontSize = 32
        warning.fontColor = .red
        warning.position = CGPoint(x: frame.midX, y: frame.height - safeTop - 80)
        warning.zPosition = 97
        warning.alpha = 0
        warning.name = "missileWarning"
        addChild(warning)

        let fadeIn = SKAction.fadeIn(withDuration: 0.15)
        let pulse = SKAction.sequence([
            SKAction.scale(to: 1.15, duration: 0.3),
            SKAction.scale(to: 0.9, duration: 0.3)
        ])
        let pulseForever = SKAction.repeat(pulse, count: 3)
        let fadeOut = SKAction.fadeOut(withDuration: 0.3)
        let remove = SKAction.removeFromParent()
        warning.run(SKAction.sequence([fadeIn, pulseForever, fadeOut, remove]))

        // Red edge tint
        let tint = SKSpriteNode(color: UIColor.red.withAlphaComponent(0.15), size: frame.size)
        tint.position = CGPoint(x: frame.midX, y: frame.midY)
        tint.zPosition = 96
        tint.alpha = 0
        addChild(tint)
        tint.run(SKAction.sequence([
            SKAction.fadeAlpha(to: 0.3, duration: 0.2),
            SKAction.fadeOut(withDuration: 1.0),
            SKAction.removeFromParent()
        ]))
    }

    func spawnMissileSalvo(waveNumber: Int) {
        let gb = Constants.GameBalance.self
        let firstWave = gb.enemyMissileFirstWave
        let salvoSize = min(
            gb.enemyMissileBaseSalvoSize + (waveNumber - firstWave) / gb.enemyMissileSalvoGrowthInterval,
            gb.enemyMissileMaxSalvoSize
        )

        pendingMissileSpawns += salvoSize
        for i in 0..<salvoSize {
            let delay = TimeInterval(i) * gb.enemyMissileInSalvoInterval
            let spawnAction = SKAction.sequence([
                SKAction.wait(forDuration: delay),
                SKAction.run { [weak self] in
                    self?.spawnSingleMissile(waveNumber: waveNumber)
                }
            ])
            run(spawnAction)
        }
    }

    private func spawnSingleMissile(waveNumber: Int) {
        pendingMissileSpawns = max(0, pendingMissileSpawns - 1)
        let gb = Constants.GameBalance.self
        let spawnX = CGFloat.random(in: 20...(frame.width - 20))
        let spawnY = frame.height + CGFloat.random(in: 30...50)
        let spawnPoint = CGPoint(x: spawnX, y: spawnY)

        // Target: HQ center + scatter
        let hqCenter: CGPoint
        if let gridMap {
            // HQ is at bottom center of the grid
            let hqRow = Constants.TowerDefense.gridRows - 1
            let hqCol = Constants.TowerDefense.gridCols / 2
            hqCenter = gridMap.worldPosition(forRow: hqRow, col: hqCol)
        } else {
            hqCenter = CGPoint(x: frame.midX, y: 60)
        }

        let scatterAngle = CGFloat.random(in: 0...(2 * .pi))
        let scatterDist = CGFloat.random(in: 0...gb.enemyMissileScatterRadius)
        let target = CGPoint(
            x: hqCenter.x + cos(scatterAngle) * scatterDist,
            y: hqCenter.y + sin(scatterAngle) * scatterDist
        )

        let missileSpeed = gb.enemyMissileBaseSpeed + CGFloat.random(in: -gb.enemyMissileSpeedVariance...gb.enemyMissileSpeedVariance)

        let missile = EnemyMissileEntity(sceneFrame: frame)

        // Add altitude component
        missile.addComponent(AltitudeComponent(altitude: .ballistic))
        let shadow = ShadowComponent()
        missile.addComponent(shadow)
        shadowLayer?.addChild(shadow.shadowNode)

        // Scale and zPosition for ballistic altitude
        if let spriteNode = missile.component(ofType: SpriteComponent.self)?.spriteNode {
            let scale = DroneAltitude.ballistic.droneVisualScale
            spriteNode.size = CGSize(width: 6 * scale, height: 18 * scale)
            spriteNode.zPosition = 61 + CGFloat(DroneAltitude.ballistic.rawValue) * 5
        }

        missile.configureFlight(from: spawnPoint, to: target, speed: missileSpeed)

        activeDrones.append(missile)
        addEntity(missile)
    }

    // MARK: - HARM (Anti-Radiation) Missile

    func showHarmWarning() {
        let warning = SKLabelNode(fontNamed: Constants.GameBalance.hudFontName)
        warning.text = "ПРР"
        warning.fontSize = 32
        warning.fontColor = .yellow
        warning.position = CGPoint(x: frame.midX, y: frame.height - safeTop - 120)
        warning.zPosition = 97
        warning.alpha = 0
        warning.name = "harmWarning"
        addChild(warning)

        let fadeIn = SKAction.fadeIn(withDuration: 0.15)
        let pulse = SKAction.sequence([
            SKAction.scale(to: 1.15, duration: 0.3),
            SKAction.scale(to: 0.9, duration: 0.3)
        ])
        let pulseForever = SKAction.repeat(pulse, count: 3)
        let fadeOut = SKAction.fadeOut(withDuration: 0.3)
        let remove = SKAction.removeFromParent()
        warning.run(SKAction.sequence([fadeIn, pulseForever, fadeOut, remove]))

        // Amber edge tint
        let tint = SKSpriteNode(color: UIColor.yellow.withAlphaComponent(0.12), size: frame.size)
        tint.position = CGPoint(x: frame.midX, y: frame.midY)
        tint.zPosition = 96
        tint.alpha = 0
        addChild(tint)
        tint.run(SKAction.sequence([
            SKAction.fadeAlpha(to: 0.3, duration: 0.2),
            SKAction.fadeOut(withDuration: 1.0),
            SKAction.removeFromParent()
        ]))
    }

    func selectHarmTargets(salvoSize: Int) -> [TowerEntity] {
        // Filter radar-emitting towers that are not disabled
        let radarEmitters = towerPlacement.towers.filter { tower in
            guard let stats = tower.stats, !stats.isDisabled else { return false }
            return stats.towerType == .samLauncher || stats.towerType == .interceptor || stats.towerType == .radar
        }

        // Exclude towers already targeted by in-flight HARMs
        let alreadyTargeted = Set(activeDrones.compactMap { ($0 as? HarmMissileEntity)?.targetTower }.map { ObjectIdentifier($0) })
        let available = radarEmitters.filter { !alreadyTargeted.contains(ObjectIdentifier($0)) }

        guard !available.isEmpty else { return [] }

        // Sort by priority: S-300 > PRCH > RLS
        let sorted = available.sorted { a, b in
            let priorityA = harmTargetPriority(a)
            let priorityB = harmTargetPriority(b)
            return priorityA > priorityB
        }

        // Assign 1 HARM per unique tower first, then wrap around
        var targets = [TowerEntity]()
        for i in 0..<salvoSize {
            let index = i % sorted.count
            targets.append(sorted[index])
        }
        return targets
    }

    private func harmTargetPriority(_ tower: TowerEntity) -> Int {
        guard let stats = tower.stats else { return 0 }
        switch stats.towerType {
        case .samLauncher: return 3
        case .interceptor: return 2
        case .radar: return 1
        default: return 0
        }
    }

    func spawnHarmSalvo(waveNumber: Int) {
        let gb = Constants.GameBalance.self
        let firstWave = gb.harmMissileFirstWave
        let salvoSize = min(
            gb.harmMissileBaseSalvoSize + (waveNumber - firstWave) / gb.harmMissileSalvoGrowthInterval,
            gb.harmMissileMaxSalvoSize
        )

        let targets = selectHarmTargets(salvoSize: salvoSize)
        guard !targets.isEmpty else { return }

        pendingHarmSpawns += targets.count
        for (i, tower) in targets.enumerated() {
            let delay = TimeInterval(i) * gb.harmMissileInSalvoInterval
            let spawnAction = SKAction.sequence([
                SKAction.wait(forDuration: delay),
                SKAction.run { [weak self, weak tower] in
                    guard let self, let tower else {
                        self?.pendingHarmSpawns = max(0, (self?.pendingHarmSpawns ?? 1) - 1)
                        return
                    }
                    self.spawnSingleHarm(targetTower: tower)
                }
            ])
            run(spawnAction)
        }
    }

    private func spawnSingleHarm(targetTower tower: TowerEntity) {
        pendingHarmSpawns = max(0, pendingHarmSpawns - 1)

        // Re-check tower not disabled at spawn time
        if let stats = tower.stats, stats.isDisabled { return }

        let gb = Constants.GameBalance.self
        let spawnX = CGFloat.random(in: 20...(frame.width - 20))
        let spawnY = frame.height + CGFloat.random(in: 30...50)
        let spawnPoint = CGPoint(x: spawnX, y: spawnY)

        let missileSpeed = gb.harmMissileBaseSpeed + CGFloat.random(in: -gb.harmMissileSpeedVariance...gb.harmMissileSpeedVariance)

        let harm = HarmMissileEntity(sceneFrame: frame)

        // Add altitude component — cruise altitude
        harm.addComponent(AltitudeComponent(altitude: .cruise))
        let shadow = ShadowComponent()
        harm.addComponent(shadow)
        shadowLayer?.addChild(shadow.shadowNode)

        // Scale and zPosition for cruise altitude
        if let spriteNode = harm.component(ofType: SpriteComponent.self)?.spriteNode {
            let scale = DroneAltitude.cruise.droneVisualScale
            spriteNode.size = CGSize(width: 7 * scale, height: 20 * scale)
            spriteNode.zPosition = 61 + CGFloat(DroneAltitude.cruise.rawValue) * 5
        }

        harm.configureFlight(from: spawnPoint, toTower: tower, speed: missileSpeed)

        activeDrones.append(harm)
        addEntity(harm)
    }

    func onHarmHitTower(harm: HarmMissileEntity) {
        guard let tower = harm.targetTower,
              let stats = tower.stats else { return }
        tower.takeBombDamage(Constants.GameBalance.harmMissileTowerDamage)

        // Impact explosion VFX
        if let pos = harm.component(ofType: SpriteComponent.self)?.spriteNode.position {
            let flash = SKSpriteNode(color: .orange, size: CGSize(width: 20, height: 20))
            flash.position = pos
            flash.zPosition = isNightWave ? Constants.NightWave.nightEffectZPosition : 50
            flash.alpha = 0.8
            addChild(flash)
            let expand = SKAction.scale(to: 2.5, duration: 0.2)
            let fade = SKAction.fadeOut(withDuration: 0.2)
            flash.run(SKAction.sequence([SKAction.group([expand, fade]), SKAction.removeFromParent()]))
        }
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
        flash.zPosition = isNightWave ? Constants.NightWave.nightEffectZPosition : 50
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

        let hqThreshold = gridMap.origin.y + gridMap.cellSize.height

        for drone in snapshot {
            guard let droneNode = drone.component(ofType: SpriteComponent.self)?.spriteNode else {
                removeEntity(drone)
                continue
            }
            if droneNode.parent == nil {
                removeEntity(drone)
                continue
            }

            // Check if drone passes through its target settlement (settlement is a waypoint, not endpoint)
            if !drone.isHit, let target = drone.targetSettlement, !target.isDestroyed {
                let targetPos = target.worldPosition
                let dist = hypot(droneNode.position.x - targetPos.x,
                                 droneNode.position.y - targetPos.y)
                let hitRadius = gridMap.cellSize.width * 1.5
                if dist < hitRadius {
                    onDroneReachedSettlement(drone: drone, settlement: target)
                    // Clear target so we don't damage it again on subsequent frames
                    drone.targetSettlement = nil
                    // Don't remove drone — it continues flying to HQ
                }
            }

            // HARM missiles that pass their target just miss — no HQ damage
            if let harm = drone as? HarmMissileEntity, !drone.isHit, droneNode.position.y < hqThreshold {
                harm.reachedDestination()
                removeEntity(drone)
                continue
            }

            // Check if drone reached HQ area (bottom of map)
            if !drone.isHit && droneNode.position.y < hqThreshold {
                onDroneReachedHQ(drone: drone)
                drone.reachedDestination()
                removeEntity(drone)
                continue
            }

            // Remove drones that went far off screen (ghost cleanup)
            if droneNode.position.y < -50 || droneNode.position.y > frame.height + 100 ||
               droneNode.position.x < -100 || droneNode.position.x > frame.width + 100 {
                let noDamageTypes: Bool = drone is HarmMissileEntity || drone is EWDroneEntity ||
                    (drone is HeavyDroneEntity && droneNode.position.y > frame.height)
                if !drone.isHit && !noDamageTypes { onDroneReachedHQ(drone: drone) }
                removeEntity(drone)
                continue
            }

            // Update shadow in same pass (avoids separate iteration)
            if let shadow = drone.component(ofType: ShadowComponent.self),
               let altitude = drone.component(ofType: AltitudeComponent.self)?.altitude {
                shadow.updateShadow(dronePosition: droneNode.position, altitude: altitude)
            }
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

    /// Returns true and increments budget if a rocket is allowed to retarget this frame.
    func consumeRetargetBudget() -> Bool {
        guard rocketRetargetBudget < maxRetargetsPerFrame else { return false }
        rocketRetargetBudget += 1
        return true
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

    private static let blastTexture: SKTexture = {
        let d: CGFloat = 64
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: d, height: d))
        let image = renderer.image { ctx in
            UIColor.white.setFill()
            ctx.cgContext.fillEllipse(in: CGRect(x: 0, y: 0, width: d, height: d))
        }
        return SKTexture(image: image)
    }()

    func spawnRocketBlast(at position: CGPoint, radius: CGFloat, damage: Int = 1) {
        let blast = SKSpriteNode(texture: Self.blastTexture)
        blast.size = CGSize(width: radius * 2, height: radius * 2)
        blast.name = "rocketBlastNode"
        blast.position = position
        blast.zPosition = isNightWave ? Constants.NightWave.nightEffectZPosition : 50
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

    /// Rebuild per-frame caches from activeDrones in a single pass.
    private func rebuildFrameCaches() {
        aliveDrones.removeAll(keepingCapacity: true)
        aliveNonMineLayerDrones.removeAll(keepingCapacity: true)
        aliveMissileCount = 0
        jammedTowerIDs.removeAll(keepingCapacity: true)

        // Collect active EW drone positions for jamming calculation
        var ewDronePositions = [(EWDroneEntity, CGPoint)]()

        for drone in activeDrones where !drone.isHit {
            aliveDrones.append(drone)
            if !(drone is MineLayerDroneEntity) {
                aliveNonMineLayerDrones.append(drone)
            }
            if drone is EnemyMissileEntity || drone is HarmMissileEntity {
                aliveMissileCount += 1
            }
            if let ewDrone = drone as? EWDroneEntity,
               let pos = ewDrone.component(ofType: SpriteComponent.self)?.spriteNode.position {
                ewDronePositions.append((ewDrone, pos))
            }
        }

        // Cache missile alert
        if waveManager?.missileWarningShown ?? false || waveManager?.harmWarningShown ?? false {
            cachedMissileAlertActive = true
        } else {
            cachedMissileAlertActive = aliveDrones.contains(where: { drone in
                guard (drone is EnemyMissileEntity || drone is HarmMissileEntity) else { return false }
                guard let pos = drone.component(ofType: SpriteComponent.self)?.spriteNode.position else { return false }
                return pos.y > -50 && pos.y < frame.height + 100
            })
        }

        // Cache active radar positions (only on night waves)
        activeRadars.removeAll(keepingCapacity: true)
        if isNightWave, let towerPlacement {
            for tower in towerPlacement.towers {
                guard let stats = tower.stats, stats.towerType == .radar, !stats.isDisabled else { continue }
                activeRadars.append((tower.worldPosition, stats.range * stats.range))
            }
        }

        // Cache EW jamming
        if !ewDronePositions.isEmpty, let towerPlacement {
            for tower in towerPlacement.towers {
                let towerPos = tower.worldPosition
                for (ewDrone, _) in ewDronePositions {
                    if ewDrone.isJamming(towerAt: towerPos) {
                        jammedTowerIDs.insert(ObjectIdentifier(tower))
                        break
                    }
                }
            }
        }
    }

    // MARK: - Node Pools

    func acquireTracer() -> SKSpriteNode {
        if let tracer = tracerPool.popLast() {
            tracer.alpha = 1.0
            tracer.isHidden = false
            tracer.removeAllActions()
            return tracer
        }
        return SKSpriteNode(texture: TowerTargetingComponent.poolTracerTexture)
    }

    func releaseTracer(_ tracer: SKSpriteNode) {
        tracer.removeFromParent()
        if tracerPool.count < nodePoolCapacity {
            tracerPool.append(tracer)
        }
    }

    func acquireSmokePuff() -> SKSpriteNode {
        if let puff = smokePuffPool.popLast() {
            puff.alpha = 1.0
            puff.isHidden = false
            puff.setScale(1.0)
            puff.removeAllActions()
            return puff
        }
        return SKSpriteNode(texture: Self.sharedSmokePuffTexture)
    }

    func releaseSmokePuff(_ puff: SKSpriteNode) {
        puff.removeFromParent()
        if smokePuffPool.count < nodePoolCapacity {
            smokePuffPool.append(puff)
        }
    }

    static let sharedSmokePuffTexture: SKTexture = {
        let size: CGFloat = 18
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        let image = renderer.image { ctx in
            let rect = CGRect(x: 0, y: 0, width: size, height: size)
            ctx.cgContext.setFillColor(UIColor.white.cgColor)
            ctx.cgContext.fillEllipse(in: rect)
        }
        return SKTexture(image: image)
    }()

    private func syncFireControlState() {
        guard !fireControlSyncedThisFrame else { return }
        fireControlSyncedThisFrame = true
        let rocketsInFlightIDs = Set(activeRockets.map { ObjectIdentifier($0) })
        fireControl.syncAssignments(
            withActiveRocketIDs: rocketsInFlightIDs,
            currentTime: elapsedGameplayTime
        )
        fireControl.syncTracks(
            with: aliveNonMineLayerDrones,
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
                selectedLevel = LevelDefinition.level1
                selectedCampaignLevelId = nil
                startGame()
            } else if touchedNode.name == "campaignButton" {
                showLevelSelect()
            } else if let name = touchedNode.name, name.hasPrefix("levelCard_") {
                if let idx = Int(name.replacingOccurrences(of: "levelCard_", with: "")) {
                    let campaign = CampaignManager.shared
                    let level = campaign.levels[idx]
                    selectedLevel = level.definition
                    selectedCampaignLevelId = level.id
                    startGame()
                }
            } else if touchedNode.name == "levelSelectBack" {
                enumerateChildNodes(withName: "//levelSelectOverlay") { node, _ in
                    node.removeFromParent()
                }
                showMainMenu()
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
            } else if touchedNode.name == "victoryNextButton" {
                enumerateChildNodes(withName: "//victoryOverlay") { node, _ in
                    node.removeFromParent()
                }
                stopGame()
                // Start next campaign level
                if let currentId = selectedCampaignLevelId,
                   let currentIdx = CampaignManager.shared.levels.firstIndex(where: { $0.id == currentId }),
                   currentIdx + 1 < CampaignManager.shared.levels.count {
                    let nextLevel = CampaignManager.shared.levels[currentIdx + 1]
                    selectedLevel = nextLevel.definition
                    selectedCampaignLevelId = nextLevel.id
                    startGame()
                }
            } else if touchedNode.name == "victoryMenuButton" {
                enumerateChildNodes(withName: "//victoryOverlay") { node, _ in
                    node.removeFromParent()
                }
                stopGame()
                showMainMenu()
                showLevelSelect()
            }

        case .build:
            // Military Aid card selection
            if hasMilitaryAidOverlay, let name = touchedNode.name, name.hasPrefix("aidCard_") {
                if let idx = Int(name.replacingOccurrences(of: "aidCard_", with: "")) {
                    handleMilitaryAidSelection(cardIndex: idx)
                }
                return
            }
            // Block other interactions while aid overlay is shown
            if hasMilitaryAidOverlay { return }

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
            if abilityManager.handleTap(at: location) { return }
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

        // Settlement upgrade button
        if touchedNode.name == "settlementUpgradeButton" || touchedNode.parent?.name == "settlementUpgradeButton" {
            if let settlement = selectedSettlement {
                let cost = settlement.upgradeCost
                if economyManager.canAfford(cost) {
                    economyManager.spend(cost)
                    settlementManager?.upgradeSettlement(settlement)
                    dismissSettlementActionPanel()
                    updateHUD()
                }
            }
            return
        }

        // Sell button
        if touchedNode.name == "sellButton" || touchedNode.parent?.name == "sellButton" {
            if let tower = selectedTower {
                towerPlacement.sellTower(tower, economy: economyManager)
                selectedTower = nil
                dismissTowerActionPanel()
                synergyManager.recalculate(towers: towerPlacement.towers, in: self)
                updateHUD()
            }
            return
        }

        // Conveyor belt card selection
        if conveyorBelt.handleTap(nodeName: touchedNode.name) {
            towerPlacement.selectTowerType(conveyorBelt.selectedTowerType)
            towerPlacement.clearPreview()
            return
        }

        // Grid tap for tower placement or tower info
        dismissSettlementActionPanel()
        if let gridPos = gridMap.gridPosition(for: location) {
            if towerPlacement.selectedTowerType != nil, !isNightWave {
                if gridMap.canPlaceTower(atRow: gridPos.row, col: gridPos.col) {
                    if towerPlacement.placeTower(at: gridPos, economy: economyManager) != nil {
                        conveyorBelt.consumeSelected()
                        towerPlacement.selectTowerType(nil)
                        synergyManager.recalculate(towers: towerPlacement.towers, in: self)
                    }
                    updateHUD()
                }
            } else {
                if let tower = towerPlacement.towerAt(gridPos: gridPos) {
                    handleTowerTap(tower)
                } else if let settlement = settlementManager?.settlement(atRow: gridPos.row, col: gridPos.col) {
                    handleSettlementTap(settlement)
                }
            }
        }
    }

    private var selectedSettlement: SettlementEntity?

    private func handleSettlementTap(_ settlement: SettlementEntity) {
        guard currentPhase == .build else { return }

        // Dismiss any tower/settlement panel
        selectedTower?.hideRangeIndicator()
        selectedTower = nil
        dismissTowerActionPanel()
        dismissSettlementActionPanel()

        if selectedSettlement === settlement {
            selectedSettlement = nil
            return
        }

        selectedSettlement = settlement
        showSettlementActions(settlement)
    }

    private func showSettlementActions(_ settlement: SettlementEntity) {
        dismissSettlementActionPanel()

        let pos = settlement.worldPosition

        let panel = SKNode()
        panel.name = "settlementActionPanel"
        panel.zPosition = 97
        panel.position = CGPoint(x: pos.x, y: pos.y + 45)

        // Info label
        let infoLabel = SKLabelNode(fontNamed: Constants.GameBalance.hudFontName)
        infoLabel.text = "\(settlement.settlementType.displayName) Lv\(settlement.level) +\(settlement.incomePerWave)/wave"
        infoLabel.fontSize = 9
        infoLabel.fontColor = .white
        infoLabel.verticalAlignmentMode = .center
        infoLabel.position = CGPoint(x: 0, y: 16)
        panel.addChild(infoLabel)

        // Upgrade button (if can upgrade)
        if settlement.canUpgrade {
            let cost = settlement.upgradeCost
            let canAfford = economyManager.canAfford(cost)
            let upgradeBtn = SKSpriteNode(
                color: canAfford ? .systemGreen : .gray,
                size: CGSize(width: 80, height: 24)
            )
            upgradeBtn.name = "settlementUpgradeButton"
            upgradeBtn.position = .zero
            let upgradeLabel = SKLabelNode(fontNamed: Constants.GameBalance.hudFontName)
            upgradeLabel.text = "UP Lv\(settlement.level + 1): \(cost)"
            upgradeLabel.fontSize = 10
            upgradeLabel.fontColor = .white
            upgradeLabel.verticalAlignmentMode = .center
            upgradeLabel.name = "settlementUpgradeButton"
            upgradeBtn.addChild(upgradeLabel)
            panel.addChild(upgradeBtn)
        } else if settlement.isDestroyed {
            let destroyedLabel = SKLabelNode(fontNamed: Constants.GameBalance.hudFontName)
            destroyedLabel.text = "ЗНИЩЕНО"
            destroyedLabel.fontSize = 10
            destroyedLabel.fontColor = .red
            destroyedLabel.verticalAlignmentMode = .center
            panel.addChild(destroyedLabel)
        } else {
            let maxLabel = SKLabelNode(fontNamed: Constants.GameBalance.hudFontName)
            maxLabel.text = "MAX"
            maxLabel.fontSize = 10
            maxLabel.fontColor = .yellow
            maxLabel.verticalAlignmentMode = .center
            panel.addChild(maxLabel)
        }

        addChild(panel)

        panel.run(SKAction.sequence([
            SKAction.wait(forDuration: 5),
            SKAction.removeFromParent()
        ]))
    }

    private func dismissSettlementActionPanel() {
        selectedSettlement = nil
        enumerateChildNodes(withName: "//settlementActionPanel") { node, _ in
            node.removeFromParent()
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

        let sellBtn = SKSpriteNode(color: .systemRed, size: CGSize(width: 60, height: 24))
        sellBtn.name = "sellButton"
        sellBtn.position = .zero
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
