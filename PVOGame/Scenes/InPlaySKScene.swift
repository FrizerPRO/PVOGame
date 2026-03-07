//
//  InPlayScene.swift
//  PVOGame
//
//  Created by Frizer on 04.12.2022.
//

import UIKit
import SpriteKit
import GameplayKit

class InPlaySKScene: SKScene {
    enum GameState {
        case menu
        case playing
        case paused
        case gameOver
    }

    private static let gameOverOverlayNodeName = "gameOverOverlay"
    private static let rocketBlastNodeName = "rocketBlastNode"
    private static let rocketLauncherInsets = CGPoint(x: 24, y: 66)
    private static let rocketVisualSize = CGSize(width: 12, height: 30)
    private static let rocketColumnsPerRow = 10
    private static let rocketColumnSpacing: CGFloat = 4.8
    private static let rocketRowDepthXOffset: CGFloat = 3.2
    private static let rocketRowDepthYOffset: CGFloat = 8.0
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
    private var crossedHalfScreenDroneIDs = Set<ObjectIdentifier>()
    private var pendingAutoRocketTargets = [CGPoint]()
    private var reroutedDroneIDs = Set<ObjectIdentifier>()

    // MARK: - HUD & Overlay
    private var scoreLabel: SKLabelNode?
    private var livesLabel: SKLabelNode?
    private var waveLabel: SKLabelNode?
    private var hudNode: SKNode?
    private var gameOverNode: SKNode?
    private var rocketLauncherNode: SKNode?
    private var rocketAmmoVisuals = [SKSpriteNode]()

    var rocketAmmoCount: Int { rocketAmmo }
    var rocketCooldownRemainingForTests: TimeInterval { rocketCooldownRemaining }
    var activeRocketSpecForTests: Constants.GameBalance.RocketSpec { rocketSpec }
    private var rocketSpec: Constants.GameBalance.RocketSpec {
        Constants.GameBalance.rocketSpec(for: rocketType)
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

    private func currentRocketLaunchPosition() -> CGPoint? {
        guard let rocketLauncherNode else { return nil }
        if let topRocket = rocketAmmoVisuals.last {
            return topRocket.convert(.zero, to: self)
        }
        return rocketLauncherNode.convert(.zero, to: self)
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
        gameState == .playing &&
            rocketAmmo > 0 &&
            rocketCooldownRemaining <= 0.01 &&
            !aliveThreatDrones().isEmpty
    }

    @discardableResult
    func triggerRocketLauncher(targetOverride: CGPoint? = nil) -> Bool {
        guard canFireRocket() else { return false }
        let launchPosition = currentRocketLaunchPosition()
        let preferredTarget = bestRocketTargetPoint(
            preferredPoint: targetOverride,
            origin: launchPosition,
            radius: rocketSpec.maxFlightDistance
        )
        launchRocket(preferredTarget: preferredTarget, startPosition: launchPosition)
        rocketAmmo = max(0, rocketAmmo - 1)
        rocketCooldownRemaining = rocketSpec.cooldown
        updateRocketLauncherUI()
        return true
    }

    private func resetRocketAutoFireState() {
        crossedHalfScreenDroneIDs.removeAll()
        pendingAutoRocketTargets.removeAll()
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

    func evaluateAutoRocketForTests() {
        registerThreatDroneCrossings()
        fireAutoRocketIfNeeded()
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
        radius: CGFloat? = nil
    ) -> CGPoint? {
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
        guard !aliveDrones.isEmpty else { return nil }
        let influence = rocketSpec.blastRadius * 1.2
        var bestPoint: CGPoint?
        var bestDensity = -1
        var bestPreferredDistance = CGFloat.greatestFiniteMagnitude
        for candidate in aliveDrones {
            guard let candidatePosition = candidate.component(ofType: SpriteComponent.self)?.spriteNode.position else {
                continue
            }
            var density = 0
            for other in aliveDrones {
                guard let otherPosition = other.component(ofType: SpriteComponent.self)?.spriteNode.position else {
                    continue
                }
                let dx = candidatePosition.x - otherPosition.x
                let dy = candidatePosition.y - otherPosition.y
                if dx * dx + dy * dy <= influence * influence {
                    density += 1
                }
            }
            let preferredDistance: CGFloat
            if let preferredPoint {
                let px = candidatePosition.x - preferredPoint.x
                let py = candidatePosition.y - preferredPoint.y
                preferredDistance = px * px + py * py
            } else {
                preferredDistance = 0
            }
            if density > bestDensity || (density == bestDensity && preferredDistance < bestPreferredDistance) {
                bestDensity = density
                bestPoint = candidatePosition
                bestPreferredDistance = preferredDistance
            }
        }
        return bestPoint
    }

    private func launchRocket(preferredTarget: CGPoint?, startPosition: CGPoint?) {
        guard let launcherNode = rocketLauncherNode else { return }
        let rocket = RocketEntity(spec: rocketSpec)
        guard let rocketSprite = rocket.component(ofType: SpriteComponent.self)?.spriteNode else { return }

        let start = startPosition ?? launcherNode.convert(.zero, to: self)
        let verticalClimbTarget = CGPoint(x: start.x, y: frame.height + 240)
        rocketSprite.position = start
        rocketSprite.zRotation = 0
        rocket.configureFlight(
            targetPoint: preferredTarget ?? verticalClimbTarget,
            initialSpeed: rocketSpec.initialSpeed
        )
        addEntity(rocket)
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
        score += Constants.GameBalance.scorePerDrone
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
        let blast = SKShapeNode(circleOfRadius: radius)
        blast.name = Self.rocketBlastNodeName
        blast.position = position
        blast.zPosition = 90
        blast.fillColor = UIColor.orange.withAlphaComponent(0.35)
        blast.strokeColor = UIColor.red
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
        }
        spawnWave()
        updateHUD()
        updateRocketLauncherUI()
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
        setupArmyOfAttackDrones(view, count: dronesForWave(currentWave), speed: speedForWave(currentWave))
    }

    // MARK: - Game Over

    private func triggerGameOver() {
        transition(to: .gameOver)
        settingsButton?.isHidden = true
        rocketLauncherNode?.isHidden = true
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
            availableDrones.append(drone)
        }
        let shells = entities.filter { $0 is Shell }
        for shell in shells {
            removeEntity(shell)
        }

        score = 0
        lives = Constants.GameBalance.defaultLives
        shotsFired = 0
        dronesDestroyed = 0
        currentWave = 0
        isWaveInProgress = false
        rocketAmmo = rocketSpec.defaultAmmo
        rocketCooldownRemaining = 0
        resetRocketAutoFireState()
        resetDroneRecoveryState()

        settingsButton?.isHidden = false
        rocketLauncherNode?.isHidden = false
        updateHUD()
        updateRocketLauncherUI()
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
        resetRocketAutoFireState()
        resetDroneRecoveryState()

        hudNode?.isHidden = false
        rocketLauncherNode?.isHidden = false
        updateHUD()
        updateRocketLauncherUI()
        startNextWave()
    }

