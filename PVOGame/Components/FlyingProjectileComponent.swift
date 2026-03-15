//
//  FlyingProjectileComponent.swift
//  PVOGame
//
//  Created by Frizer on 03.01.2023.
//

import UIKit
import GameplayKit
class FlyingProjectileComponent: GKAgent2D {
    init(speed: CGFloat, behavior: GKBehavior,position: vector_float2) {
        super.init()
        maxSpeed = Float(speed)
        self.speed = 0.00000001
        //mass = Float(self.entity?.component(ofType: SpriteComponent.self)?.spriteNode.physicsBody?.mass ?? 1)
        maxAcceleration = Float(speed)/2
        self.behavior = behavior
        radius = 4
        self.position = position
        
    }
    override func didAddToEntity() {
        super.didAddToEntity()
        if let entity = entity as? GKAgentDelegate{
            delegate = entity
        }
        if let spriteComponent = entity?.component(ofType: SpriteComponent.self){
            //position = vector_float2(x: Float(spriteComponent.spriteNode.position.x), y: Float(spriteComponent.spriteNode.position.y))
            spriteComponent.spriteNode.position = CGPoint(x: CGFloat(position.x), y: CGFloat(position.y))
        }
    }
    
    
    override func update(deltaTime seconds: TimeInterval) {
        let maxStep: TimeInterval = 1.0 / 60.0
        var remaining = seconds
        while remaining > maxStep {
            super.update(deltaTime: maxStep)
            remaining -= maxStep
        }
        if remaining > 0 {
            super.update(deltaTime: remaining)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
