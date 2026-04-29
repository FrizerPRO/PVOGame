//
//  HeavyDroneEntity.swift
//  PVOGame
//

import Foundation
import GameplayKit
import SpriteKit

// MARK: - Waypoint

/// Class wrapper holding a weak reference to the strike target — lets
/// `HeavyDroneWaypoint` (a struct) carry the target through to the
/// bomb-release callback without an ARC cycle.
final class WeakTowerRef {
    weak var tower: TowerEntity?
    init(_ tower: TowerEntity) { self.tower = tower }
}

/// One step in the Heavy drone's flight plan. The drone steers toward
/// `position`; on arrival (within `arrivalRadius`) it advances to the
/// next waypoint and runs any side-effects associated with `kind`.
struct HeavyDroneWaypoint {
    let position: CGPoint
    let kind: Kind
    let arrivalRadius: CGFloat

    enum Kind {
        /// Generic flyby. No side effects; just routes the drone.
        /// Used for the pre-strike transit waypoint and any high-
        /// altitude routing between strikes.
        case transit
        /// Drone is lining up for a strike. On arrival: descend tween,
        /// vortex emitter on, ready to release on overflight.
        case strikeApproach(target: WeakTowerRef)
        /// Release point — directly above the target. The bomb releases
        /// the moment the drone's lateral distance to the target falls
        /// within tolerance, OR on arrival as a fallback.
        case strikeRelease(target: WeakTowerRef)
        /// Climb-out point — `exitOffset` past the target on the
        /// opposite side from approach. On arrival: climb tween fires,
        /// vortex emitter off. The mirrored release→exit geometry keeps
        /// climb-out aligned with the bombing run.
        case strikeExit
        /// Final waypoint above the frame. On arrival: drone is removed.
        case egress
    }
}

// MARK: - Heavy drone entity

/// Bayraktar TB2 / Reaper-style strike UAV.
///
/// Flight model: kinematic fixed-wing controller with bank inertia.
/// State is `(position, heading, forwardSpeed, angularVelocity)`.
/// Forward speed follows the altitude/dive tween, while turn control
/// follows a separate cruise-speed maneuvering envelope. Each frame the drone:
///   1. picks the desired heading toward a lookahead point on the route,
///   2. changes angular velocity by at most the configured angular
///      acceleration, so bank-in and bank-out are continuous,
///   3. integrates position by the current forward speed.
///
/// Sharp turns and pivots-in-place are physically impossible: the
/// angular velocity is hard-capped to the bank rate, regardless
/// of where the next waypoint sits. If a waypoint is "behind" the
/// drone, it overshoots and arcs around — exactly what a real fixed-
/// wing aircraft does.
///
/// Strikes are flyby waypoint sequences (approach → release → exit);
/// the dive shape emerges from the drone banking through them, rather
/// than being scripted as a curve.
final class HeavyDroneEntity: AttackDroneEntity {

    override var isBossType: Bool { true }

    // Steering state
    private var heading: CGFloat = -.pi / 2 // initial: nose down
    private var angularVelocity: CGFloat = 0
    private var flightSpeed: CGFloat = Constants.AdvancedEnemies.heavyDroneSpeed
    private var legStart: CGPoint?
    private var waypoints: [HeavyDroneWaypoint] = []
    private var currentWaypointIndex: Int = 0
    private var bombsLaunched = 0
    private var bombReleasedForCurrentStrike = false
    private var pickedTargets: [TowerEntity] = []
    fileprivate weak var currentTarget: TowerEntity?
    private var initialPlanDone = false

    /// ±1, locked at init. Used as a tiebreaker for approach-side
    /// selection on center targets so two Heavies spawning on the
    /// same tick get visually distinct trajectories.
    private let orbitTurnDirection: CGFloat

    // Visual subsystems
    private var underWingBombSprites: [SKSpriteNode] = []
    private var leftVortexEmitter: SKEmitterNode?
    private var rightVortexEmitter: SKEmitterNode?
    private weak var offscreenIndicator: SKNode?

