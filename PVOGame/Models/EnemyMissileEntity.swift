//
//  EnemyMissileEntity.swift
//  PVOGame
//

import Foundation
import GameplayKit
import SpriteKit

final class EnemyMissileEntity: AttackDroneEntity {

    private var targetPoint: CGPoint = .zero
    private var velocity: CGVector = .zero
    private var smokeAccumulator: TimeInterval = 0
    private var positionLogAccumulator: TimeInterval = 0

    private static let smokePuffTexture: SKTexture = {
        let diameter: CGFloat = 14
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: diameter, height: diameter))
        let image = renderer.image { ctx in
            UIColor.white.setFill()
            ctx.cgContext.fillEllipse(in: CGRect(x: 0, y: 0, width: diameter, height: diameter))
        }
        return SKTexture(image: image)
    }()

    private static let smokePuffAction: SKAction = {
        let expand = SKAction.scale(to: 2.0, duration: 0.4)
        let fade = SKAction.fadeOut(withDuration: 0.4)
        return SKAction.sequence([
            SKAction.group([expand, fade]),
            SKAction.removeFromParent()
        ])
    }()

    init(sceneFrame: CGRect) {
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
            speed: Constants.GameBalance.enemyMissileBaseSpeed,
            imageName: "Bullet",
            flyingPath: dummyPath
        )
        removeComponent(ofType: FlyingProjectileComponent.self)

        // Elongated red missile sprite
        if let spriteNode = component(ofType: SpriteComponent.self)?.spriteNode {
            spriteNode.size = CGSize(width: 6, height: 18)
            spriteNode.color = UIColor(red: 0.85, green: 0.15, blue: 0.1, alpha: 1)
            spriteNode.colorBlendFactor = 1.0
        }
    }

    required init(damage: CGFloat, speed: CGFloat, imageName: String, flyingPath: FlyingPath) {
        super.init(damage: damage, speed: speed, imageName: imageName, flyingPath: flyingPath)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configureFlight(from spawnPoint: CGPoint, to target: CGPoint, speed missileSpeed: CGFloat) {
        self.targetPoint = target
        self.speed = missileSpeed

        if let spriteNode = component(ofType: SpriteComponent.self)?.spriteNode {
            spriteNode.position = spawnPoint
        }

        let dx = target.x - spawnPoint.x
        let dy = target.y - spawnPoint.y
        let dist = sqrt(dx * dx + dy * dy)
        guard dist > 0 else { return }

        let dirX = dx / dist
        let dirY = dy / dist
        velocity = CGVector(dx: dirX * missileSpeed, dy: dirY * missileSpeed)

        // Rotate sprite to face direction of travel
        if let spriteNode = component(ofType: SpriteComponent.self)?.spriteNode {
            spriteNode.zRotation = atan2(dy, dx) - .pi / 2
        }
    }

    override func update(deltaTime seconds: TimeInterval) {
        guard !isHit else { return }
        guard let spriteNode = component(ofType: SpriteComponent.self)?.spriteNode else { return }

        // Move
        spriteNode.position.x += velocity.dx * CGFloat(seconds)
        spriteNode.position.y += velocity.dy * CGFloat(seconds)

        // Throttled position logging
        positionLogAccumulator += seconds
        if positionLogAccumulator >= 1.0 {
            positionLogAccumulator = 0
            print("[MISSILE] pos=(\(Int(spriteNode.position.x)),\(Int(spriteNode.position.y))) vel=(\(Int(velocity.dx)),\(Int(velocity.dy))) isHit=\(isHit)")
        }

        // Emit smoke puffs
        smokeAccumulator += seconds
        if smokeAccumulator >= 0.1, let scene = spriteNode.scene {
            smokeAccumulator = 0

            let tailOffset = CGPoint(x: 0, y: -spriteNode.size.height * 0.55)
            var tailPoint = spriteNode.convert(tailOffset, to: scene)
            tailPoint.x += CGFloat.random(in: -1.5...1.5)
            tailPoint.y += CGFloat.random(in: -1.5...1.5)

            let puff = SKSpriteNode(texture: Self.smokePuffTexture)
            puff.size = CGSize(width: 5, height: 5)
            puff.position = tailPoint
            puff.zPosition = 40
            puff.color = UIColor(white: 0.9, alpha: 0.9)
            puff.colorBlendFactor = 1.0
            puff.alpha = 0.6
            scene.addChild(puff)
            puff.run(Self.smokePuffAction)
        }
    }

    override func didHit() {
        isHit = true

        let physicBody = component(ofType: GeometryComponent.self)?.geometryNode.physicsBody
        physicBody?.contactTestBitMask = 0
        physicBody?.categoryBitMask = 0

        // Orange explosion flash (no spin/fall — ballistic missile explodes in place)
        if let spriteNode = component(ofType: SpriteComponent.self)?.spriteNode {
            let flash = SKSpriteNode(color: .orange, size: CGSize(width: 24, height: 24))
            flash.position = spriteNode.position
            flash.zPosition = 55
            flash.alpha = 0.9
            spriteNode.scene?.addChild(flash)

            let expand = SKAction.scale(to: 2.5, duration: 0.2)
            let fade = SKAction.fadeOut(withDuration: 0.2)
            flash.run(SKAction.sequence([SKAction.group([expand, fade]), SKAction.removeFromParent()]))

            spriteNode.run(SKAction.sequence([
                SKAction.fadeOut(withDuration: 0.1),
                SKAction.run { [weak self] in self?.removeFromParent() }
            ]))
        }
    }

    override func reachedDestination() {
        guard !isHit else {
            removeFromParent()
            return
        }
        // Small explosion VFX at impact point
        if let spriteNode = component(ofType: SpriteComponent.self)?.spriteNode,
           let scene = spriteNode.scene {
            let flash = SKSpriteNode(color: .orange, size: CGSize(width: 18, height: 18))
            flash.position = spriteNode.position
            flash.zPosition = 50
            flash.alpha = 0.7
            scene.addChild(flash)

            let expand = SKAction.scale(to: 2.0, duration: 0.15)
            let fade = SKAction.fadeOut(withDuration: 0.15)
            flash.run(SKAction.sequence([SKAction.group([expand, fade]), SKAction.removeFromParent()]))
        }
        removeFromParent()
    }
}
