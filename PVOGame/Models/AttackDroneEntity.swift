//
//  AtackDrone.swift
//  PVOGame
//
//  Created by Frizer on 03.01.2023.
//

import Foundation
import GameplayKit

public class AttackDroneEntity: GKEntity, FlyingProjectile{
    private struct EscortPoseSample {
        let time: TimeInterval
        let position: CGPoint
        let heading: CGFloat
    }

    private struct DamageFireProfile {
        let fireWidthMultiplier: CGFloat
        let fireHeightMultiplier: CGFloat
        let fireMinWidth: CGFloat
        let fireMinHeight: CGFloat
        let fireYOffsetMultiplier: CGFloat
        let fireAlpha: CGFloat
        let timePerFrame: TimeInterval
        let smokeBirthRate: CGFloat
        let smokeAlpha: CGFloat
        let smokeScale: CGFloat
        let smokeSpeed: CGFloat
        let emberBirthRate: CGFloat
        let emberAlpha: CGFloat
        let emberScale: CGFloat
        let emberSpeed: CGFloat
    }

    public var flyingPath: FlyingPath

    public var damage: CGFloat

    public var speed: CGFloat

    public var imageName: String
    public var isHit = false
    /// Formation drones: SKAction drives sprite, GKAgent syncs from sprite
    public var isFormationFlight = false

    /// Whether player EW towers should affect this entity (visual lightning
    /// and any future jamming/slow effects). Default true for drones; ballistic
    /// and cruise missiles, FPV-Lancet, and Orlan recon override to false.
    /// Override in subclasses — do not flip per-instance.
    public var isJammableByEW: Bool { true }

    weak var targetSettlement: SettlementEntity?
    weak var targetRefinery: TowerEntity?

    // MARK: Leader-Follow (escort formations)

    /// When non-nil, this drone steers toward a delayed slot behind/around the leader
    /// until the leader dies. Used for "Shahed shield around EW drone"-style escorts.
    public weak var leader: AttackDroneEntity?
    /// Escort slot offset in leader-local coordinates.
    public var leaderOffset: CGPoint = .zero
    public var isLeaderFollower: Bool = false
    private var escortPoseClock: TimeInterval = 0
    private var escortPoseHistory: [EscortPoseSample] = []
    private var escortLag: TimeInterval = Constants.EW.ewEscortLagMin
    private var escortLeadTime: TimeInterval = 0
    private var escortVelocity: CGVector = .zero
    private var previousEscortSlotTarget: CGPoint?
    private var escortFollowSpeed: CGFloat = Constants.EW.ewEscortFollowSpeedMin
    private var escortTurnRate: CGFloat = Constants.EW.ewEscortTurnRateMin
    private var escortWobblePhase: CGFloat = 0
    private var escortWobbleSpeed: CGFloat = Constants.EW.ewEscortWobbleSpeedMin
    private var escortWobbleAmplitude: CGFloat = Constants.EW.ewEscortWobbleAmplitude

    public var health: Int
    public var maxHealth: Int

    private var hpBarBackground: SKSpriteNode?
    private var hpBarFill: SKSpriteNode?
    private var hpBarContainer: SKNode?

    // PvZ-style damage visuals
    private var damageSmoke: SKNode?
    private var currentDamageLevel: DamageVisualLevel = .none
    var isBossType: Bool { false }

    enum DamageVisualLevel: Int, Comparable {
        case none = 0
        case light = 1
        case medium = 2
        case critical = 3

        static func stages(forHealthSteps steps: Int) -> [DamageVisualLevel] {
            switch steps {
            case ...0:
                return []
            case 1:
                return [.critical]
            case 2:
                return [.medium, .critical]
            default:
                return [.light, .medium, .critical]
            }
        }

        static func < (lhs: DamageVisualLevel, rhs: DamageVisualLevel) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    public required init(damage: CGFloat, speed: CGFloat, imageName: String, flyingPath: FlyingPath) {
        self.health = 1
        self.maxHealth = 1
        self.damage = damage
        self.speed = speed
        self.imageName = imageName
        self.flyingPath = flyingPath
        super.init()
        let spriteComponent = SpriteComponent(imageName: imageName);
        spriteComponent.spriteNode.size = CGSize(width: 30, height: 30)
        addComponent(spriteComponent)
        addComponent(setupGeometryComponent(spriteComponent: spriteComponent))
        addComponent(FlyingProjectileComponent(speed: speed, behavior: behavior(for: flyingPath),position: flyingPath.nodes.first ?? vector_float2()))
        setupHPBar(on: spriteComponent.spriteNode)

        // Regular drones get nav lights (subclasses may add their own)
        addNavLights(wingspan: 24)
    }

    func configureHealth(_ hp: Int) {
        self.health = hp
        self.maxHealth = hp
        hpBarContainer?.isHidden = true
        updateHPBar()
    }