    /// Soft white circle reused for every vortex particle. Built once
    /// at first access — saves the per-particle texture cost across
    /// all Heavies in the scene.
    private static let vortexParticleTexture: SKTexture = {
        let s: CGFloat = 16
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: s, height: s))
        let image = renderer.image { ctx in
            UIColor.white.setFill()
            ctx.cgContext.fillEllipse(in: CGRect(x: 0, y: 0, width: s, height: s))
        }
        return SKTexture(image: image)
    }()

    init(sceneFrame: CGRect, flightPath: DroneFlightPath) {
        self.orbitTurnDirection = Bool.random() ? 1 : -1
        let flyingPath = flightPath.toFlyingPath()
        super.init(
            damage: 1,
            speed: Constants.AdvancedEnemies.heavyDroneSpeed,
            imageName: "Drone",
            flyingPath: flyingPath
        )
        removeComponent(ofType: FlyingProjectileComponent.self)
        configureHealth(Constants.AdvancedEnemies.heavyDroneHealth)

        let scale = Constants.AdvancedEnemies.heavyDroneSpriteScale
        if let spriteNode = component(ofType: SpriteComponent.self)?.spriteNode {
            spriteNode.color = .clear
            spriteNode.colorBlendFactor = 1.0
            buildBayraktarSilhouette(on: spriteNode, scale: scale)
            attachUnderWingBombs(on: spriteNode, scale: scale)
            attachWingtipVortexEmitters(on: spriteNode, scale: scale)
        }

        addNavLights(wingspan: 28 * scale)
    }

    required init(damage: CGFloat, speed: CGFloat, imageName: String, flyingPath: FlyingPath) {
        self.orbitTurnDirection = 1
        super.init(damage: damage, speed: speed, imageName: imageName, flyingPath: flyingPath)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Update loop

    override func update(deltaTime seconds: TimeInterval) {
        guard !isHit,
              let spriteNode = component(ofType: SpriteComponent.self)?.spriteNode,
              let scene = spriteNode.scene as? InPlaySKScene else { return }

        let dt = CGFloat(seconds)

        if !initialPlanDone {
            planInitialWaypoints(spriteNode: spriteNode, scene: scene)
            initialPlanDone = true
        }

        // If we've consumed all currently-planned waypoints, plan more.
        if currentWaypointIndex >= waypoints.count {
            planNextStrikeOrEgress(spriteNode: spriteNode, scene: scene)
            if currentWaypointIndex >= waypoints.count {
                removeFromParent()
                return
            }
            beginCurrentLeg(from: spriteNode.position)
        }

        var wp = waypoints[currentWaypointIndex]
        let pos = spriteNode.position
        if legStart == nil { beginCurrentLeg(from: pos) }
        var dist = distance(from: pos, to: wp.position)

        // Bomb release: trigger the moment the drone passes overhead
        // laterally. Doing this here (rather than only on waypoint
        // arrival) means the bomb separates exactly when the drone
        // visually crosses the tower, even if the drone overshoots
        // the release waypoint's vertical position. The climb-out
        // sprite tween fires later, on `strikeExit` arrival — drone
        // lingers low for a beat after release before recovering.
        if case .strikeRelease(let targetRef) = wp.kind, !bombReleasedForCurrentStrike {
            let lateralTolerance = Constants.AdvancedEnemies.heavyDroneStrikeBombReleaseLateralTolerance
            if let target = targetRef.tower,
               abs(pos.x - target.worldPosition.x) < lateralTolerance {
                if !(target.stats?.isDisabled ?? true) {
                    launchBomb(at: target, from: spriteNode, in: scene)
                    pickedTargets.append(target)
                }
                bombsLaunched += 1
                bombReleasedForCurrentStrike = true
                if currentTarget === target { currentTarget = nil }

                // Lateral-overflight release is the real completion condition
                // for this waypoint. Keep flying through to strikeExit instead
                // of continuing to chase the release point and risking a visible
                // orbit around it.
                guard advanceCurrentWaypoint(spriteNode: spriteNode, in: scene, runArrival: false) else { return }
                wp = waypoints[currentWaypointIndex]
                dist = distance(from: pos, to: wp.position)
            }
        }

        // Waypoint arrival.
        if case .egress = wp.kind,
           pos.y >= scene.frame.maxY + Constants.AdvancedEnemies.heavyDroneEgressTopMargin {
            removeFromParent()
            return
        }
        while shouldAdvanceWaypoint(wp, from: pos, distanceToWaypoint: dist) {
            guard advanceCurrentWaypoint(spriteNode: spriteNode, in: scene, runArrival: true) else { return }
            wp = waypoints[currentWaypointIndex]
            dist = distance(from: pos, to: wp.position)
            if case .egress = wp.kind,
               pos.y >= scene.frame.maxY + Constants.AdvancedEnemies.heavyDroneEgressTopMargin {
                removeFromParent()
                return
            }
        }

        let forwardSpeed = updateFlightSpeed(spriteNode: spriteNode, dt: dt)

        // Steering — combine route lookahead attraction with predictive
        // boundary containment
        // before rate-limiting the heading change.
        //
        // Attraction is the unit vector toward a lookahead point on the
        // planned route. Boundary containment predicts where the current
        // heading will carry the drone and blends the target back inside
        // the soft corridor before the fixed-wing turn radius clips a side.
        let routeTarget = lookAheadTarget(from: pos)
        let steeringTarget = boundaryAdjustedTarget(
            routeTarget,
            from: pos,
            scene: scene,
            speed: forwardSpeed
        )
        let steerDX = steeringTarget.x - pos.x
        let steerDY = steeringTarget.y - pos.y
        let steerDist = hypot(steerDX, steerDY)
        let invSteerDist = 1 / max(1, steerDist)
        let steerX = steerDX * invSteerDist
        let steerY = steerDY * invSteerDist
        let desiredHeading = atan2(steerY, steerX)
        let headingDelta = normalizedAngle(desiredHeading - heading)

        let minRadius = Constants.AdvancedEnemies.heavyDroneMinTurnRadius
        let maxTurnRate = Constants.AdvancedEnemies.heavyDroneTurnRateReferenceSpeed / minRadius
        let maxAngularAcceleration = Constants.AdvancedEnemies.heavyDroneAngularAcceleration
        let targetAngularVelocity = targetTurnRate(
            for: headingDelta,
            maxTurnRate: maxTurnRate,
            maxAngularAcceleration: maxAngularAcceleration
        )
        angularVelocity = move(
            angularVelocity,
            toward: targetAngularVelocity,
            maxDelta: maxAngularAcceleration * dt
        )

        let turnStep = angularVelocity * dt
        if wouldOvershoot(turnStep: turnStep, remaining: headingDelta) {
            heading = desiredHeading
            angularVelocity = 0
        } else {
            heading = normalizedAngle(heading + turnStep)
        }

        // Integrate position along the new heading.
        let dpos = forwardSpeed * dt
        spriteNode.position = CGPoint(
            x: pos.x + dpos * cos(heading),
            y: pos.y + dpos * sin(heading)
        )

        // Sprite local +Y is the nose; rotate so heading aligns.
        spriteNode.zRotation = heading - .pi / 2

        updateOffscreenIndicator(in: scene)
    }

    private func updateFlightSpeed(spriteNode: SKSpriteNode, dt: CGFloat) -> CGFloat {
        let target = targetSpeed(spriteNode: spriteNode)
        let maxDelta = Constants.AdvancedEnemies.heavyDroneSpeedChangeRate * dt
        flightSpeed = move(flightSpeed, toward: target, maxDelta: maxDelta)
        self.speed = flightSpeed
        return flightSpeed
    }

    private func targetSpeed(spriteNode: SKSpriteNode) -> CGFloat {
        let baseSpeed = Constants.AdvancedEnemies.heavyDroneSpeed
        let factor = altitudeProportionalSpeedFactor(spriteScale: spriteNode.xScale)
        return baseSpeed * factor
    }

    /// Map current sprite xScale to a speed multiplier so velocity
    /// ramps in lockstep with the descend/climb tween. xScale=1.0
    /// (cruise) → 1.0×; xScale at the attack value → `attackFactor`.
    private func altitudeProportionalSpeedFactor(spriteScale: CGFloat) -> CGFloat {
        let cruiseScale: CGFloat = 1.0
        let attackScale = Constants.AdvancedEnemies.heavyDroneAttackSpriteScale
        let span = cruiseScale - attackScale
        guard span > 0 else { return 1.0 }
        let descendProgress = max(0, min(1, (cruiseScale - spriteScale) / span))
        let attackFactor = Constants.AdvancedEnemies.heavyDroneAttackSpeedFactor
        return 1.0 + (attackFactor - 1.0) * descendProgress
    }

    private func targetTurnRate(
        for headingDelta: CGFloat,
        maxTurnRate: CGFloat,
        maxAngularAcceleration: CGFloat
    ) -> CGFloat {
        let error = abs(headingDelta)
        guard error > 0.001 else { return 0 }
        let sign: CGFloat = headingDelta >= 0 ? 1 : -1
        let stoppingLimitedRate = sqrt(2 * maxAngularAcceleration * error)
        return sign * min(maxTurnRate, stoppingLimitedRate)
    }

    private func move(_ value: CGFloat, toward target: CGFloat, maxDelta: CGFloat) -> CGFloat {
        if value < target {
            return min(value + maxDelta, target)
        }
        return max(value - maxDelta, target)
    }

    private func wouldOvershoot(turnStep: CGFloat, remaining: CGFloat) -> Bool {
        guard turnStep * remaining > 0 else { return false }
        return abs(turnStep) > abs(remaining)
    }

    private func normalizedAngle(_ angle: CGFloat) -> CGFloat {
        var result = angle
        while result > .pi { result -= 2 * .pi }
        while result < -.pi { result += 2 * .pi }
        return result
    }

    private func beginCurrentLeg(from position: CGPoint) {
        legStart = position
    }

    private func advanceCurrentWaypoint(
        spriteNode: SKSpriteNode,
        in scene: InPlaySKScene,
        runArrival: Bool
    ) -> Bool {
        guard currentWaypointIndex < waypoints.count else { return false }
        let wp = waypoints[currentWaypointIndex]
        let removesDrone: Bool
        if case .egress = wp.kind {
            removesDrone = true
        } else {
            removesDrone = false
        }

        if runArrival {
            handleWaypointArrival(wp, spriteNode: spriteNode, in: scene)
        }
        if removesDrone { return false }

        currentWaypointIndex += 1
        beginCurrentLeg(from: spriteNode.position)

        if currentWaypointIndex >= waypoints.count {
            planNextStrikeOrEgress(spriteNode: spriteNode, scene: scene)
            if currentWaypointIndex >= waypoints.count {
                removeFromParent()
                return false
            }
            beginCurrentLeg(from: spriteNode.position)
        }

        updateOffscreenIndicator(in: scene)
        return true
    }

    private func shouldAdvanceWaypoint(
        _ wp: HeavyDroneWaypoint,
        from position: CGPoint,
        distanceToWaypoint: CGFloat
    ) -> Bool {
        if distanceToWaypoint < wp.arrivalRadius { return true }
        return hasPassedWaypointGate(position: position, waypoint: wp)
    }

    private func hasPassedWaypointGate(position: CGPoint, waypoint: HeavyDroneWaypoint) -> Bool {
        guard let start = legStart else { return false }
        let legX = waypoint.position.x - start.x
        let legY = waypoint.position.y - start.y
        let lenSq = legX * legX + legY * legY
        guard lenSq > 1 else { return true }

        let progress = ((position.x - start.x) * legX + (position.y - start.y) * legY) / lenSq
        return progress >= 1
    }

    private func lookAheadTarget(from position: CGPoint) -> CGPoint {
        guard currentWaypointIndex < waypoints.count else { return position }
        var remaining = Constants.AdvancedEnemies.heavyDronePathLookAheadDistance
        var index = currentWaypointIndex
        var cursor = projectedPointOnCurrentLeg(from: position)

        while index < waypoints.count {
            let end = waypoints[index].position
            let segmentLength = distance(from: cursor, to: end)
            if segmentLength > 1 {
                if remaining <= segmentLength {
                    return interpolate(from: cursor, to: end, fraction: remaining / segmentLength)
                }
                remaining -= segmentLength
            }
            cursor = end
            index += 1
        }

        return cursor
    }

    private func boundaryAdjustedTarget(
        _ routeTarget: CGPoint,
        from position: CGPoint,
        scene: InPlaySKScene,
        speed: CGFloat
    ) -> CGPoint {
        let softMargin = Constants.AdvancedEnemies.heavyDroneBoundarySoftMargin
        let hardOutset = Constants.AdvancedEnemies.heavyDroneBoundaryHardOutset
        let softLeft = scene.frame.minX + softMargin
        let softRight = scene.frame.maxX - softMargin
        let hardLeft = scene.frame.minX - hardOutset
        let hardRight = scene.frame.maxX + hardOutset
        let predictionTime = Constants.AdvancedEnemies.heavyDroneBoundaryPredictionTime
        let predictedX = position.x + cos(heading) * speed * predictionTime
        let leftSpan = max(1, softLeft - hardLeft)
        let rightSpan = max(1, hardRight - softRight)

        let leftPressure = max(
            boundaryPressure(softLeft - position.x, span: leftSpan),
            boundaryPressure(softLeft - predictedX, span: leftSpan)
        )
        let rightPressure = max(
            boundaryPressure(position.x - softRight, span: rightSpan),
            boundaryPressure(predictedX - softRight, span: rightSpan)
        )

        guard leftPressure > 0 || rightPressure > 0 else { return routeTarget }

        let recoveryLead = Constants.AdvancedEnemies.heavyDroneBoundaryRecoveryLead
        let recoveryX: CGFloat
        let blend: CGFloat
        if leftPressure >= rightPressure {
            recoveryX = min(softRight, softLeft + recoveryLead)
            blend = leftPressure
        } else {
            recoveryX = max(softLeft, softRight - recoveryLead)
            blend = rightPressure
        }

        let t = min(0.95, smoothstep(blend))
        return CGPoint(
            x: routeTarget.x + (recoveryX - routeTarget.x) * t,
            y: routeTarget.y
        )
    }

    private func boundaryPressure(_ overflow: CGFloat, span: CGFloat) -> CGFloat {
        max(0, min(1, overflow / span))
    }

    private func smoothstep(_ t: CGFloat) -> CGFloat {
        let x = max(0, min(1, t))
        return x * x * (3 - 2 * x)
    }

    private func projectedPointOnCurrentLeg(from position: CGPoint) -> CGPoint {
        guard currentWaypointIndex < waypoints.count,
              let start = legStart else { return position }
        let end = waypoints[currentWaypointIndex].position
        let legX = end.x - start.x
        let legY = end.y - start.y
        let lenSq = legX * legX + legY * legY
        guard lenSq > 1 else { return end }

        let rawT = ((position.x - start.x) * legX + (position.y - start.y) * legY) / lenSq
        let t = max(0, min(1, rawT))
        return CGPoint(x: start.x + legX * t, y: start.y + legY * t)
    }

    private func distance(from a: CGPoint, to b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }

    private func interpolate(from a: CGPoint, to b: CGPoint, fraction: CGFloat) -> CGPoint {
        CGPoint(
            x: a.x + (b.x - a.x) * fraction,
            y: a.y + (b.y - a.y) * fraction
        )
    }

    private func handleWaypointArrival(_ wp: HeavyDroneWaypoint, spriteNode: SKSpriteNode, in scene: InPlaySKScene) {
        switch wp.kind {
        case .transit:
            break
        case .strikeApproach:
            descendToAttackAltitude(spriteNode: spriteNode)
            bombReleasedForCurrentStrike = false
        case .strikeRelease(let targetRef):
            // Fallback: if lateral-overflight release didn't fire
            // (drone overshot or target moved), force release here.
            if !bombReleasedForCurrentStrike {
                if let target = targetRef.tower, !(target.stats?.isDisabled ?? true) {
                    launchBomb(at: target, from: spriteNode, in: scene)
                    pickedTargets.append(target)
                }
                bombsLaunched += 1
                bombReleasedForCurrentStrike = true
                if currentTarget === targetRef.tower { currentTarget = nil }
            }
        case .strikeExit:
            // Climb-out: sprite grows back to cruise scale, vortex off.
            // Triggering here (rather than at release) gives a brief
            // "linger low" beat between the bomb dropping and the
            // drone visibly recovering altitude.
            climbToCruiseAltitude(spriteNode: spriteNode)
        case .egress:
            removeFromParent()
        }
    }

    // MARK: - Waypoint planning

    private func planInitialWaypoints(spriteNode: SKSpriteNode, scene: InPlaySKScene) {
        // Drone spawns above the frame top pointing down. Initial
        // heading: -π/2 (down). The first call to
        // `planNextStrikeOrEgress` adds a transit waypoint inside the
        // frame as the first thing the drone steers toward, so no
        // dedicated "entry" waypoint is needed — the drone naturally
        // descends from spawn into the playing field by chasing the
        // transit point.
        heading = -.pi / 2
        angularVelocity = 0
        flightSpeed = Constants.AdvancedEnemies.heavyDroneSpeed
        planNextStrikeOrEgress(spriteNode: spriteNode, scene: scene)
        beginCurrentLeg(from: spriteNode.position)
    }

    /// Append waypoints for the next strike, or egress if no more
    /// strikes are warranted. Called whenever the drone exhausts its
    /// queued waypoints.
    private func planNextStrikeOrEgress(spriteNode: SKSpriteNode, scene: InPlaySKScene) {
        let pos = spriteNode.position
        let bombCount = Constants.AdvancedEnemies.heavyDroneBombCount

        if bombsLaunched >= bombCount {
            appendEgressWaypoint(from: pos, scene: scene)
            return
        }
        guard let target = pickNextTarget(scene: scene, currentPos: pos) else {
            appendEgressWaypoint(from: pos, scene: scene)
            return
        }

        let side = approachSide(for: target, currentDronePos: pos, scene: scene)
        currentTarget = target
        let targetRef = WeakTowerRef(target)

        let approachOffset = Constants.AdvancedEnemies.heavyDroneStrikeApproachOffset
        let approachAlt = Constants.AdvancedEnemies.heavyDroneStrikeApproachAltitude
        let releaseAlt = Constants.AdvancedEnemies.heavyDroneStrikeReleaseAltitude
        let exitOffset = Constants.AdvancedEnemies.heavyDroneStrikeExitOffset
        let exitAlt = Constants.AdvancedEnemies.heavyDroneStrikeExitAltitude
        let transitOff = Constants.AdvancedEnemies.heavyDroneTransitSideOffset
        let cruiseFromTop = Constants.AdvancedEnemies.heavyDroneTransitCruiseAltitudeFromTop

        // Pre-strike transit point: high altitude on the approach side
        // of the target. Routing through here gives the drone time to
        // line up with the strike approach axis — when it arrives at
        // approach, its heading is already roughly toward release.
        let transitX = clampToCorridor(
            target.worldPosition.x + side * transitOff,
            scene: scene,
            edgeMargin: 60
        )
        let transitY = scene.frame.maxY - cruiseFromTop
        waypoints.append(HeavyDroneWaypoint(
            position: CGPoint(x: transitX, y: transitY),
            kind: .transit,
            arrivalRadius: Constants.AdvancedEnemies.heavyDroneWaypointArrivalRadius + 20
        ))

        // Strike approach: drone descends from cruise to attack
        // altitude. Sprite shrink + vortex on at this waypoint.
        let approachX = clampToCorridor(
            target.worldPosition.x + side * approachOffset,
            scene: scene,
            edgeMargin: 30
        )
        let approachY = target.worldPosition.y + approachAlt
        waypoints.append(HeavyDroneWaypoint(
            position: CGPoint(x: approachX, y: approachY),
            kind: .strikeApproach(target: targetRef),
            arrivalRadius: Constants.AdvancedEnemies.heavyDroneStrikeWaypointArrivalRadius
        ))

        // Release: directly above the target at low altitude. Bomb
        // separation fires during steering on lateral overflight (or
        // here as a fallback on arrival).
        let releaseX = clampToCorridor(
            target.worldPosition.x,
            scene: scene,
            edgeMargin: 20
        )
        let releaseY = target.worldPosition.y + releaseAlt
        waypoints.append(HeavyDroneWaypoint(
            position: CGPoint(x: releaseX, y: releaseY),
            kind: .strikeRelease(target: targetRef),
            arrivalRadius: Constants.AdvancedEnemies.heavyDroneStrikeWaypointArrivalRadius
        ))

        // Strike exit: opposite side of target, climbing back to the
        // approach altitude. Climb tween + vortex off fire here.
        // The mirrored release→exit geometry keeps the climb-out
        // reachable with the same bank envelope used during approach.
        // After exit the drone continues to the next strike's transit
        // waypoint (or to egress), both of which are long enough for
        // the bank-in/bank-out controller.
        let exitX = clampToCorridor(
            target.worldPosition.x - side * exitOffset,
            scene: scene,
            edgeMargin: 30
        )
        let exitY = target.worldPosition.y + exitAlt
        waypoints.append(HeavyDroneWaypoint(
            position: CGPoint(x: exitX, y: exitY),
            kind: .strikeExit,
            arrivalRadius: Constants.AdvancedEnemies.heavyDroneStrikeWaypointArrivalRadius
        ))
    }

    private func appendEgressWaypoint(from pos: CGPoint, scene: InPlaySKScene) {
        let exitX = clampToCorridor(
            scene.frame.midX + (pos.x - scene.frame.midX) * 0.3,
            scene: scene,
            edgeMargin: 100
        )
        let exitY = scene.frame.maxY + Constants.AdvancedEnemies.heavyDroneEgressSteeringTopMargin
        waypoints.append(HeavyDroneWaypoint(
            position: CGPoint(x: exitX, y: exitY),
            kind: .egress,
            arrivalRadius: Constants.AdvancedEnemies.heavyDroneEgressArrivalRadius
        ))
    }

    private func clampToCorridor(_ x: CGFloat, scene: InPlaySKScene, edgeMargin: CGFloat) -> CGFloat {
        return max(scene.frame.minX + edgeMargin, min(scene.frame.maxX - edgeMargin, x))
    }

    // MARK: - Target picking

    /// Approach side for a target: prefer entering from whichever
    /// side the drone is currently on, so the connector path doesn't
    /// require a frame-crossing reversal. Within
    /// `alignmentThreshold` (drone roughly above target) fall back
    /// to space-based logic — pick the side with more lateral room
    /// and break ties with `orbitTurnDirection` so co-spawned Heavies
    /// fan apart.
    private func approachSide(for target: TowerEntity, currentDronePos: CGPoint, scene: InPlaySKScene) -> CGFloat {
        let alignmentThreshold: CGFloat = 40
        let dx = currentDronePos.x - target.worldPosition.x
        if abs(dx) >= alignmentThreshold {
            return dx > 0 ? 1 : -1
        }
        let leftSpace = target.worldPosition.x - scene.frame.minX
        let rightSpace = scene.frame.maxX - target.worldPosition.x
        if abs(leftSpace - rightSpace) < 16 { return orbitTurnDirection }
        return leftSpace > rightSpace ? -1 : 1
    }

    private func pickNextTarget(scene: InPlaySKScene, currentPos: CGPoint) -> TowerEntity? {
        var claimed = Set<ObjectIdentifier>()
        for entity in scene.entities {
            if let mine = entity as? MineBombEntity, let target = mine.targetTower {
                claimed.insert(ObjectIdentifier(target))
            }
            if let other = entity as? HeavyDroneEntity, other !== self,
               let target = other.currentTarget {
                claimed.insert(ObjectIdentifier(target))
            }
        }
        let allActive = (scene.towerPlacement?.towers ?? []).filter { tower in
            !(tower.stats?.isDisabled ?? true) && !claimed.contains(ObjectIdentifier(tower))
        }
        let fresh = allActive.filter { tower in
            !pickedTargets.contains(where: { $0 === tower })
        }
        let candidates = fresh.isEmpty ? allActive : fresh
        return candidates.min { a, b in
            hypot(a.worldPosition.x - currentPos.x, a.worldPosition.y - currentPos.y)
                < hypot(b.worldPosition.x - currentPos.x, b.worldPosition.y - currentPos.y)
        }
    }

    // MARK: - Speed / altitude helpers

    private func descendToAttackAltitude(spriteNode: SKSpriteNode) {
        component(ofType: AltitudeComponent.self)?.altitude = .medium
        spriteNode.removeAction(forKey: "altitudeScale")
        let descend = SKAction.scale(
            to: Constants.AdvancedEnemies.heavyDroneAttackSpriteScale,
            duration: Constants.AdvancedEnemies.heavyDroneDescendDuration
        )
        descend.timingMode = .easeIn
        spriteNode.run(descend, withKey: "altitudeScale")
        setVortexEmissionActive(true, in: spriteNode.scene)
    }

    private func climbToCruiseAltitude(spriteNode: SKSpriteNode) {
        component(ofType: AltitudeComponent.self)?.altitude = .high
        spriteNode.removeAction(forKey: "altitudeScale")
        let climb = SKAction.scale(
            to: 1.0,
            duration: Constants.AdvancedEnemies.heavyDroneClimbDuration
        )
        climb.timingMode = .easeOut
        spriteNode.run(climb, withKey: "altitudeScale")
        setVortexEmissionActive(false, in: nil)
    }

    // MARK: - Silhouette construction

    private func buildBayraktarSilhouette(on parent: SKSpriteNode, scale: CGFloat) {
        let bodyColor = UIColor(red: 0.23, green: 0.23, blue: 0.23, alpha: 1)
        let bodyStroke = UIColor(white: 0.05, alpha: 1)

        // Main wings — long thin horizontal bar with slight rear sweep.
        let wingPath = CGMutablePath()
        wingPath.move(to: CGPoint(x: -22 * scale, y:  3 * scale))
        wingPath.addLine(to: CGPoint(x:  22 * scale, y:  3 * scale))
        wingPath.addLine(to: CGPoint(x:  20 * scale, y: -1 * scale))
        wingPath.addLine(to: CGPoint(x: -20 * scale, y: -1 * scale))
        wingPath.closeSubpath()
        let wings = SKShapeNode(path: wingPath)
        wings.fillColor = bodyColor
        wings.strokeColor = bodyStroke
        wings.lineWidth = 0.5
        wings.position = CGPoint(x: 0, y: 5 * scale)
        wings.zPosition = 0
        parent.addChild(wings)

        // V-tail booms.
        let boomLength: CGFloat = 12 * scale
        let boomWidth: CGFloat = 1.8 * scale
        for sign: CGFloat in [-1, 1] {
            let boom = SKShapeNode(rectOf: CGSize(width: boomWidth, height: boomLength))
            boom.fillColor = bodyColor
            boom.strokeColor = bodyStroke
            boom.lineWidth = 0.5
            boom.position = CGPoint(x: sign * 6 * scale, y: -10 * scale)
            boom.zRotation = sign * .pi / 7
            boom.zPosition = 0
            parent.addChild(boom)
        }

        // V-tail horizontal surfaces.
        let surfaceLength: CGFloat = 6 * scale
        let surfaceWidth: CGFloat = 1.6 * scale
        for sign: CGFloat in [-1, 1] {
            let surf = SKShapeNode(rectOf: CGSize(width: surfaceLength, height: surfaceWidth))
            surf.fillColor = bodyColor
            surf.strokeColor = bodyStroke
            surf.lineWidth = 0.5
            surf.position = CGPoint(x: sign * 9 * scale, y: -16 * scale)
            surf.zPosition = 0
            parent.addChild(surf)
        }

        // Fuselage — long narrow body, nose forward.
        let fusePath = CGMutablePath()
        fusePath.move(to: CGPoint(x: 0, y: 17 * scale))
        fusePath.addLine(to: CGPoint(x:  2.5 * scale, y:  9 * scale))
        fusePath.addLine(to: CGPoint(x:  2.5 * scale, y: -12 * scale))
        fusePath.addLine(to: CGPoint(x: 0, y: -16 * scale))
        fusePath.addLine(to: CGPoint(x: -2.5 * scale, y: -12 * scale))
        fusePath.addLine(to: CGPoint(x: -2.5 * scale, y:  9 * scale))
        fusePath.closeSubpath()
        let fuselage = SKShapeNode(path: fusePath)
        fuselage.fillColor = bodyColor
        fuselage.strokeColor = bodyStroke
        fuselage.lineWidth = 0.5
        fuselage.zPosition = 1
        parent.addChild(fuselage)

        // Bayraktar SATCOM nose dome.
        let nose = SKShapeNode(circleOfRadius: 3 * scale)
        nose.fillColor = UIColor(white: 0.4, alpha: 1)
        nose.strokeColor = bodyStroke
        nose.lineWidth = 0.5
        nose.position = CGPoint(x: 0, y: 13 * scale)
        nose.zPosition = 2
        parent.addChild(nose)
    }

    private func attachUnderWingBombs(on parent: SKSpriteNode, scale: CGFloat) {
        let bombCount = Constants.AdvancedEnemies.heavyDroneBombCount
        let pylonPositions: [CGPoint] = [
            CGPoint(x: -13 * scale, y: -2 * scale),
            CGPoint(x:  13 * scale, y: -2 * scale),
        ]
        let bombHeight: CGFloat = 26 * scale
        let aspect: CGFloat
        let texture: SKTexture?
        if let img = UIImage(named: "bomb_aerial"), img.size.height > 0 {
            aspect = img.size.width / img.size.height
            texture = SKTexture(image: img)
        } else {
            aspect = 848.0 / 1264.0
            texture = nil
        }
        let bombSize = CGSize(width: bombHeight * aspect, height: bombHeight)
        for i in 0..<min(bombCount, pylonPositions.count) {
            let sprite: SKSpriteNode
            if let texture {
                sprite = SKSpriteNode(texture: texture, size: bombSize)
            } else {
                sprite = SKSpriteNode(color: UIColor(white: 0.18, alpha: 1), size: bombSize)
            }
            sprite.position = pylonPositions[i]
            sprite.zPosition = 0.5
            parent.addChild(sprite)
            underWingBombSprites.append(sprite)
        }
    }

    // MARK: - Vortex emitters

    private func attachWingtipVortexEmitters(on parent: SKSpriteNode, scale: CGFloat) {
        for sign: CGFloat in [-1, 1] {
            let emitter = makeWingtipVortexEmitter()
            emitter.position = CGPoint(x: sign * 22 * scale, y: 8 * scale)
            emitter.zPosition = -0.5
            parent.addChild(emitter)
            if sign < 0 {
                leftVortexEmitter = emitter
            } else {
                rightVortexEmitter = emitter
            }
        }
    }

    private func makeWingtipVortexEmitter() -> SKEmitterNode {
        let emitter = SKEmitterNode()
        emitter.particleTexture = HeavyDroneEntity.vortexParticleTexture
        emitter.particleBirthRate = 0
        emitter.particleLifetime = 0.7
        emitter.particleColor = .white
        emitter.particleColorBlendFactor = 1.0
        emitter.particleAlpha = 0.9
        emitter.particleAlphaRange = 0.1
        emitter.particleAlphaSpeed = -1.2
        emitter.particleScale = 0.7
        emitter.particleScaleRange = 0.2
        emitter.particleScaleSpeed = -0.4
        emitter.particleSpeed = 0
        emitter.emissionAngle = 0
        emitter.emissionAngleRange = 0
        emitter.particleZPosition = 50
        return emitter
    }

    private func setVortexEmissionActive(_ active: Bool, in scene: SKScene?) {
        let rate: CGFloat = active
            ? Constants.AdvancedEnemies.heavyDroneVortexBirthRate
            : 0
        for emitter in [leftVortexEmitter, rightVortexEmitter].compactMap({ $0 }) {
            emitter.particleBirthRate = rate
            // Anchor particles to the scene the first time we activate
            // so they don't ride the rotating drone parent — gives the
            // trail.
            if active, emitter.targetNode == nil, let scene {
                emitter.targetNode = scene
            }
        }
    }

    // MARK: - Off-screen indicator (Jetpack-Joyride style)

    private func updateOffscreenIndicator(in scene: InPlaySKScene) {
        guard let dronePos = component(ofType: SpriteComponent.self)?.spriteNode.position else { return }
        let leftEdge: CGFloat = 0
        let rightEdge = scene.frame.width
        let edgeMargin: CGFloat = 18

        let isOff = dronePos.x < leftEdge || dronePos.x > rightEdge
        guard isOff else {
            offscreenIndicator?.removeFromParent()
            offscreenIndicator = nil
            return
        }

        if offscreenIndicator == nil {
            let node = makeOffscreenIndicator()
            scene.addChild(node)
            offscreenIndicator = node
        }
        guard let indicator = offscreenIndicator else { return }

        let clampedY = min(
            max(dronePos.y, scene.safeBottom + 30),
            scene.frame.height - scene.safeTop - 30
        )
        let arrow = indicator.childNode(withName: "//offscreenArrow")
        if dronePos.x < leftEdge {
            indicator.position = CGPoint(x: edgeMargin, y: clampedY)
            arrow?.zRotation = .pi
            arrow?.position = CGPoint(x: -10, y: 0)
        } else {
            indicator.position = CGPoint(x: rightEdge - edgeMargin, y: clampedY)
            arrow?.zRotation = 0
            arrow?.position = CGPoint(x: 10, y: 0)
        }
    }

    private func makeOffscreenIndicator() -> SKNode {
        let node = SKNode()
        node.zPosition = 98
        let pulseHost = SKNode()
        pulseHost.name = "pulseHost"
        node.addChild(pulseHost)

        let label = SKLabelNode(fontNamed: Constants.GameBalance.hudFontName)
        label.text = "!"
        label.fontSize = 22
        label.fontColor = .red
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        pulseHost.addChild(label)

        let arrow = SKShapeNode()
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 8, y: 0))
        path.addLine(to: CGPoint(x: 0, y: 6))
        path.addLine(to: CGPoint(x: 0, y: -6))
        path.closeSubpath()
        arrow.path = path
        arrow.fillColor = .red
        arrow.strokeColor = .clear
        arrow.name = "offscreenArrow"
        pulseHost.addChild(arrow)

        let pulse = SKAction.sequence([
            SKAction.scale(to: 1.15, duration: 0.4),
            SKAction.scale(to: 0.9, duration: 0.4)
        ])
        pulseHost.run(SKAction.repeatForever(pulse))
        return node
    }

    // MARK: - Bomb release

    private func launchBomb(at target: TowerEntity, from spriteNode: SKSpriteNode, in scene: InPlaySKScene) {
        let releaseWorldPos: CGPoint
        let releaseSize: CGSize
        if let pylonSprite = underWingBombSprites.first {
            releaseWorldPos = scene.convert(pylonSprite.position, from: spriteNode)
            releaseSize = pylonSprite.size
            pylonSprite.removeFromParent()
            underWingBombSprites.removeFirst()
        } else {
            releaseWorldPos = CGPoint(x: spriteNode.position.x,
                                      y: spriteNode.position.y - 20)
            releaseSize = CGSize(width: 7, height: 18)
        }

        let dropDuration: TimeInterval = 1.1
        let bomb = MineBombEntity()
        bomb.place(at: releaseWorldPos)
        bomb.configureOrigin(isFromCrashedDrone: false, sourceDrone: self)
        bomb.targetTower = target
        bomb.damage = Constants.AdvancedEnemies.heavyDroneBombDamage
        scene.addEntity(bomb)

        guard let bombSprite = bomb.component(ofType: SpriteComponent.self)?.spriteNode else {
            return
        }
        if UIImage(named: "bomb_aerial") != nil {
            bombSprite.texture = SKTexture(imageNamed: "bomb_aerial")
        }
        bombSprite.size = releaseSize
        bombSprite.zRotation = spriteNode.zRotation
        bombSprite.zPosition = 80
        if let body = bombSprite.physicsBody {
            body.affectedByGravity = false
            body.velocity = .zero
            body.categoryBitMask = 0
        }

        let glide = SKAction.move(to: target.worldPosition, duration: dropDuration)
        glide.timingMode = .easeIn
        let shrink = SKAction.scale(to: 0.6, duration: dropDuration)
        shrink.timingMode = .easeIn
        let hit = SKAction.run { [weak bomb, weak target, weak scene] in
            guard let bomb, let scene else { return }
            if let target {
                scene.onBombHitTower(bomb, tower: target)
            } else {
                bomb.silentDetonate()
            }
        }
        bombSprite.run(SKAction.sequence([
            SKAction.group([glide, shrink]),
            hit
        ]), withKey: "heavyAirDropFall")

        // Release flash anchored to the drone — separation cue.
        let flash = SKShapeNode(circleOfRadius: 6)
        flash.fillColor = .orange
        flash.strokeColor = .clear
        flash.position = releaseWorldPos
        flash.zPosition = scene.isNightWave ? Constants.NightWave.nightEffectZPosition : 50
        flash.alpha = 0.9
        scene.addChild(flash)
        flash.run(SKAction.sequence([
            SKAction.group([
                SKAction.scale(to: 2.0, duration: 0.15),
                SKAction.fadeOut(withDuration: 0.15)
            ]),
            SKAction.removeFromParent()
        ]))
    }

    // MARK: - Death / cleanup

    override func didHit() {
        isHit = true
        offscreenIndicator?.removeFromParent()
        offscreenIndicator = nil

        let physicBody = component(ofType: GeometryComponent.self)?.geometryNode.physicsBody
        physicBody?.contactTestBitMask = 0
        physicBody?.categoryBitMask = 0

        if let spriteNode = component(ofType: SpriteComponent.self)?.spriteNode {
            let flash = SKShapeNode(circleOfRadius: 16)
            flash.fillColor = .orange
            flash.strokeColor = .clear
            flash.position = spriteNode.position
            flash.zPosition = (spriteNode.scene as? InPlaySKScene)?.isNightWave == true
                ? Constants.NightWave.nightEffectZPosition
                : 55
            flash.alpha = 0.9
            spriteNode.scene?.addChild(flash)

            let expand = SKAction.scale(to: 3.0, duration: 0.25)
            let fade = SKAction.fadeOut(withDuration: 0.25)
            flash.run(SKAction.sequence([SKAction.group([expand, fade]), SKAction.removeFromParent()]))

            spriteNode.run(SKAction.sequence([
                SKAction.fadeOut(withDuration: 0.15),
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

    override func removeFromParent() {
        offscreenIndicator?.removeFromParent()
        offscreenIndicator = nil
        super.removeFromParent()
    }
}
