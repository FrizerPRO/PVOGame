//
//  Bullet.swift
//  PVOGame
//
//  Created by Frizer on 02.12.2022.
//

import Foundation
import GameplayKit

class BulletEntity: GKEntity, Shell{
    var previousPosition = CGPoint(x: -1,y: -1)
    let startImpact: Int
    internal var damage: Int = 0
    let imageName: String
    
    required init(damage: Int,imageName: String) {
        self.damage = damage
        self.startImpact = 0
        self.imageName = imageName
        super.init()
        let spriteComponent = SpriteComponent(imageName: imageName);
        spriteComponent.spriteNode.size = CGSize(width: 7.0, height: 7.0)
        addComponent(spriteComponent)
        addComponent(ShootComponent())
        addComponent(GeometryComponent(spriteNode: spriteComponent.spriteNode,
                                       categoryBitMask: Constants.bulletBitMask,
                                       contactTestBitMask: Constants.boundsBitMask,
                                       collisionBitMask: 0))
    }
    
    init(damage: Int, startImpact: Int,imageName: String){
        self.damage = damage
        self.startImpact = startImpact
        self.imageName = imageName
        super.init()
        let spriteComponent = SpriteComponent(imageName: imageName);
        spriteComponent.spriteNode.size = CGSize(width: 2, height: 3)
        addComponent(spriteComponent)
        addComponent(ShootComponent())
        addComponent(GeometryComponent(spriteNode: spriteComponent.spriteNode,
                                       categoryBitMask: Constants.bulletBitMask,
                                       contactTestBitMask: Constants.boundsBitMask,
                                       collisionBitMask: 0))
    }
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    func reset() {
        previousPosition = CGPoint(x: -1, y: -1)
        if let spriteNode = component(ofType: SpriteComponent.self)?.spriteNode {
            spriteNode.removeAllActions()
            spriteNode.alpha = 1; spriteNode.xScale = 1; spriteNode.yScale = 1
            spriteNode.zRotation = 0; spriteNode.position = .zero
            spriteNode.physicsBody?.velocity = .zero
            spriteNode.physicsBody?.angularVelocity = 0
        }
    }

    public func detonateWithAnimation(){
        silentDetonate()
    }
    public func silentDetonate(){
        if let scene = component(ofType: SpriteComponent.self)?.spriteNode.scene as? InPlaySKScene{
            scene.removeEntity(self)
        }
    }
    
    override func copy() -> Any {
        let result = BulletEntity(damage: damage, startImpact: startImpact, imageName:imageName)
        return result
    }
    fileprivate func autoDetonation() {
        guard let position = component(ofType: SpriteComponent.self)?.spriteNode.position else { return }
        if previousPosition.x < -0.5 && previousPosition.y < -0.5 {
            previousPosition = position
            return
        }
        let dx = position.x - previousPosition.x
        let dy = position.y - previousPosition.y
        let distSq = dx * dx + dy * dy
        if distSq < 0.25 && previousPosition.x >= 0 {
            detonateWithAnimation()
            return
        }
        previousPosition = position
        // Range-based detonation: check if out of scene bounds
        if let scene = component(ofType: SpriteComponent.self)?.spriteNode.scene {
            let margin: CGFloat = 50
            if position.x < -margin || position.x > scene.frame.width + margin ||
               position.y < -margin || position.y > scene.frame.height + margin {
                silentDetonate()
            }
        }
    }
    
    override func update(deltaTime seconds: TimeInterval) {
        autoDetonation()
    }
    
}