    public func takeDamage(_ amount: Int) {
        guard !isHit else { return }
        health = max(0, health - amount)
        if health <= 0 {
            clearDamageVisuals()
            didHit()
        } else {
            // White hit flash (0.05s) — restores damage tint after
            if let spriteNode = component(ofType: SpriteComponent.self)?.spriteNode {
                spriteNode.removeAction(forKey: "hitFlash")
                let savedColor = spriteNode.color
                let savedBlend = spriteNode.colorBlendFactor
                let flash = SKAction.sequence([
                    SKAction.colorize(with: .white, colorBlendFactor: 1.0, duration: 0.03),
                    SKAction.colorize(with: savedColor, colorBlendFactor: savedBlend, duration: 0.08)
                ])
                spriteNode.run(flash, withKey: "hitFlash")
            }
            updateDamageVisuals()
        }
        if isBossType { updateHPBar() }
    }

    private func setupHPBar(on spriteNode: SKSpriteNode) {
        let container = SKNode()
        container.zPosition = 10
        container.position = CGPoint(x: 0, y: spriteNode.size.height / 2 + 4)
        container.isHidden = true

        let barWidth: CGFloat = 24
        let barHeight: CGFloat = 3

        let bg = SKSpriteNode(color: UIColor.black.withAlphaComponent(0.6), size: CGSize(width: barWidth, height: barHeight))
        bg.anchorPoint = CGPoint(x: 0, y: 0.5)
        bg.position = CGPoint(x: -barWidth / 2, y: 0)
        container.addChild(bg)
        hpBarBackground = bg

        let fill = SKSpriteNode(color: .green, size: CGSize(width: barWidth, height: barHeight))
        fill.anchorPoint = CGPoint(x: 0, y: 0.5)
        fill.position = CGPoint(x: -barWidth / 2, y: 0)
        fill.zPosition = 1
        container.addChild(fill)
        hpBarFill = fill

        spriteNode.addChild(container)
        hpBarContainer = container
    }

    func updateHPBar() {
        guard maxHealth > 0 else { return }
        let ratio = CGFloat(health) / CGFloat(maxHealth)
        let barWidth: CGFloat = 24
        hpBarFill?.size.width = barWidth * ratio

        if ratio > 0.5 {
            hpBarFill?.color = .green
        } else if ratio > 0.25 {
            hpBarFill?.color = .yellow
        } else {
            hpBarFill?.color = .red
        }

        // Boss types: show bar when damaged. Non-boss: always hidden (PvZ-style visuals instead)
        if isBossType {
            hpBarContainer?.isHidden = (health >= maxHealth)
        } else {
            hpBarContainer?.isHidden = true
        }
    }

    // MARK: - PvZ-Style Damage Visuals

    func updateDamageVisuals() {
        guard maxHealth > 1 else { return }
        guard let spriteNode = component(ofType: SpriteComponent.self)?.spriteNode else { return }

        // Scale visual severity with available HP steps.
        // 2 HP (1 step)  -> [critical]
        // 3 HP (2 steps) -> [medium, critical]
        // 4+ HP          -> [light, medium, critical]
        let steps = maxHealth - 1
        let stages = DamageVisualLevel.stages(forHealthSteps: steps)
        let usedCount = stages.count

        // Evenly split HP range into (usedCount+1) bands.
        // Later stages are more severe, so keep scanning and take the strongest matching stage.
        var newLevel: DamageVisualLevel = .none
        for (i, stage) in stages.enumerated() {
            let threshold = maxHealth * (usedCount - i) / (usedCount + 1)
            if health <= threshold {
                newLevel = stage
            }
        }

        guard newLevel > currentDamageLevel else { return }
        currentDamageLevel = newLevel

        switch newLevel {
        case .none:
            break
        case .light:
            // Light smoke + slight gray tint
            addDamageSmoke(on: spriteNode, birthRate: 8, alpha: 0.3)
            spriteNode.colorBlendFactor = max(spriteNode.colorBlendFactor, 0.15)
            spriteNode.color = blendColor(spriteNode.color, with: .gray, factor: 0.3)
        case .medium:
            addDamageFire(on: spriteNode, level: .medium)
            spriteNode.color = UIColor(white: 0.38, alpha: 1)
            spriteNode.colorBlendFactor = 0.32
        case .critical:
            addDamageFire(on: spriteNode, level: .critical)
            spriteNode.color = UIColor(red: 0.6, green: 0.15, blue: 0.1, alpha: 1)
            spriteNode.colorBlendFactor = 0.45
        }
    }

    private static let smokeTexture: SKTexture = {
        let size: CGFloat = 16
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        let image = renderer.image { ctx in
            UIColor.white.setFill()
            ctx.cgContext.fillEllipse(in: CGRect(x: 0, y: 0, width: size, height: size))
        }
        return SKTexture(image: image)
    }()

    private func addDamageSmoke(on spriteNode: SKSpriteNode, birthRate: CGFloat, alpha: CGFloat) {
        damageSmoke?.removeFromParent()

        let emitter = SKEmitterNode()
        emitter.particleTexture = Self.smokeTexture
        emitter.position = CGPoint(x: 0, y: -spriteNode.size.height * 0.08)
        emitter.particleBirthRate = birthRate
        emitter.particleLifetime = 0.6
        emitter.particleLifetimeRange = 0.3
        emitter.particlePositionRange = CGVector(dx: spriteNode.size.width * 0.24, dy: spriteNode.size.height * 0.28)
        emitter.particleSpeed = 12
        emitter.particleSpeedRange = 6
        emitter.emissionAngle = -.pi / 2
        emitter.emissionAngleRange = .pi / 5
        emitter.particleAlpha = alpha
        emitter.particleAlphaSpeed = -0.8
        emitter.particleScale = 0.15
        emitter.particleScaleSpeed = 0.12
        emitter.particleColor = UIColor(white: 0.45, alpha: 1)
        emitter.particleColorBlendFactor = 1.0
        emitter.zPosition = 30
        spriteNode.addChild(emitter)
        damageSmoke = emitter
    }

