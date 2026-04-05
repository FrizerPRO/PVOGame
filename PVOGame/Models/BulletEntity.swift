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
    func reset() {
        previousPosition = CGPoint(x: -1, y: -1)
        if let spriteNode = component(ofType: SpriteComponent.self)?.spriteNode {
            spriteNode.removeAllActions()
            spriteNode.alpha = 1; spriteNode.xScale = 1; spriteNode.yScale = 1
            spriteNode.zRotation = 0; spriteNode.position = .zero
            spriteNode.physicsBody?.velocity = .zero
            spriteNode.physicsBody?.angularVelocity = 0
        }
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
        guard let position = component(ofType: SpriteComponent.self)?.spriteNode.position else { return }
        if previousPosition.x < -0.5 && previousPosition.y < -0.5 {
            previousPosition = position
            return
        }
        let dx = position.x - previousPosition.x
        let dy = position.y - previousPosition.y
        let distSq = dx * dx + dy * dy
        if distSq < 0.25 && previousPosition.x >= 0 {
            detonateWithAnimation()
            return
        }
        previousPosition = position
        // Range-based detonation: check if out of scene bounds
        if let scene = component(ofType: SpriteComponent.self)?.spriteNode.scene {
            let margin: CGFloat = 50
            if position.x < -margin || position.x > scene.frame.width + margin ||
               position.y < -margin || position.y > scene.frame.height + margin {
                silentDetonate()
            }
        }
    }
    
    override func update(deltaTime seconds: TimeInterval) {
        autoDetonation()
    }
    
}