class RocketEntity: BulletEntity {
    private static let smokePuffTexture: SKTexture = {
        let diameter: CGFloat = 18
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: diameter, height: diameter))
        let image = renderer.image { ctx in
            UIColor.white.setFill()
            ctx.cgContext.fillEllipse(in: CGRect(x: 0, y: 0, width: diameter, height: diameter))
        }
        return SKTexture(image: image)
    }()

    private static let smokePuffAction: SKAction = {
        let wait = SKAction.wait(forDuration: 0.15)
        let expand = SKAction.scale(to: 2.5, duration: 0.45)
        let fade = SKAction.fadeOut(withDuration: 0.45)
        return SKAction.sequence([wait, SKAction.group([expand, fade]), SKAction.removeFromParent()])
    }()

    enum GuidancePhase {
        case boost
        case midcourse
        case terminal
        case coast
    }

    let spec: Constants.GameBalance.RocketSpec
    var blastRadius: CGFloat { spec.blastRadius }
    var detonatesOnDirectImpact: Bool { blastRadius <= 0.01 }
    var guidanceTargetPointForDisplay: CGPoint { targetPoint }
    var shouldShowGuidanceMarker: Bool { isGuided && !isCoastingAfterFuelExhaustion }
    private(set) var guidancePhase: GuidancePhase = .boost
    private(set) var currentSpeed: CGFloat = 0
    private(set) var isCoastingAfterFuelExhaustion = false
    private var targetPoint = CGPoint.zero
    private var isGuided = false
    private var smokeSpawnAccumulator: TimeInterval = 0
    private var nightFlameNode: SKSpriteNode?
    private var retargetAccumulator: TimeInterval = 0
    private var climbsWhenNoTargets = true
    private var travelledDistance: CGFloat = 0
    private var previousTrackedPosition: CGPoint?
    private var guidedFlightTime: TimeInterval = 0

    init(
        spec: Constants.GameBalance.RocketSpec
    ) {
        self.spec = spec
        super.init(damage: spec.damage, startImpact: spec.startImpact, imageName: spec.imageName)
        configureRocketPhysicsAndTrail()
    }

    init(
        damage: Int,
        startImpact: Int,
        imageName: String,
        blastRadius: CGFloat
    ) {
        let defaultSpec = Constants.GameBalance.rocketSpec(for: .standard)
        self.spec = Constants.GameBalance.RocketSpec(
            type: .standard,
            damage: damage,
            startImpact: startImpact,
            blastRadius: blastRadius,
            imageName: imageName,
            initialSpeed: defaultSpec.initialSpeed,
            acceleration: defaultSpec.acceleration,
            maxSpeed: defaultSpec.maxSpeed,
            maxFlightDistance: defaultSpec.maxFlightDistance,
            turnSpeed: defaultSpec.turnSpeed,
            retargetInterval: defaultSpec.retargetInterval,
            cooldown: defaultSpec.cooldown,
            defaultAmmo: defaultSpec.defaultAmmo,
            ammoPerWave: defaultSpec.ammoPerWave,
            visualScale: defaultSpec.visualScale
        )
        super.init(damage: damage, startImpact: startImpact, imageName: imageName)
        configureRocketPhysicsAndTrail()
    }

    required init(damage: Int, imageName: String) {
        let defaultSpec = Constants.GameBalance.rocketSpec(for: Constants.GameBalance.defaultRocketType)
        self.spec = defaultSpec
        super.init(damage: damage, startImpact: defaultSpec.startImpact, imageName: imageName)
        configureRocketPhysicsAndTrail()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func detonateWithAnimation() {
        if let scene = component(ofType: SpriteComponent.self)?.spriteNode.scene as? InPlaySKScene,
           let position = component(ofType: SpriteComponent.self)?.spriteNode.position {
            scene.onRocketDetonated(self, at: position, blastRadius: blastRadius)
            if blastRadius > 0.01 {
                scene.spawnRocketBlast(at: position, radius: blastRadius, damage: spec.damage)
            }
        }
        silentDetonate()
    }

    override func copy() -> Any {
        RocketEntity(spec: spec)
    }

    func configureFlight(
        targetPoint: CGPoint,
        initialSpeed: CGFloat,
        climbsWhenNoTargets: Bool = true
    ) {
        self.targetPoint = targetPoint
        self.currentSpeed = max(0, initialSpeed)
        self.travelledDistance = 0
        self.previousTrackedPosition = nil
        self.isCoastingAfterFuelExhaustion = false
        self.climbsWhenNoTargets = climbsWhenNoTargets
        self.guidancePhase = .boost
        self.guidedFlightTime = 0
        self.retargetAccumulator = 0
        isGuided = true
        guard let spriteNode = component(ofType: SpriteComponent.self)?.spriteNode else { return }
        spriteNode.physicsBody?.affectedByGravity = false
        spriteNode.physicsBody?.allowsRotation = false
        previousTrackedPosition = spriteNode.position
        let heading = spriteNode.zRotation + .pi / 2
        let direction = CGVector(dx: cos(heading), dy: sin(heading))
        spriteNode.physicsBody?.velocity = CGVector(
            dx: direction.dx * currentSpeed,
            dy: direction.dy * currentSpeed
        )
    }

    override func update(deltaTime seconds: TimeInterval) {
        guard let spriteNode = component(ofType: SpriteComponent.self)?.spriteNode else { return }

        if isCoastingAfterFuelExhaustion {
            if (spriteNode.physicsBody?.velocity.dy ?? 0) <= 0 {
                detonateWithAnimation()
            }
            return
        }

        guard isGuided else { return }

        trackTravelDistance(from: spriteNode)
        if travelledDistance >= spec.maxFlightDistance {
            switchToInertialFlight(from: spriteNode)
            return
        }

        guidedFlightTime += seconds
        let preRetargetDistance = hypot(
            targetPoint.x - spriteNode.position.x,
            targetPoint.y - spriteNode.position.y
        )
        updateGuidancePhase(distanceToTarget: preRetargetDistance)

        emitSmokeIfNeeded(from: spriteNode, deltaTime: seconds)
        if !retargetIfNeeded(from: spriteNode, deltaTime: seconds) {
            return
        }

        let dx = targetPoint.x - spriteNode.position.x
        let dy = targetPoint.y - spriteNode.position.y
        let distance = sqrt(dx * dx + dy * dy)
        updateGuidancePhase(distanceToTarget: distance)
        if !detonatesOnDirectImpact {
            let detonationDistance = max(10, blastRadius * 0.2)
            if distance <= detonationDistance {
                detonateWithAnimation()
                return
            }
        }
        guard distance > 0.0001 else { return }

        let desiredRotation = atan2(dy, dx) - .pi / 2
        let rotationDelta = shortestAngle(from: spriteNode.zRotation, to: desiredRotation)
        let maxStep = spec.turnSpeed * seconds
        let clampedDelta = max(-maxStep, min(maxStep, rotationDelta))
        spriteNode.zRotation += clampedDelta

        let heading = spriteNode.zRotation + .pi / 2
        let direction = CGVector(dx: cos(heading), dy: sin(heading))
        currentSpeed = min(
            spec.maxSpeed,
            currentSpeed + spec.acceleration * seconds
        )
        spriteNode.physicsBody?.velocity = CGVector(dx: direction.dx * currentSpeed, dy: direction.dy * currentSpeed)
    }

    private func configureRocketPhysicsAndTrail() {
        guard let spriteNode = component(ofType: SpriteComponent.self)?.spriteNode else { return }

        let baseSize = CGSize(width: 12, height: 18)
        spriteNode.size = CGSize(
            width: baseSize.width * spec.visualScale,
            height: baseSize.height * spec.visualScale
        )
        spriteNode.physicsBody?.linearDamping = 0
        spriteNode.physicsBody?.angularDamping = 0
        spriteNode.physicsBody?.allowsRotation = false
        spriteNode.physicsBody?.affectedByGravity = false
        spriteNode.physicsBody?.friction = 0
        spriteNode.physicsBody?.restitution = 0
        spriteNode.physicsBody?.usesPreciseCollisionDetection = true
    }

    private func emitSmokeIfNeeded(from spriteNode: SKSpriteNode, deltaTime seconds: TimeInterval) {
        guard let scene = spriteNode.scene else { return }

        let gameScene = scene as? InPlaySKScene
        let nightMode = gameScene?.isNightWave == true

        // Night mode: persistent flame glow on rocket tail, no smoke puffs
        if nightMode {
            // Hide body via color blend (keeps alpha=1 so children stay visible)
            spriteNode.colorBlendFactor = 1.0
            spriteNode.color = .clear
            if nightFlameNode == nil {
                let flame = SKSpriteNode(texture: Self.smokePuffTexture)
                flame.size = CGSize(width: 8, height: 8)
                flame.color = UIColor(red: 1, green: 0.3, blue: 0.1, alpha: 1)
                flame.colorBlendFactor = 1.0
                flame.alpha = 0.9
                flame.position = CGPoint(x: 0, y: -spriteNode.size.height * 0.55)
                flame.zPosition = Constants.NightWave.nightEffectZPosition - spriteNode.zPosition
                spriteNode.addChild(flame)
                let flicker = SKAction.sequence([
                    SKAction.fadeAlpha(to: 0.6, duration: 0.15),
                    SKAction.fadeAlpha(to: 0.9, duration: 0.15)
                ])
                flame.run(SKAction.repeatForever(flicker))
                nightFlameNode = flame
            }
            return
        }

        // Day mode: restore body, normal smoke puffs
        spriteNode.colorBlendFactor = 0
        if let flame = nightFlameNode {
            flame.removeFromParent()
            nightFlameNode = nil
        }

        smokeSpawnAccumulator -= seconds
        guard smokeSpawnAccumulator <= 0 else { return }
        smokeSpawnAccumulator += 0.12

        var tailPoint = spriteNode.convert(CGPoint(x: 0, y: -spriteNode.size.height * 0.55), to: scene)
        tailPoint.x += CGFloat.random(in: -2...2)
        tailPoint.y += CGFloat.random(in: -2...2)

        let baseRadius = CGFloat.random(in: 2.5...4.5)
        let puff = gameScene?.acquireSmokePuff() ?? SKSpriteNode(texture: Self.smokePuffTexture)
        puff.size = CGSize(width: baseRadius * 2, height: baseRadius * 2)
        puff.position = tailPoint
        puff.zPosition = 40
        puff.color = UIColor(white: 1, alpha: 0.95)
        puff.colorBlendFactor = 1.0
        puff.alpha = 0.75
        puff.xScale = 0.75
        puff.yScale = 0.75
        scene.addChild(puff)

        puff.run(SKAction.sequence([
            SKAction.wait(forDuration: 0.15),
            SKAction.group([SKAction.scale(to: 2.5, duration: 0.45), SKAction.fadeOut(withDuration: 0.45)]),
            SKAction.run { [weak gameScene, weak puff] in
                guard let gameScene, let puff else { return }
                gameScene.releaseSmokePuff(puff)
            }
        ]))
    }

    private func retargetIfNeeded(from spriteNode: SKSpriteNode, deltaTime seconds: TimeInterval) -> Bool {
        if guidancePhase == .coast {
            return true
        }
        if guidancePhase == .terminal && !detonatesOnDirectImpact {
            return true
        }
        let canRetargetThreats = guidancePhase == .midcourse || guidancePhase == .terminal
        retargetAccumulator -= seconds
        guard retargetAccumulator <= 0 else { return true }
        retargetAccumulator += spec.retargetInterval

        guard let scene = spriteNode.scene as? InPlaySKScene else { return true }
        // Limit expensive planLaunch() calls per frame
        guard scene.consumeRetargetBudget() else { return true }
        let remainingFlightDistance = max(0, spec.maxFlightDistance - travelledDistance)
        if canRetargetThreats {
            if let updatedTarget = scene.bestRocketTargetPoint(
                preferredPoint: targetPoint,
                origin: spriteNode.position,
                radius: remainingFlightDistance,
                influenceRadius: spec.blastRadius,
                reservingActiveRocketImpacts: true,
                excludingRocket: self,
                projectileSpeed: currentSpeed,
                projectileAcceleration: spec.acceleration,
                projectileMaxSpeed: spec.maxSpeed
            ) {
                targetPoint = updatedTarget
                scene.updateRocketReservation(for: self, targetPoint: updatedTarget)
                return true
            }
        }

        guard climbsWhenNoTargets else {
            // Gameplay-launched rockets keep their latest target instead of climbing into empty sky.
            return true
        }

        // No targets: switch to vertical climb.
        targetPoint = CGPoint(x: spriteNode.position.x, y: scene.frame.height + 240)

        // If no targets appeared by the near-top phase, self-detonate.
        let nearTopY = scene.frame.height - 70
        if spriteNode.position.y >= nearTopY {
            detonateWithAnimation()
            return false
        }
        return true
    }

    private func shortestAngle(from: CGFloat, to: CGFloat) -> CGFloat {
        var angle = to - from
        while angle > .pi { angle -= 2 * .pi }
        while angle < -.pi { angle += 2 * .pi }
        return angle
    }

    private func trackTravelDistance(from spriteNode: SKSpriteNode) {
        guard let previousTrackedPosition else {
            self.previousTrackedPosition = spriteNode.position
            return
        }
        let dx = spriteNode.position.x - previousTrackedPosition.x
        let dy = spriteNode.position.y - previousTrackedPosition.y
        travelledDistance += sqrt(dx * dx + dy * dy)
        self.previousTrackedPosition = spriteNode.position
    }

    private func switchToInertialFlight(from spriteNode: SKSpriteNode) {
        guard !isCoastingAfterFuelExhaustion else { return }
        isCoastingAfterFuelExhaustion = true
        guidancePhase = .coast
        isGuided = false
        spriteNode.physicsBody?.affectedByGravity = true

        // Clear fire control reservation immediately — the rocket is no longer
        // guided and won't hit the intended target. Without this, the target
        // stays marked "overkilled" during the entire coast phase (0.5-1.5s),
        // preventing other towers from retargeting it.
        if let scene = spriteNode.scene as? InPlaySKScene {
            scene.onRocketDetonated(self, at: spriteNode.position, blastRadius: 0)
        }
    }

    private func updateGuidancePhase(distanceToTarget: CGFloat) {
        guard !isCoastingAfterFuelExhaustion else {
            guidancePhase = .coast
            return
        }
        let terminalDistance = max(28, max(blastRadius * 0.8, spec.maxFlightDistance * 0.12))
        if distanceToTarget <= terminalDistance {
            guidancePhase = .terminal
            return
        }
        guidancePhase = guidedFlightTime < 0.18 ? .boost : .midcourse
    }

}