    private func clearDamageVisuals() {
        damageSmoke?.removeAllActions()
        damageSmoke?.removeFromParent()
        damageSmoke = nil

        if let spriteNode = component(ofType: SpriteComponent.self)?.spriteNode {
            spriteNode.childNode(withName: "droneDamageFire")?.removeFromParent()
        }
    }

    private func damageFireProfile(for level: DamageVisualLevel) -> DamageFireProfile {
        switch level {
        case .medium:
            return DamageFireProfile(
                fireWidthMultiplier: 0.42,
                fireHeightMultiplier: 0.82,
                fireMinWidth: 13,
                fireMinHeight: 19,
                fireYOffsetMultiplier: -0.10,
                fireAlpha: 0.72,
                timePerFrame: 0.075,
                smokeBirthRate: 7,
                smokeAlpha: 0.24,
                smokeScale: 0.09,
                smokeSpeed: 14,
                emberBirthRate: 2.5,
                emberAlpha: 0.48,
                emberScale: 0.045,
                emberSpeed: 24
            )
        case .critical:
            return DamageFireProfile(
                fireWidthMultiplier: 0.62,
                fireHeightMultiplier: 1.20,
                fireMinWidth: 18,
                fireMinHeight: 26,
                fireYOffsetMultiplier: -0.18,
                fireAlpha: 0.98,
                timePerFrame: 0.052,
                smokeBirthRate: 15,
                smokeAlpha: 0.42,
                smokeScale: 0.13,
                smokeSpeed: 22,
                emberBirthRate: 9,
                emberAlpha: 0.82,
                emberScale: 0.06,
                emberSpeed: 34
            )
        default:
            return DamageFireProfile(
                fireWidthMultiplier: 0.54,
                fireHeightMultiplier: 1.0,
                fireMinWidth: 14,
                fireMinHeight: 22,
                fireYOffsetMultiplier: -0.14,
                fireAlpha: 0.85,
                timePerFrame: 0.06,
                smokeBirthRate: 10,
                smokeAlpha: 0.30,
                smokeScale: 0.11,
                smokeSpeed: 18,
                emberBirthRate: 5,
                emberAlpha: 0.65,
                emberScale: 0.05,
                emberSpeed: 28
            )
        }
    }

    private func addDamageFire(on spriteNode: SKSpriteNode, level: DamageVisualLevel) {
        damageSmoke?.removeFromParent()
        let profile = damageFireProfile(for: level)

        let frames = AnimationTextureCache.shared.droneFire
        if let firstFrame = frames.first {
            let effect = SKNode()
            effect.name = "droneDamageFire"
            effect.zPosition = 30

            let fire = SKSpriteNode(texture: firstFrame)
            fire.size = CGSize(
                width: max(profile.fireMinWidth, spriteNode.size.width * profile.fireWidthMultiplier),
                height: max(profile.fireMinHeight, spriteNode.size.height * profile.fireHeightMultiplier)
            )
            fire.position = CGPoint(x: spriteNode.size.width * 0.02, y: spriteNode.size.height * profile.fireYOffsetMultiplier)
            fire.alpha = profile.fireAlpha
            fire.blendMode = .alpha
            fire.zPosition = 2
            fire.run(SKAction.repeatForever(
                SKAction.animate(with: frames, timePerFrame: profile.timePerFrame, resize: false, restore: false)
            ), withKey: "droneFireFlipbook")
            effect.addChild(fire)

            let smoke = SKEmitterNode()
            smoke.particleTexture = Self.smokeTexture
            smoke.position = CGPoint(x: 0, y: -spriteNode.size.height * 0.18)
            smoke.particleBirthRate = profile.smokeBirthRate
            smoke.particleLifetime = 0.62
            smoke.particleLifetimeRange = 0.22
            smoke.particlePositionRange = CGVector(dx: spriteNode.size.width * 0.16, dy: spriteNode.size.height * 0.42)
            smoke.particleSpeed = profile.smokeSpeed
            smoke.particleSpeedRange = 7
            smoke.emissionAngle = -.pi / 2
            smoke.emissionAngleRange = .pi / 8
            smoke.particleAlpha = profile.smokeAlpha
            smoke.particleAlphaSpeed = -0.7
            smoke.particleScale = profile.smokeScale
            smoke.particleScaleRange = profile.smokeScale * 0.35
            smoke.particleScaleSpeed = 0.14
            smoke.particleColor = UIColor(white: 0.30, alpha: 1)
            smoke.particleColorBlendFactor = 1.0
            smoke.zPosition = 1
            effect.addChild(smoke)

            let embers = makeDamageEmberEmitter(spriteNode: spriteNode, profile: profile)
            effect.addChild(embers)

            spriteNode.addChild(effect)
            damageSmoke = effect
            return
        }

        let emitter = SKEmitterNode()
        emitter.particleTexture = Self.smokeTexture
        emitter.particleBirthRate = max(12, profile.emberBirthRate * 4)
        emitter.particleLifetime = 0.4
        emitter.particleLifetimeRange = 0.2
        emitter.particlePositionRange = CGVector(dx: spriteNode.size.width * 0.3, dy: spriteNode.size.height * 0.3)
        emitter.particleSpeed = profile.emberSpeed
        emitter.particleSpeedRange = 8
        emitter.emissionAngle = -.pi / 2
        emitter.emissionAngleRange = .pi / 3
        emitter.particleAlpha = profile.emberAlpha
        emitter.particleAlphaSpeed = -1.5
        emitter.particleScale = max(0.08, profile.emberScale * 2.2)
        emitter.particleScaleSpeed = 0.1
        // Fire: orange-yellow, fading to red-dark
        emitter.particleColor = UIColor(red: 1.0, green: 0.6, blue: 0.1, alpha: 1)
        emitter.particleColorBlendFactor = 1.0
        emitter.particleColorRedRange = 0.1
        emitter.particleColorGreenRange = 0.3
        emitter.particleColorBlueRange = 0.05
        emitter.particleColorRedSpeed = -0.3
        emitter.particleColorGreenSpeed = -1.2
        emitter.particleColorBlueSpeed = 0
        emitter.zPosition = 30
        spriteNode.addChild(emitter)
        damageSmoke = emitter
    }

