//
//  LancetDroneEntity.swift
//  PVOGame
//
//  ZALA Lancet — loitering munition that targets towers.
//  Behavior: spawns from top, loiters (circles) for N seconds picking
//  the weakest tower, then dives at high speed. Instant tower kill.
//  Based on real Russian Lancet barrage munition.
//

import Foundation
import GameplayKit
import SpriteKit

final class LancetDroneEntity: AttackDroneEntity {

    override var isJammableByEW: Bool { false }

    enum Phase {
        case approach      // fly toward target area
        case dive          // dive at selected tower
    }

    private(set) var phase: Phase = .approach
    private var velocity: CGVector = .zero
    private var loiterTimer: TimeInterval = Constants.Lancet.loiterDuration
    private var loiterCenter: CGPoint = .zero
    private var loiterAngle: CGFloat = 0
    private let loiterRadius: CGFloat = 40
    private(set) weak var targetTower: TowerEntity?
    private weak var gameScene: InPlaySKScene?
    private var approachEvasionPhase: CGFloat = 0
    private var approachDirection: CGVector = .zero
    private var currentHeading: CGFloat = -.pi / 2  // current facing direction
    /// Max turn rate during dive (rad/s) — smooth arc toward target.
    private let diveTurnRate: CGFloat = 2.5

