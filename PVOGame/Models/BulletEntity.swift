//
//  Bullet.swift
//  PVOGame
//
//  Created by Frizer on 02.12.2022.
//

import Foundation
import GameplayKit
class BulletEntity: GKEntity, Shell{
    var previousPosition = CGPoint(x: -1,y: -1)
    let startImpact: Int
    internal var damage: Int = 0
    let imageName: String
    
    required init(damage: Int,imageName: String) {
        self.damage = damage
        self.startImpact = 0
        self.imageName = imageName
        super.init()
        let spriteComponent = SpriteComponent(imageName: imageName);
        spriteComponent.spriteNode.size = CGSize(width: 7.0, height: 7.0)
        addComponent(spriteComponent)
        addComponent(ShootComponent())
        addComponent(GeometryComponent(spriteNode: spriteComponent.spriteNode,
                                       categoryBitMask: Constants.bulletBitMask,
                                       contactTestBitMask: Constants.boundsBitMask,
                                       collisionBitMask: 0))
    }
    
    init(damage: Int, startImpact: Int,imageName: String){
        self.damage = damage
        self.startImpact = startImpact
        self.imageName = imageName
        super.init()
        let spriteComponent = SpriteComponent(imageName: imageName);
        spriteComponent.spriteNode.size = CGSize(width: 2, height: 3)
        addComponent(spriteComponent)
        addComponent(ShootComponent())
        addComponent(GeometryComponent(spriteNode: spriteComponent.spriteNode,
                                       categoryBitMask: Constants.bulletBitMask,
                                       contactTestBitMask: Constants.boundsBitMask,
                                       collisionBitMask: 0))
    }
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    public func detonateWithAnimation(){
        silentDetonate()
    }
    public func silentDetonate(){
        if let scene = component(ofType: SpriteComponent.self)?.spriteNode.scene as? InPlaySKScene{
            scene.removeEntity(self)
        }
    }
    
    override func copy() -> Any {
        let result = BulletEntity(damage: damage, startImpact: startImpact, imageName:imageName)
        return result
    }
    fileprivate func autoDetonation() {
        if let position = component(ofType: SpriteComponent.self)?.spriteNode.position{
            if self.previousPosition.y - position.y > 0{
                detonateWithAnimation()
            } else if  self.previousPosition.y < position.y{
                self.previousPosition = position
            }
        }
    }
    
    override func update(deltaTime seconds: TimeInterval) {
        autoDetonation()
    }
    
}

