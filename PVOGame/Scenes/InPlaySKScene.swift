//
//  InPlayScene.swift
//  PVOGame
//
//  Created by Frizer on 04.12.2022.
//

import UIKit
import SpriteKit
import GameplayKit

class InPlaySKScene: SKScene, MineLayerDroneDelegate {
    enum GameState {
        case menu
        case playing
        case paused
        case gameOver
    }

    private static let gameOverOverlayNodeName = "gameOverOverlay"
    private static let rocketBlastNodeName = "rocketBlastNode"
    private static let mineBombBlastNodeName = "mineBombBlastNode"
    private static let rocketAimMarkerNodeName = "rocketAimMarkerNode"
    private static let rocketLauncherInsets = CGPoint(x: 24, y: 66)
    private static let rocketVisualSize = CGSize(width: 12, height: 30)
    private static let rocketColumnsPerRow = 10
    private static let rocketColumnSpacing: CGFloat = 4.8
    private static let rocketRowDepthXOffset: CGFloat = 3.2
    private static let rocketRowDepthYOffset: CGFloat = 8.0
    private static let interceptorLauncherInsets = CGPoint(x: 24, y: 66)
    private static let interceptorVisualSize = CGSize(width: 8, height: 22)
    private static let interceptorColumnsPerRow = 10
    private static let interceptorColumnSpacing: CGFloat = 3.8
    private static let interceptorRowDepthXOffset: CGFloat = 2.4
    private static let interceptorRowDepthYOffset: CGFloat = 6.2
    private static let blastTexture: SKTexture = {
        let d: CGFloat = 64
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: d, height: d))
        let image = renderer.image { ctx in
            UIColor.white.setFill()
            ctx.cgContext.fillEllipse(in: CGRect(x: 0, y: 0, width: d, height: d))
        }
        return SKTexture(image: image)
    }()
    private static let rocketBlastScaleDuration: TimeInterval = 0.1
    private static let rocketBlastFadeDuration: TimeInterval = 0.15
    private static let rocketImpactLockSafetyMargin: TimeInterval = 0.06
    private static var rocketImpactLockDuration: TimeInterval {
        max(rocketBlastScaleDuration, rocketBlastFadeDuration) + rocketImpactLockSafetyMargin
    }
    private static let singleTargetReservationSnapDistance: CGFloat = 72
    private static let singleTargetReservationCoverageRadius: CGFloat = 18
    var entities = [GKEntity]()
    private var entityIdentifiers = Set<ObjectIdentifier>()
    private var activeRockets = [RocketEntity]()
    private var bulletPool = [BulletEntity]()
    private static let bulletPoolMaxSize = 200
    var graphs = [String: GKGraph]()
    var lastUpdateTime: TimeInterval = 0
    var lastTap = Constants.noTapPoint
    var background = SKSpriteNode()
    var weaponRow: WeaponRow?
    var mainGun: GunEntity?
    let collisionDelegate = CollisionDetectedInGame()

    private var settingsButton: SettingsButton?
    private var settingsMenu: InGameSettingsMenu?
    private var isTouched = false
    var isGunThreatAssessmentActive: Bool { gameState == .playing && isTouched }
    private var availableDrones = [AttackDroneEntity]()
    private var activeDrones = [AttackDroneEntity]()
    private(set) var gameState: GameState = .menu
    var isStarted: Bool { gameState != .menu }
    var activeDroneCount: Int { activeDrones.count }
    var availableDroneCount: Int { availableDrones.count }

    // MARK: - Game State
    private(set) var score = 0
    private(set) var lives = Constants.GameBalance.defaultLives
    private(set) var shotsFired = 0
    private(set) var dronesDestroyed = 0
    private(set) var currentWave = 0
    private(set) var isWaveInProgress = false
    var isGameOver: Bool { gameState == .gameOver }
    private(set) var rocketType = Constants.GameBalance.defaultRocketType
    private var rocketAmmo = Constants.GameBalance.rocketSpec(for: Constants.GameBalance.defaultRocketType).defaultAmmo
    private var rocketCooldownRemaining: TimeInterval = 0
    private var interceptorAmmo = Constants.GameBalance.interceptorRocketBaseSpec.defaultAmmo
    private var interceptorCooldownRemaining: TimeInterval = 0
    private var crossedHalfScreenDroneIDs = Set<ObjectIdentifier>()
    private var pendingAutoRocketTargets = [CGPoint]()
    private var pendingAutoInterceptorTargets = [CGPoint]()
    private var reroutedDroneIDs = Set<ObjectIdentifier>()
    private var isRegularDroneFeatureEnabled = Constants.GameBalance.isRegularDroneEnabled
    private var isMineLayerFeatureEnabled = Constants.GameBalance.isMineLayerEnabled
    private var isRocketLauncherEnabled = Constants.GameBalance.isRocketLauncherEnabled
    private var isInterceptorLauncherEnabled = Constants.GameBalance.isInterceptorLauncherEnabled
    private var mineLayerRearmTickets = [MineLayerRearmTicket]()
    private var pendingMineLayerBonusForNextWave = 0
    private var elapsedGameplayTime: TimeInterval = 0
    private(set) var mineBombsDropped = 0
    private var fireControl = FireControlState()

    private struct MineLayerRearmTicket {
        let drone: MineLayerDroneEntity
        let sourceWave: Int
        let readyAt: TimeInterval
    }

    // MARK: - HUD & Overlay
    private var scoreLabel: SKLabelNode?
    private var livesLabel: SKLabelNode?
    private var waveLabel: SKLabelNode?
    private var hudNode: SKNode?
    private var gameOverNode: SKNode?
    private var rocketLauncherNode: SKNode?
    private var rocketAmmoVisuals = [SKSpriteNode]()
    private var interceptorLauncherNode: SKNode?
    private var interceptorAmmoVisuals = [SKSpriteNode]()
    private var rocketAimMarkers = [ObjectIdentifier: SKShapeNode]()

    var rocketAmmoCount: Int { rocketAmmo }
    var rocketCooldownRemainingForTests: TimeInterval { rocketCooldownRemaining }
    var activeRocketSpecForTests: Constants.GameBalance.RocketSpec { rocketSpec }
    var interceptorAmmoCountForTests: Int { interceptorAmmo }
    var interceptorCooldownRemainingForTests: TimeInterval { interceptorCooldownRemaining }
    var activeInterceptorSpecForTests: Constants.GameBalance.RocketSpec { interceptorRocketSpec }
    var interceptorLauncherPositionForTests: CGPoint? { interceptorLauncherNode?.position }
    var rocketAimMarkerCountForTests: Int { rocketAimMarkers.count }
    var activeRegularDroneCountForTests: Int { activeDrones.filter { !($0 is MineLayerDroneEntity) }.count }
    var activeMineLayerCount: Int { activeDrones.filter { $0 is MineLayerDroneEntity }.count }
    var rearmingMineLayerCountForTests: Int { mineLayerRearmTickets.count }
    var pendingMineLayerBonusForTests: Int { pendingMineLayerBonusForNextWave }
    private var rocketSpec: Constants.GameBalance.RocketSpec {
        Constants.GameBalance.rocketSpec(for: rocketType)
    }
    private var interceptorRocketSpec: Constants.GameBalance.RocketSpec {
        Constants.GameBalance.interceptorRocketSpec(forScreenHeight: frame.height)
    }

    func setMineLayerEnabledForTests(_ isEnabled: Bool) {
        isMineLayerFeatureEnabled = isEnabled
    }

    func setRegularDronesEnabledForTests(_ isEnabled: Bool) {
        isRegularDroneFeatureEnabled = isEnabled
    }

    func setRocketLauncherEnabledForTests(_ isEnabled: Bool) {
        isRocketLauncherEnabled = isEnabled
    }

    func setInterceptorLauncherEnabledForTests(_ isEnabled: Bool) {
        isInterceptorLauncherEnabled = isEnabled
    }

    func setGunAimForTests(point: CGPoint, isTouching: Bool = true) {
        lastTap = point
        isTouched = isTouching
    }

    private func canTransition(from source: GameState, to destination: GameState) -> Bool {
        switch (source, destination) {
        case (_, _) where source == destination:
            return true
        case (.menu, .playing):
            return true
        case (.playing, .paused), (.playing, .gameOver), (.playing, .menu):
            return true
        case (.paused, .playing), (.paused, .menu):
            return true
        case (.gameOver, .playing), (.gameOver, .menu):
            return true
        default:
            return false
        }
    }

    private func transition(to destination: GameState) {
        guard canTransition(from: gameState, to: destination) else {
            assertionFailure("Invalid game state transition: \(gameState) -> \(destination)")
            return
        }
        gameState = destination
        isPaused = (destination == .paused || destination == .gameOver)
    }

    // MARK: - Scene Setup

    fileprivate func setupBackground(_ view: SKView) {
        background = SKSpriteNode(color: .black, size: frame.size)
        background.name = Constants.backgroundName
        background.physicsBody = SKPhysicsBody(rectangleOf: frame.size)
        background.physicsBody?.categoryBitMask = Constants.boundsBitMask
        background.physicsBody?.collisionBitMask = 0
        background.physicsBody?.contactTestBitMask = 0
        background.physicsBody?.isDynamic = false
        background.position = CGPoint(x: view.frame.width / 2, y: view.frame.height / 2)
        addChild(background)
    }

    fileprivate func setupGround(_ view: SKView) {
        let groundHeight = frame.height / Constants.GameBalance.groundHeightRatio
        let ground = SKSpriteNode(color: .gray, size: CGSize(width: frame.width, height: groundHeight))
        ground.name = Constants.groundName
        ground.physicsBody = SKPhysicsBody(rectangleOf: ground.frame.size)
        ground.physicsBody?.categoryBitMask = Constants.groundBitMask
        ground.physicsBody?.collisionBitMask = 0
        ground.physicsBody?.contactTestBitMask = 0
        ground.physicsBody?.isDynamic = false
        ground.position = CGPoint(x: 0, y: -background.frame.height / 2 + ground.frame.height / 2)
        background.addChild(ground)
    }

    func setupMainMenu(_ view: SKView) {
        setupGunChooseRow(view)
    }

    func setupGunChooseRow(_ view: SKView) {
        weaponRow = WeaponRow(
            frame: CGRect(x: 0, y: Constants.GameBalance.gunPanelTopInset, width: view.frame.width / 2, height: Constants.GameBalance.gunPanelHeight),
            guns: [setupMiniGun(view), setupPistolGun(view), setupDickGun(view)],
            cellSize: Constants.GameBalance.gunCellSize
        )
        guard let weaponRow else { return }
        view.addSubview(weaponRow)

        weaponRow.removeConstraints(weaponRow.constraints)
        weaponRow.pinLeft(to: view, 0)
        weaponRow.pinTop(to: view, Int(Constants.GameBalance.gunPanelTopInset))
        weaponRow.setWidth(view.frame.width).isActive = true
        weaponRow.setHeight(Constants.GameBalance.gunPanelHeight).isActive = true
        weaponRow.mainGun = mainGun
        weaponRow.initUI()
    }

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
            onResume: { [weak self] in
                self?.resumeGame()
            },
            onExit: { [weak self] in
                self?.exitToMainMenu()
            }
        )
        view.addSubview(menu)
        menu.pinCenterX(to: view.centerXAnchor)
        menu.pinCenterY(to: view.centerYAnchor)
        menu.setWidth(width).isActive = true
        menu.setHeight(Constants.GameBalance.settingsMenuHeight).isActive = true
        menu.isHidden = true
        settingsMenu = menu
    }

    private func setupHUD() {
        let hud = SKNode()
        hud.zPosition = 95
        hud.isHidden = true
        addChild(hud)
        hudNode = hud

        let fontSize = Constants.GameBalance.hudFontSize
        let fontName = Constants.GameBalance.hudFontName
        let yPos = frame.height - 50

        let sLabel = SKLabelNode(fontNamed: fontName)
        sLabel.fontSize = fontSize
        sLabel.fontColor = .white
        sLabel.horizontalAlignmentMode = .left
        sLabel.position = CGPoint(x: 20, y: yPos)
        hud.addChild(sLabel)
        scoreLabel = sLabel

        let wLabel = SKLabelNode(fontNamed: fontName)
        wLabel.fontSize = fontSize
        wLabel.fontColor = .white
        wLabel.horizontalAlignmentMode = .center
        wLabel.position = CGPoint(x: frame.width / 2, y: yPos)
        hud.addChild(wLabel)
        waveLabel = wLabel

        let lLabel = SKLabelNode(fontNamed: fontName)
        lLabel.fontSize = fontSize
        lLabel.fontColor = .white
        lLabel.horizontalAlignmentMode = .right
        lLabel.position = CGPoint(x: frame.width - 20, y: yPos)
        hud.addChild(lLabel)
        livesLabel = lLabel
    }

    private func setupRocketLauncher() {
        guard isRocketLauncherEnabled else { return }
        let launcher = SKNode()
        launcher.zPosition = 97
        launcher.position = CGPoint(
            x: frame.width - Self.rocketLauncherInsets.x,
            y: Self.rocketLauncherInsets.y
        )
        launcher.isHidden = true
        launcher.alpha = 1
        addChild(launcher)
        rocketLauncherNode = launcher
        rebuildRocketAmmoStack()
    }

    private func setupInterceptorLauncher() {
        guard isInterceptorLauncherEnabled else { return }
        let launcher = SKNode()
        launcher.zPosition = 97
        launcher.position = CGPoint(
            x: Self.interceptorLauncherInsets.x,
            y: Self.interceptorLauncherInsets.y
        )
        launcher.isHidden = true
        launcher.alpha = 1
        addChild(launcher)
        interceptorLauncherNode = launcher
        rebuildInterceptorAmmoStack()
    }

    private func updateRocketLauncherUI() {
        guard let rocketLauncherNode else { return }
        let hideLauncher = !isStarted || isGameOver
        rocketLauncherNode.isHidden = hideLauncher
        guard !hideLauncher else { return }
        if rocketAmmoVisuals.count != rocketAmmo {
            rebuildRocketAmmoStack()
        }

        rocketLauncherNode.alpha = 1
        let rocketAlpha: CGFloat = 1
        for rocketVisual in rocketAmmoVisuals {
            rocketVisual.alpha = rocketAlpha
        }
    }

    private func updateInterceptorLauncherUI() {
        guard let interceptorLauncherNode else { return }
        let hideLauncher = !isStarted || isGameOver
        interceptorLauncherNode.isHidden = hideLauncher
        guard !hideLauncher else { return }
        if interceptorAmmoVisuals.count != interceptorAmmo {
            rebuildInterceptorAmmoStack()
        }

        interceptorLauncherNode.alpha = 1
        for rocketVisual in interceptorAmmoVisuals {
            rocketVisual.alpha = 1
        }
    }

    private func rebuildRocketAmmoStack() {
        guard let rocketLauncherNode else {
            rocketAmmoVisuals.forEach { $0.removeFromParent() }
            rocketAmmoVisuals.removeAll()
            return
        }
        // Remove excess
        while rocketAmmoVisuals.count > rocketAmmo {
            rocketAmmoVisuals.removeLast().removeFromParent()
        }
        // Add missing
        while rocketAmmoVisuals.count < rocketAmmo {
            let index = rocketAmmoVisuals.count
            let rocketVisual = SKSpriteNode(color: .yellow, size: Self.rocketVisualSize)
            let row = index / Self.rocketColumnsPerRow
            let column = index % Self.rocketColumnsPerRow
            let xOffset =
                -(CGFloat(column) * Self.rocketColumnSpacing) -
                (CGFloat(row) * Self.rocketRowDepthXOffset)
            let yOffset = CGFloat(row) * Self.rocketRowDepthYOffset
            rocketVisual.position = CGPoint(x: xOffset, y: yOffset)
            rocketVisual.zRotation = .pi / 10
            rocketVisual.zPosition = CGFloat(10_000 - row * Self.rocketColumnsPerRow - column)
            rocketLauncherNode.addChild(rocketVisual)
            rocketAmmoVisuals.append(rocketVisual)
        }
    }

    private func rebuildInterceptorAmmoStack() {
        guard let interceptorLauncherNode else {
            interceptorAmmoVisuals.forEach { $0.removeFromParent() }
            interceptorAmmoVisuals.removeAll()
            return
        }
        // Remove excess
        while interceptorAmmoVisuals.count > interceptorAmmo {
            interceptorAmmoVisuals.removeLast().removeFromParent()
        }
        // Add missing
        while interceptorAmmoVisuals.count < interceptorAmmo {
            let index = interceptorAmmoVisuals.count
            let rocketVisual = SKSpriteNode(color: .cyan, size: Self.interceptorVisualSize)
            let row = index / Self.interceptorColumnsPerRow
            let column = index % Self.interceptorColumnsPerRow
            let xOffset =
                CGFloat(column) * Self.interceptorColumnSpacing +
                CGFloat(row) * Self.interceptorRowDepthXOffset
            let yOffset = CGFloat(row) * Self.interceptorRowDepthYOffset
            rocketVisual.position = CGPoint(x: xOffset, y: yOffset)
            rocketVisual.zRotation = -.pi / 10
            rocketVisual.zPosition = CGFloat(10_000 - row * Self.interceptorColumnsPerRow - column)
            interceptorLauncherNode.addChild(rocketVisual)
            interceptorAmmoVisuals.append(rocketVisual)
        }
    }

    private func currentRocketLaunchPosition() -> CGPoint? {
        guard let rocketLauncherNode else { return nil }
        if let topRocket = rocketAmmoVisuals.last {
            return topRocket.convert(.zero, to: self)
        }
        return rocketLauncherNode.convert(.zero, to: self)
    }

    private func currentInterceptorLaunchPosition() -> CGPoint? {
        guard let interceptorLauncherNode else { return nil }
        if let topRocket = interceptorAmmoVisuals.last {
            return topRocket.convert(.zero, to: self)
        }
        return interceptorLauncherNode.convert(.zero, to: self)
    }

    func setRocketType(_ type: Constants.GameBalance.RocketType, resetAmmo: Bool = true) {
        rocketType = type
        if resetAmmo {
            rocketAmmo = isRocketLauncherEnabled ? rocketSpec.defaultAmmo : 0
            rocketCooldownRemaining = 0
            resetRocketAutoFireState()
        }
        updateRocketLauncherUI()
    }

    private func canFireRocket() -> Bool {
        guard gameState == .playing,
              rocketAmmo > 0,
              rocketCooldownRemaining <= 0.01
        else {
            return false
        }
        return resolveRocketLaunchPlan(
            preferredPoint: nil,
            launchPosition: currentRocketLaunchPosition()
        ) != nil
    }

    private func resolveRocketLaunchPlan(
        preferredPoint: CGPoint?,
        launchPosition: CGPoint?
    ) -> FireControlState.LaunchPlan? {
        plannedRocketLaunch(
            preferredPoint: preferredPoint,
            origin: launchPosition,
            reservingActiveRocketImpacts: true,
            excludingRocket: nil,
            radius: rocketSpec.maxFlightDistance,
            influenceRadius: rocketSpec.blastRadius,
            projectileSpeed: rocketSpec.initialSpeed,
            acceleration: rocketSpec.acceleration,
            maxSpeed: rocketSpec.maxSpeed
        )
    }

    private func canFireInterceptor() -> Bool {
        guard gameState == .playing,
              interceptorAmmo > 0,
              interceptorCooldownRemaining <= 0.01,
              let launchPosition = currentInterceptorLaunchPosition()
        else {
            return false
        }
        return resolveInterceptorLaunchPlan(
            preferredPoint: nil,
            launchPosition: launchPosition
        ) != nil
    }

    private func resolveInterceptorLaunchPlan(
        preferredPoint: CGPoint?,
        launchPosition: CGPoint?
    ) -> FireControlState.LaunchPlan? {
        plannedRocketLaunch(
            preferredPoint: preferredPoint,
            origin: launchPosition,
            reservingActiveRocketImpacts: true,
            excludingRocket: nil,
            radius: interceptorRocketSpec.maxFlightDistance,
            influenceRadius: 0,
            projectileSpeed: interceptorRocketSpec.initialSpeed,
            acceleration: interceptorRocketSpec.acceleration,
            maxSpeed: interceptorRocketSpec.maxSpeed
        )
    }

    @discardableResult
    func triggerRocketLauncher(targetOverride: CGPoint? = nil) -> Bool {
        guard isRocketLauncherEnabled,
              gameState == .playing,
              rocketAmmo > 0,
              rocketCooldownRemaining <= 0.01
        else {
            return false
        }
        let launchPosition = currentRocketLaunchPosition()
        guard let launchPlan = resolveRocketLaunchPlan(
            preferredPoint: targetOverride,
            launchPosition: launchPosition
        ) else {
            return false
        }
        launchRocket(launchPlan: launchPlan, startPosition: launchPosition, spec: rocketSpec)
        rocketAmmo = max(0, rocketAmmo - 1)
        rocketCooldownRemaining = rocketSpec.cooldown
        updateRocketLauncherUI()
        return true
    }

    @discardableResult
    func triggerInterceptorLauncher(targetOverride: CGPoint? = nil) -> Bool {
        guard isInterceptorLauncherEnabled, canFireInterceptor() else { return false }
        let launchPosition = currentInterceptorLaunchPosition()
        guard let launchPlan = resolveInterceptorLaunchPlan(
            preferredPoint: targetOverride,
            launchPosition: launchPosition
        ) else {
            return false
        }
        launchRocket(
            launchPlan: launchPlan,
            startPosition: launchPosition,
            spec: interceptorRocketSpec
        )
        interceptorAmmo = max(0, interceptorAmmo - 1)
        interceptorCooldownRemaining = interceptorRocketSpec.cooldown
        updateInterceptorLauncherUI()
        return true
    }

    private func resetRocketAutoFireState() {
        crossedHalfScreenDroneIDs.removeAll()
        pendingAutoRocketTargets.removeAll()
        pendingAutoInterceptorTargets.removeAll()
    }

    private func resetDroneRecoveryState() {
        reroutedDroneIDs.removeAll()
    }

    private func registerThreatDroneCrossings() {
        guard gameState == .playing else { return }

        let halfScreenY = frame.height * 0.5
        for drone in activeDrones where !drone.isHit {
            guard let position = drone.component(ofType: SpriteComponent.self)?.spriteNode.position else {
                continue
            }
            let droneID = ObjectIdentifier(drone)
            if position.y <= halfScreenY {
                if !crossedHalfScreenDroneIDs.contains(droneID) {
                    crossedHalfScreenDroneIDs.insert(droneID)
                    if isRocketLauncherEnabled { pendingAutoRocketTargets.append(position) }
                    if isInterceptorLauncherEnabled { pendingAutoInterceptorTargets.append(position) }
                }
            } else {
                crossedHalfScreenDroneIDs.remove(droneID)
            }
        }

        let activeIDs = Set(activeDrones.map { ObjectIdentifier($0) })
        crossedHalfScreenDroneIDs = crossedHalfScreenDroneIDs.intersection(activeIDs)
    }

    private func fireAutoRocketIfNeeded() {
        guard isRocketLauncherEnabled, canFireRocket(), !pendingAutoRocketTargets.isEmpty else { return }
        while !pendingAutoRocketTargets.isEmpty {
            pendingAutoRocketTargets.removeFirst()
            if triggerRocketLauncher() {
                return
            }
        }
    }

    private func fireAutoInterceptorIfNeeded() {
        guard isInterceptorLauncherEnabled, canFireInterceptor(), !pendingAutoInterceptorTargets.isEmpty else { return }
        while !pendingAutoInterceptorTargets.isEmpty {
            pendingAutoInterceptorTargets.removeFirst()
            if triggerInterceptorLauncher() {
                return
            }
        }
    }

    func evaluateAutoRocketForTests() {
        registerThreatDroneCrossings()
        fireAutoRocketIfNeeded()
    }

    func evaluateAutoInterceptorForTests() {
        registerThreatDroneCrossings()
        fireAutoInterceptorIfNeeded()
    }

    private struct FireControlState {
        struct PlanningProfile {
            let blastRadius: CGFloat
            let maxRange: CGFloat?
            let nominalSpeed: CGFloat
            let acceleration: CGFloat
            let maxSpeed: CGFloat
        }

        struct LaunchPlan {
            let targetPoint: CGPoint
            let claimedTrackIDs: Set<ObjectIdentifier>
            let eta: TimeInterval
            let score: CGFloat
        }

        private struct TrackState {
            let id: ObjectIdentifier
            var position: CGPoint
            var velocity: CGVector
            var lastUpdateTime: TimeInterval
            var threatWeight: CGFloat
        }

        private struct Assignment {
            enum Phase {
                case inFlight
                case impactLock(expiresAt: TimeInterval)
            }

            let assignmentID: UUID
            let rocketID: ObjectIdentifier
            let spec: Constants.GameBalance.RocketSpec
            var targetPoint: CGPoint
            var claimedTrackIDs: Set<ObjectIdentifier>
            var eta: TimeInterval
            var createdAt: TimeInterval
            var updatedAt: TimeInterval
            var phase: Phase
        }

        private var tracks = [ObjectIdentifier: TrackState]()
        private var assignments = [ObjectIdentifier: Assignment]()
        private(set) var decisionLog = [String]()

        mutating func reset() {
            tracks.removeAll()
            assignments.removeAll()
            decisionLog.removeAll()
        }

        mutating func syncTracks(
            with drones: [AttackDroneEntity],
            currentTime: TimeInterval,
            sceneHeight: CGFloat
        ) {
            let safeHeight = max(sceneHeight, 1)
            var observedIDs = Set<ObjectIdentifier>()
            for drone in drones {
                guard let point = drone.component(ofType: SpriteComponent.self)?.spriteNode.position else {
                    continue
                }
                let id = ObjectIdentifier(drone)
                observedIDs.insert(id)
                let previous = tracks[id]
                let velocity: CGVector
                if let previous {
                    let dt = currentTime - previous.lastUpdateTime
                    if dt > 0.0001 {
                        velocity = CGVector(
                            dx: (point.x - previous.position.x) / dt,
                            dy: (point.y - previous.position.y) / dt
                        )
                    } else {
                        // Keep previous estimate when the planner syncs multiple times within one frame.
                        velocity = previous.velocity
                    }
                } else {
                    velocity = CGVector(
                        dx: 0,
                        dy: 0
                    )
                }
                let yNormalized = min(1, max(0, point.y / safeHeight))
                let threatWeight = 1 + (1 - yNormalized) * 1.75
                tracks[id] = TrackState(
                    id: id,
                    position: point,
                    velocity: velocity,
                    lastUpdateTime: currentTime,
                    threatWeight: threatWeight
                )
            }
            tracks = tracks.filter { observedIDs.contains($0.key) }
        }

        mutating func syncAssignments(
            withActiveRocketIDs activeRocketIDs: Set<ObjectIdentifier>,
            currentTime: TimeInterval
        ) {
            pruneExpiredImpactLocks(currentTime: currentTime)
            assignments = assignments.filter { _, assignment in
                switch assignment.phase {
                case .inFlight:
                    return activeRocketIDs.contains(assignment.rocketID)
                case .impactLock:
                    return true
                }
            }
        }

        mutating func handleRocketRemoved(_ rocketID: ObjectIdentifier) {
            guard let assignment = assignments[rocketID] else { return }
            guard case .inFlight = assignment.phase else { return }
            assignments.removeValue(forKey: rocketID)
        }

        mutating func lockAssignmentForImpact(
            rocketID: ObjectIdentifier,
            impactPoint: CGPoint,
            impactRadius: CGFloat,
            currentTime: TimeInterval,
            lockDuration: TimeInterval
        ) {
            guard var assignment = assignments[rocketID] else { return }
            guard impactRadius > 0.01 else {
                assignments.removeValue(forKey: rocketID)
                return
            }
            assignment.targetPoint = impactPoint
            assignment.claimedTrackIDs.removeAll()
            assignment.eta = 0
            assignment.updatedAt = currentTime
            assignment.phase = .impactLock(expiresAt: currentTime + max(lockDuration, 0.01))
            assignments[rocketID] = assignment
        }

        mutating func upsertAssignment(
            rocketID: ObjectIdentifier,
            spec: Constants.GameBalance.RocketSpec,
            targetPoint: CGPoint,
            launchOrigin: CGPoint?,
            currentTime: TimeInterval,
            forcedClaimedTrackIDs: Set<ObjectIdentifier>? = nil
        ) {
            let speed = max(120, spec.initialSpeed)
            let eta = estimatedETA(origin: launchOrigin, target: targetPoint, speed: speed, acceleration: spec.acceleration, maxSpeed: spec.maxSpeed)
            let claimedIDs = forcedClaimedTrackIDs ?? claimedTrackIDs(
                around: targetPoint,
                blastRadius: spec.blastRadius,
                eta: eta
            )
            if var existing = assignments[rocketID] {
                existing.targetPoint = targetPoint
                existing.claimedTrackIDs = claimedIDs
                existing.eta = eta
                existing.updatedAt = currentTime
                existing.phase = .inFlight
                assignments[rocketID] = existing
                return
            }
            assignments[rocketID] = Assignment(
                assignmentID: UUID(),
                rocketID: rocketID,
                spec: spec,
                targetPoint: targetPoint,
                claimedTrackIDs: claimedIDs,
                eta: eta,
                createdAt: currentTime,
                updatedAt: currentTime,
                phase: .inFlight
            )
        }

        mutating func planLaunch(
            preferredPoint: CGPoint?,
            origin: CGPoint?,
            reservingAssignments: Bool,
            excludingRocketID: ObjectIdentifier?,
            profile: PlanningProfile
        ) -> LaunchPlan? {
            guard !tracks.isEmpty else {
                appendLog("No tracks: planner has nothing to target.")
                return nil
            }

            let speed = max(120, profile.nominalSpeed)
            let accel = profile.acceleration
            let vMax = profile.maxSpeed
            let blastRadius = max(0, profile.blastRadius)
            let assignmentSnapshot = assignments.values.filter { assignment in
                if let excludingRocketID {
                    return assignment.rocketID != excludingRocketID
                }
                return true
            }

            let candidateTracks = tracks.values.filter { track in
                guard let origin, let maxRange = profile.maxRange else { return true }
                return Self.squaredDistance(track.position, origin) <= maxRange * maxRange
            }
            guard !candidateTracks.isEmpty else {
                appendLog("No reachable tracks in launch range.")
                return nil
            }

            var candidatePointsByKey = [String: CGPoint]()
            for track in candidateTracks {
                let baseETA = estimatedETA(origin: origin, target: track.position, speed: speed, acceleration: accel, maxSpeed: vMax)
                let projected0 = predictedPosition(for: track, after: baseETA)
                let refinedETA = estimatedETA(origin: origin, target: projected0, speed: speed, acceleration: accel, maxSpeed: vMax)
                let projectedSeed = predictedPosition(for: track, after: refinedETA)
                if let origin, let maxRange = profile.maxRange,
                   Self.squaredDistance(projectedSeed, origin) > maxRange * maxRange {
                    continue
                }
                let candidatePoint: CGPoint
                if blastRadius > 0.01 {
                    let neighbors = candidateTracks.filter { otherTrack in
                        let otherProjected = predictedPosition(for: otherTrack, after: baseETA)
                        return Self.squaredDistance(otherProjected, projectedSeed) <= blastRadius * blastRadius
                    }
                    let centroidSources: [TrackState]
                    if reservingAssignments {
                        centroidSources = neighbors.filter { neighbor in
                            let predicted = predictedPosition(for: neighbor, after: baseETA)
                            return !isTrackReserved(
                                hitID: neighbor.id,
                                predictedPosition: predicted,
                                by: assignmentSnapshot
                            )
                        }
                    } else {
                        centroidSources = neighbors
                    }
                    if centroidSources.isEmpty {
                        if reservingAssignments {
                            continue
                        }
                        candidatePoint = projectedSeed
                    } else {
                        let centroidX = centroidSources.map { predictedPosition(for: $0, after: baseETA).x }.reduce(0, +)
                        let centroidY = centroidSources.map { predictedPosition(for: $0, after: baseETA).y }.reduce(0, +)
                        candidatePoint = CGPoint(
                            x: centroidX / CGFloat(centroidSources.count),
                            y: centroidY / CGFloat(centroidSources.count)
                        )
                    }
                } else {
                    candidatePoint = projectedSeed
                }
                let key = "\(Int((candidatePoint.x * 2).rounded())):\(Int((candidatePoint.y * 2).rounded()))"
                candidatePointsByKey[key] = candidatePoint
            }

            if let preferredPoint {
                let key = "\(Int((preferredPoint.x * 2).rounded())):\(Int((preferredPoint.y * 2).rounded()))"
                candidatePointsByKey[key] = preferredPoint
            }

            let candidatePoints = candidatePointsByKey.values.sorted { lhs, rhs in
                if lhs.x == rhs.x { return lhs.y < rhs.y }
                return lhs.x < rhs.x
            }
            guard !candidatePoints.isEmpty else {
                appendLog("Planner produced no candidate points.")
                return nil
            }

            var bestPlan: LaunchPlan?
            var bestNewCoverage = -1
            var bestPreferredDistance = CGFloat.greatestFiniteMagnitude
            var bestSeparatedPlan: LaunchPlan?
            var bestSeparatedNewCoverage = -1
            var bestSeparatedPreferredDistance = CGFloat.greatestFiniteMagnitude

            func shouldReplacePlan(
                _ currentPlan: LaunchPlan?,
                currentCoverage: Int,
                currentPreferredDistance: CGFloat,
                candidatePoint: CGPoint,
                candidateScore: CGFloat,
                candidateCoverage: Int,
                candidatePreferredDistance: CGFloat
            ) -> Bool {
                guard let currentPlan else { return true }
                let scoreDelta = candidateScore - currentPlan.score
                if scoreDelta > 0.0001 {
                    return true
                }
                if abs(scoreDelta) <= 0.0001, candidateCoverage > currentCoverage {
                    return true
                }
                if abs(scoreDelta) <= 0.0001,
                   candidateCoverage == currentCoverage,
                   candidatePreferredDistance < currentPreferredDistance {
                    return true
                }
                if abs(scoreDelta) <= 0.0001,
                   candidateCoverage == currentCoverage,
                   abs(candidatePreferredDistance - currentPreferredDistance) <= 0.0001 {
                    if candidatePoint.x == currentPlan.targetPoint.x {
                        return candidatePoint.y < currentPlan.targetPoint.y
                    }
                    return candidatePoint.x < currentPlan.targetPoint.x
                }
                return false
            }

            for point in candidatePoints {
                if let origin, let maxRange = profile.maxRange,
                   Self.squaredDistance(point, origin) > maxRange * maxRange {
                    continue
                }

                let eta = estimatedETA(origin: origin, target: point, speed: speed, acceleration: accel, maxSpeed: vMax)
                let hits = impactedTrackIDs(
                    around: point,
                    blastRadius: blastRadius,
                    eta: eta
                )
                guard !hits.isEmpty else { continue }

                var newHits = Set<ObjectIdentifier>()
                var overlapCount = 0
                var weightedThreat: CGFloat = 0
                for hitID in hits {
                    guard let track = tracks[hitID] else { continue }
                    let predicted = predictedPosition(for: track, after: eta)
                    if isTrackReserved(
                        hitID: hitID,
                        predictedPosition: predicted,
                        by: assignmentSnapshot
                    ) {
                        overlapCount += 1
                    } else {
                        newHits.insert(hitID)
                        weightedThreat += track.threatWeight
                    }
                }

                if reservingAssignments && newHits.isEmpty {
                    continue
                }

                var geometricProximityPenalty: CGFloat = 0
                for assignment in assignmentSnapshot {
                    let avoidanceRadius = softAvoidanceRadius(
                        for: assignment,
                        candidateBlastRadius: blastRadius
                    )
                    guard avoidanceRadius > 0.01 else { continue }
                    let distanceSquared = Self.squaredDistance(point, assignment.targetPoint)
                    guard distanceSquared < avoidanceRadius * avoidanceRadius else { continue }
                    let distance = sqrt(distanceSquared)
                    let normalized = 1 - min(1, distance / avoidanceRadius)
                    geometricProximityPenalty += normalized
                }
                let preferredDistance: CGFloat
                if let preferredPoint {
                    preferredDistance = sqrt(Self.squaredDistance(point, preferredPoint))
                } else {
                    preferredDistance = 0
                }
                let etaPenalty = CGFloat(eta) * 0.9
                let overlapPenalty = CGFloat(overlapCount) * 8
                let geometricPenalty = geometricProximityPenalty * (reservingAssignments ? 42 : 18)
                let preferredPenalty = preferredDistance * 0.015
                let score =
                    weightedThreat * 12 +
                    CGFloat(newHits.count) * 5 -
                    overlapPenalty -
                    geometricPenalty -
                    etaPenalty -
                    preferredPenalty

                let claimed = newHits.isEmpty ? hits : newHits
                if shouldReplacePlan(
                    bestPlan,
                    currentCoverage: bestNewCoverage,
                    currentPreferredDistance: bestPreferredDistance,
                    candidatePoint: point,
                    candidateScore: score,
                    candidateCoverage: newHits.count,
                    candidatePreferredDistance: preferredDistance
                ) {
                    bestPlan = LaunchPlan(
                        targetPoint: point,
                        claimedTrackIDs: claimed,
                        eta: eta,
                        score: score
                    )
                    bestNewCoverage = newHits.count
                    bestPreferredDistance = preferredDistance
                }

                let isSeparatedFromAssignments = assignmentSnapshot.allSatisfy { assignment in
                    isBlastSeparated(
                        candidatePoint: point,
                        candidateBlastRadius: blastRadius,
                        from: assignment
                    )
                }
                if isSeparatedFromAssignments,
                   shouldReplacePlan(
                    bestSeparatedPlan,
                    currentCoverage: bestSeparatedNewCoverage,
                    currentPreferredDistance: bestSeparatedPreferredDistance,
                    candidatePoint: point,
                    candidateScore: score,
                    candidateCoverage: newHits.count,
                    candidatePreferredDistance: preferredDistance
                   ) {
                    bestSeparatedPlan = LaunchPlan(
                        targetPoint: point,
                        claimedTrackIDs: claimed,
                        eta: eta,
                        score: score
                    )
                    bestSeparatedNewCoverage = newHits.count
                    bestSeparatedPreferredDistance = preferredDistance
                }
            }

            let selectedPlan: LaunchPlan?
            if reservingAssignments, let bestSeparatedPlan {
                selectedPlan = bestSeparatedPlan
                appendLog("Using non-overlapping impact plan.")
            } else {
                selectedPlan = bestPlan
            }

            if let selectedPlan {
                appendLog(
                    "Selected point (\(Int(selectedPlan.targetPoint.x)), \(Int(selectedPlan.targetPoint.y))) " +
                    "score=\(String(format: "%.2f", selectedPlan.score)) " +
                    "claimed=\(selectedPlan.claimedTrackIDs.count)"
                )
            } else {
                appendLog("No launch plan survived overlap/range constraints.")
            }
            return selectedPlan
        }

        private func impactedTrackIDs(
            around point: CGPoint,
            blastRadius: CGFloat,
            eta: TimeInterval
        ) -> Set<ObjectIdentifier> {
            if blastRadius > 0.01 {
                let radiusSquared = blastRadius * blastRadius
                let hits = tracks.values.filter { track in
                    let predicted = predictedPosition(for: track, after: eta)
                    return Self.squaredDistance(predicted, point) <= radiusSquared
                }
                return Set(hits.map(\.id))
            }

            var nearestID: ObjectIdentifier?
            var nearestDistanceSquared = CGFloat.greatestFiniteMagnitude
            for track in tracks.values {
                let predicted = predictedPosition(for: track, after: eta)
                let distanceSquared = Self.squaredDistance(predicted, point)
                if distanceSquared < nearestDistanceSquared {
                    nearestDistanceSquared = distanceSquared
                    nearestID = track.id
                }
            }
            guard let nearestID else { return [] }
            let maxSnapDistanceSquared =
                InPlaySKScene.singleTargetReservationSnapDistance * InPlaySKScene.singleTargetReservationSnapDistance
            guard nearestDistanceSquared <= maxSnapDistanceSquared else {
                return []
            }
            return [nearestID]
        }

        private func claimedTrackIDs(
            around point: CGPoint,
            blastRadius: CGFloat,
            eta: TimeInterval
        ) -> Set<ObjectIdentifier> {
            impactedTrackIDs(around: point, blastRadius: blastRadius, eta: eta)
        }

        private func isTrackReserved(
            hitID: ObjectIdentifier,
            predictedPosition: CGPoint,
            by assignments: [Assignment]
        ) -> Bool {
            for assignment in assignments {
                if !assignment.claimedTrackIDs.isEmpty {
                    if assignment.claimedTrackIDs.contains(hitID) { return true }
                    continue
                }
                if isPointCovered(predictedPosition, by: assignment) { return true }
            }
            return false
        }

        private func isPointCovered(_ point: CGPoint, by assignment: Assignment) -> Bool {
            let coverageRadius: CGFloat = assignment.spec.blastRadius > 0.01
                ? assignment.spec.blastRadius
                : InPlaySKScene.singleTargetReservationCoverageRadius
            return Self.squaredDistance(point, assignment.targetPoint) <= coverageRadius * coverageRadius
        }

        private func softAvoidanceRadius(
            for assignment: Assignment,
            candidateBlastRadius: CGFloat
        ) -> CGFloat {
            let assignmentCoverage: CGFloat = assignment.spec.blastRadius > 0.01
                ? assignment.spec.blastRadius
                : InPlaySKScene.singleTargetReservationCoverageRadius * 2.2
            let candidateCoverage: CGFloat = candidateBlastRadius > 0.01
                ? candidateBlastRadius
                : InPlaySKScene.singleTargetReservationCoverageRadius * 1.6
            return max(assignmentCoverage, candidateCoverage)
        }

        private func isBlastSeparated(
            candidatePoint: CGPoint,
            candidateBlastRadius: CGFloat,
            from assignment: Assignment
        ) -> Bool {
            let minimumDistance = blastConflictDistance(
                candidateBlastRadius: candidateBlastRadius,
                assignment: assignment
            )
            return Self.squaredDistance(candidatePoint, assignment.targetPoint) >= minimumDistance * minimumDistance
        }

        private func blastConflictDistance(
            candidateBlastRadius: CGFloat,
            assignment: Assignment
        ) -> CGFloat {
            let assignmentCoverage: CGFloat = assignment.spec.blastRadius > 0.01
                ? assignment.spec.blastRadius
                : InPlaySKScene.singleTargetReservationCoverageRadius
            let candidateCoverage: CGFloat = candidateBlastRadius > 0.01
                ? candidateBlastRadius
                : InPlaySKScene.singleTargetReservationCoverageRadius
            return assignmentCoverage + candidateCoverage
        }

        private mutating func pruneExpiredImpactLocks(currentTime: TimeInterval) {
            assignments = assignments.filter { _, assignment in
                switch assignment.phase {
                case .inFlight:
                    return true
                case let .impactLock(expiresAt):
                    return expiresAt > currentTime
                }
            }
        }

        private func predictedPosition(for track: TrackState, after delta: TimeInterval) -> CGPoint {
            CGPoint(
                x: track.position.x + track.velocity.dx * delta,
                y: track.position.y + track.velocity.dy * delta
            )
        }

        private func estimatedETA(
            origin: CGPoint?,
            target: CGPoint,
            speed: CGFloat,
            acceleration: CGFloat = 0,
            maxSpeed: CGFloat = .greatestFiniteMagnitude
        ) -> TimeInterval {
            guard let origin else { return 0 }
            let distance = sqrt(Self.squaredDistance(origin, target))
            let v0 = max(speed, 1)
            guard distance > 0.0001 else { return 0 }
            guard acceleration > 0.0001, v0 < maxSpeed else {
                return TimeInterval(distance / v0)
            }
            let vMax = maxSpeed
            let a = acceleration
            let tAccel = (vMax - v0) / a
            let dAccel = v0 * tAccel + 0.5 * a * tAccel * tAccel
            if dAccel >= distance {
                // Rocket is still accelerating when it reaches target
                let t = (-v0 + sqrt(v0 * v0 + 2 * a * distance)) / a
                return TimeInterval(t)
            }
            // Accelerate to max, then cruise
            return TimeInterval(tAccel + (distance - dAccel) / vMax)
        }

        private static func squaredDistance(_ lhs: CGPoint, _ rhs: CGPoint) -> CGFloat {
            let dx = lhs.x - rhs.x
            let dy = lhs.y - rhs.y
            return dx * dx + dy * dy
        }

        private mutating func appendLog(_ line: String) {
            decisionLog.append(line)
            let maxEntries = 60
            if decisionLog.count > maxEntries {
                decisionLog.removeFirst(decisionLog.count - maxEntries)
            }
        }
    }

    private func aliveThreatDrones() -> [AttackDroneEntity] {
        let halfScreenY = frame.height * 0.5
        return activeDrones.filter { drone in
            guard !drone.isHit else { return false }
            guard let position = drone.component(ofType: SpriteComponent.self)?.spriteNode.position else { return false }
            return position.y <= halfScreenY
        }
    }

    private func syncFireControlState() {
        let rocketsInFlightIDs = Set(activeRockets.map { ObjectIdentifier($0) })
        fireControl.syncAssignments(
            withActiveRocketIDs: rocketsInFlightIDs,
            currentTime: elapsedGameplayTime
        )
        fireControl.syncTracks(
            with: aliveThreatDrones(),
            currentTime: elapsedGameplayTime,
            sceneHeight: frame.height
        )
    }

    private func fireControlProfile(
        radius: CGFloat?,
        influenceRadius: CGFloat?,
        projectileSpeed: CGFloat?,
        acceleration: CGFloat? = nil,
        maxSpeed: CGFloat? = nil
    ) -> FireControlState.PlanningProfile {
        FireControlState.PlanningProfile(
            blastRadius: max(0, influenceRadius ?? rocketSpec.blastRadius),
            maxRange: radius,
            nominalSpeed: max(120, projectileSpeed ?? rocketSpec.initialSpeed),
            acceleration: acceleration ?? rocketSpec.acceleration,
            maxSpeed: maxSpeed ?? rocketSpec.maxSpeed
        )
    }

    private func plannedRocketLaunch(
        preferredPoint: CGPoint?,
        origin: CGPoint?,
        reservingActiveRocketImpacts: Bool,
        excludingRocket: RocketEntity?,
        radius: CGFloat?,
        influenceRadius: CGFloat?,
        projectileSpeed: CGFloat?,
        acceleration: CGFloat? = nil,
        maxSpeed: CGFloat? = nil
    ) -> FireControlState.LaunchPlan? {
        syncFireControlState()
        return fireControl.planLaunch(
            preferredPoint: preferredPoint,
            origin: origin,
            reservingAssignments: reservingActiveRocketImpacts,
            excludingRocketID: excludingRocket.map { ObjectIdentifier($0) },
            profile: fireControlProfile(
                radius: radius,
                influenceRadius: influenceRadius,
                projectileSpeed: projectileSpeed,
                acceleration: acceleration,
                maxSpeed: maxSpeed
            )
        )
    }

    func bestRocketTargetPoint(
        preferredPoint: CGPoint? = nil,
        origin: CGPoint? = nil,
        radius: CGFloat? = nil,
        influenceRadius: CGFloat? = nil,
        reservingActiveRocketImpacts: Bool = false,
        excludingRocket: RocketEntity? = nil
    ) -> CGPoint? {
        plannedRocketLaunch(
            preferredPoint: preferredPoint,
            origin: origin,
            reservingActiveRocketImpacts: reservingActiveRocketImpacts,
            excludingRocket: excludingRocket,
            radius: radius,
            influenceRadius: influenceRadius,
            projectileSpeed: rocketSpec.initialSpeed,
            acceleration: rocketSpec.acceleration,
            maxSpeed: rocketSpec.maxSpeed
        )?.targetPoint
    }

    func bestRocketTargetPoint(
        preferredPoint: CGPoint? = nil,
        origin: CGPoint? = nil,
        radius: CGFloat? = nil,
        influenceRadius: CGFloat? = nil,
        reservingActiveRocketImpacts: Bool = false,
        excludingRocket: RocketEntity? = nil,
        projectileSpeed: CGFloat,
        projectileAcceleration: CGFloat? = nil,
        projectileMaxSpeed: CGFloat? = nil
    ) -> CGPoint? {
        plannedRocketLaunch(
            preferredPoint: preferredPoint,
            origin: origin,
            reservingActiveRocketImpacts: reservingActiveRocketImpacts,
            excludingRocket: excludingRocket,
            radius: radius,
            influenceRadius: influenceRadius,
            projectileSpeed: projectileSpeed,
            acceleration: projectileAcceleration,
            maxSpeed: projectileMaxSpeed
        )?.targetPoint
    }

    func updateRocketReservation(
        for rocket: RocketEntity,
        targetPoint overrideTargetPoint: CGPoint? = nil
    ) {
        syncFireControlState()
        let rocketID = ObjectIdentifier(rocket)
        let targetPoint = overrideTargetPoint ?? rocket.guidanceTargetPointForDisplay
        let launchOrigin = rocket.component(ofType: SpriteComponent.self)?.spriteNode.position
        fireControl.upsertAssignment(
            rocketID: rocketID,
            spec: rocket.spec,
            targetPoint: targetPoint,
            launchOrigin: launchOrigin,
            currentTime: elapsedGameplayTime
        )
    }

    func onRocketDetonated(
        _ rocket: RocketEntity,
        at position: CGPoint,
        blastRadius: CGFloat
    ) {
        fireControl.lockAssignmentForImpact(
            rocketID: ObjectIdentifier(rocket),
            impactPoint: position,
            impactRadius: blastRadius,
            currentTime: elapsedGameplayTime,
            lockDuration: Self.rocketImpactLockDuration
        )
    }

    private func launchRocket(
        launchPlan: FireControlState.LaunchPlan,
        startPosition: CGPoint?,
        spec: Constants.GameBalance.RocketSpec
    ) {
        let rocket = RocketEntity(spec: spec)
        guard let rocketSprite = rocket.component(ofType: SpriteComponent.self)?.spriteNode else { return }

        let start = startPosition ?? CGPoint(x: frame.midX, y: 0)
        rocketSprite.position = start
        rocketSprite.zRotation = 0
        rocket.configureFlight(
            targetPoint: launchPlan.targetPoint,
            initialSpeed: spec.initialSpeed,
            climbsWhenNoTargets: false
        )
        addEntity(rocket)
        fireControl.upsertAssignment(
            rocketID: ObjectIdentifier(rocket),
            spec: spec,
            targetPoint: launchPlan.targetPoint,
            launchOrigin: start,
            currentTime: elapsedGameplayTime,
            forcedClaimedTrackIDs: launchPlan.claimedTrackIDs
        )
        ensureRocketAimMarker(for: rocket)
    }

    private func ensureRocketAimMarker(for rocket: RocketEntity) {
        let rocketID = ObjectIdentifier(rocket)
        if rocketAimMarkers[rocketID] == nil {
            let marker = makeRocketAimMarkerNode(for: rocket.spec.type)
            marker.name = Self.rocketAimMarkerNodeName
            marker.zPosition = 92
            addChild(marker)
            rocketAimMarkers[rocketID] = marker
        }
        updateRocketAimMarker(for: rocket)
    }

    private func updateRocketAimMarker(for rocket: RocketEntity) {
        let rocketID = ObjectIdentifier(rocket)
        guard let marker = rocketAimMarkers[rocketID] else { return }
        guard rocket.shouldShowGuidanceMarker else {
            marker.isHidden = true
            return
        }
        marker.isHidden = false
        marker.position = rocket.guidanceTargetPointForDisplay
    }

    private func removeRocketAimMarker(for rocket: RocketEntity) {
        let rocketID = ObjectIdentifier(rocket)
        guard let marker = rocketAimMarkers.removeValue(forKey: rocketID) else { return }
        marker.removeFromParent()
    }

    private func clearRocketAimMarkers() {
        for marker in rocketAimMarkers.values {
            marker.removeFromParent()
        }
        rocketAimMarkers.removeAll()
    }

    private func syncRocketAimMarkers() {
        let activeIDs = Set(activeRockets.map { ObjectIdentifier($0) })

        let staleIDs = rocketAimMarkers.keys.filter { !activeIDs.contains($0) }
        for staleID in staleIDs {
            rocketAimMarkers[staleID]?.removeFromParent()
            rocketAimMarkers.removeValue(forKey: staleID)
        }

        for rocket in activeRockets {
            ensureRocketAimMarker(for: rocket)
        }
    }

    private func makeRocketAimMarkerNode(for type: Constants.GameBalance.RocketType) -> SKShapeNode {
        let radius: CGFloat = 9
        let path = CGMutablePath()
        path.addEllipse(in: CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2))
        path.move(to: CGPoint(x: -radius - 4, y: 0))
        path.addLine(to: CGPoint(x: radius + 4, y: 0))
        path.move(to: CGPoint(x: 0, y: -radius - 4))
        path.addLine(to: CGPoint(x: 0, y: radius + 4))

        let marker = SKShapeNode(path: path)
        marker.fillColor = .clear
        marker.lineWidth = 1.6
        marker.strokeColor = (type == .interceptor) ? .systemTeal : .systemOrange
        marker.alpha = 0.95
        return marker
    }

    // MARK: - Gun Setup

    private func setupPistolGun(_ view: UIView) -> GunEntity {
        let bullet = BulletEntity(
            damage: Constants.GameBalance.defaultBulletDamage,
            startImpact: Constants.GameBalance.defaultBulletStartImpact,
            imageName: "Bullet"
        )
        return PistolGun(view, shell: bullet)
    }

    private func setupMiniGun(_ view: UIView) -> GunEntity {
        let bullet = BulletEntity(
            damage: Constants.GameBalance.defaultBulletDamage,
            startImpact: Constants.GameBalance.defaultBulletStartImpact,
            imageName: "Bullet"
        )
        return MiniGun(view, shell: bullet)
    }

    private func setupDickGun(_ view: UIView) -> GunEntity {
        let bullet = BulletEntity(
            damage: Constants.GameBalance.defaultBulletDamage,
            startImpact: Constants.GameBalance.defaultBulletStartImpact,
            imageName: "BulletY"
        )
        return DickGun(view, shell: bullet)
    }

    private func setupMainGun(_ view: UIView) {
        mainGun = setupMiniGun(view)
        if let mainGun {
            addEntity(mainGun)
        }
    }

    // MARK: - Drone Pool & Spawning

    private func prepareDronePool(_ view: UIView) {
        guard isRegularDroneFeatureEnabled else { return }
        guard availableDrones.isEmpty, activeDrones.isEmpty else { return }
        for _ in 0..<Constants.GameBalance.dronesPerWave {
            availableDrones.append(setupAttackDrone(view))
        }
    }

    private func setupArmyOfAttackDrones(_ view: UIView, count: Int, speed: CGFloat) {
        while availableDrones.count < count {
            availableDrones.append(setupAttackDrone(view))
        }

        for _ in 0..<count {
            guard let drone = availableDrones.popLast() else { break }
            drone.resetFlight(flyingPath: makeRandomFlyingPath(for: view), speed: speed)
            activeDrones.append(drone)
            addEntity(drone)
        }
    }

    private func setupAttackDrone(_ view: UIView) -> AttackDroneEntity {
        AttackDroneEntity(
            damage: 1,
            speed: Constants.GameBalance.droneSpeed,
            imageName: "Drone",
            flyingPath: makeRandomFlyingPath(for: view)
        )
    }

    private func setupMineLayerDrone() -> MineLayerDroneEntity {
        let mineLayer = MineLayerDroneEntity(sceneFrame: frame)
        mineLayer.mineLayerDelegate = self
        return mineLayer
    }

    private func mineLayersForWave(_ wave: Int) -> Int {
        guard isMineLayerFeatureEnabled else { return 0 }
        guard wave >= Constants.GameBalance.mineLayerFirstWave else { return 0 }
        return Constants.GameBalance.mineLayerBasePerWave
    }

    private func spawnMineLayers(_ count: Int) {
        guard count > 0 else { return }
        for _ in 0..<count {
            let mineLayer = setupMineLayerDrone()
            mineLayer.beginCycle(in: frame)
            activeDrones.append(mineLayer)
            addEntity(mineLayer)
        }
    }

    private func makeRandomFlyingPath(for view: UIView) -> FlyingPath {
        FlyingPath(
            topLevel: view.frame.height,
            bottomLevel: 30,
            leadingLevel: 0,
            trailingLevel: view.frame.width,
            startLevel: view.frame.height,
            endLevel: 0,
            pathGenerator: { flyingPath in
                var nodes = [vector_float2]()
                nodes.append(
                    vector_float2(
                        x: Float.random(in: flyingPath.leadingLevel...flyingPath.trailingLevel),
                        y: Float(flyingPath.startLevel)
                    )
                )
                let counter = Int.random(
                    in: Constants.GameBalance.dronePathMinNodes...Constants.GameBalance.dronePathMaxNodes
                )
                for i in 1..<counter {
                    nodes.append(
                        vector_float2(
                            x: Float.random(in: flyingPath.leadingLevel...flyingPath.trailingLevel),
                            y: flyingPath.topLevel * Float(counter - i) / Float(counter)
                        )
                    )
                }
                nodes.append(vector_float2(x: Float(flyingPath.trailingLevel / 2), y: Float(flyingPath.endLevel)))
                return nodes
            }
        )
    }

    // MARK: - HUD Updates

    private func updateHUD() {
        scoreLabel?.text = "Score: \(score)"
        waveLabel?.text = "Wave \(currentWave)"
        livesLabel?.text = "Lives: \(lives)"
    }

    // MARK: - Game Events

    func onDroneDestroyed(drone: AttackDroneEntity? = nil) {
        guard gameState == .playing else { return }
        if let drone, !activeDrones.contains(drone) { return }
        let scoreDelta: Int
        if drone is MineLayerDroneEntity {
            scoreDelta = Constants.GameBalance.scorePerMineLayerDrone
        } else {
            scoreDelta = Constants.GameBalance.scorePerDrone
        }
        score += scoreDelta
        dronesDestroyed += 1
        updateHUD()
    }

    func onDroneReachedGround(drone: AttackDroneEntity? = nil) {
        guard gameState == .playing else { return }
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

    private func cleanupStrayDrones() {
        guard gameState == .playing else { return }
        let dronesSnapshot = activeDrones
        let bottomThreshold: CGFloat = -40
        let sideTopThreshold: CGFloat = 120
        let activeIDs = Set(dronesSnapshot.map { ObjectIdentifier($0) })
        reroutedDroneIDs = reroutedDroneIDs.intersection(activeIDs)

        for drone in dronesSnapshot {
            guard let droneNode = drone.component(ofType: SpriteComponent.self)?.spriteNode else {
                removeEntity(drone)
                continue
            }
            if droneNode.parent == nil {
                removeEntity(drone)
                continue
            }

            if drone is MineLayerDroneEntity {
                if droneNode.position.y < bottomThreshold && drone.isHit {
                    removeEntity(drone)
                }
                continue
            }

            // Life penalty is applied only for drones that escaped through the bottom.
            if droneNode.position.y < bottomThreshold {
                if drone.isHit {
                    removeEntity(drone)
                } else {
                    onDroneReachedGround(drone: drone)
                    drone.reachedDestination()
                }
                continue
            }

            // If a live drone escaped via top/sides, reroute it back to a natural flight path.
            if !drone.isHit &&
                (droneNode.position.x < -sideTopThreshold ||
                 droneNode.position.x > frame.width + sideTopThreshold ||
                 droneNode.position.y > frame.height + sideTopThreshold) {
                let droneID = ObjectIdentifier(drone)
                if !reroutedDroneIDs.contains(droneID) {
                    let recoveryPath = makeRecoveryFlyingPath(from: droneNode.position)
                    drone.resetFlight(flyingPath: recoveryPath, speed: drone.speed)
                    reroutedDroneIDs.insert(droneID)
                }
                continue
            }

            // Drone returned to normal play area, no need to track reroute state.
            if droneNode.position.x >= -20,
               droneNode.position.x <= frame.width + 20,
               droneNode.position.y <= frame.height + 20 {
                reroutedDroneIDs.remove(ObjectIdentifier(drone))
            }

            if !drone.isHit && droneNode.position.y <= 1 {
                onDroneReachedGround(drone: drone)
                drone.reachedDestination()
            }
        }
    }

    private func makeRecoveryFlyingPath(from start: CGPoint) -> FlyingPath {
        let safeX = min(max(start.x, 30), frame.width - 30)
        let midY = min(max(start.y - 120, frame.height * 0.45), frame.height * 0.75)
        let secondY = max(midY - 180, 130)
        let midX = frame.width * 0.5
        return FlyingPath(
            topLevel: frame.height,
            bottomLevel: 0,
            leadingLevel: 0,
            trailingLevel: frame.width,
            startLevel: start.y,
            endLevel: 0,
            pathGenerator: { _ in
                [
                    vector_float2(x: Float(safeX), y: Float(start.y)),
                    vector_float2(x: Float(midX), y: Float(midY)),
                    vector_float2(x: Float(midX), y: Float(secondY)),
                    vector_float2(x: Float(midX), y: 0)
                ]
            }
        )
    }

    func spawnRocketBlast(at position: CGPoint, radius: CGFloat) {
        spawnBlast(
            name: Self.rocketBlastNodeName,
            at: position,
            radius: radius,
            fillColor: UIColor.orange.withAlphaComponent(0.35),
            strokeColor: .red
        )
    }

    func spawnMineBombBlast(at position: CGPoint) {
        spawnBlast(
            name: Self.mineBombBlastNodeName,
            at: position,
            radius: Constants.GameBalance.mineBombBlastRadius,
            fillColor: UIColor.systemYellow.withAlphaComponent(0.33),
            strokeColor: .orange
        )
    }

    private func spawnBlast(
        name: String,
        at position: CGPoint,
        radius: CGFloat,
        fillColor: UIColor,
        strokeColor: UIColor
    ) {
        let blast = SKSpriteNode(texture: Self.blastTexture)
        blast.size = CGSize(width: radius * 2, height: radius * 2)
        blast.name = name
        blast.position = position
        blast.zPosition = 90
        blast.color = fillColor
        blast.colorBlendFactor = 1.0
        blast.physicsBody = SKPhysicsBody(circleOfRadius: radius)
        blast.physicsBody?.isDynamic = false
        blast.physicsBody?.categoryBitMask = Constants.rocketBlastBitMask
        blast.physicsBody?.contactTestBitMask = Constants.droneBitMask
        blast.physicsBody?.collisionBitMask = 0
        addChild(blast)

        let scale = SKAction.scale(to: 1.2, duration: Self.rocketBlastScaleDuration)
        let fade = SKAction.fadeOut(withDuration: Self.rocketBlastFadeDuration)
        let remove = SKAction.removeFromParent()
        blast.run(SKAction.sequence([SKAction.group([scale, fade]), remove]))
    }

    func mineLayer(
        _ mineLayer: MineLayerDroneEntity,
        spawnBombAt position: CGPoint,
        isFromCrashedDrone: Bool
    ) {
        guard gameState == .playing else { return }
        let mineBomb = MineBombEntity()
        mineBomb.configureOrigin(
            isFromCrashedDrone: isFromCrashedDrone,
            sourceDrone: mineLayer
        )
        mineBomb.place(at: position)
        mineBombsDropped += 1
        addEntity(mineBomb)
    }

    func mineLayerDidExitForRearm(_ mineLayer: MineLayerDroneEntity) {
        guard gameState == .playing else { return }
        guard activeDrones.contains(mineLayer), !mineLayer.isHit else { return }
        let ticket = MineLayerRearmTicket(
            drone: mineLayer,
            sourceWave: currentWave,
            readyAt: elapsedGameplayTime + Constants.GameBalance.mineLayerRearmCooldown
        )
        mineLayerRearmTickets.append(ticket)
        removeEntity(mineLayer)
    }

    func onMineReachedGround(_ mine: MineBombEntity? = nil) {
        guard gameState == .playing else { return }
        if let mine {
            let containsMine = entities.contains { current in
                guard let mineEntity = current as? MineBombEntity else { return false }
                return mineEntity === mine
            }
            if !containsMine { return }
            if mine.isFromCrashedMineLayer { return }
        }
        lives -= 1
        updateHUD()
        if lives <= 0 {
            triggerGameOver()
        }
    }

    func onMineShotInAir(_ mine: MineBombEntity) {
        detonateMineBomb(mine, guaranteedDrone: nil)
    }

    func onMineHitDrone(_ mine: MineBombEntity, drone: AttackDroneEntity?) {
        detonateMineBomb(mine, guaranteedDrone: drone)
    }

    private func detonateMineBomb(_ mine: MineBombEntity, guaranteedDrone: AttackDroneEntity?) {
        guard gameState == .playing else { return }
        let containsMine = entities.contains { current in
            guard let mineEntity = current as? MineBombEntity else { return false }
            return mineEntity === mine
        }
        guard containsMine,
              let position = mine.component(ofType: SpriteComponent.self)?.spriteNode.position
        else { return }
        let blastRadius = Constants.GameBalance.mineBombBlastRadius
        for drone in activeDrones where !drone.isHit {
            guard let dronePosition = drone.component(ofType: SpriteComponent.self)?.spriteNode.position else { continue }
            let dx = dronePosition.x - position.x
            let dy = dronePosition.y - position.y
            if drone === guaranteedDrone || sqrt(dx * dx + dy * dy) <= blastRadius {
                drone.didHit()
                onDroneDestroyed(drone: drone)
            }
        }
        spawnMineBombBlast(at: position)
        mine.silentDetonate()
    }

    private func processMineLayerRearm() {
        guard gameState == .playing else { return }
        guard !mineLayerRearmTickets.isEmpty else { return }

        var remainingTickets = [MineLayerRearmTicket]()
        for ticket in mineLayerRearmTickets {
            // Wave already advanced: return as bonus in the next wave, not as re-entry in old wave.
            if ticket.sourceWave != currentWave {
                continue
            }
            if elapsedGameplayTime >= ticket.readyAt {
                let drone = ticket.drone
                drone.beginCycle(in: frame)
                activeDrones.append(drone)
                addEntity(drone)
            } else {
                remainingTickets.append(ticket)
            }
        }
        mineLayerRearmTickets = remainingTickets
    }

    private func consumeMineLayerCarryOverBonus(for wave: Int) {
        guard !mineLayerRearmTickets.isEmpty else { return }
        var remainingTickets = [MineLayerRearmTicket]()
        var carryOverCount = 0
        for ticket in mineLayerRearmTickets {
            if ticket.sourceWave == wave {
                carryOverCount += 1
            } else {
                remainingTickets.append(ticket)
            }
        }
        mineLayerRearmTickets = remainingTickets
        pendingMineLayerBonusForNextWave += carryOverCount
    }

    // MARK: - Wave System

    func dronesForWave(_ wave: Int) -> Int {
        Constants.GameBalance.dronesPerWave + (wave - 1) * Constants.GameBalance.waveDroneIncrease
    }

    func speedForWave(_ wave: Int) -> CGFloat {
        Constants.GameBalance.droneSpeed + CGFloat(wave - 1) * Constants.GameBalance.waveSpeedIncrease
    }

    private func startNextWave() {
        resetRocketAutoFireState()
        resetDroneRecoveryState()
        currentWave += 1
        if currentWave > 1 {
            showWaveAnnouncement(wave: currentWave)
            if isRocketLauncherEnabled { rocketAmmo += rocketSpec.ammoPerWave }
            if isInterceptorLauncherEnabled { interceptorAmmo += interceptorRocketSpec.ammoPerWave }
        }
        spawnWave()
        updateHUD()
        updateRocketLauncherUI()
        updateInterceptorLauncherUI()
    }

    private func showWaveAnnouncement(wave: Int) {
        let label = SKLabelNode(fontNamed: Constants.GameBalance.hudFontName)
        label.text = "Wave \(wave)"
        label.fontSize = 40
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

    private func spawnWave() {
        guard let view else { return }
        isWaveInProgress = true
        if isRegularDroneFeatureEnabled {
            setupArmyOfAttackDrones(view, count: dronesForWave(currentWave), speed: speedForWave(currentWave))
        }
        let mineLayerCount = mineLayersForWave(currentWave) + pendingMineLayerBonusForNextWave
        pendingMineLayerBonusForNextWave = 0
        spawnMineLayers(mineLayerCount)
    }

    // MARK: - Game Over

    private func triggerGameOver() {
        transition(to: .gameOver)
        settingsButton?.isHidden = true
        rocketLauncherNode?.isHidden = true
        interceptorLauncherNode?.isHidden = true
        clearRocketAimMarkers()
        showGameOverOverlay()
    }

    private func hideGameOverOverlay() {
        gameOverNode?.removeFromParent()
        gameOverNode = nil
        enumerateChildNodes(withName: "//\(Self.gameOverOverlayNodeName)") { node, _ in
            node.removeFromParent()
        }
    }

    private func showGameOverOverlay() {
        hideGameOverOverlay()
        let overlay = SKNode()
        overlay.name = Self.gameOverOverlayNodeName
        overlay.zPosition = 100
        addChild(overlay)
        gameOverNode = overlay

        let bg = SKSpriteNode(color: UIColor.black.withAlphaComponent(0.75), size: frame.size)
        bg.position = CGPoint(x: frame.width / 2, y: frame.height / 2)
        overlay.addChild(bg)

        let centerX = frame.width / 2
        let centerY = frame.height / 2

        let title = SKLabelNode(fontNamed: Constants.GameBalance.hudFontName)
        title.text = "GAME OVER"
        title.fontSize = 44
        title.fontColor = .red
        title.position = CGPoint(x: centerX, y: centerY + 120)
        overlay.addChild(title)

        let accuracy = shotsFired > 0 ? Int(Double(dronesDestroyed) / Double(shotsFired) * 100) : 0
        let statsTexts = [
            "Score: \(score)",
            "Wave: \(currentWave)",
            "Drones Destroyed: \(dronesDestroyed)",
            "Accuracy: \(accuracy)%"
        ]
        for (i, text) in statsTexts.enumerated() {
            let label = SKLabelNode(fontNamed: Constants.GameBalance.hudFontName)
            label.text = text
            label.fontSize = 24
            label.fontColor = .white
            label.position = CGPoint(x: centerX, y: centerY + 50 - CGFloat(i * 35))
            overlay.addChild(label)
        }

        let playAgainBg = SKSpriteNode(color: .darkGray, size: CGSize(width: 200, height: 50))
        playAgainBg.position = CGPoint(x: centerX, y: centerY - 120)
        playAgainBg.name = "playAgainButton"
        overlay.addChild(playAgainBg)

        let playAgainLabel = SKLabelNode(fontNamed: Constants.GameBalance.hudFontName)
        playAgainLabel.text = "Play Again"
        playAgainLabel.fontSize = 22
        playAgainLabel.fontColor = .green
        playAgainLabel.verticalAlignmentMode = .center
        playAgainLabel.name = "playAgainButton"
        playAgainBg.addChild(playAgainLabel)

        let menuBg = SKSpriteNode(color: .red, size: CGSize(width: 200, height: 50))
        menuBg.position = CGPoint(x: centerX, y: centerY - 185)
        menuBg.name = "menuButton_gameOver"
        overlay.addChild(menuBg)

        let menuLabel = SKLabelNode(fontNamed: Constants.GameBalance.hudFontName)
        menuLabel.text = "Menu"
        menuLabel.fontSize = 22
        menuLabel.fontColor = .white
        menuLabel.verticalAlignmentMode = .center
        menuLabel.name = "menuButton_gameOver"
        menuBg.addChild(menuLabel)
    }

    func playAgain() {
        transition(to: .playing)
        hideGameOverOverlay()
        lastUpdateTime = 0

        let currentDrones = activeDrones
        activeDrones.removeAll()
        for drone in currentDrones {
            removeEntity(drone)
            if !(drone is MineLayerDroneEntity), !availableDrones.contains(drone) {
                availableDrones.append(drone)
            }
        }
        let transientEntities = entities.filter { $0 is Shell || $0 is MineBombEntity }
        for entity in transientEntities {
            removeEntity(entity)
        }
        bulletPool.removeAll()
        activeRockets.removeAll()
        entityIdentifiers.removeAll()
        clearRocketAimMarkers()
        fireControl.reset()
        for entity in entities {
            entityIdentifiers.insert(ObjectIdentifier(entity))
        }

        score = 0
        lives = Constants.GameBalance.defaultLives
        shotsFired = 0
        dronesDestroyed = 0
        currentWave = 0
        isWaveInProgress = false
        rocketAmmo = isRocketLauncherEnabled ? rocketSpec.defaultAmmo : 0
        rocketCooldownRemaining = 0
        interceptorAmmo = isInterceptorLauncherEnabled ? interceptorRocketSpec.defaultAmmo : 0
        interceptorCooldownRemaining = 0
        elapsedGameplayTime = 0
        mineBombsDropped = 0
        mineLayerRearmTickets.removeAll()
        pendingMineLayerBonusForNextWave = 0
        resetRocketAutoFireState()
        resetDroneRecoveryState()

        settingsButton?.isHidden = false
        rocketLauncherNode?.isHidden = false
        interceptorLauncherNode?.isHidden = false
        updateHUD()
        updateRocketLauncherUI()
        updateInterceptorLauncherUI()
        startNextWave()
    }

    func returnToMenu() {
        stopGame()
    }

    // MARK: - Pause & Settings

    private func presentPauseMenu() {
        guard gameState == .playing else { return }
        settingsMenu?.isHidden = false
        transition(to: .paused)
        isTouched = false
    }

    private func resumeGame() {
        guard gameState == .paused else { return }
        settingsMenu?.isHidden = true
        transition(to: .playing)
        lastUpdateTime = 0
    }

    private func exitToMainMenu() {
        resumeGame()
        stopGame()
    }

    // MARK: - Start & Stop

    func startGame() {
        guard view != nil else { return }
        guard gameState == .menu else { return }

        transition(to: .playing)
        clearRocketAimMarkers()
        isTouched = false
        settingsButton?.isHidden = false
        settingsMenu?.isHidden = true
        weaponRow?.isHidden = true

        score = 0
        lives = Constants.GameBalance.defaultLives
        shotsFired = 0
        dronesDestroyed = 0
        currentWave = 0
        rocketAmmo = isRocketLauncherEnabled ? rocketSpec.defaultAmmo : 0
        rocketCooldownRemaining = 0
        interceptorAmmo = isInterceptorLauncherEnabled ? interceptorRocketSpec.defaultAmmo : 0
        interceptorCooldownRemaining = 0
        elapsedGameplayTime = 0
        mineBombsDropped = 0
        mineLayerRearmTickets.removeAll()
        pendingMineLayerBonusForNextWave = 0
        fireControl.reset()
        resetRocketAutoFireState()
        resetDroneRecoveryState()

        hudNode?.isHidden = false
        rocketLauncherNode?.isHidden = false
        interceptorLauncherNode?.isHidden = false
        updateHUD()
        updateRocketLauncherUI()
        updateInterceptorLauncherUI()
        startNextWave()
    }

    func stopGame() {
        transition(to: .menu)
        isWaveInProgress = false
        settingsButton?.isHidden = true
        settingsMenu?.isHidden = true
        hudNode?.isHidden = true
        rocketLauncherNode?.isHidden = true
        interceptorLauncherNode?.isHidden = true
        hideGameOverOverlay()
        weaponRow?.isHidden = false
        isTouched = false
        lastUpdateTime = 0
        lastTap = Constants.noTapPoint
        rocketCooldownRemaining = 0
        rocketAmmo = isRocketLauncherEnabled ? rocketSpec.defaultAmmo : 0
        interceptorCooldownRemaining = 0
        interceptorAmmo = isInterceptorLauncherEnabled ? interceptorRocketSpec.defaultAmmo : 0
        elapsedGameplayTime = 0
        mineBombsDropped = 0
        mineLayerRearmTickets.removeAll()
        pendingMineLayerBonusForNextWave = 0
        fireControl.reset()
        resetRocketAutoFireState()
        resetDroneRecoveryState()

        let currentDrones = activeDrones
        activeDrones.removeAll()
        for drone in currentDrones {
            removeEntity(drone)
            if !(drone is MineLayerDroneEntity), !availableDrones.contains(drone) {
                availableDrones.append(drone)
            }
        }

        let transientEntities = entities.filter { $0 is Shell || $0 is MineBombEntity }
        for entity in transientEntities {
            removeEntity(entity)
        }

        enumerateChildNodes(withName: "//\(Self.rocketBlastNodeName)") { node, _ in
            node.removeFromParent()
        }
        clearRocketAimMarkers()
    }

    var hasGameOverOverlay: Bool {
        childNode(withName: "//\(Self.gameOverOverlayNodeName)") != nil
    }

    // MARK: - Scene Lifecycle

    override func didMove(to view: SKView) {
        super.didMove(to: view)
        size = view.frame.size
        backgroundColor = .white
        physicsWorld.contactDelegate = collisionDelegate
        collisionDelegate.gameScene = self
        setupBackground(view)
        setupGround(view)
        setupMainGun(view)
        setupMainMenu(view)
        setupSettingsButton(view)
        setupSettingsMenu(view)
        setupHUD()
        setupRocketLauncher()
        setupInterceptorLauncher()
        prepareDronePool(view)
    }

    // MARK: - Entity Management

    public func addEntity(_ entity: GKEntity) {
        let id = ObjectIdentifier(entity)
        guard !entityIdentifiers.contains(id) else { return }
        if gameState == .playing && entity is Shell {
            shotsFired += 1
        }
        entities.append(entity)
        entityIdentifiers.insert(id)
        if let rocket = entity as? RocketEntity {
            activeRockets.append(rocket)
            ensureRocketAimMarker(for: rocket)
        }
        if let node = entity.component(ofType: SpriteComponent.self)?.spriteNode, node.parent == nil {
            addChild(node)
        }
    }

    public func removeEntity(_ entity: GKEntity) {
        entityIdentifiers.remove(ObjectIdentifier(entity))
        if let rocket = entity as? RocketEntity {
            removeRocketAimMarker(for: rocket)
            fireControl.handleRocketRemoved(ObjectIdentifier(rocket))
            if let idx = activeRockets.firstIndex(where: { $0 === rocket }) {
                activeRockets.remove(at: idx)
            }
        }
        if let node = entity.component(ofType: SpriteComponent.self)?.spriteNode {
            node.removeFromParent()
        }
        if let index = entities.firstIndex(of: entity) {
            entities.remove(at: index)
        }
        if let drone = entity as? AttackDroneEntity,
           let activeIndex = activeDrones.firstIndex(of: drone) {
            activeDrones.remove(at: activeIndex)
            if !(drone is MineLayerDroneEntity),
               !availableDrones.contains(drone) {
                availableDrones.append(drone)
            }
        }
    }

    // MARK: - Bullet Pool

    func dequeueBullet(matching template: BulletEntity) -> BulletEntity? {
        guard !(template is RocketEntity) else { return nil }
        guard let index = bulletPool.lastIndex(where: { $0.imageName == template.imageName }) else {
            return nil
        }
        let bullet = bulletPool.remove(at: index)
        bullet.reset()
        bullet.damage = template.damage
        return bullet
    }

    func returnBulletToPool(_ bullet: BulletEntity) {
        guard !(bullet is RocketEntity),
              bulletPool.count < Self.bulletPoolMaxSize else { return }
        bullet.reset()
        bulletPool.append(bullet)
    }

    // MARK: - Touch Handling

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)

        guard let touch = touches.first else { return }
        let location = touch.location(in: self)
        let touchedNode = atPoint(location)

        if gameState == .gameOver {
            if touchedNode.name == "playAgainButton" {
                playAgain()
            } else if touchedNode.name == "menuButton_gameOver" {
                returnToMenu()
            }
            return
        }
        if gameState == .menu {
            if touchedNode.name == Constants.backgroundName {
                startGame()
            }
            return
        }
        guard gameState == .playing else { return }
        isTouched = true
        lastTap = location
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesMoved(touches, with: event)
        guard gameState == .playing else { return }
        isTouched = true
        if let touch = touches.first {
            lastTap = touch.location(in: self)
        }
    }

    override func touchesEstimatedPropertiesUpdated(_ touches: Set<UITouch>) {
        super.touchesEstimatedPropertiesUpdated(touches)
        touchesBegan(touches, with: nil)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        guard gameState == .playing else { return }
        isTouched = false
        guard let view else { return }
        lastTap = CGPoint(x: view.frame.width / 2, y: view.frame.height)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        touchesEnded(touches, with: event)
    }

    // MARK: - Update Loop

    override func update(_ currentTime: TimeInterval) {
        super.update(currentTime)
        if lastUpdateTime == 0 {
            lastUpdateTime = currentTime
            return
        }

        let dt = currentTime - lastUpdateTime
        if gameState == .playing && rocketCooldownRemaining > 0 {
            rocketCooldownRemaining = max(0, rocketCooldownRemaining - dt)
        }
        if gameState == .playing && interceptorCooldownRemaining > 0 {
            interceptorCooldownRemaining = max(0, interceptorCooldownRemaining - dt)
        }
        if gameState == .playing {
            elapsedGameplayTime += dt
        }
        for entity in entities {
            entity.update(deltaTime: dt)
        }
        if !lastTap.equalTo(Constants.noTapPoint),
           let playerControlled = mainGun?.component(ofType: PlayerControlComponent.self) {
            playerControlled.changedFingerPosition(deltaTime: dt, lastTap: lastTap)
            if isTouched { playerControlled.newTap(deltaTime: dt, lastTap: lastTap) }
        }
        cleanupStrayDrones()
        syncFireControlState()
        processMineLayerRearm()
        registerThreatDroneCrossings()
        fireAutoRocketIfNeeded()
        fireAutoInterceptorIfNeeded()
        lastUpdateTime = currentTime

        if gameState == .playing && isWaveInProgress && activeDrones.isEmpty {
            consumeMineLayerCarryOverBonus(for: currentWave)
            isWaveInProgress = false
            startNextWave()
        }
        updateRocketLauncherUI()
        updateInterceptorLauncherUI()
        syncRocketAimMarkers()
    }
}
