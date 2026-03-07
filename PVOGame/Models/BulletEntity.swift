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
        if let position = component(ofType: SpriteComponent.self)?.spriteNode.position{
            if self.previousPosition.y - position.y > 0{
                detonateWithAnimation()
            } else if  self.previousPosition.y < position.y{
                self.previousPosition = position
            }
        }
    }
    
    override func update(deltaTime seconds: TimeInterval) {
        autoDetonation()
    }
    
}

class RocketEntity: BulletEntity {
    let spec: Constants.GameBalance.RocketSpec
    var blastRadius: CGFloat { spec.blastRadius }
    private(set) var currentSpeed: CGFloat = 0
    private(set) var isCoastingAfterFuelExhaustion = false
    private var targetPoint = CGPoint.zero
    private var isGuided = false
    private var smokeSpawnAccumulator: TimeInterval = 0
    private var retargetAccumulator: TimeInterval = 0
    private var travelledDistance: CGFloat = 0
    private var previousTrackedPosition: CGPoint?

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
            ammoPerWave: defaultSpec.ammoPerWave
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
            scene.spawnRocketBlast(at: position, radius: blastRadius)
        }
        silentDetonate()
    }

    override func copy() -> Any {
        RocketEntity(spec: spec)
    }

    func configureFlight(targetPoint: CGPoint, initialSpeed: CGFloat) {
        self.targetPoint = targetPoint
        self.currentSpeed = max(0, initialSpeed)
        self.travelledDistance = 0
        self.previousTrackedPosition = nil
        self.isCoastingAfterFuelExhaustion = false
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

        emitSmokeIfNeeded(from: spriteNode, deltaTime: seconds)
        if !retargetIfNeeded(from: spriteNode, deltaTime: seconds) {
            return
        }

        let dx = targetPoint.x - spriteNode.position.x
        let dy = targetPoint.y - spriteNode.position.y
        let distance = sqrt(dx * dx + dy * dy)
        let detonationDistance = max(10, blastRadius * 0.2)
        if distance <= detonationDistance {
            detonateWithAnimation()
            return
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

        spriteNode.size = CGSize(width: 12, height: 18)
        spriteNode.physicsBody?.linearDamping = 0
        spriteNode.physicsBody?.angularDamping = 0
        spriteNode.physicsBody?.allowsRotation = false
        spriteNode.physicsBody?.affectedByGravity = false
        spriteNode.physicsBody?.friction = 0
        spriteNode.physicsBody?.restitution = 0
    }

    private func emitSmokeIfNeeded(from spriteNode: SKSpriteNode, deltaTime seconds: TimeInterval) {
        guard let scene = spriteNode.scene else { return }

        smokeSpawnAccumulator -= seconds
        guard smokeSpawnAccumulator <= 0 else { return }
        smokeSpawnAccumulator += 0.025

        var tailPoint = spriteNode.convert(CGPoint(x: 0, y: -spriteNode.size.height * 0.55), to: scene)
        tailPoint.x += CGFloat.random(in: -2...2)
        tailPoint.y += CGFloat.random(in: -2...2)

        let puff = SKShapeNode(circleOfRadius: CGFloat.random(in: 2.5...4.5))
        puff.position = tailPoint
        puff.zPosition = 40
        puff.fillColor = UIColor(white: 1, alpha: 0.95)
        puff.strokeColor = .clear
        puff.alpha = 0.75
        puff.xScale = 0.75
        puff.yScale = 0.75
        scene.addChild(puff)

        let wait = SKAction.wait(forDuration: 1.1)
        let expand = SKAction.scale(to: 3.6, duration: 1.35)
        let fade = SKAction.fadeOut(withDuration: 1.35)
        puff.run(SKAction.sequence([wait, SKAction.group([expand, fade]), SKAction.removeFromParent()]))
    }

    private func retargetIfNeeded(from spriteNode: SKSpriteNode, deltaTime seconds: TimeInterval) -> Bool {
        retargetAccumulator -= seconds
        guard retargetAccumulator <= 0 else { return true }
        retargetAccumulator += spec.retargetInterval

        guard let scene = spriteNode.scene as? InPlaySKScene else { return true }
        if let updatedTarget = scene.bestRocketTargetPoint(
            preferredPoint: targetPoint,
            origin: spriteNode.position,
            radius: spec.maxFlightDistance
        ) {
            targetPoint = updatedTarget
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
        isGuided = false
        spriteNode.physicsBody?.affectedByGravity = true
    }

}