    init(sceneFrame: CGRect, scene: InPlaySKScene) {
        self.gameScene = scene
        let dummyPath = FlyingPath(
            topLevel: sceneFrame.height,
            bottomLevel: 0,
            leadingLevel: 0,
            trailingLevel: sceneFrame.width,
            startLevel: sceneFrame.height + 50,
            endLevel: 0,
            pathGenerator: { _ in
                [
                    vector_float2(x: Float(sceneFrame.midX), y: Float(sceneFrame.height + 50)),
                    vector_float2(x: Float(sceneFrame.midX), y: 0)
                ]
            }
        )
        super.init(
            damage: 1,
            speed: Constants.Lancet.speed,
            imageName: "Bullet",
            flyingPath: dummyPath
        )
        removeComponent(ofType: FlyingProjectileComponent.self)
        configureHealth(Constants.Lancet.health)

        // Small terrain-masked loitering munition — gun/MANPADS only.
        addComponent(AltitudeComponent(altitude: .micro))

        // Lancet loitering munition sprite
        if let spriteNode = component(ofType: SpriteComponent.self)?.spriteNode {
            spriteNode.size = Constants.SpriteSize.lancet
            if let tex = AnimationTextureCache.shared.droneTextures["drone_lancet"] {
                spriteNode.texture = tex
                spriteNode.color = .white
                spriteNode.colorBlendFactor = 0
            } else {
                spriteNode.color = UIColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1)
                spriteNode.colorBlendFactor = 1.0
            }

            // Spinning propeller at the rear (same as Shahed)
            let propeller = SKSpriteNode(color: UIColor(white: 0.25, alpha: 1), size: CGSize(width: 5, height: 1.5))
            propeller.position = CGPoint(x: 0, y: -7) // rear of drone
            propeller.zPosition = 1
            let spin = SKAction.repeatForever(SKAction.rotate(byAngle: .pi * 2, duration: 0.15))
            propeller.run(spin)
            spriteNode.addChild(propeller)
        }
    }

    required init(damage: CGFloat, speed: CGFloat, imageName: String, flyingPath: FlyingPath) {
        super.init(damage: damage, speed: speed, imageName: imageName, flyingPath: flyingPath)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Pre-assign a tower target (e.g. from Orlan recon).
    func assignTarget(_ tower: TowerEntity) {
        targetTower = tower
    }

    func configureFlight(from spawnPoint: CGPoint, loiterAt center: CGPoint) {
        self.loiterCenter = center
        self.loiterAngle = CGFloat.random(in: 0...(2 * .pi))
        self.approachEvasionPhase = CGFloat.random(in: 0...(2 * .pi))

        if let spriteNode = component(ofType: SpriteComponent.self)?.spriteNode {
            spriteNode.position = spawnPoint
        }

        // Fly toward loiter center
        let dx = center.x - spawnPoint.x
        let dy = center.y - spawnPoint.y
        let dist = sqrt(dx * dx + dy * dy)
        guard dist > 0 else { return }
        let ux = dx / dist
        let uy = dy / dist
        approachDirection = CGVector(dx: ux, dy: uy)
        velocity = CGVector(dx: ux * speed, dy: uy * speed)
        currentHeading = atan2(dy, dx)

        if let spriteNode = component(ofType: SpriteComponent.self)?.spriteNode {
            spriteNode.zRotation = currentHeading - .pi / 2
        }
    }

    override func update(deltaTime seconds: TimeInterval) {
        guard !isHit else { return }
        guard let spriteNode = component(ofType: SpriteComponent.self)?.spriteNode else { return }

        switch phase {
        case .approach:
            // Base forward motion along approach direction at configured speed.
            spriteNode.position.x += approachDirection.dx * speed * CGFloat(seconds)
            spriteNode.position.y += approachDirection.dy * speed * CGFloat(seconds)

            // Sinusoidal evasion perpendicular to the approach axis.
            approachEvasionPhase += CGFloat(seconds) * Constants.Lancet.approachEvasionFrequency * 2 * .pi
            let lateralOffset = sin(approachEvasionPhase) * Constants.Lancet.approachEvasionAmplitude * CGFloat(seconds) * 2
            let perpX = -approachDirection.dy
            let perpY = approachDirection.dx
            spriteNode.position.x += perpX * lateralOffset
            spriteNode.position.y += perpY * lateralOffset
            spriteNode.zRotation = atan2(approachDirection.dy, approachDirection.dx) - .pi / 2

            // Check if close to loiter center
            let dx = loiterCenter.x - spriteNode.position.x
            let dy = loiterCenter.y - spriteNode.position.y
            if dx * dx + dy * dy < 30 * 30 {
                if targetTower == nil { pickTarget() }
                startDive()
            }

        case .dive:
            // Smooth steering toward target with bounded turn rate
            let diveSpeed = Constants.Lancet.diveSpeed
            if let tower = targetTower {
                let towerPos = tower.worldPosition
                let dx = towerPos.x - spriteNode.position.x
                let dy = towerPos.y - spriteNode.position.y

                // Steer toward target
                let desiredHeading = atan2(dy, dx)
                var delta = desiredHeading - currentHeading
                while delta > .pi { delta -= 2 * .pi }
                while delta < -.pi { delta += 2 * .pi }
                let maxStep = diveTurnRate * CGFloat(seconds)
                currentHeading += max(-maxStep, min(maxStep, delta))

                // Check if reached target tower
                if dx * dx + dy * dy < 20 * 20 {
                    hitTower(tower)
                }
            }

            velocity = CGVector(dx: cos(currentHeading) * diveSpeed, dy: sin(currentHeading) * diveSpeed)
            spriteNode.position.x += velocity.dx * CGFloat(seconds)
            spriteNode.position.y += velocity.dy * CGFloat(seconds)
            spriteNode.zRotation = currentHeading - .pi / 2

            // If off-screen, die
            if spriteNode.position.y < -50 {
                didHit()
            }
            // If target destroyed, retarget
            if targetTower == nil {
                pickTarget()
                if targetTower == nil {
                    didHit()
                }
            }
        }
    }

    private func pickTarget() {
        guard let scene = gameScene else { return }
        // Pick the tower with lowest durability ratio (weakest)
        var bestTower: TowerEntity?
        var bestScore: CGFloat = .infinity
        for tower in scene.towerPlacement.towers {
            guard let stats = tower.stats, !stats.isDisabled else { continue }
            let ratio = CGFloat(stats.durability) / CGFloat(stats.maxDurability)
            // Prefer expensive towers
            let value = ratio - CGFloat(stats.cost) / 1000.0
            if value < bestScore {
                bestScore = value
                bestTower = tower
            }
        }
        targetTower = bestTower

        // If no towers available, fly toward HQ
        if targetTower == nil {
            loiterCenter.y -= 100  // shift loiter lower
        }
    }

    private func startDive() {
        phase = .dive
        // Heading and velocity are updated smoothly each frame in the dive phase.
        // No instant snap — the lancet arcs toward the target.
    }

    private func hitTower(_ tower: TowerEntity) {
        // Destroy tower
        tower.takeBombDamage(Constants.Lancet.towerDestroyDamage)

        // Explosion VFX at impact
        if let spriteNode = component(ofType: SpriteComponent.self)?.spriteNode,
           let scene = spriteNode.scene {
            let flash = SKShapeNode(circleOfRadius: 12)
            flash.fillColor = .orange
            flash.strokeColor = .clear
            flash.position = spriteNode.position
            flash.zPosition = 55
            flash.alpha = 0.9
            scene.addChild(flash)
            let expand = SKAction.scale(to: 2.5, duration: 0.2)
            let fade = SKAction.fadeOut(withDuration: 0.15)
            flash.run(SKAction.sequence([SKAction.group([expand, fade]), SKAction.removeFromParent()]))
        }

        didHit()
    }

    override func didHit() {
        isHit = true
        let physicBody = component(ofType: GeometryComponent.self)?.geometryNode.physicsBody
        physicBody?.contactTestBitMask = 0
        physicBody?.categoryBitMask = 0

        if let spriteNode = component(ofType: SpriteComponent.self)?.spriteNode {
            let flash = SKShapeNode(circleOfRadius: 8)
            flash.fillColor = .orange
            flash.strokeColor = .clear
            flash.position = spriteNode.position
            flash.zPosition = 55
            flash.alpha = 0.9
            spriteNode.scene?.addChild(flash)
            let expand = SKAction.scale(to: 2.0, duration: 0.15)
            let fade = SKAction.fadeOut(withDuration: 0.15)
            flash.run(SKAction.sequence([SKAction.group([expand, fade]), SKAction.removeFromParent()]))

            spriteNode.run(SKAction.sequence([
                SKAction.fadeOut(withDuration: 0.08),
                SKAction.run { [weak self] in self?.removeFromParent() }
            ]))
        }
    }

    override func reachedDestination() {
        guard !isHit else {
            removeFromParent()
            return
        }
        removeFromParent()
    }
}
