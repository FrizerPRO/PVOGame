//
//  GunEntity.swift
//  PVOGame
//
//  Created by Frizer on 03.12.2022.
//

import UIKit
import GameplayKit
class GunEntity: GKEntity {
    var shootingSpeed: Int
    var shell: Shell
    var rotateSpeed: CGFloat
    var label: String
    var imageName: String
    private var timeSinceLastShot: TimeInterval = 0.0
    
    init(imageName: String, shell: Shell, shootingSpeed: Int,rotateSpeed: CGFloat, label: String){
        self.shell = shell
        self.shootingSpeed = shootingSpeed
        self.rotateSpeed = rotateSpeed
        self.label = label
        self.imageName = imageName
        super.init()
        addComponent(SpriteComponent(imageName: imageName))
        if let component = component(ofType: SpriteComponent.self){
            self.addComponent(PlayerControlComponent(spriteComponent: component))
        }
    }
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    func copyFrom(gun: GunEntity){
        self.shootingSpeed = gun.shootingSpeed
        self.shell = gun.shell
        self.rotateSpeed = gun.rotateSpeed
        self.label = gun.label
        self.imageName = gun.imageName

        timeSinceLastShot = 0
        if let component = component(ofType: SpriteComponent.self){
            component.spriteNode.texture = .init(imageNamed: imageName)
        }
    }
    func shoot(deltaTime: TimeInterval){
        timeSinceLastShot += deltaTime
        guard timeSinceLastShot >= 60/CGFloat(shootingSpeed) else{
            return
        }
        let newShell: Shell
        if let bulletTemplate = shell as? BulletEntity,
           let scene = component(ofType: SpriteComponent.self)?.spriteNode.scene as? InPlaySKScene,
           let pooled = scene.dequeueBullet(matching: bulletTemplate) {
            newShell = pooled
        } else if let copied = shell.copy() as? Shell {
            newShell = copied
        } else {
            timeSinceLastShot -= 60/CGFloat(shootingSpeed)
            return
        }
        if let gunSprite = component(ofType: SpriteComponent.self){
            if let shellSprite = newShell.component(ofType: SpriteComponent.self){
                if let scene = gunSprite.spriteNode.scene as? InPlaySKScene{
                    scene.addEntity(newShell)
                }
                let randHeight = Int.random(in: 0...30)

                shellSprite.setPosition(position: CGPoint(x: gunSprite.spriteNode.position.x + (CGFloat(randHeight) +
                                                          gunSprite.spriteNode.frame.width) * cos(gunSprite.spriteNode.zRotation + .pi/2),
                                                          y: gunSprite.spriteNode.position.y + (CGFloat(randHeight) +
                                                          gunSprite.spriteNode.frame.height) * sin(gunSprite.spriteNode.zRotation + .pi/2)))
                shellSprite.spriteNode.zRotation = gunSprite.spriteNode.zRotation
                if let shootComp = newShell.component(ofType: ShootComponent.self){
                    shootComp.shoot(vector: CGVector(dx: cos(gunSprite.spriteNode.zRotation + .pi/2),
                                                 dy: sin(gunSprite.spriteNode.zRotation + .pi/2)))
                }
            }
        }
        timeSinceLastShot -= 60/CGFloat(shootingSpeed)
    }
}
