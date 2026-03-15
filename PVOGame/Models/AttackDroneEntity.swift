//
//  AtackDrone.swift
//  PVOGame
//
//  Created by Frizer on 03.01.2023.
//

import Foundation
import GameplayKit

protocol MineLayerDroneDelegate: AnyObject {
    func mineLayer(
        _ mineLayer: MineLayerDroneEntity,
        spawnBombAt position: CGPoint,
        isFromCrashedDrone: Bool
    )
    func mineLayerDidExitForRearm(_ mineLayer: MineLayerDroneEntity)
}

public class AttackDroneEntity: GKEntity, FlyingProjectile{
    public var flyingPath: FlyingPath

    public var damage: CGFloat

    public var speed: CGFloat

    public var imageName: String
    public var isHit = false

    public var health: Int
    public var maxHealth: Int

    private var hpBarBackground: SKSpriteNode?
    private var hpBarFill: SKSpriteNode?
    private var hpBarContainer: SKNode?

    public required init(damage: CGFloat, speed: CGFloat, imageName: String, flyingPath: FlyingPath) {
        self.health = 1
        self.maxHealth = 1
        self.damage = damage
        self.speed = speed
        self.imageName = imageName
        self.flyingPath = flyingPath
        super.init()
        let spriteComponent = SpriteComponent(imageName: imageName);
        spriteComponent.spriteNode.size = CGSize(width: 30, height: 30)
        addComponent(spriteComponent)
        addComponent(setupGeometryComponent(spriteComponent: spriteComponent))
        addComponent(FlyingProjectileComponent(speed: speed, behavior: behavior(for: flyingPath),position: flyingPath.nodes.first ?? vector_float2()))
        setupHPBar(on: spriteComponent.spriteNode)
    }

    func configureHealth(_ hp: Int) {
        self.health = hp
        self.maxHealth = hp
        hpBarContainer?.isHidden = true
        updateHPBar()
    }

    public func takeDamage(_ amount: Int) {
        guard !isHit else { return }
        health = max(0, health - amount)
        if health <= 0 {
            didHit()
        } else {
            // Red flash on hit
            if let spriteNode = component(ofType: SpriteComponent.self)?.spriteNode {
                let colorize = SKAction.colorize(with: .red, colorBlendFactor: 0.8, duration: 0.05)
                let revert = SKAction.colorize(withColorBlendFactor: 0, duration: 0.1)
                spriteNode.run(SKAction.sequence([colorize, revert]))
            }
        }
        updateHPBar()
    }

    private func setupHPBar(on spriteNode: SKSpriteNode) {
        let container = SKNode()
        container.zPosition = 10
        container.position = CGPoint(x: 0, y: spriteNode.size.height / 2 + 4)
        container.isHidden = true

        let barWidth: CGFloat = 24
        let barHeight: CGFloat = 3

        let bg = SKSpriteNode(color: UIColor.black.withAlphaComponent(0.6), size: CGSize(width: barWidth, height: barHeight))
        bg.anchorPoint = CGPoint(x: 0, y: 0.5)
        bg.position = CGPoint(x: -barWidth / 2, y: 0)
        container.addChild(bg)
        hpBarBackground = bg

        let fill = SKSpriteNode(color: .green, size: CGSize(width: barWidth, height: barHeight))
        fill.anchorPoint = CGPoint(x: 0, y: 0.5)
        fill.position = CGPoint(x: -barWidth / 2, y: 0)
        fill.zPosition = 1
        container.addChild(fill)
        hpBarFill = fill

        spriteNode.addChild(container)
        hpBarContainer = container
    }

    func updateHPBar() {
        guard maxHealth > 0 else { return }
        let ratio = CGFloat(health) / CGFloat(maxHealth)
        let barWidth: CGFloat = 24
        hpBarFill?.size.width = barWidth * ratio

        if ratio > 0.5 {
            hpBarFill?.color = .green
        } else if ratio > 0.25 {
            hpBarFill?.color = .yellow
        } else {
            hpBarFill?.color = .red
        }

        // Show bar only when damaged
        hpBarContainer?.isHidden = (health >= maxHealth)
    }

    public func resetFlight(flyingPath: FlyingPath, speed: CGFloat) {
        self.flyingPath = flyingPath
        self.speed = speed
        isHit = false
        health = maxHealth
        updateHPBar()
        let startPosition = flyingPath.nodes.first ?? vector_float2()

        if let flight = component(ofType: FlyingProjectileComponent.self) {
            flight.maxSpeed = Float(speed)
            flight.maxAcceleration = Float(speed) / 2
            flight.behavior = behavior(for: flyingPath)
            flight.position = startPosition
        }
        if let spriteNode = component(ofType: SpriteComponent.self)?.spriteNode {
            spriteNode.position = CGPoint(x: CGFloat(startPosition.x), y: CGFloat(startPosition.y))
            spriteNode.zRotation = 0
        }
        if let physicsBody = component(ofType: GeometryComponent.self)?.geometryNode.physicsBody {
            physicsBody.affectedByGravity = false
            physicsBody.contactTestBitMask = Constants.bulletBitMask | Constants.groundBitMask
            physicsBody.collisionBitMask = 0
            physicsBody.velocity = .zero
            physicsBody.angularVelocity = 0
            physicsBody.isResting = false
        }
    }

