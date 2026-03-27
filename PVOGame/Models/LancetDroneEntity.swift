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

    enum Phase {
        case approach      // fly to loiter area
        case loiter        // circle, choosing target
        case dive          // dive at selected tower
    }

    private(set) var phase: Phase = .approach
    private var velocity: CGVector = .zero
    private var loiterTimer: TimeInterval = Constants.Lancet.loiterDuration
    private var loiterCenter: CGPoint = .zero
    private var loiterAngle: CGFloat = 0
    private let loiterRadius: CGFloat = 40
    private weak var targetTower: TowerEntity?
    private weak var gameScene: InPlaySKScene?

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

        // Small dark triangular sprite — loitering munition
        if let spriteNode = component(ofType: SpriteComponent.self)?.spriteNode {
            spriteNode.size = CGSize(width: 14, height: 16)
            spriteNode.color = UIColor(red: 0.5, green: 0.15, blue: 0.15, alpha: 1)
            spriteNode.colorBlendFactor = 1.0
        }
    }

    required init(damage: CGFloat, speed: CGFloat, imageName: String, flyingPath: FlyingPath) {
        super.init(damage: damage, speed: speed, imageName: imageName, flyingPath: flyingPath)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configureFlight(from spawnPoint: CGPoint, loiterAt center: CGPoint) {
        self.loiterCenter = center
        self.loiterAngle = CGFloat.random(in: 0...(2 * .pi))

        if let spriteNode = component(ofType: SpriteComponent.self)?.spriteNode {
            spriteNode.position = spawnPoint
        }

        // Fly toward loiter center
        let dx = center.x - spawnPoint.x
        let dy = center.y - spawnPoint.y
        let dist = sqrt(dx * dx + dy * dy)
        guard dist > 0 else { return }
        velocity = CGVector(dx: dx / dist * speed, dy: dy / dist * speed)

        if let spriteNode = component(ofType: SpriteComponent.self)?.spriteNode {
            spriteNode.zRotation = atan2(dy, dx) - .pi / 2
        }
    }

    override func update(deltaTime seconds: TimeInterval) {
        guard !isHit else { return }
        guard let spriteNode = component(ofType: SpriteComponent.self)?.spriteNode else { return }

        switch phase {
        case .approach:
            spriteNode.position.x += velocity.dx * CGFloat(seconds)
            spriteNode.position.y += velocity.dy * CGFloat(seconds)

            // Check if close to loiter center
            let dx = loiterCenter.x - spriteNode.position.x
            let dy = loiterCenter.y - spriteNode.position.y
            if dx * dx + dy * dy < 30 * 30 {
                phase = .loiter
                pickTarget()
            }

        case .loiter:
            loiterTimer -= seconds
            loiterAngle += CGFloat(seconds) * 1.5  // angular speed

            // Circle around loiter center
            let targetPos = CGPoint(
                x: loiterCenter.x + cos(loiterAngle) * loiterRadius,
                y: loiterCenter.y + sin(loiterAngle) * loiterRadius
            )
            let dx = targetPos.x - spriteNode.position.x
            let dy = targetPos.y - spriteNode.position.y
            spriteNode.position.x += dx * CGFloat(seconds) * 3
            spriteNode.position.y += dy * CGFloat(seconds) * 3
            spriteNode.zRotation = atan2(dy, dx) - .pi / 2

            if loiterTimer <= 0 {
                startDive()
            }

        case .dive:
            spriteNode.position.x += velocity.dx * CGFloat(seconds)
            spriteNode.position.y += velocity.dy * CGFloat(seconds)

            // Check if reached target tower
            if let tower = targetTower {
                let towerPos = tower.worldPosition
                let dx = towerPos.x - spriteNode.position.x
                let dy = towerPos.y - spriteNode.position.y
                if dx * dx + dy * dy < 20 * 20 {
                    hitTower(tower)
                }
            }

            // If target is gone or off-screen, just die
            if targetTower == nil || spriteNode.position.y < -50 {
                didHit()
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
        guard let spriteNode = component(ofType: SpriteComponent.self)?.spriteNode else { return }

        let target: CGPoint
        if let tower = targetTower {
            target = tower.worldPosition
        } else {
            target = CGPoint(x: spriteNode.position.x, y: 50)  // fallback
        }

        let dx = target.x - spriteNode.position.x
        let dy = target.y - spriteNode.position.y
        let dist = sqrt(dx * dx + dy * dy)
        guard dist > 0 else { return }

        let diveSpeed = Constants.Lancet.diveSpeed
        velocity = CGVector(dx: dx / dist * diveSpeed, dy: dy / dist * diveSpeed)
        spriteNode.zRotation = atan2(dy, dx) - .pi / 2
    }

    private func hitTower(_ tower: TowerEntity) {
        // Destroy tower
        tower.takeBombDamage(Constants.Lancet.towerDestroyDamage)

        // Explosion VFX at impact
        if let spriteNode = component(ofType: SpriteComponent.self)?.spriteNode,
           let scene = spriteNode.scene {
            let flash = SKSpriteNode(color: .orange, size: CGSize(width: 24, height: 24))
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
            let flash = SKSpriteNode(color: .orange, size: CGSize(width: 16, height: 16))
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
