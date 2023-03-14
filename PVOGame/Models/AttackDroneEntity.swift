//
//  AtackDrone.swift
//  PVOGame
//
//  Created by Frizer on 03.01.2023.
//

import Foundation
import GameplayKit
public class AttackDroneEntity: GKEntity, FlyingProjectile{
    public var flyingPath: FlyingPath
    
    public var damage: CGFloat
    
    public var speed: CGFloat
    
    public var imageName: String
    public var isHitted = false
    public required init(damage: CGFloat, speed: CGFloat, imageName: String, flyingPath: FlyingPath) {
        self.damage = damage
        self.speed = speed
        self.imageName = imageName
        self.flyingPath = flyingPath
        super.init()
        let spriteComponent = SpriteComponent(imageName: imageName);
        spriteComponent.spriteNode.size = CGSize(width: 30, height: 30)
        addComponent(spriteComponent)
        addComponent(setupGeometryComponent(spriteComponent: spriteComponent))
        addComponent(FlyingProjectileComponent(speed: speed, behavior: getBehavior(flyingPath: flyingPath),position: flyingPath.nodes.first ?? vector_float2()))

    }
    public func didHit(){
        isHitted = true
        component(ofType: FlyingProjectileComponent.self)?.behavior?.removeAllGoals()
        let physicBody = component(ofType: GeometryComponent.self)?.geometryNode.physicsBody
        physicBody?.affectedByGravity = true
        physicBody?.contactTestBitMask = Constants.boundsBitMask
    }
    public func reachedDestination(){
        removeFromParent()
    }
    public func removeFromParent(){
        guard let scene = component(ofType: SpriteComponent.self)?.spriteNode.scene as? InPlaySKScene
        else {return}
        scene.removeEntity(self)
    }
    public func getBehavior(flyingPath: FlyingPath)->GKBehavior{
//        guard let spriteNode = component(ofType: SpriteComponent.self)?.spriteNode
//        else{
//            return GKBehavior()
//        }
        
        //let path = GKPath(graphNodes: nodes, radius: Float(max(spriteNode.frame.width,spriteNode.frame.height)),cyclical: false)
        let path = GKPath(points: flyingPath.nodes, radius: 1/*Float(max(spriteNode.frame.width,spriteNode.frame.height))*/, cyclical: false)
        
        let goal = GKGoal(toFollow: path, maxPredictionTime: 100/speed * 1.5, forward: true)
        return GKBehavior(goal: goal, weight: 100000)
    }
    
    private func setupGeometryComponent(spriteComponent: SpriteComponent)->GeometryComponent{
        let geometryComponent = GeometryComponent(spriteNode: spriteComponent.spriteNode,
                                                  categoryBitMask: Constants.droneBitMask,
                                                  contactTestBitMask: Constants.bulletBitMask | Constants.groundBitMask,
                                                  collisionBitMask: 0)
        let physicsBody = geometryComponent.geometryNode.physicsBody
        physicsBody?.affectedByGravity = false
        return geometryComponent
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public func agentDidUpdate(_ agent: GKAgent) {
        guard let agent2d = agent as? GKAgent2D,
              let spriteNode = component(ofType: SpriteComponent.self)?.spriteNode,
              !isHitted
        else{
            return
        }
        spriteNode.position = CGPoint(x: CGFloat(agent2d.position.x), y: CGFloat(agent2d.position.y))
        spriteNode.zRotation = CGFloat(agent2d.rotation)
    }
    
}