    public func didHit(){
        isHit = true
        component(ofType: FlyingProjectileComponent.self)?.behavior?.removeAllGoals()
        let physicBody = component(ofType: GeometryComponent.self)?.geometryNode.physicsBody
        physicBody?.affectedByGravity = false
        physicBody?.velocity = .zero
        physicBody?.angularVelocity = 0
        physicBody?.contactTestBitMask = 0
        physicBody?.categoryBitMask = 0

        // Animate fall + fade, then remove
        if let spriteNode = component(ofType: SpriteComponent.self)?.spriteNode {
            let spin = SKAction.rotate(byAngle: .pi * 2, duration: 0.6)
            let fall = SKAction.moveBy(x: 0, y: -120, duration: 0.6)
            fall.timingMode = .easeIn
            let fade = SKAction.fadeOut(withDuration: 0.6)
            let group = SKAction.group([spin, fall, fade])
            spriteNode.run(group) { [weak self] in
                self?.removeFromParent()
            }
        }
    }
    public func reachedDestination(){
        removeFromParent()
    }
    public func removeFromParent(){
        guard let scene = component(ofType: SpriteComponent.self)?.spriteNode.scene as? InPlaySKScene
        else {return}
        scene.removeEntity(self)
    }
    private func behavior(for flyingPath: FlyingPath)->GKBehavior{
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
              !isHit
        else{
            return
        }
        spriteNode.position = CGPoint(x: CGFloat(agent2d.position.x), y: CGFloat(agent2d.position.y))
        spriteNode.zRotation = CGFloat(agent2d.rotation)
    }
    
}

final class MineLayerDroneEntity: AttackDroneEntity {
    private struct GunAimSnapshot {
        let origin: CGPoint
        let direction: CGVector
        let leftPerpendicular: CGVector
    }

    struct TowerThreatInfo {
        let position: CGPoint
        let range: CGFloat
        let id: ObjectIdentifier
    }

    enum Phase {
        case inactive
        case approaching
        case waitingForDrop
        case repositioning
        case evading
        case crashRun
        case exiting
    }

    weak var mineLayerDelegate: MineLayerDroneDelegate?

    private(set) var phase: Phase = .inactive
    private(set) var bombsDroppedInCurrentCycle = 0
    private var hoverPoint = CGPoint.zero
    private var exitPoint = CGPoint.zero
    private var dropCooldownRemaining: TimeInterval = 0
    private(set) var evadeTargetPoint = CGPoint.zero
    private var aimThreatHoldTime: TimeInterval = 0
    private var isAimThreatLatched = false
    private var evadeRepathAccumulator: TimeInterval = 0
    private var crashVelocity = CGVector.zero
    private var crashBombsRemaining = 0
    private var crashDropCooldownRemaining: TimeInterval = 0

    // TD bomber properties
    private(set) weak var targetTower: TowerEntity?
    private var knownTowerThreats: [ObjectIdentifier: TimeInterval] = [:]
    private var approachWaypoint: CGPoint?

    var evadeTargetPointForTests: CGPoint { evadeTargetPoint }

    init(sceneFrame: CGRect) {
        let path = FlyingPath(
            topLevel: sceneFrame.height,
            bottomLevel: 0,
            leadingLevel: 0,
            trailingLevel: sceneFrame.width,
            startLevel: sceneFrame.height + 90,
            endLevel: 0,
            pathGenerator: { _ in
                [
                    vector_float2(x: Float(sceneFrame.midX), y: Float(sceneFrame.height + 90)),
                    vector_float2(
                        x: Float(sceneFrame.midX),
                        y: Float(sceneFrame.height * Constants.GameBalance.mineLayerHoverMinHeightRatio)
                    )
                ]
            }
        )
        super.init(
            damage: 1,
            speed: Constants.GameBalance.mineLayerApproachSpeed,
            imageName: "Drone",
            flyingPath: path
        )
        removeComponent(ofType: FlyingProjectileComponent.self)
        if let spriteNode = component(ofType: SpriteComponent.self)?.spriteNode {
            spriteNode.size = CGSize(width: 42, height: 42)
        }
    }

