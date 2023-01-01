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
    
    override func didMove(to view: SKView) {
        physicsBody = SKPhysicsBody(edgeLoopFrom: frame)
        backgroundColor = .white
        physicsWorld.contactDelegate = self
        physicsBody?.categoryBitMask = Constants.boundsBitMask
        physicsBody?.collisionBitMask = 0
        physicsBody?.isDynamic = false
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
        if let touch = touches.first{
            penultimateTap = lastTap
            lastTap = touch.location(in: self)
        }
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let touch = touches.first{
            penultimateTap = lastTap
            lastTap = touch.location(in: self)
        }
    }
    func didEnd(_ contact: SKPhysicsContact) {
        guard let nodeA = contact.bodyA.node else{ return}
        guard let nodeB = contact.bodyB.node else{ return}
        if nodeA.name == Constants.shellName{
            nodeA.removeFromParent()
        }
        if nodeB.name == Constants.shellName{
           nodeB.removeFromParent()
        }

    }
    override func touchesEstimatedPropertiesUpdated(_ touches: Set<UITouch>) {
        touchesBegan(touches, with: nil)
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let view = view
        else{
            return
        }
        lastTap = CGPoint(x: view.frame.width/2,y: view.frame.height)
        penultimateTap = lastTap
    }
    
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchesEnded(touches, with: event)
    }
    
    
    override func update(_ currentTime: TimeInterval) {
        // Called before each frame is rendered
        // Initialize _lastUpdateTime if it has not already been
        if (self.lastUpdateTime == 0) {
            self.lastUpdateTime = currentTime
        }
//        if abs(self.penultimateTap.x/sqrt(pow(penultimateTap.x,2) + pow(penultimateTap.y,2))
//               - self.lastTap.x/sqrt(pow(lastTap.x,2) + pow(lastTap.y,2))) < 0.01{
//            return
//        }
        // Calculate time since last update
        let dt = currentTime - self.lastUpdateTime
        if dt == 0{
            return
        }
        // Update entities
        for entity in self.entities {
            if lastTap.equalTo(CGPoint(x: 0.5,y: -1)){
                break
            }
            if let playerControlled = entity.component(ofType: PlayerControlComponent.self){
                playerControlled.newTap(deltaTime: dt, lastTap: lastTap)
            }
        }
        
        self.lastUpdateTime = currentTime
    }
    
}
