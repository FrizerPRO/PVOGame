//
//  RocketEntity.swift
//  PVOGame
//
//  Extracted from BulletEntity.swift
//

import Foundation
import GameplayKit

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
    /// Distance-based smoke trail. Each 5pt of flight path gets a puff; gaps
    /// between puffs are impossible regardless of rocket speed.
    private var smokeSpawnDistance: CGFloat = 0
    private var nightFlameNode: SKSpriteNode?
    private var retargetAccumulator: TimeInterval = 0
    private var climbsWhenNoTargets = true
    weak var trackedTarget: AttackDroneEntity?
    var trackingLockGranted = false
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
        self.smokeSpawnDistance = 0
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

        // Pure pursuit: track actual target position each frame
        if detonatesOnDirectImpact,
           let target = trackedTarget,
           !target.isHit,
           let targetSprite = target.component(ofType: SpriteComponent.self)?.spriteNode,
           targetSprite.parent != nil {
            targetPoint = targetSprite.position
        } else if detonatesOnDirectImpact, trackedTarget != nil {
            trackedTarget = nil
        }

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
        let cache = AnimationTextureCache.shared

        // Night mode: persistent flame glow on rocket tail, no smoke puffs
        if nightMode {
            // Hide body via color blend (keeps alpha=1 so children stay visible)
            spriteNode.colorBlendFactor = 1.0
            spriteNode.color = .clear
            if nightFlameNode == nil {
                let flameTex = cache.flameGlow ?? Self.smokePuffTexture
                let flame = SKSpriteNode(texture: flameTex)
                flame.size = CGSize(width: 8, height: 8)
                flame.color = UIColor(red: 1, green: 0.3, blue: 0.1, alpha: 1)
                flame.colorBlendFactor = cache.flameGlow != nil ? 0 : 1.0
                flame.alpha = 0.9
                flame.position = CGPoint(x: 0, y: -spriteNode.size.height * 0.55)
                flame.zPosition = Constants.NightWave.nightEffectZPosition - spriteNode.zPosition
                spriteNode.addChild(flame)
                // Enhanced flicker: vary both alpha and scale for more dynamic flame
                let flicker = SKAction.sequence([
                    SKAction.group([
                        SKAction.fadeAlpha(to: 0.5, duration: 0.08),
                        SKAction.scale(to: 0.85, duration: 0.08)
                    ]),
                    SKAction.group([
                        SKAction.fadeAlpha(to: 1.0, duration: 0.06),
                        SKAction.scale(to: 1.15, duration: 0.06)
                    ]),
                    SKAction.group([
                        SKAction.fadeAlpha(to: 0.7, duration: 0.10),
                        SKAction.scale(to: 0.95, duration: 0.10)
                    ]),
                    SKAction.group([
                        SKAction.fadeAlpha(to: 0.9, duration: 0.06),
                        SKAction.scale(to: 1.05, duration: 0.06)
                    ])
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

        // Distance-based spawn — guarantees no gap between puffs even at
        // terminal-dive speeds. 5pt spacing vs ~8pt minimum puff diameter
        // means every two consecutive puffs overlap by at least 40%.
        let puffSpacing: CGFloat = 5.0
        // Safety cap: at 60fps a teleporting frame could in theory request
        // hundreds of puffs; bound it so one freak tick doesn't saturate the
        // pool.
        var perFrameSpawns = 0
        let maxPerFrame = 8
        while travelledDistance >= smokeSpawnDistance && perFrameSpawns < maxPerFrame {
            spawnSmokePuff(spriteNode: spriteNode, scene: scene, gameScene: gameScene, cache: cache)
            smokeSpawnDistance += puffSpacing
            perFrameSpawns += 1
        }
        // If we hit the cap, jump smokeSpawnDistance forward so we don't
        // replay the backlog next frame (the rocket moved too fast once).
        if perFrameSpawns >= maxPerFrame {
            smokeSpawnDistance = travelledDistance + puffSpacing
        }
    }

    private func spawnSmokePuff(spriteNode: SKSpriteNode, scene: SKScene,
                                 gameScene: InPlaySKScene?, cache: AnimationTextureCache) {
        var tailPoint = spriteNode.convert(CGPoint(x: 0, y: -spriteNode.size.height * 0.55), to: scene)
        tailPoint.x += CGFloat.random(in: -2...2)
        tailPoint.y += CGFloat.random(in: -2...2)

        // Use the warm "hot exhaust" puff for the first ~25pt of trail (≈ 5
        // puffs at 5pt spacing) — that segment is right out of the motor and
        // should glow warm. Beyond that, the motor exhaust has cooled to gray
        // smoke (smokePuff).
        let isHotExhaust = travelledDistance < 25
        let texture: SKTexture
        if isHotExhaust, let warm = cache.rocketTrailPuff {
            texture = warm
        } else {
            texture = cache.smokePuff ?? Self.smokePuffTexture
        }

        let baseRadius = CGFloat.random(in: 4.0...7.0)
        let puff = gameScene?.acquireSmokePuff() ?? SKSpriteNode(texture: texture)
        puff.texture = texture
        puff.size = CGSize(width: baseRadius * 2, height: baseRadius * 2)
        puff.position = tailPoint
        puff.zPosition = 40
        puff.color = UIColor(white: 1, alpha: 0.95)
        puff.colorBlendFactor = (cache.smokePuff != nil || cache.rocketTrailPuff != nil) ? 0 : 1.0
        puff.alpha = 0.95
        puff.xScale = 0.95
        puff.yScale = 0.95
        scene.addChild(puff)

        puff.run(SKAction.sequence([
            SKAction.wait(forDuration: 0.60),
            SKAction.group([SKAction.scale(to: 1.4, duration: 1.30), SKAction.fadeOut(withDuration: 1.30)]),
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
                if detonatesOnDirectImpact, trackingLockGranted {
                    trackedTarget = scene.nearestAliveDrone(to: updatedTarget)
                }
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
