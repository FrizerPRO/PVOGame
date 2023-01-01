//
//  GunEntity.swift
//  PVOGame
//
//  Created by Frizer on 03.12.2022.
//

import UIKit
import GameplayKit
class GunEntity: GKEntity {
    let shootingSpeed: Int
    let shell: Shell
    
    private var timeSinceLastShot: TimeInterval = 0.0
    
    init(imageName: String, shell: Shell, shootingSpeed: Int){
        self.shell = shell
        self.shootingSpeed = shootingSpeed
        super.init()
        addComponent(SpriteComponent(imageName: imageName))
        if let component = component(ofType: SpriteComponent.self){
            self.addComponent(PlayerControlComponent(spriteComponent: component))
        }
    }
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    func shoot(deltaTime: TimeInterval){
        timeSinceLastShot += deltaTime
        guard timeSinceLastShot >= 60/CGFloat(shootingSpeed) else{
            return
        }
        if let shell = shell.copy() as? Shell{
            if let gunSprite = component(ofType: SpriteComponent.self){
                if let shellSprite = shell.component(ofType: SpriteComponent.self){
                    gunSprite.spriteNode.scene?.addChild(shellSprite.spriteNode)
                    shellSprite.setPosition(position: CGPoint(x: gunSprite.spriteNode.position.x +
                                                              gunSprite.spriteNode.frame.width * cos(gunSprite.spriteNode.zRotation + .pi/2),
                                                              y: gunSprite.spriteNode.position.y +
                                                              gunSprite.spriteNode.frame.height * sin(gunSprite.spriteNode.zRotation + .pi/2)))
                    shellSprite.spriteNode.zRotation = gunSprite.spriteNode.zRotation
                    if let shell = shell.component(ofType: ShootComponent.self){
                        shell.shoot(vector: CGVector(dx: cos(gunSprite.spriteNode.zRotation + .pi/2),
                                                     dy: sin(gunSprite.spriteNode.zRotation + .pi/2)))
                    }
                }
            }
        }
        timeSinceLastShot -= 60/CGFloat(shootingSpeed)
    }
}
