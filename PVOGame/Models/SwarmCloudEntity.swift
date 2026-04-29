//
//  SwarmCloudEntity.swift
//  PVOGame
//

import Foundation
import GameplayKit
import SpriteKit

/// A single drone within a swarm. Managed as a regular AttackDroneEntity in activeDrones.
final class SwarmDroneEntity: AttackDroneEntity {

    weak var swarmCloud: SwarmCloudEntity?
    var swarmOffset: CGPoint = .zero  // Offset from swarm center

    private var velocity: CGVector = .zero

    init(sceneFrame: CGRect, offset: CGPoint) {
        self.swarmOffset = offset
        let dummyPath = FlyingPath(
            topLevel: sceneFrame.height,
            bottomLevel: 0,
            leadingLevel: 0,
            trailingLevel: sceneFrame.width,
            startLevel: sceneFrame.height + 50,
            endLevel: 0,
            pathGenerator: { _ in
                [
                    vector_float2(x: Float(sceneFrame.midX), y: Float(sceneFrame.height + 50)),
                    vector_float2(x: Float(sceneFrame.midX), y: 0)
                ]
            }
        )
        super.init(
            damage: 1,
            speed: Constants.AdvancedEnemies.swarmSpeed,
            imageName: "Bullet",
            flyingPath: dummyPath
        )
        removeComponent(ofType: FlyingProjectileComponent.self)
        configureHealth(Constants.AdvancedEnemies.swarmDroneHealth)

        // Enable tower contact detection so swarm drones actually damage
        // gun/radar towers on impact (the collision handler deals the damage).
        if let geoNode = component(ofType: GeometryComponent.self)?.geometryNode {
            geoNode.physicsBody?.contactTestBitMask |= Constants.towerBitMask
        }

        // Tiny swarm micro-drone
        if let spriteNode = component(ofType: SpriteComponent.self)?.spriteNode {
            spriteNode.size = CGSize(width: Constants.SpriteSize.swarmUnit, height: Constants.SpriteSize.swarmUnit)
            if let tex = AnimationTextureCache.shared.droneTextures["drone_swarm"] {
                spriteNode.texture = tex
                spriteNode.color = .white
                spriteNode.colorBlendFactor = 0
            } else {
                spriteNode.color = UIColor(white: 0.4, alpha: 1)
                spriteNode.colorBlendFactor = 1.0
            }
        }

        addPropellerBuzz()
    }

    required init(damage: CGFloat, speed: CGFloat, imageName: String, flyingPath: FlyingPath) {
        super.init(damage: damage, speed: speed, imageName: imageName, flyingPath: flyingPath)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func update(deltaTime seconds: TimeInterval) {
        guard !isHit else { return }
        guard let spriteNode = component(ofType: SpriteComponent.self)?.spriteNode else { return }

        if let cloud = swarmCloud, !cloud.isDisorganized {
            // Follow swarm center + offset with oscillation
            let center = cloud.swarmCenter
            let targetPos = CGPoint(
                x: center.x + swarmOffset.x + CGFloat.random(in: -2...2),
                y: center.y + swarmOffset.y + CGFloat.random(in: -2...2)
            )
            let dx = targetPos.x - spriteNode.position.x
            let dy = targetPos.y - spriteNode.position.y
            let dist = sqrt(dx * dx + dy * dy)
            if dist > 1 {
                let moveSpeed = speed * 1.5
                spriteNode.position.x += (dx / dist) * moveSpeed * CGFloat(seconds)
                spriteNode.position.y += (dy / dist) * moveSpeed * CGFloat(seconds)
            }
        } else {
            // Disorganized: straight-line fan flight toward HQ
            spriteNode.position.x += velocity.dx * CGFloat(seconds)
            spriteNode.position.y += velocity.dy * CGFloat(seconds)
        }
    }

    func setInitialVelocity(_ vel: CGVector) {
        velocity = vel
    }

    override func didHit() {
        isHit = true
        swarmCloud?.onDroneLost()

        let physicBody = component(ofType: GeometryComponent.self)?.geometryNode.physicsBody
        physicBody?.contactTestBitMask = 0
        physicBody?.categoryBitMask = 0

        if let spriteNode = component(ofType: SpriteComponent.self)?.spriteNode {
            spriteNode.run(SKAction.sequence([
                SKAction.fadeOut(withDuration: 0.1),
                SKAction.run { [weak self] in self?.removeFromParent() }
            ]))
        }
    }

    override func reachedDestination() {
        guard !isHit else {
            removeFromParent()
            return
        }
        removeFromParent()
    }
}

/// Manages a swarm of micro drones with flocking behavior.
final class SwarmCloudEntity {

    let swarmDrones: [SwarmDroneEntity]
    private(set) var swarmCenter: CGPoint
    private(set) var targetPoint: CGPoint
    private weak var targetTower: TowerEntity?
    /// Called when the current target tower is destroyed — should return the
    /// next combat tower (NEVER an oil refinery) or `nil` to fall back to HQ.
    var retargetProvider: ((CGPoint) -> TowerEntity?)?
    /// Fallback target (HQ) when no combat towers remain.
    var fallbackPoint: CGPoint = .zero
    private var speed: CGFloat
    private(set) var isDisorganized = false
    private var initialDroneCount: Int
    private var oscillationTimer: TimeInterval = 0
    private var retargetCheckTimer: TimeInterval = 0

