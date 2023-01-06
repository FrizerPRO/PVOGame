//
//  InPlayScene.swift
//  PVOGame
//
//  Created by Frizer on 03.12.2022.
//

import UIKit
import GameplayKit

class InPlayGKScene:GKScene {
    
    init(scene: SKScene){
        super.init()
        self.rootNode = scene
    }
    public override func addEntity(_ entity: GKEntity) {
        super.addEntity(entity)
        if let node = entity.component(ofType: SpriteComponent.self)?.spriteNode{
            if let rootNode = self.rootNode as? SKScene {
                rootNode.addChild(node)
            }
        }
    }
    public override func removeEntity(_ entity: GKEntity) {
        if let node = entity.component(ofType: SpriteComponent.self)?.spriteNode{
            node.removeFromParent()
        }
        super.removeEntity(entity)
    }
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
