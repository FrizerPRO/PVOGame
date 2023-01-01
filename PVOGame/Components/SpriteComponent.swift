//
//  SpriteComponent.swift
//  PVOGame
//
//  Created by Frizer on 03.12.2022.
//

import UIKit
import GameplayKit
class SpriteComponent: GKComponent {
    let spriteNode: SKSpriteNode;
    init(imageName: String){
        spriteNode = SKSpriteNode(imageNamed: imageName)
        super.init()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    func rotate(angle: CGFloat){
        spriteNode.zRotation += angle
    }
    func setPosition(position: CGPoint){
        spriteNode.position = position
    }
}
