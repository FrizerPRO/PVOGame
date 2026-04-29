//
//  AtackDrone.swift
//  PVOGame
//
//  Created by Frizer on 03.01.2023.
//

import Foundation
import GameplayKit

public class AttackDroneEntity: GKEntity, FlyingProjectile{
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

    /// When non-nil, this drone's sprite is slaved to `leader.position + leaderOffset`
    /// until the leader dies. Used for "Shahed shield around EW drone"-style escorts.
    public weak var leader: AttackDroneEntity?
    /// World-space offset from the leader's sprite, locked in at attach time.
    public var leaderOffset: CGPoint = .zero
    public var isLeaderFollower: Bool = false

    public var health: Int
    public var maxHealth: Int

    private var hpBarBackground: SKSpriteNode?
    private var hpBarFill: SKSpriteNode?
    private var hpBarContainer: SKNode?

    // PvZ-style damage visuals
    private var damageSmoke: SKEmitterNode?
    private var currentDamageLevel: DamageVisualLevel = .none
    var isBossType: Bool { false }

    enum DamageVisualLevel: Int, Comparable {
        case none = 0
        case light = 1
        case medium = 2
        case critical = 3

        /// All damage stages from most severe to least, used for threshold distribution.
        static let allStages: [DamageVisualLevel] = [.critical, .medium, .light]

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

        // Take as many visual stages as the drone has HP steps, filling from most severe.
        // 2 HP (1 step)  → [critical]
        // 3 HP (2 steps) → [critical, medium]
        // 4+ HP (3+ steps) → [critical, medium, light]
        let steps = maxHealth - 1
        let stages = Array(DamageVisualLevel.allStages.prefix(min(steps, DamageVisualLevel.allStages.count)))
        let usedCount = stages.count

        // Evenly split HP range into (usedCount+1) bands.
        // Band i triggers stages[i] when health <= maxHealth * (usedCount - i) / (usedCount + 1)
        var newLevel: DamageVisualLevel = .none
        for (i, stage) in stages.enumerated() {
            let threshold = maxHealth * (usedCount - i) / (usedCount + 1)
            if health <= threshold {
                newLevel = stage
                break
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
            // Heavier smoke + darker tint
            addDamageSmoke(on: spriteNode, birthRate: 20, alpha: 0.5)
            spriteNode.color = UIColor(white: 0.35, alpha: 1)
            spriteNode.colorBlendFactor = 0.35
        case .critical:
            // Fire effect — drone is burning
            addDamageFire(on: spriteNode)
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
        emitter.particleBirthRate = birthRate
        emitter.particleLifetime = 0.6
        emitter.particleLifetimeRange = 0.3
        emitter.particlePositionRange = CGVector(dx: spriteNode.size.width * 0.3, dy: spriteNode.size.height * 0.3)
        emitter.particleSpeed = 12
        emitter.particleSpeedRange = 6
        emitter.emissionAngle = .pi / 2
        emitter.emissionAngleRange = .pi / 4
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

    private func addDamageFire(on spriteNode: SKSpriteNode) {
        damageSmoke?.removeFromParent()

        let emitter = SKEmitterNode()
        emitter.particleTexture = Self.smokeTexture
        emitter.particleBirthRate = 40
        emitter.particleLifetime = 0.4
        emitter.particleLifetimeRange = 0.2
        emitter.particlePositionRange = CGVector(dx: spriteNode.size.width * 0.3, dy: spriteNode.size.height * 0.3)
        emitter.particleSpeed = 18
        emitter.particleSpeedRange = 8
        emitter.emissionAngle = .pi / 2
        emitter.emissionAngleRange = .pi / 3
        emitter.particleAlpha = 0.9
        emitter.particleAlphaSpeed = -1.5
        emitter.particleScale = 0.2
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
        damageSmoke?.removeFromParent()
        damageSmoke = nil
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
            applyLeaderFollowTick()
        }
    }

    /// Attach this drone to a leader. Disables its path-following behavior so the
    /// GKAgent doesn't fight the sprite position we drive directly each frame.
    /// `offset` is in world coordinates relative to the leader sprite at attach time.
    public func attachToLeader(_ newLeader: AttackDroneEntity, offset: CGPoint) {
        self.leader = newLeader
        self.leaderOffset = offset
        self.isLeaderFollower = true
        self.isFormationFlight = true  // reuse the "sprite drives agent" sync path
        component(ofType: FlyingProjectileComponent.self)?.behavior?.removeAllGoals()
    }

    /// Detach from leader. Caller is responsible for providing a fresh path via `retargetPath`.
    public func detachFromLeader() {
        self.leader = nil
        self.isLeaderFollower = false
        self.isFormationFlight = false
    }

    /// Called every frame when this drone is in leader-follow mode.
    /// Default: offset-in-screen-space — hex shield remains axis-aligned as leader flies south.
    /// When the leader dies, subclasses or callers can hook `onLeaderLost` to rebuild a path.
    private func applyLeaderFollowTick() {
        guard let leader = leader, !leader.isHit,
              let leaderSprite = leader.component(ofType: SpriteComponent.self)?.spriteNode,
              let spriteNode = component(ofType: SpriteComponent.self)?.spriteNode
        else {
            if isLeaderFollower {
                onLeaderLost()
            }
            return
        }

        spriteNode.position = CGPoint(
            x: leaderSprite.position.x + leaderOffset.x,
            y: leaderSprite.position.y + leaderOffset.y
        )
        spriteNode.zRotation = leaderSprite.zRotation
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
