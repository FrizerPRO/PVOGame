//
//  InPlayScene.swift
//  PVOGame
//
//  Created by Frizer on 04.12.2022.
//

import UIKit
import SpriteKit
import GameplayKit

class InPlaySKScene: SKScene, SKPhysicsContactDelegate {
    var entities = [GKEntity]()
    var graphs = [String : GKGraph]()
    var lastUpdateTime: TimeInterval = 0
    var lastTap = CGPoint(x: 0.5,y: -1)
    var penultimateTap = CGPoint(x: 0.5, y: -1)
    var background = SKSpriteNode()
    var isTouched = false
    var agent = GKAgent2D()

    fileprivate func setupBackground(_ view: SKView) {
        background = SKSpriteNode(color: .black, size: frame.size)
        background.name = Constants.backgroundName
        background.physicsBody = SKPhysicsBody(rectangleOf: frame.size)
        background.physicsBody?.categoryBitMask = Constants.boundsBitMask
        background.physicsBody?.collisionBitMask = 0
        background.physicsBody?.contactTestBitMask = 0
        background.physicsBody?.isDynamic = false
        background.position = CGPoint(x: view.frame.width/2, y: view.frame.height/2)
        addChild(background)
    }
    
    fileprivate func setupGround(_ view: SKView) {
        let ground = SKSpriteNode(color: .gray, size: CGSize(width: frame.width, height: frame.height/30))
        ground.name = Constants.groundName
        ground.physicsBody = SKPhysicsBody(rectangleOf: ground.frame.size)
        ground.physicsBody?.categoryBitMask = Constants.groundBitMask
        ground.physicsBody?.collisionBitMask = 0
        ground.physicsBody?.contactTestBitMask = 0
        ground.physicsBody?.isDynamic = false
        ground.position = CGPoint(x: 0, y: -background.frame.height/2 + ground.frame.height/2)
        background.addChild(ground)
    }
    
    override func didMove(to view: SKView) {
        super.didMove(to: view)
        backgroundColor = .white
        physicsWorld.contactDelegate = self
        setupBackground(view)
        setupGround(view)
    }
    public func addEntity(_ entity: GKEntity) {
        entities.append(entity)
        if let node = entity.component(ofType: SpriteComponent.self)?.spriteNode{
            addChild(node)
        }
    }
    public func removeEntity(_ entity: GKEntity) {
        if let node = entity.component(ofType: SpriteComponent.self)?.spriteNode{
            node.removeFromParent()
        }
        if let index = entities.firstIndex(of: entity){
            entities.remove(at: index)
        }
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        isTouched = true
        if let touch = touches.first{
            penultimateTap = lastTap
            lastTap = touch.location(in: self)
        }
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesMoved(touches, with: event)
        isTouched = true
        if let touch = touches.first{
            penultimateTap = lastTap
            lastTap = touch.location(in: self)
        }
    }
    func didEnd(_ contact: SKPhysicsContact) {
        guard let nodeA = contact.bodyA.node
        else {
            return
        }
        guard let nodeB = contact.bodyB.node
        else {
            return
        }
        if let bullet = nodeA.entity as? Shell{
            if nodeB.name == Constants.backgroundName{
                bullet.silentDetonate()
            } else if let drone = nodeB.entity as? FlyingProjectile{
                drone.didHit()
            }
        }
        if let bullet = nodeB.entity as? Shell{
            if nodeA.name == Constants.backgroundName{
                bullet.silentDetonate()
            } else if let drone = nodeA.entity as? FlyingProjectile{
                drone.didHit()
            }
        }
        if let drone = nodeA.entity as? FlyingProjectile{
            if nodeB.name == Constants.backgroundName{
                drone.removeFromParent()
            }
        }
        if let drone = nodeB.entity as? FlyingProjectile{
            if nodeA.name == Constants.backgroundName{
                drone.removeFromParent()
            }
        }
    }
    func didBegin(_ contact: SKPhysicsContact) {
        guard let nodeA = contact.bodyA.node
        else {
            return
        }
        guard let nodeB = contact.bodyB.node
        else {
            return
        }
        if let bullet = nodeA.entity as? Shell{
            if let drone = nodeB.entity as? FlyingProjectile{
                drone.didHit()
                bullet.detonateWithAnimation()
            }
        }
        if let bullet = nodeB.entity as? Shell{
            if let drone = nodeA.entity as? FlyingProjectile{
                drone.didHit()
                bullet.detonateWithAnimation()
            }
        }
        if let drone = nodeA.entity as? FlyingProjectile{
            if nodeB.name == Constants.groundName{
                drone.reachedDestination()
            }
        }
        if let drone = nodeB.entity as? FlyingProjectile{
            if nodeA.name == Constants.groundName{
                drone.reachedDestination()
            }
        }

    }
    override func touchesEstimatedPropertiesUpdated(_ touches: Set<UITouch>) {
        super.touchesEstimatedPropertiesUpdated(touches)
        touchesBegan(touches, with: nil)
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        isTouched = false
        guard let view = view
        else{
            return
        }
        lastTap = CGPoint(x: view.frame.width/2,y: view.frame.height)
        penultimateTap = lastTap
    }
    
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        touchesEnded(touches, with: event)
    }
    
    
    override func update(_ currentTime: TimeInterval) {
        super.update(currentTime)
        // Called before each frame is rendered
        // Initialize _lastUpdateTime if it has not already been
        if (self.lastUpdateTime == 0) {
            self.lastUpdateTime = currentTime
        }
        // Calculate time since last update
        let dt = currentTime - self.lastUpdateTime
        if dt == 0{
            return
        }
        for entity in self.entities {
            entity.update(deltaTime: dt)
            if lastTap.equalTo(CGPoint(x: 0.5,y: -1)){
                break
            }
            if let playerControlled = entity.component(ofType: PlayerControlComponent.self){
                playerControlled.changedFingerPosition(deltaTime: dt, lastTap: lastTap)
                if isTouched {
                    playerControlled.newTap(deltaTime: dt, lastTap: lastTap)
                }
            }
        }
        
        self.lastUpdateTime = currentTime
    }
    
}