    private func makeDamageEmberEmitter(spriteNode: SKSpriteNode, profile: DamageFireProfile) -> SKEmitterNode {
        let emitter = SKEmitterNode()
        emitter.name = "droneDamageEmberEmitter"
        emitter.particleTexture = Self.smokeTexture
        emitter.position = CGPoint(x: 0, y: -spriteNode.size.height * 0.24)
        emitter.particleBirthRate = profile.emberBirthRate
        emitter.particleLifetime = 0.36
        emitter.particleLifetimeRange = 0.16
        emitter.particlePositionRange = CGVector(dx: spriteNode.size.width * 0.16, dy: spriteNode.size.height * 0.26)
        emitter.particleSpeed = profile.emberSpeed
        emitter.particleSpeedRange = 10
        emitter.emissionAngle = -.pi / 2
        emitter.emissionAngleRange = .pi / 7
        emitter.particleAlpha = profile.emberAlpha
        emitter.particleAlphaSpeed = -1.7
        emitter.particleScale = profile.emberScale
        emitter.particleScaleRange = profile.emberScale * 0.45
        emitter.particleScaleSpeed = -0.02
        emitter.particleColor = UIColor(red: 1.0, green: 0.45, blue: 0.08, alpha: 1)
        emitter.particleColorBlendFactor = 1.0
        emitter.particleBlendMode = .add
        emitter.zPosition = 3
        return emitter
    }

    private func blendColor(_ base: UIColor, with overlay: UIColor, factor: CGFloat) -> UIColor {
        var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
        var or: CGFloat = 0, og: CGFloat = 0, ob: CGFloat = 0, oa: CGFloat = 0
        base.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
        overlay.getRed(&or, green: &og, blue: &ob, alpha: &oa)
        return UIColor(
            red: br + (or - br) * factor,
            green: bg + (og - bg) * factor,
            blue: bb + (ob - bb) * factor,
            alpha: 1
        )
    }

    public func resetFlight(flyingPath: FlyingPath, speed: CGFloat) {
        self.flyingPath = flyingPath
        self.speed = speed
        isHit = false
        health = maxHealth
        currentDamageLevel = .none
        clearDamageVisuals()
        if let spriteNode = component(ofType: SpriteComponent.self)?.spriteNode {
            spriteNode.colorBlendFactor = 0
        }
        updateHPBar()
        let startPosition = flyingPath.nodes.first ?? vector_float2()

        if let flight = component(ofType: FlyingProjectileComponent.self) {
            flight.maxSpeed = Float(speed)
            flight.maxAcceleration = Float(speed) / 2
            flight.behavior = behavior(for: flyingPath)
            flight.position = startPosition
        }
        if let spriteNode = component(ofType: SpriteComponent.self)?.spriteNode {
            spriteNode.position = CGPoint(x: CGFloat(startPosition.x), y: CGFloat(startPosition.y))
            spriteNode.zRotation = 0
        }
        if let physicsBody = component(ofType: GeometryComponent.self)?.geometryNode.physicsBody {
            physicsBody.affectedByGravity = false
            physicsBody.contactTestBitMask = Constants.bulletBitMask | Constants.groundBitMask
            physicsBody.collisionBitMask = 0
            physicsBody.velocity = .zero
            physicsBody.angularVelocity = 0
            physicsBody.isResting = false
        }
    }

