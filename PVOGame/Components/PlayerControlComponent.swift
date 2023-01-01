//
//  PlayerControlComponent.swift
//  PVOGame
//
//  Created by Frizer on 02.12.2022.
//

import UIKit
import GameplayKit

class PlayerControlComponent: GKComponent {
    let spriteComponent: SpriteComponent
    init(spriteComponent: SpriteComponent){
        self.spriteComponent = spriteComponent
        super.init()
        spriteComponent.spriteNode.anchorPoint = CGPoint(x: 0.5, y: 0)
    }
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    func newTap(deltaTime: TimeInterval,lastTap: CGPoint){
        if let rotation = entity?.component(ofType: RotationComponent.self){
            rotation.rotate(tap: lastTap, deltaTime: deltaTime)
        }
        if let gun = entity as? GunEntity{
            gun.shoot(deltaTime: deltaTime)
        }
    }
    
}
