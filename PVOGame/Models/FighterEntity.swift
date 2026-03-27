//
//  FighterEntity.swift
//  PVOGame
//

import Foundation
import GameplayKit
import SpriteKit

/// Visual-only entity for the fighter jet fly-by ability.
final class FighterEntity: GKEntity {

    init(sceneFrame: CGRect) {
        super.init()

        let spriteComponent = SpriteComponent(imageName: "Bullet")
        let spriteNode = spriteComponent.spriteNode
        spriteNode.size = CGSize(width: 40, height: 20)
        spriteNode.color = UIColor(red: 0.5, green: 0.55, blue: 0.6, alpha: 1)
        spriteNode.colorBlendFactor = 1.0
        spriteNode.zRotation = .pi / 2  // Face right
        addComponent(spriteComponent)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
