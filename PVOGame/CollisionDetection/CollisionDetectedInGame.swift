//
//  CollisionDetectedInGame.swift
//  PVOGame
//
//  Created by Frizer on 13.03.2023.
//

import SpriteKit

class CollisionDetectedInGame: NSObject, SKPhysicsContactDelegate {
    weak var gameScene: InPlaySKScene?
    private static let rocketBlastNodeName = "rocketBlastNode"
    private static let mineBombBlastNodeName = "mineBombBlastNode"

    private func handleShellHitsDrone(shell: Shell, droneProjectile: FlyingProjectile) {
        if let rocket = shell as? RocketEntity, !rocket.detonatesOnDirectImpact {
            return
        }
        if let drone = droneProjectile as? AttackDroneEntity, drone.isHit {
            shell.silentDetonate()
            return
        }
        droneProjectile.didHit()
        shell.detonateWithAnimation()
        gameScene?.onDroneDestroyed(drone: droneProjectile as? AttackDroneEntity)
    }

    private func handleBlastHitsDrone(nodeA: SKNode, nodeB: SKNode) -> Bool {
        if (nodeA.name == Self.rocketBlastNodeName || nodeA.name == Self.mineBombBlastNodeName),
           let drone = nodeB.entity as? AttackDroneEntity {
            if drone.isHit { return true }
            drone.didHit()
            gameScene?.onDroneDestroyed(drone: drone)
            return true
        }
        if (nodeB.name == Self.rocketBlastNodeName || nodeB.name == Self.mineBombBlastNodeName),
           let drone = nodeA.entity as? AttackDroneEntity {
            if drone.isHit { return true }
            drone.didHit()
            gameScene?.onDroneDestroyed(drone: drone)
            return true
        }
        return false
    }

    private func handleShellHitsMine(shell: Shell, mineBomb: MineBombEntity) {
        // Rockets and rocket blast are intentionally ineffective against mines.
        if shell is RocketEntity {
            return
        }
        // Crash-run bombs must not be shootable by player bullets.
        if mineBomb.isFromCrashedMineLayer {
            return
        }
        shell.silentDetonate()
        gameScene?.onMineShotInAir(mineBomb)
    }

    private func handleMineHitsGround(nodeA: SKNode, nodeB: SKNode) -> Bool {
        if let mine = nodeA.entity as? MineBombEntity, nodeB.name == Constants.groundName {
            gameScene?.onMineReachedGround(mine)
            mine.reachedDestination()
            return true
        }
        if let mine = nodeB.entity as? MineBombEntity, nodeA.name == Constants.groundName {
            gameScene?.onMineReachedGround(mine)
            mine.reachedDestination()
            return true
        }
        return false
    }

    private func handleMineHitsDrone(nodeA: SKNode, nodeB: SKNode) -> Bool {
        if let mine = nodeA.entity as? MineBombEntity,
           let drone = nodeB.entity as? AttackDroneEntity {
            guard mine.isFromCrashedMineLayer else { return false }
            guard mine.canHitDrone(drone) else { return true }
            gameScene?.onMineHitDrone(mine, drone: drone)
            return true
        }
        if let mine = nodeB.entity as? MineBombEntity,
           let drone = nodeA.entity as? AttackDroneEntity {
            guard mine.isFromCrashedMineLayer else { return false }
            guard mine.canHitDrone(drone) else { return true }
            gameScene?.onMineHitDrone(mine, drone: drone)
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
                if let rocket = bullet as? RocketEntity, !rocket.detonatesOnDirectImpact {
                    // AoE rockets may pass through drones without direct hit confirmation.
                } else {
                    drone.didHit()
                }
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
                if let rocket = bullet as? RocketEntity, !rocket.detonatesOnDirectImpact {
                    // AoE rockets may pass through drones without direct hit confirmation.
                } else {
                    drone.didHit()
                }
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
        if handleMineHitsGround(nodeA: nodeA, nodeB: nodeB) {
            return
        }
        if handleMineHitsDrone(nodeA: nodeA, nodeB: nodeB) {
            return
        }
        if let shell = nodeA.entity as? Shell,
           let mine = nodeB.entity as? MineBombEntity {
            handleShellHitsMine(shell: shell, mineBomb: mine)
            return
        }
        if let shell = nodeB.entity as? Shell,
           let mine = nodeA.entity as? MineBombEntity {
            handleShellHitsMine(shell: shell, mineBomb: mine)
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