    required init(damage: CGFloat, speed: CGFloat, imageName: String, flyingPath: FlyingPath) {
        super.init(damage: damage, speed: speed, imageName: imageName, flyingPath: flyingPath)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didHit() {
        phase = .inactive
        resetAimThreatTracking()
        approachWaypoint = nil
        super.didHit()
    }

    override func update(deltaTime seconds: TimeInterval) {
        super.update(deltaTime: seconds)
        guard let spriteNode = component(ofType: SpriteComponent.self)?.spriteNode else { return }
        if !isHit {
            evaluateGunAimThreatIfNeeded(spriteNode: spriteNode, deltaTime: seconds)
        }
        if isHit {
            return
        }

        // TD tower threat evaluation
        if !isHit {
            switch phase {
            case .approaching, .waitingForDrop, .repositioning:
                evaluateTowerThreats(spriteNode: spriteNode, deltaTime: seconds)
            default:
                break
            }
        }

        switch phase {
        case .inactive:
            return
        case .approaching, .repositioning:
            // Check if target tower is still worth approaching
            if targetTower != nil, targetTower?.stats?.isDisabled != false {
                retargetOrExit(spriteNode: spriteNode)
                return
            }
            if rerouteApproachIfNeeded(spriteNode: spriteNode) {
                return
            }
            // Plan route around known tower threats
            if let scene = spriteNode.scene as? InPlaySKScene {
                planApproachRoute(from: spriteNode.position, to: hoverPoint, in: scene)
            }
            let moveTarget = approachWaypoint ?? hoverPoint
            if move(spriteNode: spriteNode, to: moveTarget, speed: Constants.GameBalance.mineLayerApproachSpeed, deltaTime: seconds) {
                if approachWaypoint != nil {
                    approachWaypoint = nil
                    // Reached waypoint, continue approaching
                } else {
                    freezeInHover(spriteNode)
                    phase = .waitingForDrop
                    dropCooldownRemaining = max(
                        dropCooldownRemaining,
                        Constants.GameBalance.mineBombDropInterval
                    )
                }
            }
        case .waitingForDrop:
            freezeInHover(spriteNode)
            // If target tower is disabled or gone, conserve bombs and switch target
            if targetTower != nil, targetTower?.stats?.isDisabled != false {
                retargetOrExit(spriteNode: spriteNode)
                return
            }
            guard bombsDroppedInCurrentCycle < Constants.GameBalance.mineBombsPerCycle else {
                phase = .exiting
                return
            }
            dropCooldownRemaining -= seconds
            if dropCooldownRemaining <= 0 {
                mineLayerDelegate?.mineLayer(
                    self,
                    spawnBombAt: bombSpawnPoint(from: spriteNode),
                    isFromCrashedDrone: false
                )
                bombsDroppedInCurrentCycle += 1
                if bombsDroppedInCurrentCycle >= Constants.GameBalance.mineBombsPerCycle {
                    phase = .exiting
                    return
                }
                dropCooldownRemaining = Constants.GameBalance.mineBombDropInterval
            }
        case .evading:
            // Gun-based evasion (legacy)
            if let scene = spriteNode.scene as? InPlaySKScene,
               let aimSnapshot = makeGunAimSnapshot(in: scene) {
                evadeRepathAccumulator -= seconds
                let segmentInDanger = isSegmentInsideFireCorridor(
                    from: spriteNode.position,
                    to: evadeTargetPoint,
                    aimSnapshot: aimSnapshot,
                    extraMargin: Constants.GameBalance.mineLayerFireCorridorSafetyMargin
                )
                let targetInDanger = isPointInsideFireCorridor(
                    evadeTargetPoint,
                    aimSnapshot: aimSnapshot,
                    extraMargin: Constants.GameBalance.mineLayerFireCorridorSafetyMargin
                )
                let currentDistanceToFireLine = abs(
                    signedDistanceToFireLine(point: spriteNode.position, aimSnapshot: aimSnapshot)
                )
                let shouldThreatRetarget =
                    scene.isGunThreatAssessmentActive &&
                    evadeRepathAccumulator <= 0 &&
                    currentDistanceToFireLine <=
                        Constants.GameBalance.mineLayerFireCorridorHalfWidth +
                        Constants.GameBalance.mineLayerFireCorridorSafetyMargin * 1.3

                if segmentInDanger || targetInDanger || shouldThreatRetarget {
                    evadeTargetPoint = makeEvadePoint(
                        in: scene.frame,
                        from: spriteNode.position,
                        aimSnapshot: aimSnapshot
                    )
                    evadeRepathAccumulator = Constants.GameBalance.mineLayerEvadeRepathInterval
                } else if evadeRepathAccumulator <= 0 {
                    evadeRepathAccumulator = Constants.GameBalance.mineLayerEvadeRepathInterval
                }
            }
            if move(
                spriteNode: spriteNode,
                to: evadeTargetPoint,
                speed: Constants.GameBalance.mineLayerEvadeSpeed,
                deltaTime: seconds
            ) {
                // After evading, check if target is still valid
                approachWaypoint = nil
                if targetTower != nil, targetTower?.stats?.isDisabled != false {
                    retargetOrExit(spriteNode: spriteNode)
                } else if targetTower != nil {
                    phase = .approaching
                } else {
                    hoverPoint = evadeTargetPoint
                    freezeInHover(spriteNode)
                    phase = .waitingForDrop
                }
                dropCooldownRemaining = max(
                    dropCooldownRemaining,
                    Constants.GameBalance.mineBombDropInterval
                )
            }
        case .crashRun:
            updateCrashRun(spriteNode: spriteNode, deltaTime: seconds)
        case .exiting:
            if move(spriteNode: spriteNode, to: exitPoint, speed: Constants.GameBalance.mineLayerExitSpeed, deltaTime: seconds) {
                phase = .inactive
                mineLayerDelegate?.mineLayerDidExitForRearm(self)
            }
        }
    }

    func beginCycle(in sceneFrame: CGRect) {
        guard let spriteNode = component(ofType: SpriteComponent.self)?.spriteNode else { return }

        let startX = CGFloat.random(in: 60...(sceneFrame.width - 60))
        let startY = sceneFrame.height + 90
        hoverPoint = makeRandomHoverPoint(in: sceneFrame)
        let exitsLeft = Bool.random()
        exitPoint = CGPoint(
            x: exitsLeft ? -140 : sceneFrame.width + 140,
            y: CGFloat.random(
                in: sceneFrame.height * Constants.GameBalance.mineLayerHoverMinHeightRatio...sceneFrame.height * 0.97
            )
        )
        bombsDroppedInCurrentCycle = 0
        dropCooldownRemaining = Constants.GameBalance.mineBombDropInterval
        phase = .approaching
        isHit = false
        health = maxHealth
        updateHPBar()
        evadeTargetPoint = .zero
        evadeRepathAccumulator = 0
        crashVelocity = .zero
        crashBombsRemaining = 0
        crashDropCooldownRemaining = 0
        approachWaypoint = nil
        resetAimThreatTracking()

        spriteNode.position = CGPoint(x: startX, y: startY)
        spriteNode.zRotation = 0
        if let physicsBody = component(ofType: GeometryComponent.self)?.geometryNode.physicsBody {
            physicsBody.affectedByGravity = false
            physicsBody.contactTestBitMask = Constants.bulletBitMask | Constants.groundBitMask
            physicsBody.collisionBitMask = 0
            physicsBody.velocity = .zero
            physicsBody.angularVelocity = 0
            physicsBody.isResting = false
        }
    }

    func forceHoverForTests(at point: CGPoint) {
        guard let spriteNode = component(ofType: SpriteComponent.self)?.spriteNode else { return }
        hoverPoint = point
        spriteNode.position = point
        dropCooldownRemaining = 0
        bombsDroppedInCurrentCycle = 0
        phase = .waitingForDrop
        evadeTargetPoint = .zero
        evadeRepathAccumulator = 0
        crashVelocity = .zero
        crashBombsRemaining = 0
        crashDropCooldownRemaining = 0
        approachWaypoint = nil
        resetAimThreatTracking()
        if let physicsBody = component(ofType: GeometryComponent.self)?.geometryNode.physicsBody {
            physicsBody.velocity = .zero
            physicsBody.angularVelocity = 0
            physicsBody.affectedByGravity = false
        }
    }

    func forceApproachForTests(from start: CGPoint, to target: CGPoint) {
        guard let spriteNode = component(ofType: SpriteComponent.self)?.spriteNode else { return }
        hoverPoint = target
        spriteNode.position = start
        dropCooldownRemaining = Constants.GameBalance.mineBombDropInterval
        bombsDroppedInCurrentCycle = 0
        phase = .approaching
        evadeTargetPoint = .zero
        evadeRepathAccumulator = 0
        crashVelocity = .zero
        crashBombsRemaining = 0
        crashDropCooldownRemaining = 0
        approachWaypoint = nil
        resetAimThreatTracking()
        if let physicsBody = component(ofType: GeometryComponent.self)?.geometryNode.physicsBody {
            physicsBody.velocity = .zero
            physicsBody.angularVelocity = 0
            physicsBody.affectedByGravity = false
        }
    }

    // MARK: - TD Bomber

    func beginCycleTD(in sceneFrame: CGRect, targetingTower tower: TowerEntity) {
        guard let spriteNode = component(ofType: SpriteComponent.self)?.spriteNode else { return }

        targetTower = tower
        knownTowerThreats.removeAll()

        let startX = CGFloat.random(in: 60...(sceneFrame.width - 60))
        let startY = sceneFrame.height + 90
        hoverPoint = CGPoint(x: tower.worldPosition.x, y: tower.worldPosition.y)

        let exitsLeft = Bool.random()
        exitPoint = CGPoint(
            x: exitsLeft ? -140 : sceneFrame.width + 140,
            y: CGFloat.random(
                in: sceneFrame.height * Constants.GameBalance.mineLayerHoverMinHeightRatio...sceneFrame.height * 0.97
            )
        )
        bombsDroppedInCurrentCycle = 0
        dropCooldownRemaining = Constants.GameBalance.mineBombDropInterval
        phase = .approaching
        isHit = false
        health = maxHealth
        updateHPBar()
        evadeTargetPoint = .zero
        evadeRepathAccumulator = 0
        crashVelocity = .zero
        crashBombsRemaining = 0
        crashDropCooldownRemaining = 0
        approachWaypoint = nil
        resetAimThreatTracking()

        spriteNode.position = CGPoint(x: startX, y: startY)
        spriteNode.zRotation = 0
        if let physicsBody = component(ofType: GeometryComponent.self)?.geometryNode.physicsBody {
            physicsBody.affectedByGravity = false
            physicsBody.contactTestBitMask = Constants.bulletBitMask | Constants.groundBitMask
            physicsBody.collisionBitMask = 0
            physicsBody.velocity = .zero
            physicsBody.angularVelocity = 0
            physicsBody.isResting = false
        }
    }

    private func evaluateTowerThreats(spriteNode: SKSpriteNode, deltaTime: TimeInterval) {
        guard let scene = spriteNode.scene as? InPlaySKScene else { return }
        let threats = scene.activeTowerThreats()

        // Update known threats from currently firing towers
        for threat in threats {
            knownTowerThreats[threat.id] = 0
        }

        // Age all known threats and remove expired ones
        var expiredKeys = [ObjectIdentifier]()
        for (key, age) in knownTowerThreats {
            let newAge = age + deltaTime
            if newAge >= Constants.GameBalance.mineLayerThreatAwarenessTime {
                expiredKeys.append(key)
            } else {
                knownTowerThreats[key] = newAge
            }
        }
        for key in expiredKeys {
            knownTowerThreats.removeValue(forKey: key)
        }

        // Check if drone is inside any known threat's range
        let allThreats = scene.allTowerThreatZones()
        for threat in allThreats {
            guard knownTowerThreats[threat.id] != nil else { continue }
            let dx = spriteNode.position.x - threat.position.x
            let dy = spriteNode.position.y - threat.position.y
            let distSq = dx * dx + dy * dy
            let dangerRange = threat.range + 20
            if distSq <= dangerRange * dangerRange {
                // Inside danger zone — evade
                let dist = sqrt(distSq)
                let escapeRange = threat.range + 40
                let evadeX: CGFloat
                let evadeY: CGFloat
                if dist > 0.001 {
                    evadeX = threat.position.x + (dx / dist) * escapeRange
                    evadeY = threat.position.y + (dy / dist) * escapeRange
                } else {
                    evadeX = spriteNode.position.x + escapeRange
                    evadeY = spriteNode.position.y
                }
                let sceneFrame = scene.frame
                evadeTargetPoint = CGPoint(
                    x: min(max(evadeX, 30), sceneFrame.width - 30),
                    y: min(max(evadeY, 30), sceneFrame.height - 30)
                )
                phase = .evading
                evadeRepathAccumulator = 0.5
                return
            }
        }
    }

    // MARK: - Approach Route Planning

    private func retargetOrExit(spriteNode: SKSpriteNode) {
        guard bombsDroppedInCurrentCycle < Constants.GameBalance.mineBombsPerCycle,
              let scene = spriteNode.scene as? InPlaySKScene,
              let nextTarget = scene.bestBombingTarget()
        else {
            phase = .exiting
            return
        }
        targetTower = nextTarget
        hoverPoint = CGPoint(x: nextTarget.worldPosition.x, y: nextTarget.worldPosition.y)
        approachWaypoint = nil
        phase = .approaching
    }

    private func planApproachRoute(from start: CGPoint, to destination: CGPoint, in scene: InPlaySKScene) {
        let allThreats = scene.allTowerThreatZones()
        let margin: CGFloat = 40

        for threat in allThreats {
            guard knownTowerThreats[threat.id] != nil else { continue }
            let dangerRadius = threat.range + margin

            guard segmentIntersectsCircle(from: start, to: destination, center: threat.position, radius: dangerRadius) else { continue }

            // Perpendicular to path direction
            let pathDx = destination.x - start.x
            let pathDy = destination.y - start.y
            let pathLen = sqrt(pathDx * pathDx + pathDy * pathDy)
            guard pathLen > 0.001 else { continue }

            let perpX = -pathDy / pathLen
            let perpY = pathDx / pathLen

            // Two bypass options on either side of the threat
            let bypass1 = CGPoint(
                x: threat.position.x + perpX * dangerRadius,
                y: threat.position.y + perpY * dangerRadius
            )
            let bypass2 = CGPoint(
                x: threat.position.x - perpX * dangerRadius,
                y: threat.position.y - perpY * dangerRadius
            )

            // Choose the shorter total path
            let totalDist1 = distance(from: start, to: bypass1) + distance(from: bypass1, to: destination)
            let totalDist2 = distance(from: start, to: bypass2) + distance(from: bypass2, to: destination)

            var chosen = totalDist1 <= totalDist2 ? bypass1 : bypass2

            // Clamp to scene bounds
            let sceneFrame = scene.frame
            chosen = CGPoint(
                x: min(max(chosen.x, 30), sceneFrame.width - 30),
                y: min(max(chosen.y, 30), sceneFrame.height - 30)
            )

            approachWaypoint = chosen
            return
        }

        approachWaypoint = nil
    }

    private func segmentIntersectsCircle(from start: CGPoint, to end: CGPoint, center: CGPoint, radius: CGFloat) -> Bool {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let segLenSq = dx * dx + dy * dy
        guard segLenSq > 0.001 else { return false }

        let fx = start.x - center.x
        let fy = start.y - center.y

        let a = segLenSq
        let b = 2 * (fx * dx + fy * dy)
        let c = fx * fx + fy * fy - radius * radius

        let discriminant = b * b - 4 * a * c
        guard discriminant >= 0 else { return false }

        let sqrtDisc = sqrt(discriminant)
        let t1 = (-b - sqrtDisc) / (2 * a)
        let t2 = (-b + sqrtDisc) / (2 * a)

        return (t1 >= 0 && t1 <= 1) || (t2 >= 0 && t2 <= 1) || (t1 < 0 && t2 > 1)
    }

    private func startCrashRun(from spriteNode: SKSpriteNode) {
        let sceneFrame = spriteNode.scene?.frame ?? CGRect(x: 0, y: 0, width: 390, height: 844)
        let horizontalDirection: CGFloat
        if spriteNode.position.x < sceneFrame.midX {
            horizontalDirection = 1
        } else if spriteNode.position.x > sceneFrame.midX {
            horizontalDirection = -1
        } else if let gunX = (spriteNode.scene as? InPlaySKScene)?
            .mainGun?
            .component(ofType: SpriteComponent.self)?
            .spriteNode
            .position
            .x {
            horizontalDirection = spriteNode.position.x >= gunX ? 1 : -1
        } else {
            horizontalDirection = Bool.random() ? 1 : -1
        }

        crashVelocity = CGVector(
            dx: horizontalDirection * Constants.GameBalance.mineLayerCrashHorizontalSpeed,
            dy: -Constants.GameBalance.mineLayerCrashVerticalSpeed
        )
        crashBombsRemaining = max(0, Constants.GameBalance.mineBombsPerCycle - bombsDroppedInCurrentCycle)
        crashDropCooldownRemaining = crashBombsRemaining > 0 ? Constants.GameBalance.mineLayerCrashDropInterval : 0
        hoverPoint = spriteNode.position
    }

    private func updateCrashRun(spriteNode: SKSpriteNode, deltaTime seconds: TimeInterval) {
        guard let sceneFrame = spriteNode.scene?.frame else { return }

        spriteNode.position = CGPoint(
            x: spriteNode.position.x + crashVelocity.dx * seconds,
            y: spriteNode.position.y + crashVelocity.dy * seconds
        )
        spriteNode.zRotation = atan2(crashVelocity.dy, crashVelocity.dx) - .pi / 2

        crashDropCooldownRemaining -= seconds
        while crashBombsRemaining > 0, crashDropCooldownRemaining <= 0 {
            mineLayerDelegate?.mineLayer(
                self,
                spawnBombAt: bombSpawnPoint(from: spriteNode),
                isFromCrashedDrone: true
            )
            bombsDroppedInCurrentCycle += 1
            crashBombsRemaining -= 1
            crashDropCooldownRemaining += Constants.GameBalance.mineLayerCrashDropInterval
        }

        guard crashBombsRemaining == 0 else { return }
        if isCrashRunOutOfBounds(spriteNode.position, in: sceneFrame) {
            phase = .inactive
            removeFromParent()
        }
    }

    private func isCrashRunOutOfBounds(_ point: CGPoint, in sceneFrame: CGRect) -> Bool {
        let margin = Constants.GameBalance.mineLayerCrashOutOfBoundsMargin
        return point.x < -margin || point.x > sceneFrame.width + margin || point.y < -margin
    }

    private func evaluateGunAimThreatIfNeeded(spriteNode: SKSpriteNode, deltaTime seconds: TimeInterval) {
        switch phase {
        case .approaching, .waitingForDrop, .repositioning:
            break
        default:
            resetAimThreatTracking()
            return
        }

        guard let scene = spriteNode.scene as? InPlaySKScene,
              scene.isGunThreatAssessmentActive,
              let aimSnapshot = makeGunAimSnapshot(in: scene),
              let angleToGun = angleBetweenGunAimAndDrone(
                aimSnapshot: aimSnapshot,
                dronePosition: spriteNode.position
              )
        else {
            resetAimThreatTracking()
            return
        }

        let forwardDistance = forwardProjectionOnFireLine(
            point: spriteNode.position,
            aimSnapshot: aimSnapshot
        )
        guard forwardDistance >= -6 else {
            resetAimThreatTracking()
            return
        }

        let lineDistance = abs(
            signedDistanceToFireLine(point: spriteNode.position, aimSnapshot: aimSnapshot)
        )
        let lineDistanceLimit = isAimThreatLatched
            ? Constants.GameBalance.mineLayerAimThreatLineDistance * 1.4
            : Constants.GameBalance.mineLayerAimThreatLineDistance
        guard lineDistance <= lineDistanceLimit else {
            resetAimThreatTracking()
            return
        }

        let isWithinThreatCone: Bool
        if isAimThreatLatched {
            isWithinThreatCone = angleToGun <= Constants.GameBalance.mineLayerAimThreatExitAngle
        } else {
            isWithinThreatCone = angleToGun <= Constants.GameBalance.mineLayerAimThreatEnterAngle
        }

        guard isWithinThreatCone else {
            resetAimThreatTracking()
            return
        }

        isAimThreatLatched = true
        aimThreatHoldTime += seconds
        guard aimThreatHoldTime >= Constants.GameBalance.mineLayerAimThreatConfirmTime else { return }
        triggerEvade(from: spriteNode, in: scene.frame, aimSnapshot: aimSnapshot)
        resetAimThreatTracking()
    }

    private func triggerEvade(
        from spriteNode: SKSpriteNode,
        in sceneFrame: CGRect,
        aimSnapshot: GunAimSnapshot
    ) {
        guard phase != .inactive && phase != .exiting && phase != .evading && phase != .crashRun else { return }
        let target = makeEvadePoint(
            in: sceneFrame,
            from: spriteNode.position,
            aimSnapshot: aimSnapshot
        )
        evadeTargetPoint = target
        hoverPoint = target
        phase = .evading
        evadeRepathAccumulator = Constants.GameBalance.mineLayerEvadeRepathInterval
        dropCooldownRemaining = max(dropCooldownRemaining, Constants.GameBalance.mineBombDropInterval)
    }

    private func rerouteApproachIfNeeded(spriteNode: SKSpriteNode) -> Bool {
        guard phase == .approaching || phase == .repositioning else { return false }
        guard let scene = spriteNode.scene as? InPlaySKScene,
              scene.isGunThreatAssessmentActive,
              let aimSnapshot = makeGunAimSnapshot(in: scene)
        else {
            return false
        }
        let isPathDangerous = isSegmentInsideFireCorridor(
            from: spriteNode.position,
            to: hoverPoint,
            aimSnapshot: aimSnapshot,
            extraMargin: Constants.GameBalance.mineLayerFireCorridorSafetyMargin
        )
        let isCurrentPointDangerous = isPointInsideFireCorridor(
            spriteNode.position,
            aimSnapshot: aimSnapshot,
            extraMargin: Constants.GameBalance.mineLayerFireCorridorSafetyMargin
        )
        guard isPathDangerous || isCurrentPointDangerous else { return false }
        triggerEvade(from: spriteNode, in: scene.frame, aimSnapshot: aimSnapshot)
        return true
    }

    private func makeGunAimSnapshot(in scene: InPlaySKScene) -> GunAimSnapshot? {
        guard let gunSprite = scene.mainGun?.component(ofType: SpriteComponent.self)?.spriteNode else { return nil }
        let rawDirection = CGVector(
            dx: cos(gunSprite.zRotation + .pi / 2),
            dy: sin(gunSprite.zRotation + .pi / 2)
        )
        let length = sqrt(rawDirection.dx * rawDirection.dx + rawDirection.dy * rawDirection.dy)
        guard length > 0.001 else { return nil }
        let direction = CGVector(dx: rawDirection.dx / length, dy: rawDirection.dy / length)
        let leftPerpendicular = CGVector(dx: -direction.dy, dy: direction.dx)
        return GunAimSnapshot(
            origin: gunSprite.position,
            direction: direction,
            leftPerpendicular: leftPerpendicular
        )
    }

    private func angleBetweenGunAimAndDrone(aimSnapshot: GunAimSnapshot, dronePosition: CGPoint) -> CGFloat? {
        let toDrone = CGVector(
            dx: dronePosition.x - aimSnapshot.origin.x,
            dy: dronePosition.y - aimSnapshot.origin.y
        )
        let toDroneLength = sqrt(toDrone.dx * toDrone.dx + toDrone.dy * toDrone.dy)
        guard toDroneLength > 0.001 else { return 0 }
        let dot = (aimSnapshot.direction.dx * toDrone.dx + aimSnapshot.direction.dy * toDrone.dy) / toDroneLength
        return acos(max(-1, min(1, dot)))
    }

    private func resetAimThreatTracking() {
        aimThreatHoldTime = 0
        isAimThreatLatched = false
    }

    private func move(spriteNode: SKSpriteNode, to target: CGPoint, speed: CGFloat, deltaTime: TimeInterval) -> Bool {
        let dx = target.x - spriteNode.position.x
        let dy = target.y - spriteNode.position.y
        let distance = sqrt(dx * dx + dy * dy)
        guard distance > 0.001 else {
            spriteNode.position = target
            return true
        }
        let maxStep = speed * deltaTime
        if distance <= maxStep {
            spriteNode.position = target
            return true
        }
        let stepScale = maxStep / distance
        spriteNode.position = CGPoint(
            x: spriteNode.position.x + dx * stepScale,
            y: spriteNode.position.y + dy * stepScale
        )
        spriteNode.zRotation = atan2(dy, dx) - .pi / 2
        return false
    }

    private func freezeInHover(_ spriteNode: SKSpriteNode) {
        spriteNode.position = hoverPoint
        spriteNode.zRotation = 0
        component(ofType: GeometryComponent.self)?.geometryNode.physicsBody?.velocity = .zero
    }

    private func bombSpawnPoint(from spriteNode: SKSpriteNode) -> CGPoint {
        CGPoint(x: spriteNode.position.x, y: spriteNode.position.y)
    }

    private func makeEvadePoint(
        in sceneFrame: CGRect,
        from currentPoint: CGPoint,
        aimSnapshot: GunAimSnapshot?
    ) -> CGPoint {
        let minX: CGFloat = 60
        let maxX: CGFloat = max(sceneFrame.width - 60, minX + 1)
        let minY = sceneFrame.height * Constants.GameBalance.mineLayerHoverMinHeightRatio
        let maxY = sceneFrame.height * Constants.GameBalance.mineLayerHoverMaxHeightRatio
        let minTravel = max(
            Constants.GameBalance.mineLayerDropMinTravelDistance,
            Constants.GameBalance.mineLayerEvadeMinTravelDistance
        )

        func clampPoint(_ point: CGPoint) -> CGPoint {
            CGPoint(
                x: min(max(point.x, minX), maxX),
                y: min(max(point.y, minY), maxY)
            )
        }

        func randomPoint() -> CGPoint {
            CGPoint(x: CGFloat.random(in: minX...maxX), y: CGFloat.random(in: minY...maxY))
        }

        guard let aimSnapshot else {
            return fallbackEvadePoint(
                from: currentPoint,
                randomPoint: randomPoint,
                minX: minX,
                maxX: maxX,
                minY: minY,
                maxY: maxY,
                minTravel: minTravel,
                sceneFrame: sceneFrame
            )
        }

        let lateralStep = Constants.GameBalance.mineLayerEvadeLateralStep
        let lateralOptions = [lateralStep, lateralStep * 1.22, lateralStep * 1.5]
        let forwardBias = Constants.GameBalance.mineLayerEvadeForwardBias
        let forwardOptions = [forwardBias, 0, -forwardBias * 0.4]

        let currentSignedDistance = signedDistanceToFireLine(
            point: currentPoint,
            aimSnapshot: aimSnapshot
        )
        let preferredSide: CGFloat
        if abs(currentSignedDistance) > 3 {
            preferredSide = currentSignedDistance >= 0 ? 1 : -1
        } else {
            preferredSide = currentPoint.x < sceneFrame.midX ? 1 : -1
        }

        var bestPoint: CGPoint?
        var bestScore = -CGFloat.greatestFiniteMagnitude

        for side in [preferredSide, -preferredSide] {
            for lateral in lateralOptions {
                for forward in forwardOptions {
                    var candidate = currentPoint
                    candidate.x += aimSnapshot.leftPerpendicular.dx * side * lateral
                    candidate.y += aimSnapshot.leftPerpendicular.dy * side * lateral
                    candidate.x += aimSnapshot.direction.dx * forward
                    candidate.y += aimSnapshot.direction.dy * forward
                    candidate = clampPoint(candidate)

                    if distance(from: candidate, to: currentPoint) < minTravel {
                        continue
                    }
                    let corridorDistance = abs(
                        signedDistanceToFireLine(point: candidate, aimSnapshot: aimSnapshot)
                    )
                    let pointInDanger = isPointInsideFireCorridor(
                        candidate,
                        aimSnapshot: aimSnapshot,
                        extraMargin: Constants.GameBalance.mineLayerFireCorridorSafetyMargin
                    )
                    let pathInDanger = isSegmentInsideFireCorridor(
                        from: currentPoint,
                        to: candidate,
                        aimSnapshot: aimSnapshot,
                        extraMargin: Constants.GameBalance.mineLayerFireCorridorSafetyMargin
                    )
                    var score = corridorDistance
                    score += (candidate.y - minY) * 0.03
                    if side == preferredSide {
                        score += 12
                    }
                    if pointInDanger {
                        score -= 500
                    }
                    if pathInDanger {
                        score -= 350
                    }
                    if score > bestScore {
                        bestScore = score
                        bestPoint = candidate
                    }
                }
            }
        }

        if let bestPoint {
            return bestPoint
        }

        return fallbackEvadePoint(
            from: currentPoint,
            randomPoint: randomPoint,
            minX: minX,
            maxX: maxX,
            minY: minY,
            maxY: maxY,
            minTravel: minTravel,
            sceneFrame: sceneFrame
        )
    }

    private func fallbackEvadePoint(
        from currentPoint: CGPoint,
        randomPoint: () -> CGPoint,
        minX: CGFloat,
        maxX: CGFloat,
        minY: CGFloat,
        maxY: CGFloat,
        minTravel: CGFloat,
        sceneFrame: CGRect
    ) -> CGPoint {
        for _ in 0..<20 {
            let candidate = randomPoint()
            if distance(from: candidate, to: currentPoint) >= minTravel {
                return candidate
            }
        }

        let direction: CGFloat = currentPoint.x < sceneFrame.midX ? 1 : -1
        let shiftedX = min(max(currentPoint.x + direction * minTravel, minX), maxX)
        return CGPoint(x: shiftedX, y: CGFloat.random(in: minY...maxY))
    }

    private func signedDistanceToFireLine(
        point: CGPoint,
        aimSnapshot: GunAimSnapshot
    ) -> CGFloat {
        let toPoint = CGVector(
            dx: point.x - aimSnapshot.origin.x,
            dy: point.y - aimSnapshot.origin.y
        )
        return aimSnapshot.direction.dx * toPoint.dy - aimSnapshot.direction.dy * toPoint.dx
    }

    private func forwardProjectionOnFireLine(
        point: CGPoint,
        aimSnapshot: GunAimSnapshot
    ) -> CGFloat {
        let toPoint = CGVector(
            dx: point.x - aimSnapshot.origin.x,
            dy: point.y - aimSnapshot.origin.y
        )
        return aimSnapshot.direction.dx * toPoint.dx + aimSnapshot.direction.dy * toPoint.dy
    }

    private func isPointInsideFireCorridor(
        _ point: CGPoint,
        aimSnapshot: GunAimSnapshot,
        extraMargin: CGFloat = 0
    ) -> Bool {
        let forward = forwardProjectionOnFireLine(point: point, aimSnapshot: aimSnapshot)
        guard forward >= -12 else { return false }
        let halfWidth = Constants.GameBalance.mineLayerFireCorridorHalfWidth + extraMargin
        return abs(signedDistanceToFireLine(point: point, aimSnapshot: aimSnapshot)) <= halfWidth
    }

    private func isSegmentInsideFireCorridor(
        from start: CGPoint,
        to end: CGPoint,
        aimSnapshot: GunAimSnapshot,
        extraMargin: CGFloat = 0
    ) -> Bool {
        let sampleCount = 8
        for index in 0...sampleCount {
            let t = CGFloat(index) / CGFloat(sampleCount)
            let point = CGPoint(
                x: start.x + (end.x - start.x) * t,
                y: start.y + (end.y - start.y) * t
            )
            if isPointInsideFireCorridor(point, aimSnapshot: aimSnapshot, extraMargin: extraMargin) {
                return true
            }
        }
        return false
    }

    private func makeRandomHoverPoint(in sceneFrame: CGRect) -> CGPoint {
        let minX: CGFloat = 60
        let maxX: CGFloat = max(sceneFrame.width - 60, minX + 1)
        let minY = sceneFrame.height * Constants.GameBalance.mineLayerHoverMinHeightRatio
        let maxY = sceneFrame.height * Constants.GameBalance.mineLayerHoverMaxHeightRatio
        return CGPoint(
            x: CGFloat.random(in: minX...maxX),
            y: CGFloat.random(in: minY...maxY)
        )
    }

    private func distance(from pointA: CGPoint, to pointB: CGPoint) -> CGFloat {
        let dx = pointA.x - pointB.x
        let dy = pointA.y - pointB.y
        return sqrt(dx * dx + dy * dy)
    }
}
