//
//  EWDroneEntity.swift
//  PVOGame
//

import Foundation
import GameplayKit
import SpriteKit

final class EWDroneEntity: AttackDroneEntity {

    private var targetPoint: CGPoint = .zero
    private var velocity: CGVector = .zero
    private var jammingRingNode: SKShapeNode?
    private var jammingPulseTimer: TimeInterval = 0

    let jamRadius: CGFloat = Constants.EW.ewDroneJamRadius

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
            damage: 0,
            speed: Constants.EW.ewDroneSpeed,
            imageName: "Drone",
            flyingPath: dummyPath
        )
        removeComponent(ofType: FlyingProjectileComponent.self)
        configureHealth(Constants.EW.ewDroneHealth)

        // Purple/magenta EW drone
        if let spriteNode = component(ofType: SpriteComponent.self)?.spriteNode {
            spriteNode.size = CGSize(width: Constants.SpriteSize.ewDrone, height: Constants.SpriteSize.ewDrone)
            if let tex = AnimationTextureCache.shared.droneTextures["drone_ew"] {
                spriteNode.texture = tex
                spriteNode.color = .white
                spriteNode.colorBlendFactor = 0
            } else {
                spriteNode.color = UIColor(red: 0.6, green: 0.2, blue: 0.8, alpha: 1)
                spriteNode.colorBlendFactor = 1.0
            }
        }

        addNavLights(wingspan: 20)
    }

    required init(damage: CGFloat, speed: CGFloat, imageName: String, flyingPath: FlyingPath) {
        super.init(damage: damage, speed: speed, imageName: imageName, flyingPath: flyingPath)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configureFlight(from spawnPoint: CGPoint, to target: CGPoint, speed ewSpeed: CGFloat) {
        self.targetPoint = target
        self.speed = ewSpeed

        if let spriteNode = component(ofType: SpriteComponent.self)?.spriteNode {
            spriteNode.position = spawnPoint
        }

        let dx = target.x - spawnPoint.x
        let dy = target.y - spawnPoint.y
        let dist = sqrt(dx * dx + dy * dy)
        guard dist > 0 else { return }

        let dirX = dx / dist
        let dirY = dy / dist
        velocity = CGVector(dx: dirX * ewSpeed, dy: dirY * ewSpeed)

        if let spriteNode = component(ofType: SpriteComponent.self)?.spriteNode {
            spriteNode.zRotation = atan2(dy, dx) - .pi / 2
        }
    }

    override func update(deltaTime seconds: TimeInterval) {
        guard !isHit else { return }
        guard let spriteNode = component(ofType: SpriteComponent.self)?.spriteNode else { return }

        spriteNode.position.x += velocity.dx * CGFloat(seconds)
        spriteNode.position.y += velocity.dy * CGFloat(seconds)

        // Jamming pulse visual
        jammingPulseTimer += seconds
        if jammingPulseTimer >= 1.5 {
            jammingPulseTimer = 0
            spawnJammingPulse(at: spriteNode)
        }
    }

    private func spawnJammingPulse(at spriteNode: SKSpriteNode) {
        guard let scene = spriteNode.scene else { return }

        let ring = SKShapeNode(circleOfRadius: 10)
        ring.strokeColor = UIColor.magenta.withAlphaComponent(0.6)
        ring.fillColor = .clear
        ring.lineWidth = 2.0
        ring.position = spriteNode.position
        ring.zPosition = (scene as? InPlaySKScene)?.isNightWave == true ? Constants.NightWave.nightEffectZPosition : (spriteNode.zPosition - 1)
        scene.addChild(ring)

        let expand = SKAction.scale(to: jamRadius / 10, duration: 0.8)
        expand.timingMode = .easeOut
        let fade = SKAction.fadeOut(withDuration: 0.8)
        ring.run(SKAction.sequence([
            SKAction.group([expand, fade]),
            SKAction.removeFromParent()
        ]))
    }

    /// Check if a tower at `towerPos` is within jamming range.
    func isJamming(towerAt towerPos: CGPoint) -> Bool {
        guard !isHit else { return false }
        guard let dronePos = component(ofType: SpriteComponent.self)?.spriteNode.position else { return false }
        let dx = dronePos.x - towerPos.x
        let dy = dronePos.y - towerPos.y
        return dx * dx + dy * dy <= jamRadius * jamRadius
    }

    override func didHit() {
        isHit = true
        jammingRingNode?.removeFromParent()

        let physicBody = component(ofType: GeometryComponent.self)?.geometryNode.physicsBody
        physicBody?.contactTestBitMask = 0
        physicBody?.categoryBitMask = 0

        if let spriteNode = component(ofType: SpriteComponent.self)?.spriteNode {
            let flash = SKSpriteNode(color: .magenta, size: CGSize(width: 28, height: 28))
            flash.position = spriteNode.position
            flash.zPosition = (spriteNode.scene as? InPlaySKScene)?.isNightWave == true ? Constants.NightWave.nightEffectZPosition : 55
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
        removeFromParent()
    }
}
