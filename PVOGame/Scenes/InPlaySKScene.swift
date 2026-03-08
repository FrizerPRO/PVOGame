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
    private static let singleTargetReservationSnapDistance: CGFloat = 72
    private static let singleTargetReservationCoverageRadius: CGFloat = 18
    var entities = [GKEntity]()
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
    private var mineLayerRearmTickets = [MineLayerRearmTicket]()
    private var pendingMineLayerBonusForNextWave = 0
    private var elapsedGameplayTime: TimeInterval = 0
    private(set) var mineBombsDropped = 0
    private var rocketReservedDroneIDs = [ObjectIdentifier: Set<ObjectIdentifier>]()

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
        for rocketVisual in rocketAmmoVisuals {
            rocketVisual.removeFromParent()
        }
        rocketAmmoVisuals.removeAll()

        guard let rocketLauncherNode else { return }
        guard rocketAmmo > 0 else { return }
        for index in 0..<rocketAmmo {
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
        for rocketVisual in interceptorAmmoVisuals {
            rocketVisual.removeFromParent()
        }
        interceptorAmmoVisuals.removeAll()

        guard let interceptorLauncherNode else { return }
        guard interceptorAmmo > 0 else { return }
        for index in 0..<interceptorAmmo {
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
            rocketAmmo = rocketSpec.defaultAmmo
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
        return resolveRocketLaunchTarget(
            preferredPoint: nil,
            launchPosition: currentRocketLaunchPosition()
        ) != nil
    }

    private func resolveRocketLaunchTarget(
        preferredPoint: CGPoint?,
        launchPosition: CGPoint?
    ) -> CGPoint? {
        bestRocketTargetPoint(
            preferredPoint: preferredPoint,
            origin: launchPosition,
            radius: rocketSpec.maxFlightDistance,
            influenceRadius: rocketSpec.blastRadius,
            reservingActiveRocketImpacts: true
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
        return bestRocketTargetPoint(
            origin: launchPosition,
            radius: interceptorRocketSpec.maxFlightDistance,
            influenceRadius: 0,
            reservingActiveRocketImpacts: true
        ) != nil
    }

    @discardableResult
    func triggerRocketLauncher(targetOverride: CGPoint? = nil) -> Bool {
        guard gameState == .playing,
              rocketAmmo > 0,
              rocketCooldownRemaining <= 0.01
        else {
            return false
        }
        let launchPosition = currentRocketLaunchPosition()
        guard let preferredTarget = resolveRocketLaunchTarget(
            preferredPoint: targetOverride,
            launchPosition: launchPosition
        ) else {
            return false
        }
        launchRocket(preferredTarget: preferredTarget, startPosition: launchPosition, spec: rocketSpec)
        rocketAmmo = max(0, rocketAmmo - 1)
        rocketCooldownRemaining = rocketSpec.cooldown
        updateRocketLauncherUI()
        return true
    }

    @discardableResult
    func triggerInterceptorLauncher(targetOverride: CGPoint? = nil) -> Bool {
        guard canFireInterceptor() else { return false }
        let launchPosition = currentInterceptorLaunchPosition()
        guard let preferredTarget = bestRocketTargetPoint(
            preferredPoint: targetOverride,
            origin: launchPosition,
            radius: interceptorRocketSpec.maxFlightDistance,
            influenceRadius: 0,
            reservingActiveRocketImpacts: true
        ) else {
            return false
        }
        launchRocket(
            preferredTarget: preferredTarget,
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
                    pendingAutoRocketTargets.append(position)
                    pendingAutoInterceptorTargets.append(position)
                }
            } else {
                crossedHalfScreenDroneIDs.remove(droneID)
            }
        }

        let activeIDs = Set(activeDrones.map { ObjectIdentifier($0) })
        crossedHalfScreenDroneIDs = crossedHalfScreenDroneIDs.intersection(activeIDs)
    }

    private func fireAutoRocketIfNeeded() {
        guard canFireRocket(), !pendingAutoRocketTargets.isEmpty else { return }
        while !pendingAutoRocketTargets.isEmpty {
            let target = pendingAutoRocketTargets.removeFirst()
            if triggerRocketLauncher(targetOverride: target) {
                return
            }
        }
    }

    private func fireAutoInterceptorIfNeeded() {
        guard canFireInterceptor(), !pendingAutoInterceptorTargets.isEmpty else { return }
        while !pendingAutoInterceptorTargets.isEmpty {
            let target = pendingAutoInterceptorTargets.removeFirst()
            if triggerInterceptorLauncher(targetOverride: target) {
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

    private func aliveThreatDrones() -> [AttackDroneEntity] {
        let halfScreenY = frame.height * 0.5
        return activeDrones.filter { drone in
            guard !drone.isHit else { return false }
            guard let position = drone.component(ofType: SpriteComponent.self)?.spriteNode.position else { return false }
            return position.y <= halfScreenY
        }
    }

    func bestRocketTargetPoint(
        preferredPoint: CGPoint? = nil,
        origin: CGPoint? = nil,
        radius: CGFloat? = nil,
        influenceRadius: CGFloat? = nil,
        reservingActiveRocketImpacts: Bool = false,
        excludingRocket: RocketEntity? = nil
    ) -> CGPoint? {
        var aliveDrones = filteredThreatDrones(origin: origin, radius: radius)
        let activeReservations: [RocketImpactReservation]
        if reservingActiveRocketImpacts {
            activeReservations = activeRocketImpactReservations(excludingRocket: excludingRocket)
            aliveDrones = applyActiveRocketReservations(
                to: aliveDrones,
                reservations: activeReservations
            )
        } else {
            activeReservations = []
        }

        guard !aliveDrones.isEmpty else { return nil }
        let influence = max(0, influenceRadius ?? rocketSpec.blastRadius)
        return bestRocketTargetPoint(
            from: aliveDrones,
            preferredPoint: preferredPoint,
            influenceRadius: influence,
            reservedImpacts: activeReservations
        )
    }

    private func filteredThreatDrones(origin: CGPoint?, radius: CGFloat?) -> [AttackDroneEntity] {
        var aliveDrones = aliveThreatDrones()
        if let origin, let radius {
            let radiusSquared = radius * radius
            aliveDrones = aliveDrones.filter { drone in
                guard let candidatePosition = drone.component(ofType: SpriteComponent.self)?.spriteNode.position else {
                    return false
                }
                let dx = candidatePosition.x - origin.x
                let dy = candidatePosition.y - origin.y
                return dx * dx + dy * dy <= radiusSquared
            }
        }
        return aliveDrones
    }

    private struct RocketImpactReservation {
        let spec: Constants.GameBalance.RocketSpec
        let targetPoint: CGPoint
        let reservedDroneIDs: Set<ObjectIdentifier>
    }

    private func activeRocketImpactReservations(
        excludingRocket: RocketEntity? = nil
    ) -> [RocketImpactReservation] {
        let rocketsInFlight = entities.compactMap { $0 as? RocketEntity }.filter { rocket in
            guard rocket.shouldShowGuidanceMarker else { return false }
            if let excludingRocket {
                return rocket !== excludingRocket
            }
            return true
        }
        return rocketsInFlight.map { rocket in
            let rocketID = ObjectIdentifier(rocket)
            if rocketReservedDroneIDs[rocketID] == nil {
                updateRocketReservation(for: rocket)
            }
            return RocketImpactReservation(
                spec: rocket.spec,
                targetPoint: rocket.guidanceTargetPointForDisplay,
                reservedDroneIDs: rocketReservedDroneIDs[rocketID] ?? []
            )
        }
    }

    private func applyActiveRocketReservations(
        to drones: [AttackDroneEntity],
        reservations: [RocketImpactReservation]
    ) -> [AttackDroneEntity] {
        var remainingDrones = drones
        for reservation in reservations {
            if !reservation.reservedDroneIDs.isEmpty {
                remainingDrones.removeAll { drone in
                    reservation.reservedDroneIDs.contains(ObjectIdentifier(drone))
                }
                if remainingDrones.isEmpty {
                    return remainingDrones
                }
                continue
            }
            reserveProjectedRocketImpact(
                spec: reservation.spec,
                targetPoint: reservation.targetPoint,
                remainingDrones: &remainingDrones
            )
            if remainingDrones.isEmpty {
                return remainingDrones
            }
        }
        return remainingDrones
    }

    private func reserveProjectedRocketImpact(
        spec: Constants.GameBalance.RocketSpec,
        targetPoint: CGPoint,
        remainingDrones: inout [AttackDroneEntity]
    ) {
        guard !remainingDrones.isEmpty else { return }
        if spec.blastRadius > 0.01 {
            let radiusSquared = spec.blastRadius * spec.blastRadius
            remainingDrones.removeAll { drone in
                guard let dronePoint = drone.component(ofType: SpriteComponent.self)?.spriteNode.position else {
                    return false
                }
                let dx = dronePoint.x - targetPoint.x
                let dy = dronePoint.y - targetPoint.y
                return dx * dx + dy * dy <= radiusSquared
            }
            return
        }

        var nearestIndex: Int?
        var nearestDistance = CGFloat.greatestFiniteMagnitude
        for (index, drone) in remainingDrones.enumerated() {
            guard let dronePoint = drone.component(ofType: SpriteComponent.self)?.spriteNode.position else {
                continue
            }
            let dx = dronePoint.x - targetPoint.x
            let dy = dronePoint.y - targetPoint.y
            let distanceSquared = dx * dx + dy * dy
            if distanceSquared < nearestDistance {
                nearestDistance = distanceSquared
                nearestIndex = index
            }
        }

        guard let nearestIndex else { return }
        let maxSnapDistanceSquared =
            Self.singleTargetReservationSnapDistance * Self.singleTargetReservationSnapDistance
        if nearestDistance <= maxSnapDistanceSquared {
            remainingDrones.remove(at: nearestIndex)
        }
    }

    private func bestRocketTargetPoint(
        from drones: [AttackDroneEntity],
        preferredPoint: CGPoint?,
        influenceRadius: CGFloat,
        reservedImpacts: [RocketImpactReservation]
    ) -> CGPoint? {
        let positionedDrones = drones.compactMap { drone -> CGPoint? in
            drone.component(ofType: SpriteComponent.self)?.spriteNode.position
        }
        guard !positionedDrones.isEmpty else { return nil }

        let influenceRadiusSquared = influenceRadius * influenceRadius
        let useClusterCentroid = influenceRadius > 0.01
        let geometricReservations = reservedImpacts.filter { $0.reservedDroneIDs.isEmpty }
        var bestPoint: CGPoint?
        var bestNewCoverage = -1
        var bestCoverage = -1
        var bestPreferredDistance = CGFloat.greatestFiniteMagnitude

        for candidatePosition in positionedDrones {
            var clusterCount = 0
            var centroidX: CGFloat = 0
            var centroidY: CGFloat = 0

            for otherPosition in positionedDrones {
                let dx = candidatePosition.x - otherPosition.x
                let dy = candidatePosition.y - otherPosition.y
                if dx * dx + dy * dy <= influenceRadiusSquared {
                    clusterCount += 1
                    centroidX += otherPosition.x
                    centroidY += otherPosition.y
                }
            }

            guard clusterCount > 0 else { continue }
            let candidateTargetPoint: CGPoint
            if useClusterCentroid {
                let centroidTarget = CGPoint(
                    x: centroidX / CGFloat(clusterCount),
                    y: centroidY / CGFloat(clusterCount)
                )
                if isPointCoveredByReservations(centroidTarget, reservations: geometricReservations) {
                    candidateTargetPoint = candidatePosition
                } else {
                    candidateTargetPoint = centroidTarget
                }
            } else {
                // Single-target rockets keep locking a concrete drone position.
                candidateTargetPoint = candidatePosition
            }

            var coverage = 0
            var newCoverage = 0
            for otherPosition in positionedDrones {
                let dx = candidateTargetPoint.x - otherPosition.x
                let dy = candidateTargetPoint.y - otherPosition.y
                let isCovered: Bool
                if useClusterCentroid {
                    isCovered = dx * dx + dy * dy <= influenceRadiusSquared
                } else {
                    isCovered = dx * dx + dy * dy <= 1
                }
                guard isCovered else { continue }
                coverage += 1
                if !isPointCoveredByReservations(otherPosition, reservations: geometricReservations) {
                    newCoverage += 1
                }
            }

            guard coverage > 0 else { continue }
            if !reservedImpacts.isEmpty && newCoverage == 0 {
                continue
            }

            let preferredDistance: CGFloat
            if let preferredPoint {
                let px = candidateTargetPoint.x - preferredPoint.x
                let py = candidateTargetPoint.y - preferredPoint.y
                preferredDistance = px * px + py * py
            } else {
                preferredDistance = 0
            }

            if newCoverage > bestNewCoverage
                || (newCoverage == bestNewCoverage && coverage > bestCoverage)
                || (newCoverage == bestNewCoverage
                    && coverage == bestCoverage
                    && preferredDistance < bestPreferredDistance) {
                bestNewCoverage = newCoverage
                bestCoverage = coverage
                bestPoint = candidateTargetPoint
                bestPreferredDistance = preferredDistance
            }
        }

        return bestPoint
    }

    private func isPointCoveredByReservations(
        _ point: CGPoint,
        reservations: [RocketImpactReservation]
    ) -> Bool {
        for reservation in reservations where isPointCoveredByReservation(point, reservation: reservation) {
            return true
        }
        return false
    }

    private func isPointCoveredByReservation(
        _ point: CGPoint,
        reservation: RocketImpactReservation
    ) -> Bool {
        let coverageRadius: CGFloat = reservation.spec.blastRadius > 0.01
            ? reservation.spec.blastRadius
            : Self.singleTargetReservationCoverageRadius
        let dx = point.x - reservation.targetPoint.x
        let dy = point.y - reservation.targetPoint.y
        return dx * dx + dy * dy <= coverageRadius * coverageRadius
    }

    func updateRocketReservation(
        for rocket: RocketEntity,
        targetPoint overrideTargetPoint: CGPoint? = nil
    ) {
        let rocketID = ObjectIdentifier(rocket)
        let targetPoint = overrideTargetPoint ?? rocket.guidanceTargetPointForDisplay
        let reservedIDs = reserveThreatDroneIDs(for: rocket.spec, around: targetPoint)
        if reservedIDs.isEmpty {
            rocketReservedDroneIDs.removeValue(forKey: rocketID)
        } else {
            rocketReservedDroneIDs[rocketID] = reservedIDs
        }
    }

    private func reserveThreatDroneIDs(
        for spec: Constants.GameBalance.RocketSpec,
        around targetPoint: CGPoint
    ) -> Set<ObjectIdentifier> {
        let threatPoints: [(id: ObjectIdentifier, position: CGPoint)] = aliveThreatDrones().compactMap { drone in
            guard let position = drone.component(ofType: SpriteComponent.self)?.spriteNode.position else {
                return nil
            }
            return (ObjectIdentifier(drone), position)
        }
        guard !threatPoints.isEmpty else { return [] }

        if spec.blastRadius > 0.01 {
            let radiusSquared = spec.blastRadius * spec.blastRadius
            let inBlast = threatPoints
                .filter { threat in
                    let dx = threat.position.x - targetPoint.x
                    let dy = threat.position.y - targetPoint.y
                    return dx * dx + dy * dy <= radiusSquared
                }
                .map(\.id)
            if !inBlast.isEmpty {
                return Set(inBlast)
            }
        }

        var nearestID: ObjectIdentifier?
        var nearestDistanceSquared = CGFloat.greatestFiniteMagnitude
        for threat in threatPoints {
            let dx = threat.position.x - targetPoint.x
            let dy = threat.position.y - targetPoint.y
            let distanceSquared = dx * dx + dy * dy
            if distanceSquared < nearestDistanceSquared {
                nearestDistanceSquared = distanceSquared
                nearestID = threat.id
            }
        }
        guard let nearestID else { return [] }
        if spec.blastRadius <= 0.01 {
            let snapDistanceSquared =
                Self.singleTargetReservationSnapDistance * Self.singleTargetReservationSnapDistance
            guard nearestDistanceSquared <= snapDistanceSquared else {
                return []
            }
        }
        return [nearestID]
    }

    private func launchRocket(
        preferredTarget: CGPoint,
        startPosition: CGPoint?,
        spec: Constants.GameBalance.RocketSpec
    ) {
        let rocket = RocketEntity(spec: spec)
        guard let rocketSprite = rocket.component(ofType: SpriteComponent.self)?.spriteNode else { return }

        let start = startPosition ?? CGPoint(x: frame.midX, y: 0)
        rocketSprite.position = start
        rocketSprite.zRotation = 0
        rocket.configureFlight(
            targetPoint: preferredTarget,
            initialSpeed: spec.initialSpeed,
            climbsWhenNoTargets: false
        )
        addEntity(rocket)
        updateRocketReservation(for: rocket, targetPoint: preferredTarget)
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
        let activeRockets = entities.compactMap { $0 as? RocketEntity }
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
        let blast = SKShapeNode(circleOfRadius: radius)
        blast.name = name
        blast.position = position
        blast.zPosition = 90
        blast.fillColor = fillColor
        blast.strokeColor = strokeColor
        blast.lineWidth = 2
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
            rocketAmmo += rocketSpec.ammoPerWave
            interceptorAmmo += interceptorRocketSpec.ammoPerWave
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
        clearRocketAimMarkers()
        rocketReservedDroneIDs.removeAll()

        score = 0
        lives = Constants.GameBalance.defaultLives
        shotsFired = 0
        dronesDestroyed = 0
        currentWave = 0
        isWaveInProgress = false
        rocketAmmo = rocketSpec.defaultAmmo
        rocketCooldownRemaining = 0
        interceptorAmmo = interceptorRocketSpec.defaultAmmo
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
        rocketAmmo = rocketSpec.defaultAmmo
        rocketCooldownRemaining = 0
        interceptorAmmo = interceptorRocketSpec.defaultAmmo
        interceptorCooldownRemaining = 0
        elapsedGameplayTime = 0
        mineBombsDropped = 0
        mineLayerRearmTickets.removeAll()
        pendingMineLayerBonusForNextWave = 0
        rocketReservedDroneIDs.removeAll()
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
        rocketAmmo = rocketSpec.defaultAmmo
        interceptorCooldownRemaining = 0
        interceptorAmmo = interceptorRocketSpec.defaultAmmo
        elapsedGameplayTime = 0
        mineBombsDropped = 0
        mineLayerRearmTickets.removeAll()
        pendingMineLayerBonusForNextWave = 0
        rocketReservedDroneIDs.removeAll()
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
        if entities.contains(entity) {
            return
        }
        if gameState == .playing && entity is Shell {
            shotsFired += 1
        }
        entities.append(entity)
        if let rocket = entity as? RocketEntity {
            ensureRocketAimMarker(for: rocket)
        }
        if let node = entity.component(ofType: SpriteComponent.self)?.spriteNode, node.parent == nil {
            addChild(node)
        }
    }

    public func removeEntity(_ entity: GKEntity) {
        if let rocket = entity as? RocketEntity {
            removeRocketAimMarker(for: rocket)
            rocketReservedDroneIDs.removeValue(forKey: ObjectIdentifier(rocket))
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
            if lastTap.equalTo(Constants.noTapPoint) {
                continue
            }
            if let playerControlled = entity.component(ofType: PlayerControlComponent.self) {
                playerControlled.changedFingerPosition(deltaTime: dt, lastTap: lastTap)
                if isTouched {
                    playerControlled.newTap(deltaTime: dt, lastTap: lastTap)
                }
            }
        }
        cleanupStrayDrones()
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