    public func didHit(){
        isHit = true
        clearDamageVisuals()
        component(ofType: FlyingProjectileComponent.self)?.behavior?.removeAllGoals()
        let physicBody = component(ofType: GeometryComponent.self)?.geometryNode.physicsBody
        physicBody?.affectedByGravity = false
        physicBody?.velocity = .zero
        physicBody?.angularVelocity = 0
        physicBody?.contactTestBitMask = 0
        physicBody?.categoryBitMask = 0

        // Animate fall + fade, then remove
        if let spriteNode = component(ofType: SpriteComponent.self)?.spriteNode {
            let scene = spriteNode.scene as? InPlaySKScene
            let nightMode = scene?.isNightWave == true

            // Animated explosion if sprite sheet available, otherwise orange flash
            let textures = AnimationTextureCache.shared.smallExplosion
            if !textures.isEmpty, let scene {
                let node = scene.acquireExplosionNode()
                node.texture = textures[0]
                node.size = CGSize(width: 20, height: 20)
                node.color = .white; node.colorBlendFactor = 0
                node.position = spriteNode.position
                node.zPosition = nightMode ? Constants.NightWave.nightEffectZPosition : 55
                node.alpha = 1.0; node.setScale(1.0)
                scene.addChild(node)
                node.run(SKAction.sequence([
                    SKAction.animate(with: textures, timePerFrame: 0.05, resize: false, restore: false),
                    SKAction.run { [weak scene, weak node] in
                        guard let scene, let node else { return }
                        scene.releaseExplosionNode(node)
                    }
                ]))
            } else {
                let flash = SKShapeNode(circleOfRadius: 5)
                flash.fillColor = .orange
                flash.strokeColor = .clear
                flash.position = spriteNode.position
                flash.zPosition = nightMode ? Constants.NightWave.nightEffectZPosition : 55
                flash.alpha = 0.9
                spriteNode.scene?.addChild(flash)
                flash.run(SKAction.sequence([
                    SKAction.group([
                        SKAction.scale(to: 2.0, duration: 0.15),
                        SKAction.fadeOut(withDuration: 0.15)
                    ]),
                    SKAction.removeFromParent()
                ]))
            }

            let spin = SKAction.rotate(byAngle: .pi * 2, duration: 0.6)
            let fall = SKAction.moveBy(x: 0, y: -120, duration: 0.6)
            fall.timingMode = .easeIn
            let fade = SKAction.fadeOut(withDuration: 0.6)
            let group = SKAction.group([spin, fall, fade])
            spriteNode.run(group) { [weak self] in
                self?.removeFromParent()
            }
        }
    }

    /// Adds blinking navigation lights to fixed-wing drones.
    /// Red on left wing, green on right wing.
    func addNavLights(wingspan: CGFloat) {
        guard let spriteNode = component(ofType: SpriteComponent.self)?.spriteNode else { return }

        let leftLight = SKSpriteNode(color: .red, size: CGSize(width: 2, height: 2))
        leftLight.position = CGPoint(x: -wingspan / 2, y: 0)
        leftLight.zPosition = 1
        leftLight.alpha = 0.6
        spriteNode.addChild(leftLight)

        let rightLight = SKSpriteNode(color: .green, size: CGSize(width: 2, height: 2))
        rightLight.position = CGPoint(x: wingspan / 2, y: 0)
        rightLight.zPosition = 1
        rightLight.alpha = 0.6
        spriteNode.addChild(rightLight)

        let blink = SKAction.sequence([
            SKAction.fadeAlpha(to: 1.0, duration: 0.05),
            SKAction.wait(forDuration: 0.8),
            SKAction.fadeAlpha(to: 0.1, duration: 0.05),
            SKAction.wait(forDuration: 0.4)
        ])
        leftLight.run(SKAction.repeatForever(blink))
        // Right light offset so they don't blink in sync
        rightLight.run(SKAction.sequence([
            SKAction.wait(forDuration: 0.3),
            SKAction.repeatForever(blink)
        ]))
    }

    /// Adds propeller buzz vibration to quadcopter drones.
    func addPropellerBuzz() {
        guard let spriteNode = component(ofType: SpriteComponent.self)?.spriteNode else { return }
        let buzz = SKAction.sequence([
            SKAction.moveBy(x: CGFloat.random(in: -0.3...0.3), y: CGFloat.random(in: -0.3...0.3), duration: 0.05),
            SKAction.moveBy(x: CGFloat.random(in: -0.3...0.3), y: CGFloat.random(in: -0.3...0.3), duration: 0.05)
        ])
        spriteNode.run(SKAction.repeatForever(buzz), withKey: "propBuzz")
    }
    public func reachedDestination(){
        removeFromParent()
    }
    public func removeFromParent(){
        guard let scene = component(ofType: SpriteComponent.self)?.spriteNode.scene as? InPlaySKScene
        else {return}
        scene.removeEntity(self)
    }
    public override func update(deltaTime seconds: TimeInterval) {
        super.update(deltaTime: seconds)
        guard !isHit else { return }
        if isLeaderFollower {
            applyLeaderFollowTick(deltaTime: CGFloat(seconds))
        } else {
            recordEscortPose(deltaTime: seconds)
        }
    }

