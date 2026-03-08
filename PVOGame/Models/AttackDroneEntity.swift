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
        addComponent(FlyingProjectileComponent(speed: speed, behavior: behavior(for: flyingPath),position: flyingPath.nodes.first ?? vector_float2()))

    }

    public func resetFlight(flyingPath: FlyingPath, speed: CGFloat) {
        self.flyingPath = flyingPath
        self.speed = speed
        isHit = false
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
        guard let spriteNode = component(ofType: SpriteComponent.self)?.spriteNode else {
            phase = .inactive
            super.didHit()
            return
        }
        isHit = true
        phase = .crashRun
        resetAimThreatTracking()
        evadeRepathAccumulator = 0
        component(ofType: FlyingProjectileComponent.self)?.behavior?.removeAllGoals()
        if let physicsBody = component(ofType: GeometryComponent.self)?.geometryNode.physicsBody {
            physicsBody.affectedByGravity = false
            physicsBody.velocity = .zero
            physicsBody.angularVelocity = 0
            physicsBody.contactTestBitMask = Constants.bulletBitMask | Constants.groundBitMask
            physicsBody.collisionBitMask = 0
        }
        startCrashRun(from: spriteNode)
    }

    override func update(deltaTime seconds: TimeInterval) {
        super.update(deltaTime: seconds)
        guard let spriteNode = component(ofType: SpriteComponent.self)?.spriteNode else { return }
        if !isHit {
            evaluateGunAimThreatIfNeeded(spriteNode: spriteNode, deltaTime: seconds)
        }
        if isHit && phase != .crashRun {
            return
        }

        switch phase {
        case .inactive:
            return
        case .approaching, .repositioning:
            if rerouteApproachIfNeeded(spriteNode: spriteNode) {
                return
            }
            if move(spriteNode: spriteNode, to: hoverPoint, speed: Constants.GameBalance.mineLayerApproachSpeed, deltaTime: seconds) {
                freezeInHover(spriteNode)
                phase = .waitingForDrop
                dropCooldownRemaining = max(
                    dropCooldownRemaining,
                    Constants.GameBalance.mineBombDropInterval
                )
            }
        case .waitingForDrop:
            freezeInHover(spriteNode)
            guard bombsDroppedInCurrentCycle < Constants.GameBalance.mineBombsPerCycle else {
                phase = .exiting
                return
            }
            dropCooldownRemaining -= seconds
            while dropCooldownRemaining <= 0 {
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
                dropCooldownRemaining += Constants.GameBalance.mineBombDropInterval
            }
        case .evading:
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
                hoverPoint = evadeTargetPoint
                freezeInHover(spriteNode)
                phase = .waitingForDrop
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
        evadeTargetPoint = .zero
        evadeRepathAccumulator = 0
        crashVelocity = .zero
        crashBombsRemaining = 0
        crashDropCooldownRemaining = 0
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
        resetAimThreatTracking()
        if let physicsBody = component(ofType: GeometryComponent.self)?.geometryNode.physicsBody {
            physicsBody.velocity = .zero
            physicsBody.angularVelocity = 0
            physicsBody.affectedByGravity = false
        }
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
        CGPoint(x: spriteNode.position.x, y: spriteNode.position.y - spriteNode.size.height * 0.62)
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
