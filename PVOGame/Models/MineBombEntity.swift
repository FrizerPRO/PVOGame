//
//  MineBombEntity.swift
//  PVOGame
//
//  Extracted from BulletEntity.swift
//

import Foundation
import GameplayKit

final class MineBombEntity: GKEntity {
    private(set) var isFromCrashedMineLayer = false
    private weak var sourceDrone: AttackDroneEntity?
    weak var targetTower: TowerEntity?

    override init() {
        super.init()
        let spriteComponent = SpriteComponent(imageName: "Bullet")
        spriteComponent.spriteNode.size = CGSize(width: 12, height: 12)
        addComponent(spriteComponent)
        addComponent(
            GeometryComponent(
                spriteNode: spriteComponent.spriteNode,
                categoryBitMask: Constants.mineBombBitMask,
                contactTestBitMask: Constants.bulletBitMask | Constants.groundBitMask,
                collisionBitMask: 0
            )
        )
        if let body = spriteComponent.spriteNode.physicsBody {
            body.affectedByGravity = true
            body.linearDamping = 0
            body.angularDamping = 0
            body.allowsRotation = true
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func place(at position: CGPoint) {
        guard let spriteNode = component(ofType: SpriteComponent.self)?.spriteNode else { return }
        spriteNode.position = position
        spriteNode.zRotation = 0
        if let body = spriteNode.physicsBody {
            body.velocity = .zero
            body.angularVelocity = 0
            body.isResting = false
        }
    }

    func configureOrigin(
        isFromCrashedDrone: Bool,
        sourceDrone: AttackDroneEntity? = nil
    ) {
        isFromCrashedMineLayer = isFromCrashedDrone
        self.sourceDrone = sourceDrone
        if let body = component(ofType: GeometryComponent.self)?.geometryNode.physicsBody {
            var contactMask = Constants.groundBitMask
            if !isFromCrashedDrone {
                contactMask |= Constants.bulletBitMask
            }
            if isFromCrashedDrone {
                contactMask |= Constants.droneBitMask
            }
            body.contactTestBitMask = contactMask
        }
    }

    func configureOrigin(isFromCrashedDrone: Bool) {
        configureOrigin(isFromCrashedDrone: isFromCrashedDrone, sourceDrone: nil)
    }

    func canHitDrone(_ drone: AttackDroneEntity) -> Bool {
        !(isFromCrashedMineLayer && sourceDrone === drone)
    }

    func silentDetonate() {
        if let scene = component(ofType: SpriteComponent.self)?.spriteNode.scene as? InPlaySKScene {
            scene.removeEntity(self)
        }
    }

    func reachedDestination() {
        silentDetonate()
    }

    func configureForTDBombing(target: TowerEntity? = nil) {
        guard let spriteNode = component(ofType: SpriteComponent.self)?.spriteNode,
              let body = spriteNode.physicsBody else { return }

        // Visual: bomb sized like a drone, between drone (z61+) and tower (z25)
        spriteNode.size = CGSize(width: 40, height: 40)
        spriteNode.zPosition = 45

        // Physics: bomb stays in place (no Y velocity), but bullets can still shoot it down
        body.affectedByGravity = false
        body.velocity = .zero
        // No towerBitMask — damage delivered via animation callback, not physics contact

        targetTower = target

        // Fall animation: bomb shrinks (simulates falling away from camera toward ground)
        let fallDuration: TimeInterval = 0.45
        let scaleDown = SKAction.scale(to: 0.3, duration: fallDuration)
        scaleDown.timingMode = .easeIn
        spriteNode.run(SKAction.sequence([
            scaleDown,
            SKAction.run { [weak self] in
                guard let self else { return }
                if let target = self.targetTower,
                   let scene = spriteNode.scene as? InPlaySKScene {
                    scene.onBombHitTower(self, tower: target)
                } else {
                    self.silentDetonate()
                }
            }
        ]))
    }
}