    /// Attach this drone to a leader. Disables its path-following behavior so the
    /// GKAgent doesn't fight the sprite position we drive directly each frame.
    /// `offset` is in leader-local slot coordinates: x is right/left, negative y is front.
    public func attachToLeader(_ newLeader: AttackDroneEntity, offset: CGPoint) {
        self.leader = newLeader
        self.leaderOffset = offset
        self.isLeaderFollower = true
        self.isFormationFlight = true  // reuse the "sprite drives agent" sync path
        if offset.y < Constants.EW.ewEscortFrontSlotThreshold {
            self.escortLag = 0
            self.escortLeadTime = TimeInterval.random(in: Constants.EW.ewEscortFrontLeadTimeMin...Constants.EW.ewEscortFrontLeadTimeMax)
        } else if offset.y < Constants.EW.ewEscortSideSlotThreshold {
            self.escortLag = TimeInterval.random(in: 0...(Constants.EW.ewEscortLagMin * 0.5))
            self.escortLeadTime = TimeInterval.random(in: 0...(Constants.EW.ewEscortFrontLeadTimeMin * 0.5))
        } else {
            self.escortLag = TimeInterval.random(in: Constants.EW.ewEscortLagMin...Constants.EW.ewEscortLagMax)
            self.escortLeadTime = 0
        }
        self.escortFollowSpeed = CGFloat.random(in: Constants.EW.ewEscortFollowSpeedMin...Constants.EW.ewEscortFollowSpeedMax)
        self.escortTurnRate = CGFloat.random(in: Constants.EW.ewEscortTurnRateMin...Constants.EW.ewEscortTurnRateMax)
        self.escortWobblePhase = CGFloat.random(in: 0...(2 * .pi))
        self.escortWobbleSpeed = CGFloat.random(in: Constants.EW.ewEscortWobbleSpeedMin...Constants.EW.ewEscortWobbleSpeedMax)
        self.escortWobbleAmplitude = Constants.EW.ewEscortWobbleAmplitude * CGFloat.random(in: 0.65...1.15)
        self.previousEscortSlotTarget = nil
        component(ofType: FlyingProjectileComponent.self)?.behavior?.removeAllGoals()

        if let leaderSprite = newLeader.component(ofType: SpriteComponent.self)?.spriteNode,
           let spriteNode = component(ofType: SpriteComponent.self)?.spriteNode {
            let heading = leaderSprite.zRotation + .pi / 2
            escortVelocity = CGVector(dx: cos(heading) * newLeader.speed,
                                      dy: sin(heading) * newLeader.speed)
            spriteNode.zRotation = leaderSprite.zRotation
        }
    }

    /// Detach from leader. Caller is responsible for providing a fresh path via `retargetPath`.
    public func detachFromLeader() {
        self.leader = nil
        self.isLeaderFollower = false
        self.isFormationFlight = false
        self.escortVelocity = .zero
        self.previousEscortSlotTarget = nil
    }

    func resetEscortPoseHistory() {
        escortPoseClock = 0
        escortPoseHistory.removeAll()
        recordEscortPose(deltaTime: 0)
    }

    func recordEscortPose(deltaTime seconds: TimeInterval) {
        guard let spriteNode = component(ofType: SpriteComponent.self)?.spriteNode else { return }
        escortPoseClock += seconds
        let sample = EscortPoseSample(
            time: escortPoseClock,
            position: spriteNode.position,
            heading: spriteNode.zRotation + .pi / 2
        )
        escortPoseHistory.append(sample)

        let cutoff = escortPoseClock - Constants.EW.ewEscortHistoryDuration
        while let first = escortPoseHistory.first, first.time < cutoff {
            escortPoseHistory.removeFirst()
        }
    }

    private func sampleEscortPose(lag: TimeInterval) -> EscortPoseSample? {
        guard !escortPoseHistory.isEmpty else {
            guard let spriteNode = component(ofType: SpriteComponent.self)?.spriteNode else { return nil }
            return EscortPoseSample(
                time: escortPoseClock,
                position: spriteNode.position,
                heading: spriteNode.zRotation + .pi / 2
            )
        }

        let targetTime = escortPoseClock - lag
        guard let first = escortPoseHistory.first else { return nil }
        if targetTime <= first.time { return first }

        guard let last = escortPoseHistory.last else { return nil }
        if targetTime >= last.time { return last }

        for index in 1..<escortPoseHistory.count {
            let next = escortPoseHistory[index]
            guard targetTime <= next.time else { continue }
            let previous = escortPoseHistory[index - 1]
            let duration = max(next.time - previous.time, 0.0001)
            let t = CGFloat((targetTime - previous.time) / duration)
            let headingDelta = normalizedAngle(next.heading - previous.heading)
            return EscortPoseSample(
                time: targetTime,
                position: CGPoint(
                    x: previous.position.x + (next.position.x - previous.position.x) * t,
                    y: previous.position.y + (next.position.y - previous.position.y) * t
                ),
                heading: normalizedAngle(previous.heading + headingDelta * t)
            )
        }

        return last
    }

    private func projectedEscortPose(leadTime: TimeInterval) -> EscortPoseSample? {
        guard let current = escortPoseHistory.last else {
            guard let spriteNode = component(ofType: SpriteComponent.self)?.spriteNode else { return nil }
            let heading = spriteNode.zRotation + .pi / 2
            let leadDistance = speed * CGFloat(leadTime)
            return EscortPoseSample(
                time: escortPoseClock + leadTime,
                position: CGPoint(
                    x: spriteNode.position.x + cos(heading) * leadDistance,
                    y: spriteNode.position.y + sin(heading) * leadDistance
                ),
                heading: heading
            )
        }

        let leadDistance = speed * CGFloat(leadTime)
        return EscortPoseSample(
            time: current.time + leadTime,
            position: CGPoint(
                x: current.position.x + cos(current.heading) * leadDistance,
                y: current.position.y + sin(current.heading) * leadDistance
            ),
            heading: current.heading
        )
    }