final class MineBombEntity: GKEntity {
    private(set) var isFromCrashedMineLayer = false
    private weak var sourceDrone: AttackDroneEntity?
    weak var targetTower: TowerEntity?

    override init() {
        super.init()
        let spriteComponent = SpriteComponent(imageName: "Bullet")
        spriteComponent.spriteNode.size = CGSize(width: 12, height: 12)
        addComponent(spriteComponent)
        addComponent(
            GeometryComponent(
                spriteNode: spriteComponent.spriteNode,
                categoryBitMask: Constants.mineBombBitMask,
                contactTestBitMask: Constants.bulletBitMask | Constants.groundBitMask,
                collisionBitMask: 0
            )
        )
        if let body = spriteComponent.spriteNode.physicsBody {
            body.affectedByGravity = true
            body.linearDamping = 0
            body.angularDamping = 0
            body.allowsRotation = true
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func place(at position: CGPoint) {
        guard let spriteNode = component(ofType: SpriteComponent.self)?.spriteNode else { return }
        spriteNode.position = position
        spriteNode.zRotation = 0
        if let body = spriteNode.physicsBody {
            body.velocity = .zero
            body.angularVelocity = 0
            body.isResting = false
        }
    }

    func configureOrigin(
        isFromCrashedDrone: Bool,
        sourceDrone: AttackDroneEntity? = nil
    ) {
        isFromCrashedMineLayer = isFromCrashedDrone
        self.sourceDrone = sourceDrone
        if let body = component(ofType: GeometryComponent.self)?.geometryNode.physicsBody {
            var contactMask = Constants.groundBitMask
            if !isFromCrashedDrone {
                contactMask |= Constants.bulletBitMask
            }
            if isFromCrashedDrone {
                contactMask |= Constants.droneBitMask
            }
            body.contactTestBitMask = contactMask
        }
    }

    func configureOrigin(isFromCrashedDrone: Bool) {
        configureOrigin(isFromCrashedDrone: isFromCrashedDrone, sourceDrone: nil)
    }

    func canHitDrone(_ drone: AttackDroneEntity) -> Bool {
        !(isFromCrashedMineLayer && sourceDrone === drone)
    }

    func silentDetonate() {
        if let scene = component(ofType: SpriteComponent.self)?.spriteNode.scene as? InPlaySKScene {
            scene.removeEntity(self)
        }
    }

    func reachedDestination() {
        silentDetonate()
    }

    func configureForTDBombing(target: TowerEntity? = nil) {
        guard let spriteNode = component(ofType: SpriteComponent.self)?.spriteNode,
              let body = spriteNode.physicsBody else { return }

        // Visual: bomb sized like a drone, between drone (z61+) and tower (z25)
        spriteNode.size = CGSize(width: 40, height: 40)
        spriteNode.zPosition = 45

        // Physics: bomb stays in place (no Y velocity), but bullets can still shoot it down
        body.affectedByGravity = false
        body.velocity = .zero
        // No towerBitMask — damage delivered via animation callback, not physics contact

        targetTower = target

        // Fall animation: bomb shrinks (simulates falling away from camera toward ground)
        let fallDuration: TimeInterval = 0.45
        let scaleDown = SKAction.scale(to: 0.3, duration: fallDuration)
        scaleDown.timingMode = .easeIn
        spriteNode.run(SKAction.sequence([
            scaleDown,
            SKAction.run { [weak self] in
                guard let self else { return }
                if let target = self.targetTower,
                   let scene = spriteNode.scene as? InPlaySKScene {
                    scene.onBombHitTower(self, tower: target)
                } else {
                    self.silentDetonate()
                }
            }
        ]))
    }
}
