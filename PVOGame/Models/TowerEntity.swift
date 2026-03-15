//
//  TowerEntity.swift
//  PVOGame
//

import UIKit
import GameplayKit
import SpriteKit

class TowerEntity: GKEntity {
    let towerType: TowerType
    private var timeSinceLastShot: TimeInterval = 0
    private(set) var currentTarget: AttackDroneEntity?
    private var rangeIndicator: SKShapeNode?
    private var wasDisabled = false
    private var smokeEmitter: SKNode?

    init(towerType: TowerType, at gridPosition: (row: Int, col: Int), worldPosition: CGPoint) {
        self.towerType = towerType
        super.init()

        let size: CGFloat = 28
        let spriteComponent = SpriteComponent(color: towerType.color, size: CGSize(width: size, height: size))
        spriteComponent.spriteNode.position = worldPosition
        spriteComponent.spriteNode.zPosition = 25
        addComponent(spriteComponent)

        // Physics body for bomb collision detection
        let body = SKPhysicsBody(rectangleOf: CGSize(width: size, height: size))
        body.categoryBitMask = Constants.towerBitMask
        body.contactTestBitMask = Constants.mineBombBitMask
        body.collisionBitMask = 0
        body.isDynamic = false
        spriteComponent.spriteNode.physicsBody = body

        addComponent(GridPositionComponent(row: gridPosition.row, col: gridPosition.col))

        addComponent(TowerStatsComponent(
            towerType: towerType,
            range: towerType.baseRange,
            fireRate: towerType.baseFireRate,
            damage: towerType.baseDamage,
            reachableAltitudes: towerType.reachableAltitudes,
            cost: towerType.cost
        ))

        addComponent(TowerTargetingComponent())
        addComponent(TowerRotationComponent())
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var stats: TowerStatsComponent? {
        component(ofType: TowerStatsComponent.self)
    }

    var worldPosition: CGPoint {
        component(ofType: SpriteComponent.self)?.spriteNode.position ?? .zero
    }

    func showRangeIndicator() {
        guard let spriteNode = component(ofType: SpriteComponent.self)?.spriteNode,
              let range = stats?.range,
              rangeIndicator == nil else { return }
        let circle = SKShapeNode(circleOfRadius: range)
        circle.strokeColor = towerType.color.withAlphaComponent(0.4)
        circle.fillColor = towerType.color.withAlphaComponent(0.08)
        circle.lineWidth = 1.5
        circle.zPosition = 22
        circle.position = .zero
        let pattern: [CGFloat] = [6, 4]
        if let originalPath = circle.path {
            let dashed = originalPath.copy(dashingWithPhase: 0, lengths: pattern)
            circle.path = dashed
        }
        spriteNode.addChild(circle)
        rangeIndicator = circle
    }

    func hideRangeIndicator() {
        rangeIndicator?.removeFromParent()
        rangeIndicator = nil
    }

    // MARK: - Durability

    func takeBombDamage(_ amount: Int) {
        guard let stats else { return }
        stats.takeBombDamage(amount)
        if stats.isDisabled {
            showDisabledEffect()
        }
    }

    func fullRepair() {
        guard let stats else { return }
        let wasDamaged = stats.isDisabled
        stats.fullRepair()
        if wasDamaged {
            hideDisabledEffect()
            wasDisabled = false
        }
    }

    private func showDisabledEffect() {
        guard let spriteNode = component(ofType: SpriteComponent.self)?.spriteNode else { return }
        spriteNode.colorBlendFactor = 0.7
        spriteNode.color = .darkGray

        if smokeEmitter == nil {
            let smoke = SKNode()
            smoke.name = "towerSmoke"
            let smokeAction = SKAction.repeatForever(SKAction.sequence([
                SKAction.run { [weak spriteNode, weak smoke] in
                    guard spriteNode != nil, let smoke else { return }
                    let puff = SKSpriteNode(color: UIColor.gray.withAlphaComponent(0.5), size: CGSize(width: 8, height: 8))
                    puff.position = CGPoint(
                        x: CGFloat.random(in: -6...6),
                        y: CGFloat.random(in: -2...4)
                    )
                    puff.zPosition = 30
                    smoke.addChild(puff)
                    let rise = SKAction.moveBy(x: CGFloat.random(in: -4...4), y: 18, duration: 0.8)
                    let fade = SKAction.fadeOut(withDuration: 0.8)
                    puff.run(SKAction.sequence([SKAction.group([rise, fade]), SKAction.removeFromParent()]))
                },
                SKAction.wait(forDuration: 0.25)
            ]))
            smoke.run(smokeAction, withKey: "smokeLoop")
            spriteNode.addChild(smoke)
            smokeEmitter = smoke
        }
        wasDisabled = true
    }

    private func hideDisabledEffect() {
        guard let spriteNode = component(ofType: SpriteComponent.self)?.spriteNode else { return }

        smokeEmitter?.removeAllActions()
        smokeEmitter?.removeFromParent()
        smokeEmitter = nil

        // Repair flash: white → original color
        let originalColor = towerType.color
        spriteNode.color = .white
        spriteNode.colorBlendFactor = 0
        let flash = SKAction.sequence([
            SKAction.wait(forDuration: 0.15),
            SKAction.run { [weak spriteNode] in
                spriteNode?.color = originalColor
                spriteNode?.colorBlendFactor = 0
            }
        ])
        spriteNode.run(flash)
    }

    override func update(deltaTime seconds: TimeInterval) {
        super.update(deltaTime: seconds)
        guard let stats else { return }
        let wasDisabledBefore = stats.isDisabled
        stats.updateRepair(deltaTime: seconds)
        if wasDisabledBefore && !stats.isDisabled {
            hideDisabledEffect()
            wasDisabled = false
        }
    }
}
