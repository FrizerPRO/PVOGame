//
//  Bullet.swift
//  PVOGame
//
//  Created by Frizer on 02.12.2022.
//

import Foundation
import GameplayKit
class BulletEntity: GKEntity, Shell{
    let startImpact: Int
    internal var damage: Int = 0
    let imageName: String
    
    required init(damage: Int,imageName: String) {
        self.damage = damage
        self.startImpact = 0
        self.imageName = imageName
        super.init()
        let spriteComponent = SpriteComponent(imageName: imageName);
        spriteComponent.spriteNode.size = CGSize(width: 70.0, height: 70.0)
        addComponent(spriteComponent)
        addComponent(ShootComponent())
        addComponent(getGeometryComponent(spriteComponent: spriteComponent))
    }
    
    init(damage: Int, startImpact: Int,imageName: String){
        self.damage = damage
        self.startImpact = startImpact
        self.imageName = imageName
        super.init()
        let spriteComponent = SpriteComponent(imageName: imageName);
        spriteComponent.spriteNode.size = CGSize(width: 70.0, height: 70.0)
        addComponent(spriteComponent)
        addComponent(ShootComponent())
        addComponent(getGeometryComponent(spriteComponent: spriteComponent))
    }
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func copy() -> Any {
        let result = BulletEntity(damage: damage, startImpact: startImpact, imageName:imageName)
        return result
    }
    private func getGeometryComponent(spriteComponent: SpriteComponent)->GKComponent{
        let geometryComponent = GeometryComponent(geometryNode: spriteComponent.spriteNode)
        geometryComponent.geometryNode.physicsBody?.categoryBitMask = Constants.bulletBitMask
        geometryComponent.geometryNode.physicsBody?.collisionBitMask = 0
        geometryComponent.geometryNode.name = Constants.shellName
        return geometryComponent;
    }
}
