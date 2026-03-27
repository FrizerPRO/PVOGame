//
//  OrlanDroneEntity.swift
//  PVOGame
//
//  Orlan-10 — reconnaissance/spotter drone.
//  Does not attack. While alive: enemy missile salvos come faster.
//  Based on real Russian Orlan-10 UAV used for artillery correction.
//

import Foundation
import GameplayKit
import SpriteKit

final class OrlanDroneEntity: AttackDroneEntity {

    private var velocity: CGVector = .zero
    private var patrolPoints: [CGPoint] = []
    private var currentPatrolIndex = 0
    private let patrolSpeed: CGFloat = Constants.Orlan.speed

    required init(damage: CGFloat, speed: CGFloat, imageName: String, flyingPath: FlyingPath) {
        super.init(damage: damage, speed: speed, imageName: imageName, flyingPath: flyingPath)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Factory
    static func create(sceneFrame: CGRect) -> OrlanDroneEntity {
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
        let drone = OrlanDroneEntity(
            damage: 0,
            speed: Constants.Orlan.speed,
            imageName: "Drone",
            flyingPath: dummyPath
        )
        drone.removeComponent(ofType: FlyingProjectileComponent.self)
        drone.configureHealth(Constants.Orlan.health)

        // Distinct cyan/blue appearance — recon drone
        if let spriteNode = drone.component(ofType: SpriteComponent.self)?.spriteNode {
            spriteNode.size = CGSize(width: 20, height: 20)
            spriteNode.color = UIColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1)
            spriteNode.colorBlendFactor = 1.0
        }

        // Patrol points — figure-8 across the field
        let midY = sceneFrame.height * 0.6
        drone.patrolPoints = [
            CGPoint(x: sceneFrame.width * 0.25, y: midY + 40),
            CGPoint(x: sceneFrame.width * 0.75, y: midY - 20),
            CGPoint(x: sceneFrame.width * 0.75, y: midY + 40),
            CGPoint(x: sceneFrame.width * 0.25, y: midY - 20),
        ]

        return drone
    }

    func configureSpawn(at spawnPoint: CGPoint) {
        if let spriteNode = component(ofType: SpriteComponent.self)?.spriteNode {
            spriteNode.position = spawnPoint
        }
        // Start heading toward first patrol point
        updateVelocityToward(patrolPoints[0])
    }

    override func update(deltaTime seconds: TimeInterval) {
        guard !isHit else { return }
        guard let spriteNode = component(ofType: SpriteComponent.self)?.spriteNode else { return }

        spriteNode.position.x += velocity.dx * CGFloat(seconds)
        spriteNode.position.y += velocity.dy * CGFloat(seconds)

        // Check if reached current patrol point
        guard !patrolPoints.isEmpty else { return }
        let target = patrolPoints[currentPatrolIndex]
        let dx = target.x - spriteNode.position.x
        let dy = target.y - spriteNode.position.y
        if dx * dx + dy * dy < 25 * 25 {
            currentPatrolIndex = (currentPatrolIndex + 1) % patrolPoints.count
            updateVelocityToward(patrolPoints[currentPatrolIndex])
        }

        // Rotate to face direction
        spriteNode.zRotation = atan2(velocity.dy, velocity.dx) - .pi / 2
    }

    private func updateVelocityToward(_ point: CGPoint) {
        guard let spriteNode = component(ofType: SpriteComponent.self)?.spriteNode else { return }
        let dx = point.x - spriteNode.position.x
        let dy = point.y - spriteNode.position.y
        let dist = sqrt(dx * dx + dy * dy)
        guard dist > 0 else { return }
        velocity = CGVector(dx: dx / dist * patrolSpeed, dy: dy / dist * patrolSpeed)
    }

    override func didHit() {
        isHit = true
        let physicBody = component(ofType: GeometryComponent.self)?.geometryNode.physicsBody
        physicBody?.contactTestBitMask = 0
        physicBody?.categoryBitMask = 0

        if let spriteNode = component(ofType: SpriteComponent.self)?.spriteNode {
            let flash = SKSpriteNode(color: .cyan, size: CGSize(width: 20, height: 20))
            flash.position = spriteNode.position
            flash.zPosition = 55
            flash.alpha = 0.8
            spriteNode.scene?.addChild(flash)
            let expand = SKAction.scale(to: 2.0, duration: 0.2)
            let fade = SKAction.fadeOut(withDuration: 0.15)
            flash.run(SKAction.sequence([SKAction.group([expand, fade]), SKAction.removeFromParent()]))

            spriteNode.run(SKAction.sequence([
                SKAction.fadeOut(withDuration: 0.1),
                SKAction.run { [weak self] in self?.removeFromParent() }
            ]))
        }
    }

    override func reachedDestination() {
        // Orlan never reaches "destination" — it patrols until killed
    }
}