    /// Called every frame when this drone is in leader-follow mode.
    /// Followers aim at delayed leader poses and steer into their slots instead
    /// of being hard-locked to the leader sprite.
    private func applyLeaderFollowTick(deltaTime dt: CGFloat) {
        guard let leader = leader, !leader.isHit,
              let leaderSprite = leader.component(ofType: SpriteComponent.self)?.spriteNode,
              let spriteNode = component(ofType: SpriteComponent.self)?.spriteNode
        else {
            if isLeaderFollower {
                onLeaderLost()
            }
            return
        }

        escortPoseClock += TimeInterval(dt)
        let fallbackPose = EscortPoseSample(
            time: 0,
            position: leaderSprite.position,
            heading: leaderSprite.zRotation + .pi / 2
        )
        let leaderPose = escortLeadTime > 0
            ? leader.projectedEscortPose(leadTime: escortLeadTime) ?? fallbackPose
            : leader.sampleEscortPose(lag: escortLag) ?? fallbackPose
        let slotOffset = rotatedEscortOffset(leaderOffset, heading: leaderPose.heading)
        let forward = CGPoint(x: cos(leaderPose.heading), y: sin(leaderPose.heading))
        let right = CGPoint(x: cos(leaderPose.heading + .pi / 2), y: sin(leaderPose.heading + .pi / 2))
        let time = CGFloat(escortPoseClock)
        let wobble = sin(time * escortWobbleSpeed + escortWobblePhase) * escortWobbleAmplitude
        let bob = cos(time * escortWobbleSpeed * 0.7 + escortWobblePhase) * escortWobbleAmplitude * 0.35
        let slotTarget = CGPoint(
            x: leaderPose.position.x + slotOffset.x + right.x * wobble + forward.x * bob,
            y: leaderPose.position.y + slotOffset.y + right.y * wobble + forward.y * bob
        )
        let separation = escortSeparationVector(for: spriteNode, leader: leader)
        let target = CGPoint(
            x: slotTarget.x + separation.dx,
            y: slotTarget.y + separation.dy
        )
        let dx = target.x - spriteNode.position.x
        let dy = target.y - spriteNode.position.y
        let dist = sqrt(dx * dx + dy * dy)

        let fallbackVelocity = CGVector(dx: forward.x * leader.speed, dy: forward.y * leader.speed)
        let slotVelocity = escortSlotVelocity(
            for: slotTarget,
            deltaTime: dt,
            fallbackVelocity: fallbackVelocity
        )
        let correctionVelocity: CGVector
        if dist > 0.5 {
            let correctionSpeed = min(escortFollowSpeed, dist / Constants.EW.ewEscortCorrectionTime)
            correctionVelocity = CGVector(dx: dx / dist * correctionSpeed,
                                          dy: dy / dist * correctionSpeed)
        } else {
            correctionVelocity = .zero
        }
        let driftVelocity = velocityWithMinimumForwardSpeed(
            CGVector(dx: slotVelocity.dx + correctionVelocity.dx,
                     dy: slotVelocity.dy + correctionVelocity.dy),
            forward: forward,
            minimumSpeed: leader.speed * Constants.EW.ewEscortMinForwardSpeedRatio
        )
        let desiredVelocity = clampedVector(
            driftVelocity,
            maxLength: escortFollowSpeed
        )
        escortVelocity = moveVector(
            escortVelocity,
            toward: desiredVelocity,
            maxDelta: Constants.EW.ewEscortAcceleration * dt
        )

        spriteNode.position.x += escortVelocity.dx * dt
        spriteNode.position.y += escortVelocity.dy * dt

        let currentHeading = spriteNode.zRotation + .pi / 2
        let velocitySpeed = sqrt(escortVelocity.dx * escortVelocity.dx + escortVelocity.dy * escortVelocity.dy)
        let desiredHeading = velocitySpeed > 1 ? atan2(escortVelocity.dy, escortVelocity.dx) : leaderPose.heading
        let delta = normalizedAngle(desiredHeading - currentHeading)
        let maxTurn = escortTurnRate * dt
        let newHeading: CGFloat
        if abs(delta) <= maxTurn {
            newHeading = desiredHeading
        } else {
            newHeading = normalizedAngle(currentHeading + (delta > 0 ? maxTurn : -maxTurn))
        }
        spriteNode.zRotation = newHeading - .pi / 2
    }

    private func escortSlotVelocity(for slotTarget: CGPoint,
                                    deltaTime dt: CGFloat,
                                    fallbackVelocity: CGVector) -> CGVector {
        defer { previousEscortSlotTarget = slotTarget }
        guard dt > 0.0001, let previous = previousEscortSlotTarget else { return fallbackVelocity }

        return CGVector(
            dx: (slotTarget.x - previous.x) / dt,
            dy: (slotTarget.y - previous.y) / dt
        )
    }

    private func velocityWithMinimumForwardSpeed(_ velocity: CGVector,
                                                 forward: CGPoint,
                                                 minimumSpeed: CGFloat) -> CGVector {
        let forwardSpeed = velocity.dx * forward.x + velocity.dy * forward.y
        guard forwardSpeed < minimumSpeed else { return velocity }

        let missingSpeed = minimumSpeed - forwardSpeed
        return CGVector(
            dx: velocity.dx + forward.x * missingSpeed,
            dy: velocity.dy + forward.y * missingSpeed
        )
    }