    init(sceneFrame: CGRect, spawnCenter: CGPoint, target: CGPoint) {
        self.swarmCenter = spawnCenter
        self.targetPoint = target
        self.speed = Constants.AdvancedEnemies.swarmSpeed

        let count = Constants.AdvancedEnemies.swarmDroneCount
        self.initialDroneCount = count

        var drones = [SwarmDroneEntity]()
        for _ in 0..<count {
            let offset = CGPoint(
                x: CGFloat.random(in: -Constants.AdvancedEnemies.swarmSeparation...Constants.AdvancedEnemies.swarmSeparation),
                y: CGFloat.random(in: -Constants.AdvancedEnemies.swarmSeparation...Constants.AdvancedEnemies.swarmSeparation)
            )
            let drone = SwarmDroneEntity(sceneFrame: sceneFrame, offset: offset)
            if let spriteNode = drone.component(ofType: SpriteComponent.self)?.spriteNode {
                spriteNode.position = CGPoint(x: spawnCenter.x + offset.x, y: spawnCenter.y + offset.y)
                spriteNode.zPosition = 61 + CGFloat(DroneAltitude.micro.rawValue) * 5
            }

            // Set initial velocity toward target
            let dx = target.x - spawnCenter.x
            let dy = target.y - spawnCenter.y
            let dist = sqrt(dx * dx + dy * dy)
            if dist > 0 {
                drone.setInitialVelocity(CGVector(
                    dx: (dx / dist) * speed + CGFloat.random(in: -5...5),
                    dy: (dy / dist) * speed + CGFloat.random(in: -5...5)
                ))
            }

            drones.append(drone)
        }

        self.swarmDrones = drones
        for drone in drones {
            drone.swarmCloud = self
        }
    }

    /// Set the primary target tower. The swarm will track its position and
    /// retarget to the nearest remaining combat tower if this one is destroyed.
    func setTargetTower(_ tower: TowerEntity) {
        self.targetTower = tower
        self.targetPoint = tower.worldPosition
    }

    /// Immediately pick the next combat tower (called from the collision
    /// handler the moment one drone destroys the current target — every
    /// surviving drone instantly heads for the next priority target instead
    /// of wasting itself on an already-dead one).
    func forceRetargetAfterKill() {
        retargetCheckTimer = 0
        if let next = retargetProvider?(swarmCenter) {
            targetTower = next
            targetPoint = next.worldPosition
        } else {
            targetTower = nil
            targetPoint = fallbackPoint
        }
    }

    func update(deltaTime seconds: TimeInterval) {
        guard !isDisorganized else { return }

        // Retarget every ~0.8s: if the current tower is dead/disabled, try to
        // find another combat tower; otherwise, fall back to the HQ point.
        retargetCheckTimer += seconds
        if retargetCheckTimer >= 0.8 {
            retargetCheckTimer = 0
            let towerGone = targetTower == nil || (targetTower?.stats?.isDisabled ?? true)
            if towerGone {
                if let next = retargetProvider?(swarmCenter) {
                    targetTower = next
                    targetPoint = next.worldPosition
                } else {
                    targetTower = nil
                    targetPoint = fallbackPoint
                }
            } else if let tower = targetTower {
                // Track the tower's current position (usually static, but cheap to sync).
                targetPoint = tower.worldPosition
            }
        }

        // Move swarm center toward target
        let dx = targetPoint.x - swarmCenter.x
        let dy = targetPoint.y - swarmCenter.y
        let dist = sqrt(dx * dx + dy * dy)
        guard dist > 0 else { return }

        let dirX = dx / dist
        let dirY = dy / dist
        swarmCenter.x += dirX * speed * CGFloat(seconds)
        swarmCenter.y += dirY * speed * CGFloat(seconds)

        // Oscillation (breathing effect)
        oscillationTimer += seconds
        let breath = sin(oscillationTimer * 3) * 3
        for drone in swarmDrones where !drone.isHit {
            drone.swarmOffset = CGPoint(
                x: drone.swarmOffset.x + CGFloat.random(in: -0.5...0.5),
                y: drone.swarmOffset.y + CGFloat(breath) * 0.1
            )
        }
    }

    func onDroneLost() {
        let alive = swarmDrones.filter { !$0.isHit }
        guard alive.count <= initialDroneCount / 2, !isDisorganized else { return }
        isDisorganized = true

        let disorgSpeed = Constants.AdvancedEnemies.swarmDisorganizedSpeed

        for drone in alive {
            guard let pos = drone.component(ofType: SpriteComponent.self)?.spriteNode.position else { continue }
            // Each surviving drone picks its OWN nearest combat tower — swarms
            // never target the oil refinery.
            let perDroneTarget = retargetProvider?(pos)?.worldPosition ?? fallbackPoint
            let dx = perDroneTarget.x - pos.x
            let dy = perDroneTarget.y - pos.y
            let dist = sqrt(dx * dx + dy * dy)
            guard dist > 0 else { continue }
            drone.setInitialVelocity(CGVector(
                dx: (dx / dist) * disorgSpeed,
                dy: (dy / dist) * disorgSpeed
            ))
        }
    }
}
