//
//  CollisionDetectedInGame.swift
//  PVOGame
//
//  Created by Frizer on 13.03.2023.
//

import SpriteKit

class CollisionDetectedInGame: NSObject, SKPhysicsContactDelegate {
    weak var gameScene: InPlaySKScene?

    private func handleShellHitsDrone(shell: Shell, droneProjectile: FlyingProjectile) {
        if let drone = droneProjectile as? AttackDroneEntity, drone.isHit {
            shell.silentDetonate()
            return
        }
        droneProjectile.didHit()
        shell.detonateWithAnimation()
        gameScene?.onDroneDestroyed(drone: droneProjectile as? AttackDroneEntity)
    }

    private func handleBlastHitsDrone(nodeA: SKNode, nodeB: SKNode) -> Bool {
        if nodeA.name == "rocketBlastNode",
           let drone = nodeB.entity as? AttackDroneEntity {
            if drone.isHit { return true }
            drone.didHit()
            gameScene?.onDroneDestroyed(drone: drone)
            return true
        }
        if nodeB.name == "rocketBlastNode",
           let drone = nodeA.entity as? AttackDroneEntity {
            if drone.isHit { return true }
            drone.didHit()
            gameScene?.onDroneDestroyed(drone: drone)
            return true
        }
        return false
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
                if bullet is RocketEntity {
                    bullet.detonateWithAnimation()
                } else {
                    bullet.silentDetonate()
                }
            } else if let drone = nodeB.entity as? FlyingProjectile{
                drone.didHit()
            }
        }
        if let bullet = nodeB.entity as? Shell{
            if nodeA.name == Constants.backgroundName{
                if bullet is RocketEntity {
                    bullet.detonateWithAnimation()
                } else {
                    bullet.silentDetonate()
                }
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
        if handleBlastHitsDrone(nodeA: nodeA, nodeB: nodeB) {
            return
        }
        if let bullet = nodeA.entity as? Shell{
            if let drone = nodeB.entity as? FlyingProjectile{
                handleShellHitsDrone(shell: bullet, droneProjectile: drone)
            }
        }
        if let bullet = nodeB.entity as? Shell{
            if let drone = nodeA.entity as? FlyingProjectile{
                handleShellHitsDrone(shell: bullet, droneProjectile: drone)
            }
        }
        if let drone = nodeA.entity as? FlyingProjectile{
            if nodeB.name == Constants.groundName{
                gameScene?.onDroneReachedGround(drone: drone as? AttackDroneEntity)
                drone.reachedDestination()
            }
        }
        if let drone = nodeB.entity as? FlyingProjectile{
            if nodeA.name == Constants.groundName{
                gameScene?.onDroneReachedGround(drone: drone as? AttackDroneEntity)
                drone.reachedDestination()
            }
        }
    }

}
