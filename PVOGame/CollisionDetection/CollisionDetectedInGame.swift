//
//  CollisionDetectedInGame.swift
//  PVOGame
//
//  Created by Frizer on 13.03.2023.
//

import SpriteKit

class CollisionDetectedInGame: NSObject, SKPhysicsContactDelegate {
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

}