    private func moveVector(_ value: CGVector, toward target: CGVector, maxDelta: CGFloat) -> CGVector {
        let dx = target.dx - value.dx
        let dy = target.dy - value.dy
        let distance = sqrt(dx * dx + dy * dy)
        guard distance > maxDelta, distance > 0.0001 else { return target }
        let scale = maxDelta / distance
        return CGVector(dx: value.dx + dx * scale, dy: value.dy + dy * scale)
    }

    private func clampedVector(_ vector: CGVector, maxLength: CGFloat) -> CGVector {
        let length = sqrt(vector.dx * vector.dx + vector.dy * vector.dy)
        guard length > maxLength, length > 0.0001 else { return vector }
        let scale = maxLength / length
        return CGVector(dx: vector.dx * scale, dy: vector.dy * scale)
    }

    private func rotatedEscortOffset(_ offset: CGPoint, heading: CGFloat) -> CGPoint {
        let forward = CGPoint(x: cos(heading), y: sin(heading))
        let right = CGPoint(x: cos(heading + .pi / 2), y: sin(heading + .pi / 2))
        return CGPoint(
            x: right.x * offset.x - forward.x * offset.y,
            y: right.y * offset.x - forward.y * offset.y
        )
    }

    private func escortSeparationVector(for spriteNode: SKSpriteNode, leader: AttackDroneEntity) -> CGVector {
        guard let scene = spriteNode.scene as? InPlaySKScene else { return .zero }

        let minDistance = Constants.EW.ewEscortSeparationDistance
        let minDistanceSq = minDistance * minDistance
        var separationX: CGFloat = 0
        var separationY: CGFloat = 0

        for other in scene.activeDrones where other !== self && other.isLeaderFollower && !other.isHit {
            guard let otherLeader = other.leader, otherLeader === leader,
                  let otherSprite = other.component(ofType: SpriteComponent.self)?.spriteNode else { continue }

            let dx = spriteNode.position.x - otherSprite.position.x
            let dy = spriteNode.position.y - otherSprite.position.y
            let distSq = dx * dx + dy * dy
            guard distSq > 0.0001 && distSq < minDistanceSq else { continue }

            let dist = sqrt(distSq)
            let strength = (1 - dist / minDistance) * Constants.EW.ewEscortSeparationStrength
            separationX += (dx / dist) * strength
            separationY += (dy / dist) * strength
        }

        return CGVector(dx: separationX, dy: separationY)
    }

    private func normalizedAngle(_ angle: CGFloat) -> CGFloat {
        var result = angle
        while result > .pi { result -= 2 * .pi }
        while result < -.pi { result += 2 * .pi }
        return result
    }

    /// Hook for subclasses/callers: leader is gone. Default: just detach.
    /// The shahed escort system overrides this via closure (see `onLeaderLostHandler`).
    public var onLeaderLostHandler: ((AttackDroneEntity) -> Void)?

    private func onLeaderLost() {
        let handler = onLeaderLostHandler
        detachFromLeader()
        handler?(self)
    }

    /// Retarget the drone mid-flight: rebuild GKAgent path from current position through new waypoints
    func retargetPath(waypoints: [CGPoint]) {
        guard !waypoints.isEmpty else { return }
        let nodes = waypoints.map { vector_float2(x: Float($0.x), y: Float($0.y)) }
        let path = GKPath(points: nodes, radius: 15, cyclical: false)
        let goal = GKGoal(toFollow: path, maxPredictionTime: 100 / speed * 1.5, forward: true)
        let newBehavior = GKBehavior(goal: goal, weight: 100000)
        component(ofType: FlyingProjectileComponent.self)?.behavior = newBehavior
    }

    private func behavior(for flyingPath: FlyingPath)->GKBehavior{
        let path = GKPath(points: flyingPath.nodes, radius: 15, cyclical: false)

        let goal = GKGoal(toFollow: path, maxPredictionTime: 100/speed * 1.5, forward: true)
        return GKBehavior(goal: goal, weight: 100000)
    }
    
    private func setupGeometryComponent(spriteComponent: SpriteComponent)->GeometryComponent{
        let geometryComponent = GeometryComponent(spriteNode: spriteComponent.spriteNode,
                                                  categoryBitMask: Constants.droneBitMask,
                                                  contactTestBitMask: Constants.bulletBitMask | Constants.groundBitMask,
                                                  collisionBitMask: 0)
        let physicsBody = geometryComponent.geometryNode.physicsBody
        physicsBody?.affectedByGravity = false
        return geometryComponent
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public func agentDidUpdate(_ agent: GKAgent) {
        guard let agent2d = agent as? GKAgent2D,
              let spriteNode = component(ofType: SpriteComponent.self)?.spriteNode,
              !isHit
        else{
            return
        }
        if isFormationFlight {
            // SKAction drives sprite — sync agent position from sprite for targeting
            agent2d.position = vector_float2(
                x: Float(spriteNode.position.x),
                y: Float(spriteNode.position.y)
            )
        } else {
            spriteNode.position = CGPoint(x: CGFloat(agent2d.position.x), y: CGFloat(agent2d.position.y))
            spriteNode.zRotation = CGFloat(agent2d.rotation) - .pi / 2
        }
    }

}
