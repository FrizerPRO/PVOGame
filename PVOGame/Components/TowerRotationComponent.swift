//
//  TowerRotationComponent.swift
//  PVOGame
//

import GameplayKit
import SpriteKit

class TowerRotationComponent: GKComponent {
    private let rotationSpeed: CGFloat = .pi * 3
    private let returnSpeed: CGFloat = .pi * 1.5

    override init() {
        super.init()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func update(deltaTime seconds: TimeInterval) {
        guard let tower = entity as? TowerEntity,
              let stats = tower.component(ofType: TowerStatsComponent.self),
              stats.towerType.tracksTarget,
              !stats.isDisabled,
              let targeting = tower.component(ofType: TowerTargetingComponent.self),
              let spriteNode = tower.component(ofType: SpriteComponent.self)?.spriteNode
        else { return }

        let desiredAngle: CGFloat
        let speed: CGFloat

        if let target = targeting.currentTarget,
           let targetPos = target.component(ofType: SpriteComponent.self)?.spriteNode.position {
            let dx = targetPos.x - spriteNode.position.x
            let dy = targetPos.y - spriteNode.position.y
            desiredAngle = atan2(dy, dx) - .pi / 2
            speed = rotationSpeed
        } else {
            desiredAngle = 0
            speed = returnSpeed
        }

        var angleDiff = desiredAngle - spriteNode.zRotation
        while angleDiff > .pi { angleDiff -= 2 * .pi }
        while angleDiff < -.pi { angleDiff += 2 * .pi }

        let maxStep = speed * seconds
        let step = max(-maxStep, min(maxStep, angleDiff))
        spriteNode.zRotation += step
    }
}
