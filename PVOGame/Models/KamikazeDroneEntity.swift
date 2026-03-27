//
//  KamikazeDroneEntity.swift
//  PVOGame
//

import Foundation
import GameplayKit
import SpriteKit

final class KamikazeDroneEntity: AttackDroneEntity {

    private var targetPoint: CGPoint = .zero
    private var velocity: CGVector = .zero

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
            speed: Constants.Kamikaze.speed,
            imageName: "Bullet",
            flyingPath: dummyPath
        )
        removeComponent(ofType: FlyingProjectileComponent.self)
        configureHealth(Constants.Kamikaze.health)

        // Small triangular kamikaze sprite
        if let spriteNode = component(ofType: SpriteComponent.self)?.spriteNode {
            spriteNode.size = CGSize(width: 12, height: 14)
            spriteNode.color = UIColor(red: 0.3, green: 0.3, blue: 0.3, alpha: 1)
            spriteNode.colorBlendFactor = 1.0
        }
        // Add tower contact detection
        if let geoNode = component(ofType: GeometryComponent.self)?.geometryNode {
            geoNode.physicsBody?.contactTestBitMask |= Constants.towerBitMask
        }
    }

    required init(damage: CGFloat, speed: CGFloat, imageName: String, flyingPath: FlyingPath) {
        super.init(damage: damage, speed: speed, imageName: imageName, flyingPath: flyingPath)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configureFlight(from spawnPoint: CGPoint, to target: CGPoint, speed kamikazeSpeed: CGFloat) {
        self.targetPoint = target
        self.speed = kamikazeSpeed

        if let spriteNode = component(ofType: SpriteComponent.self)?.spriteNode {
            spriteNode.position = spawnPoint
        }

        let dx = target.x - spawnPoint.x
        let dy = target.y - spawnPoint.y
        let dist = sqrt(dx * dx + dy * dy)
        guard dist > 0 else { return }

        let dirX = dx / dist
        let dirY = dy / dist
        velocity = CGVector(dx: dirX * kamikazeSpeed, dy: dirY * kamikazeSpeed)

        if let spriteNode = component(ofType: SpriteComponent.self)?.spriteNode {
            spriteNode.zRotation = atan2(dy, dx) - .pi / 2
        }
    }

    override func update(deltaTime seconds: TimeInterval) {
        guard !isHit else { return }
        guard let spriteNode = component(ofType: SpriteComponent.self)?.spriteNode else { return }

        spriteNode.position.x += velocity.dx * CGFloat(seconds)
        spriteNode.position.y += velocity.dy * CGFloat(seconds)
    }

    override func didHit() {
        isHit = true

        let physicBody = component(ofType: GeometryComponent.self)?.geometryNode.physicsBody
        physicBody?.contactTestBitMask = 0
        physicBody?.categoryBitMask = 0

        if let spriteNode = component(ofType: SpriteComponent.self)?.spriteNode {
            let flash = SKSpriteNode(color: .orange, size: CGSize(width: 16, height: 16))
            flash.position = spriteNode.position
            flash.zPosition = (spriteNode.scene as? InPlaySKScene)?.isNightWave == true ? Constants.NightWave.nightEffectZPosition : 55
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
        if let spriteNode = component(ofType: SpriteComponent.self)?.spriteNode,
           let scene = spriteNode.scene {
            let flash = SKSpriteNode(color: .orange, size: CGSize(width: 14, height: 14))
            flash.position = spriteNode.position
            flash.zPosition = (scene as? InPlaySKScene)?.isNightWave == true ? Constants.NightWave.nightEffectZPosition : 50
            flash.alpha = 0.7
            scene.addChild(flash)
            let expand = SKAction.scale(to: 1.5, duration: 0.12)
            let fade = SKAction.fadeOut(withDuration: 0.12)
            flash.run(SKAction.sequence([SKAction.group([expand, fade]), SKAction.removeFromParent()]))
        }
        removeFromParent()
    }
}
