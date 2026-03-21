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
        // Rockets cannot hit micro-altitude drones (mine layers)
        if shell is RocketEntity,
           let drone = droneProjectile as? AttackDroneEntity,
           let alt = drone.component(ofType: AltitudeComponent.self),
           alt.altitude == .micro {
            return
        }
        // Non-rocket shells cannot hit ballistic-altitude targets
        if !(shell is RocketEntity),
           let drone = droneProjectile as? AttackDroneEntity,
           let alt = drone.component(ofType: AltitudeComponent.self),
           alt.altitude == .ballistic {
            return
        }
        droneProjectile.takeDamage(shell.damage)
        shell.detonateWithAnimation()
        if let drone = droneProjectile as? AttackDroneEntity, drone.isHit {
            gameScene?.onDroneDestroyed(drone: drone)
        }
    }

    private func handleBlastHitsDrone(nodeA: SKNode, nodeB: SKNode) -> Bool {
        if (nodeA.name == Self.rocketBlastNodeName || nodeA.name == Self.mineBombBlastNodeName),
           let drone = nodeB.entity as? AttackDroneEntity {
            if drone.isHit { return true }
            // Rocket blasts cannot hit micro-altitude drones
            if nodeA.name == Self.rocketBlastNodeName,
               let alt = drone.component(ofType: AltitudeComponent.self),
               alt.altitude == .micro { return true }
            // Rocket blasts cannot hit ballistic-altitude targets (each missile needs a direct hit)
            if nodeA.name == Self.rocketBlastNodeName,
               let alt = drone.component(ofType: AltitudeComponent.self),
               alt.altitude == .ballistic { return true }
            let blastDamage = (nodeA.userData?["damage"] as? Int) ?? 1
            drone.takeDamage(blastDamage)
            if drone.isHit {
                gameScene?.onDroneDestroyed(drone: drone)
            }
            return true
        }
        if (nodeB.name == Self.rocketBlastNodeName || nodeB.name == Self.mineBombBlastNodeName),
           let drone = nodeA.entity as? AttackDroneEntity {
            if drone.isHit { return true }
            // Rocket blasts cannot hit micro-altitude drones
            if nodeB.name == Self.rocketBlastNodeName,
               let alt = drone.component(ofType: AltitudeComponent.self),
               alt.altitude == .micro { return true }
            // Rocket blasts cannot hit ballistic-altitude targets (each missile needs a direct hit)
            if nodeB.name == Self.rocketBlastNodeName,
               let alt = drone.component(ofType: AltitudeComponent.self),
               alt.altitude == .ballistic { return true }
            let blastDamage = (nodeB.userData?["damage"] as? Int) ?? 1
            drone.takeDamage(blastDamage)
            if drone.isHit {
                gameScene?.onDroneDestroyed(drone: drone)
            }
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
        if let mine = nodeA.entity as? MineBombEntity,
           nodeB.name == Constants.groundName || nodeB.name == Constants.hqName {
            gameScene?.onMineReachedGround(mine)
            mine.reachedDestination()
            return true
        }
        if let mine = nodeB.entity as? MineBombEntity,
           nodeA.name == Constants.groundName || nodeA.name == Constants.hqName {
            gameScene?.onMineReachedGround(mine)
            mine.reachedDestination()
            return true
        }
        return false
    }

    private func handleBombHitsTower(nodeA: SKNode, nodeB: SKNode) -> Bool {
        if let mine = nodeA.entity as? MineBombEntity,
           nodeB.physicsBody?.categoryBitMask == Constants.towerBitMask {
            if let tower = findTowerForNode(nodeB) {
                // Skip towers that are not the intended target
                if let intended = mine.targetTower, intended !== tower { return false }
                gameScene?.onBombHitTower(mine, tower: tower)
            }
            return true
        }
        if let mine = nodeB.entity as? MineBombEntity,
           nodeA.physicsBody?.categoryBitMask == Constants.towerBitMask {
            if let tower = findTowerForNode(nodeA) {
                if let intended = mine.targetTower, intended !== tower { return false }
                gameScene?.onBombHitTower(mine, tower: tower)
            }
            return true
        }
        return false
    }

    private func findTowerForNode(_ node: SKNode) -> TowerEntity? {
        guard let scene = gameScene else { return nil }
        for entity in scene.entities {
            guard let tower = entity as? TowerEntity,
                  let spriteNode = tower.component(ofType: SpriteComponent.self)?.spriteNode,
                  spriteNode === node
            else { continue }
            return tower
        }
        return nil
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
            }
        }
        if let bullet = nodeB.entity as? Shell{
            if nodeA.name == Constants.backgroundName{
                if bullet is RocketEntity {
                    bullet.detonateWithAnimation()
                } else {
                    bullet.silentDetonate()
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
        if handleBombHitsTower(nodeA: nodeA, nodeB: nodeB) {
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
            if nodeB.name == Constants.groundName || nodeB.name == Constants.hqName {
                gameScene?.onDroneReachedHQ(drone: drone as? AttackDroneEntity)
                drone.reachedDestination()
            }
        }
        if let drone = nodeB.entity as? FlyingProjectile{
            if nodeA.name == Constants.groundName || nodeA.name == Constants.hqName {
                gameScene?.onDroneReachedHQ(drone: drone as? AttackDroneEntity)
                drone.reachedDestination()
            }
        }
    }

}