    func stopGame() {
        transition(to: .menu)
        isWaveInProgress = false
        settingsButton?.isHidden = true
        settingsMenu?.isHidden = true
        hudNode?.isHidden = true
        rocketLauncherNode?.isHidden = true
        hideGameOverOverlay()
        weaponRow?.isHidden = false
        isTouched = false
        lastUpdateTime = 0
        lastTap = Constants.noTapPoint
        rocketCooldownRemaining = 0
        rocketAmmo = rocketSpec.defaultAmmo
        resetRocketAutoFireState()
        resetDroneRecoveryState()

        let currentDrones = activeDrones
        activeDrones.removeAll()
        for drone in currentDrones {
            removeEntity(drone)
            availableDrones.append(drone)
        }

        let shells = entities.filter { $0 is Shell }
        for shell in shells {
            removeEntity(shell)
        }

        enumerateChildNodes(withName: "//\(Self.rocketBlastNodeName)") { node, _ in
            node.removeFromParent()
        }
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
        if let node = entity.component(ofType: SpriteComponent.self)?.spriteNode, node.parent == nil {
            addChild(node)
        }
    }

    public func removeEntity(_ entity: GKEntity) {
        if let node = entity.component(ofType: SpriteComponent.self)?.spriteNode {
            node.removeFromParent()
        }
        if let index = entities.firstIndex(of: entity) {
            entities.remove(at: index)
        }
        if let drone = entity as? AttackDroneEntity,
           let activeIndex = activeDrones.firstIndex(of: drone) {
            activeDrones.remove(at: activeIndex)
            if !availableDrones.contains(drone) {
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
        registerThreatDroneCrossings()
        fireAutoRocketIfNeeded()
        lastUpdateTime = currentTime

        if gameState == .playing && isWaveInProgress && activeDrones.isEmpty {
            isWaveInProgress = false
            startNextWave()
        }
        updateRocketLauncherUI()
    }
}
