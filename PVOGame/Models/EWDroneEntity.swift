//
//  EWDroneEntity.swift
//  PVOGame
//

import Foundation
import GameplayKit
import SpriteKit

final class EWDroneEntity: AttackDroneEntity {

    private var waypoints: [CGPoint] = []
    private var currentWaypointIndex = 0
    private var velocity: CGVector = .zero
    private var homePoint: CGPoint = .zero
    private var heading: CGFloat = -.pi / 2
    private var angularVelocity: CGFloat = 0
    private var isReturningToBase = false
    private var lightningTimer: TimeInterval = 0
    /// Randomized delay until next lightning discharge.
    private var nextLightningDelay: TimeInterval = Constants.EW.ewLightningInitialDelay
    private let waypointArrivalRadius: CGFloat = Constants.EW.ewDroneWaypointArrivalRadius

    let effectRadius: CGFloat = Constants.EW.ewDroneEffectRadius

    init(sceneFrame: CGRect) {
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
            damage: 0,
            speed: Constants.EW.ewDroneSpeed,
            imageName: "Drone",
            flyingPath: dummyPath
        )
        removeComponent(ofType: FlyingProjectileComponent.self)
        configureHealth(Constants.EW.ewDroneHealth)

        // Purple/magenta EW drone
        if let spriteNode = component(ofType: SpriteComponent.self)?.spriteNode {
            spriteNode.size = CGSize(width: Constants.SpriteSize.ewDrone, height: Constants.SpriteSize.ewDrone)
            if let tex = AnimationTextureCache.shared.droneTextures["drone_ew"] {
                spriteNode.texture = tex
                spriteNode.color = .white
                spriteNode.colorBlendFactor = 0
            } else {
                spriteNode.color = UIColor(red: 0.6, green: 0.2, blue: 0.8, alpha: 1)
                spriteNode.colorBlendFactor = 1.0
            }
        }

        addNavLights(wingspan: 20)
    }

    required init(damage: CGFloat, speed: CGFloat, imageName: String, flyingPath: FlyingPath) {
        super.init(damage: damage, speed: speed, imageName: imageName, flyingPath: flyingPath)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configureFlight(from spawnPoint: CGPoint, to target: CGPoint, speed ewSpeed: CGFloat) {
        configureSweepRoute(from: spawnPoint, waypoints: [target], speed: ewSpeed)
    }

    func configureSweepRoute(from spawnPoint: CGPoint, waypoints route: [CGPoint], speed ewSpeed: CGFloat) {
        self.speed = ewSpeed
        self.waypoints = route
        self.currentWaypointIndex = 0
        self.homePoint = spawnPoint
        self.isReturningToBase = false
        self.angularVelocity = 0

        if let spriteNode = component(ofType: SpriteComponent.self)?.spriteNode {
            spriteNode.position = spawnPoint
        }

        updateVelocityTowardCurrentWaypoint()
        resetEscortPoseHistory()
    }

    private func updateVelocityTowardCurrentWaypoint() {
        guard currentWaypointIndex < waypoints.count,
              let spriteNode = component(ofType: SpriteComponent.self)?.spriteNode else {
            velocity = .zero
            return
        }

        let target = waypoints[currentWaypointIndex]
        let dx = target.x - spriteNode.position.x
        let dy = target.y - spriteNode.position.y
        let dist = sqrt(dx * dx + dy * dy)
        guard dist > waypointArrivalRadius else {
            advanceToNextWaypoint()
            return
        }

        let dirX = dx / dist
        let dirY = dy / dist
        velocity = CGVector(dx: dirX * speed, dy: dirY * speed)

        heading = atan2(dy, dx)
        spriteNode.zRotation = heading - .pi / 2
    }

    private func advanceToNextWaypoint() {
        currentWaypointIndex += 1
        if currentWaypointIndex >= waypoints.count {
            reachedDestination()
        }
    }

    override func update(deltaTime seconds: TimeInterval) {
        guard !isHit else { return }
        guard let spriteNode = component(ofType: SpriteComponent.self)?.spriteNode else { return }

        if !isReturningToBase && !hasActiveTowerTargets(from: spriteNode) {
            beginReturnToBase()
        }

        if currentWaypointIndex < waypoints.count {
            let target = waypoints[currentWaypointIndex]
            let dx = target.x - spriteNode.position.x
            let dy = target.y - spriteNode.position.y
            let dist = sqrt(dx * dx + dy * dy)

            if dist <= waypointArrivalRadius {
                advanceToNextWaypoint()
                if currentWaypointIndex >= waypoints.count { return }
            } else {
                steerToward(target, from: spriteNode, deltaTime: CGFloat(seconds))
            }
        } else {
            reachedDestination()
            return
        }

        recordEscortPose(deltaTime: seconds)

        // Crackling EW lightning instead of a persistent radius effect.
        lightningTimer += seconds
        if lightningTimer >= nextLightningDelay {
            lightningTimer = 0
            nextLightningDelay = TimeInterval.random(
                in: Constants.EW.ewLightningDelayMin...Constants.EW.ewLightningDelayMax
            )
            spawnEWLightning(at: spriteNode)
        }

    }

    private func beginReturnToBase() {
        isReturningToBase = true
        waypoints = [homePoint]
        currentWaypointIndex = 0
        angularVelocity = 0
    }

    private func hasActiveTowerTargets(from spriteNode: SKSpriteNode) -> Bool {
        guard let scene = spriteNode.scene as? InPlaySKScene,
              let towerPlacement = scene.towerPlacement else { return true }
        return towerPlacement.towers.contains { tower in
            guard let stats = tower.stats else { return false }
            return !stats.isDisabled
        }
    }

    private func steerToward(_ target: CGPoint, from spriteNode: SKSpriteNode, deltaTime dt: CGFloat) {
        let pos = spriteNode.position
        let dx = target.x - pos.x
        let dy = target.y - pos.y
        let dist = max(1, sqrt(dx * dx + dy * dy))
        let desiredHeading = atan2(dy / dist, dx / dist)
        let headingDelta = normalizedAngle(desiredHeading - heading)

        let maxTurnRate = Constants.EW.ewDroneSpeed / Constants.EW.ewDroneMinTurnRadius
        let maxAngularAcceleration = Constants.EW.ewDroneAngularAcceleration
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

        let step = speed * dt
        spriteNode.position = CGPoint(
            x: pos.x + cos(heading) * step,
            y: pos.y + sin(heading) * step
        )
        spriteNode.zRotation = heading - .pi / 2
        velocity = CGVector(dx: cos(heading) * speed, dy: sin(heading) * speed)
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

    /// Spawns a short, layered EW discharge. Procedural paths provide the
    /// moving shape; small optional sprites keep the effect in the painted VFX
    /// family when generated assets are available.
    private func spawnEWLightning(at spriteNode: SKSpriteNode) {
        let towerTargets = activeTowerTargets(inRangeOf: spriteNode)
        if towerTargets.isEmpty {
            spawnAmbientLightning(at: spriteNode)
        } else {
            spawnAttackLightning(from: spriteNode, toward: towerTargets)
        }

        applyLightningDamage(to: towerTargets)
    }

    private func activeTowerTargets(inRangeOf spriteNode: SKSpriteNode) -> [TowerEntity] {
        guard let scene = spriteNode.scene as? InPlaySKScene,
              let towerPlacement = scene.towerPlacement else { return [] }
        let dronePos = spriteNode.position
        let radiusSq = effectRadius * effectRadius

        return towerPlacement.towers.filter { tower in
            guard let stats = tower.stats, !stats.isDisabled else { return false }
            let towerPos = tower.worldPosition
            let dx = towerPos.x - dronePos.x
            let dy = towerPos.y - dronePos.y
            return dx * dx + dy * dy <= radiusSq
        }
    }

    private func spawnAttackLightning(from spriteNode: SKSpriteNode, toward towers: [TowerEntity]) {
        guard let scene = spriteNode.scene else {
            spawnAmbientLightning(at: spriteNode)
            return
        }

        let arcZPosition = absoluteLightningZ(for: spriteNode, offset: -1)
        let origin = spriteNode.position
        let selectedTargets = visualLightningTargets(from: towers, origin: origin)

        for tower in selectedTargets {
            let target = tower.worldPosition
            let endpointJitter = Constants.EW.ewLightningTargetEndpointJitter
            let end = CGPoint(
                x: target.x + CGFloat.random(in: -endpointJitter...endpointJitter),
                y: target.y + CGFloat.random(in: -endpointJitter...endpointJitter)
            )
            let start = lightningStartPoint(from: origin, toward: end)
            let spawned = spawnProceduralLightningArc(
                on: scene,
                start: start,
                end: end,
                zPosition: arcZPosition,
                branchCount: Int.random(
                    in: Constants.EW.ewLightningAttackBranchCountMin...Constants.EW.ewLightningAttackBranchCountMax
                ),
                addEndpointAccents: true
            )
            if !spawned {
                let angle = atan2(end.y - origin.y, end.x - origin.x) - spriteNode.zRotation
                spawnLegacySpriteBolt(at: spriteNode, angle: angle)
            }
        }

        if selectedTargets.count == 1 && Bool.random() {
            spawnAmbientLightning(at: spriteNode, countOverride: 1)
        }
    }

    private func visualLightningTargets(from towers: [TowerEntity], origin: CGPoint) -> [TowerEntity] {
        let sorted = towers.sorted { lhs, rhs in
            distanceSquared(lhs.worldPosition, origin) < distanceSquared(rhs.worldPosition, origin)
        }
        let candidateCount = min(Constants.EW.ewLightningVisualCandidateLimit, sorted.count)
        guard candidateCount > 0 else { return [] }
        let arcCount = Int.random(in: 1...min(Constants.EW.ewLightningVisualTargetLimit, candidateCount))
        return Array(sorted.prefix(candidateCount).shuffled().prefix(arcCount))
    }

    private func spawnAmbientLightning(at spriteNode: SKSpriteNode, countOverride: Int? = nil) {
        let arcZPosition = relativeZPos(under: spriteNode, offset: -1)
        let count = countOverride ?? Int.random(
            in: Constants.EW.ewLightningAmbientArcCountMin...Constants.EW.ewLightningAmbientArcCountMax
        )

        for _ in 0..<count {
            let angle = CGFloat.random(in: 0..<(.pi * 2))
            let innerRadius = CGFloat.random(
                in: Constants.EW.ewLightningAmbientInnerRadiusMin...Constants.EW.ewLightningAmbientInnerRadiusMax
            )
            let length = CGFloat.random(
                in: Constants.EW.ewLightningAmbientLengthMin...min(
                    Constants.EW.ewLightningAmbientLengthMax,
                    effectRadius * Constants.EW.ewLightningAmbientLengthRadiusRatio
                )
            )
            let perp = angle + .pi / 2
            let startJitter = Constants.EW.ewLightningAmbientStartJitter
            let endJitter = Constants.EW.ewLightningAmbientEndJitter
            let start = CGPoint(
                x: cos(angle) * innerRadius + cos(perp) * CGFloat.random(in: -startJitter...startJitter),
                y: sin(angle) * innerRadius + sin(perp) * CGFloat.random(in: -startJitter...startJitter)
            )
            let end = CGPoint(
                x: cos(angle) * length + cos(perp) * CGFloat.random(in: -endJitter...endJitter),
                y: sin(angle) * length + sin(perp) * CGFloat.random(in: -endJitter...endJitter)
            )
            let spawned = spawnProceduralLightningArc(
                on: spriteNode,
                start: start,
                end: end,
                zPosition: arcZPosition,
                branchCount: Int.random(
                    in: Constants.EW.ewLightningAmbientBranchCountMin...Constants.EW.ewLightningAmbientBranchCountMax
                ),
                addEndpointAccents: false
            )
            if !spawned {
                spawnLegacySpriteBolt(at: spriteNode, angle: angle)
            }
        }
    }

    /// Each discharge damages active towers inside the EW effect radius.
    private func applyLightningDamage(to towers: [TowerEntity]) {
        for tower in towers {
            tower.takeBombDamage(Constants.EW.ewLightningTowerDamage)
        }
    }

    @discardableResult
    private func spawnProceduralLightningArc(on parent: SKNode,
                                             start: CGPoint,
                                             end: CGPoint,
                                             zPosition: CGFloat,
                                             branchCount: Int,
                                             addEndpointAccents: Bool) -> Bool {
        let points = lightningPoints(from: start, to: end)
        guard points.count >= 2 else { return false }

        let container = SKNode()
        container.zPosition = zPosition
        container.alpha = 0
        parent.addChild(container)

        addLightningLayers(path: path(from: points), to: container, widthScale: 1.0)

        let branchPaths = lightningBranchPaths(from: points, maxCount: branchCount)
        for branchPath in branchPaths {
            addLightningLayers(path: branchPath,
                               to: container,
                               widthScale: Constants.EW.ewLightningBranchWidthScale)
        }

        let cache = AnimationTextureCache.shared
        if addEndpointAccents {
            addTerminalFork(to: container, points: points)
            addLightningAccent(cache.ewHitFlash,
                               to: container,
                               at: end,
                               size: Constants.EW.ewLightningHitFlashSize,
                               fallbackColor: UIColor(red: 0.85, green: 0.25, blue: 1.0, alpha: 0.45))
            addLightningEndpointSpriteNode(to: container, points: points)
        }

        if let sparkPoint = points.dropFirst().dropLast().randomElement() {
            addLightningAccent(cache.ewSparkCluster,
                               to: container,
                               at: sparkPoint,
                               size: Constants.EW.ewLightningSparkClusterSize,
                               fallbackColor: nil)
        }

        container.run(lightningFlickerAction(duration: Constants.EW.ewLightningDuration))
        return true
    }

    private func addTerminalFork(to container: SKNode, points: [CGPoint]) {
        guard points.count >= 2,
              let end = points.last else { return }
        let previous = points[points.count - 2]
        let dx = end.x - previous.x
        let dy = end.y - previous.y
        let length = max(1, sqrt(dx * dx + dy * dy))
        let angle = atan2(dy / length, dx / length)
        let forkLength = CGFloat.random(
            in: Constants.EW.ewLightningTerminalForkLengthMin...Constants.EW.ewLightningTerminalForkLengthMax
        )
        let splitAngle = CGFloat.random(
            in: Constants.EW.ewLightningTerminalForkSplitAngleMin...Constants.EW.ewLightningTerminalForkSplitAngleMax
        )

        for side in [-1.0, 1.0] {
            let forkAngle = angle + CGFloat(side) * splitAngle
            let tip = CGPoint(
                x: end.x + cos(forkAngle) * forkLength,
                y: end.y + sin(forkAngle) * forkLength
            )
            addLightningLayers(path: path(from: [end, tip]),
                               to: container,
                               widthScale: Constants.EW.ewLightningTerminalForkWidthScale)
        }
    }

    private func addLightningEndpointSpriteNode(to container: SKNode, points: [CGPoint]) {
        guard points.count >= 2,
              let end = points.last else { return }
        let previous = points[points.count - 2]
        let dx = end.x - previous.x
        let dy = end.y - previous.y
        let incomingAngle = atan2(dy, dx)
        let backAngle = incomingAngle + .pi
        let sideAngle = incomingAngle + .pi / 2

        let endpoint = SKNode()
        endpoint.position = end
        endpoint.zPosition = 0.8
        container.addChild(endpoint)

        let pinchGlowSize = CGSize(width: Constants.EW.ewLightningEndpointPinchSize.width * 2.0,
                                   height: Constants.EW.ewLightningEndpointPinchSize.height * 2.0)
        addEndpointSprite(to: endpoint,
                          color: UIColor(red: 0.75, green: 0.10, blue: 1.0, alpha: 0.55),
                          size: pinchGlowSize,
                          position: .zero,
                          angle: CGFloat.random(in: 0..<(.pi * 2)),
                          anchorPoint: CGPoint(x: 0.5, y: 0.5))
        addEndpointSprite(to: endpoint,
                          color: UIColor(red: 0.88, green: 1.0, blue: 1.0, alpha: 0.95),
                          size: Constants.EW.ewLightningEndpointPinchSize,
                          position: .zero,
                          angle: CGFloat.random(in: 0..<(.pi * 2)),
                          anchorPoint: CGPoint(x: 0.5, y: 0.5))

        let strokeCount = Int.random(
            in: Constants.EW.ewLightningEndpointStrokeCountMin...Constants.EW.ewLightningEndpointStrokeCountMax
        )
        let centerIndex = CGFloat(strokeCount - 1) * 0.5

        for index in 0..<strokeCount {
            let normalizedSide = (CGFloat(index) - centerIndex) / max(1, centerIndex)
            let sideOffset = normalizedSide * Constants.EW.ewLightningEndpointSideOffset
                + CGFloat.random(in: -1.2...1.2)
            let backOffset = CGFloat.random(in: 0...Constants.EW.ewLightningEndpointBackOffset)
            let position = CGPoint(
                x: cos(backAngle) * backOffset + cos(sideAngle) * sideOffset,
                y: sin(backAngle) * backOffset + sin(sideAngle) * sideOffset
            )
            let angle = backAngle
                + normalizedSide * Constants.EW.ewLightningEndpointStrokeSpread
                + CGFloat.random(in: -0.22...0.22)
            let length = CGFloat.random(
                in: Constants.EW.ewLightningEndpointStrokeLengthMin...Constants.EW.ewLightningEndpointStrokeLengthMax
            )
            addEndpointStroke(to: endpoint, position: position, angle: angle, length: length)
        }
    }

    private func addEndpointStroke(to parent: SKNode,
                                   position: CGPoint,
                                   angle: CGFloat,
                                   length: CGFloat) {
        addEndpointSprite(to: parent,
                          color: UIColor(red: 0.70, green: 0.05, blue: 1.0, alpha: 0.48),
                          size: CGSize(width: length,
                                       height: Constants.EW.ewLightningEndpointOuterStrokeWidth),
                          position: position,
                          angle: angle,
                          anchorPoint: CGPoint(x: 0.0, y: 0.5))
        addEndpointSprite(to: parent,
                          color: UIColor(red: 0.92, green: 1.0, blue: 1.0, alpha: 0.92),
                          size: CGSize(width: length * 0.68,
                                       height: Constants.EW.ewLightningEndpointCoreStrokeWidth),
                          position: position,
                          angle: angle,
                          anchorPoint: CGPoint(x: 0.0, y: 0.5))
    }

    private func addEndpointSprite(to parent: SKNode,
                                   color: UIColor,
                                   size: CGSize,
                                   position: CGPoint,
                                   angle: CGFloat,
                                   anchorPoint: CGPoint) {
        let sprite = SKSpriteNode(color: color, size: size)
        sprite.position = position
        sprite.anchorPoint = anchorPoint
        sprite.zRotation = angle
        sprite.blendMode = .add
        parent.addChild(sprite)
    }

    private func lightningPoints(from start: CGPoint, to end: CGPoint) -> [CGPoint] {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let distance = max(1, sqrt(dx * dx + dy * dy))
        guard distance >= Constants.EW.ewLightningMinArcLength else { return [] }

        let segmentCount = max(
            Constants.EW.ewLightningSegmentMin,
            min(Constants.EW.ewLightningSegmentMax,
                Int(distance / Constants.EW.ewLightningSegmentTargetLength))
        )
        let unitX = dx / distance
        let unitY = dy / distance
        let perpX = -unitY
        let perpY = unitX
        let maxJitter = min(
            Constants.EW.ewLightningJitterMax,
            max(Constants.EW.ewLightningJitterMin,
                distance * Constants.EW.ewLightningJitterDistanceRatio)
        )

        var points: [CGPoint] = [start]
        var previousSign: CGFloat = Bool.random() ? 1 : -1
        for index in 1..<segmentCount {
            let t = CGFloat(index) / CGFloat(segmentCount)
            let base = CGPoint(x: start.x + dx * t, y: start.y + dy * t)
            let shouldFlip = CGFloat.random(in: Constants.EW.ewLightningJitterMinFactor...1.0)
                > Constants.EW.ewLightningJitterFlipThreshold
            previousSign *= shouldFlip ? -1 : 1
            let jitter = previousSign
                * CGFloat.random(in: maxJitter * Constants.EW.ewLightningJitterMinFactor...maxJitter)
                * sin(.pi * t)
            points.append(CGPoint(x: base.x + perpX * jitter,
                                  y: base.y + perpY * jitter))
        }
        points.append(end)
        return points
    }

    private func lightningBranchPaths(from points: [CGPoint], maxCount: Int) -> [CGPath] {
        guard maxCount > 0, points.count >= 4 else { return [] }
        let branchCount = min(maxCount, Int.random(in: 0...maxCount))
        guard branchCount > 0 else { return [] }

        var paths: [CGPath] = []
        var usedIndices = Set<Int>()
        for _ in 0..<branchCount {
            let candidates = Array(1..<(points.count - 1)).filter { !usedIndices.contains($0) }
            guard let index = candidates.randomElement() else { break }
            usedIndices.insert(index)

            let anchor = points[index]
            let before = points[max(0, index - 1)]
            let after = points[min(points.count - 1, index + 1)]
            let tangentX = after.x - before.x
            let tangentY = after.y - before.y
            let tangentLength = max(1, sqrt(tangentX * tangentX + tangentY * tangentY))
            let normalizedTangent = CGVector(dx: tangentX / tangentLength,
                                             dy: tangentY / tangentLength)
            let side: CGFloat = Bool.random() ? 1 : -1
            let angle = atan2(normalizedTangent.dy, normalizedTangent.dx)
                + side * CGFloat.random(
                    in: Constants.EW.ewLightningBranchAngleMin...Constants.EW.ewLightningBranchAngleMax
                )
            let length = CGFloat.random(
                in: Constants.EW.ewLightningBranchLengthMin...Constants.EW.ewLightningBranchLengthMax
            )
            let midpointOffset = Constants.EW.ewLightningBranchMidpointOffsetFactor
            let midpointJitter = Constants.EW.ewLightningBranchMidpointJitter
            let mid = CGPoint(
                x: anchor.x + cos(angle) * length * midpointOffset
                    + cos(angle + .pi / 2) * CGFloat.random(in: -midpointJitter...midpointJitter),
                y: anchor.y + sin(angle) * length * midpointOffset
                    + sin(angle + .pi / 2) * CGFloat.random(in: -midpointJitter...midpointJitter)
            )
            let tip = CGPoint(
                x: anchor.x + cos(angle) * length,
                y: anchor.y + sin(angle) * length
            )
            paths.append(path(from: [anchor, mid, tip]))
        }
        return paths
    }

    private func path(from points: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        guard let first = points.first else { return path }
        path.move(to: first)
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        return path
    }

    private func addLightningLayers(path: CGPath, to container: SKNode, widthScale: CGFloat) {
        let layers: [(UIColor, CGFloat, CGFloat, CGFloat)] = [
            (UIColor(red: 0.50, green: 0.05, blue: 1.00, alpha: 1.0),
             Constants.EW.ewLightningOuterLineWidth,
             Constants.EW.ewLightningOuterGlowWidth,
             Constants.EW.ewLightningOuterLayerAlpha),
            (UIColor(red: 0.95, green: 0.20, blue: 1.00, alpha: 1.0),
             Constants.EW.ewLightningBodyLineWidth,
             Constants.EW.ewLightningBodyGlowWidth,
             Constants.EW.ewLightningBodyLayerAlpha),
            (UIColor(red: 0.92, green: 1.00, blue: 1.00, alpha: 1.0),
             Constants.EW.ewLightningCoreLineWidth,
             0.0,
             Constants.EW.ewLightningCoreLayerAlpha)
        ]

        for (color, lineWidth, glowWidth, alpha) in layers {
            let node = SKShapeNode(path: path)
            node.strokeColor = color
            node.fillColor = .clear
            node.lineWidth = lineWidth * widthScale
            node.glowWidth = glowWidth * widthScale
            node.alpha = alpha
            node.blendMode = .add
            container.addChild(node)
        }
    }

    private func addLightningAccent(_ texture: SKTexture?,
                                    to container: SKNode,
                                    at position: CGPoint,
                                    size: CGSize,
                                    fallbackColor: UIColor?) {
        if let texture = texture {
            let node = SKSpriteNode(texture: texture, size: size)
            node.position = position
            node.zRotation = CGFloat.random(in: 0..<(.pi * 2))
            node.alpha = Constants.EW.ewLightningAccentSpriteAlpha
            node.blendMode = .add
            container.addChild(node)
        } else if let fallbackColor = fallbackColor {
            let node = SKShapeNode(circleOfRadius: min(size.width, size.height) * 0.5)
            node.position = position
            node.fillColor = fallbackColor
            node.strokeColor = .clear
            node.glowWidth = min(size.width, size.height) * Constants.EW.ewLightningFallbackGlowScale
            node.alpha = Constants.EW.ewLightningFallbackAccentAlpha
            node.blendMode = .add
            container.addChild(node)
        }
    }

    private func spawnLightningAccent(_ texture: SKTexture?,
                                      at position: CGPoint,
                                      on parent: SKNode,
                                      zPosition: CGFloat,
                                      size: CGSize,
                                      fallbackColor: UIColor?) {
        let container = SKNode()
        container.position = .zero
        container.zPosition = zPosition
        container.alpha = 0
        parent.addChild(container)
        addLightningAccent(texture, to: container, at: position, size: size, fallbackColor: fallbackColor)
        container.run(lightningFlickerAction(duration: Constants.EW.ewLightningAccentDuration))
    }

    private func lightningFlickerAction(duration: TimeInterval) -> SKAction {
        SKAction.sequence([
            SKAction.fadeAlpha(to: 1.0, duration: Constants.EW.ewLightningFlickerInDuration),
            SKAction.fadeAlpha(to: Constants.EW.ewLightningFlickerDimAlpha,
                               duration: Constants.EW.ewLightningFlickerDimDuration),
            SKAction.fadeAlpha(to: Constants.EW.ewLightningFlickerReturnAlpha,
                               duration: Constants.EW.ewLightningFlickerInDuration),
            SKAction.wait(forDuration: max(Constants.EW.ewLightningFlickerMinHold,
                                           duration - lightningFlickerFixedDuration())),
            SKAction.fadeOut(withDuration: Constants.EW.ewLightningFlickerOutDuration),
            SKAction.removeFromParent()
        ])
    }

    private func lightningFlickerFixedDuration() -> TimeInterval {
        Constants.EW.ewLightningFlickerInDuration
            + Constants.EW.ewLightningFlickerDimDuration
            + Constants.EW.ewLightningFlickerInDuration
            + Constants.EW.ewLightningFlickerOutDuration
    }

    private func lightningStartPoint(from origin: CGPoint, toward end: CGPoint) -> CGPoint {
        let dx = end.x - origin.x
        let dy = end.y - origin.y
        let distance = max(1, sqrt(dx * dx + dy * dy))
        let unitX = dx / distance
        let unitY = dy / distance
        let perpX = -unitY
        let perpY = unitX
        let forwardOffset = CGFloat.random(
            in: Constants.EW.ewLightningOriginForwardOffsetMin...Constants.EW.ewLightningOriginForwardOffsetMax
        )
        let sideOffset = CGFloat.random(
            in: -Constants.EW.ewLightningOriginSideOffset...Constants.EW.ewLightningOriginSideOffset
        )
        return CGPoint(
            x: origin.x + unitX * forwardOffset + perpX * sideOffset,
            y: origin.y + unitY * forwardOffset + perpY * sideOffset
        )
    }

    private func distanceSquared(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = a.x - b.x
        let dy = a.y - b.y
        return dx * dx + dy * dy
    }

    private func spawnLegacySpriteBolt(at spriteNode: SKSpriteNode, angle: CGFloat) {
        guard let texture = AnimationTextureCache.shared.ewBoltTextures.randomElement() else {
            spawnFallbackBolt(parent: spriteNode, angle: angle)
            return
        }
        let bolt = SKSpriteNode(texture: texture)
        // Anchor at the top-center of the sprite so the drone sits at the
        // bolt's origin and the bolt extends outward in the rotation direction.
        bolt.anchorPoint = CGPoint(x: 0.5, y: 1.0)
        // Uniform scale: keep the PNG's native aspect ratio. Long axis of the
        // sprite lands at effectRadius / 1.5 ≈ 100 pt in scene units.
        let texSize = texture.size()
        let scale = (effectRadius / 1.5) / max(texSize.width, texSize.height)
        bolt.setScale(scale)
        bolt.position = .zero
        // Local -y → drone-local direction `angle` ⇒ zRotation = angle + π/2.
        bolt.zRotation = angle + .pi / 2
        bolt.alpha = 0.95
        bolt.blendMode = .add
        bolt.zPosition = relativeZPos(under: spriteNode, offset: -1)
        spriteNode.addChild(bolt)

        bolt.run(SKAction.sequence([
            SKAction.fadeOut(withDuration: 0.18),
            SKAction.removeFromParent()
        ]))
    }

    private func absoluteLightningZ(for spriteNode: SKSpriteNode, offset: CGFloat) -> CGFloat {
        let isNight = (spriteNode.scene as? InPlaySKScene)?.isNightWave == true
        return isNight ? Constants.NightWave.nightEffectZPosition : spriteNode.zPosition + offset
    }

    /// SpriteKit applies child zPositions cumulatively — child world z =
    /// parent.zPosition + child.zPosition. Returns the relative zPosition that
    /// produces the desired absolute target (night-wave overlay or sibling +
    /// offset).
    private func relativeZPos(under parent: SKSpriteNode, offset: CGFloat) -> CGFloat {
        let isNight = (parent.scene as? InPlaySKScene)?.isNightWave == true
        let absoluteTarget = isNight
            ? Constants.NightWave.nightEffectZPosition
            : parent.zPosition + offset
        return absoluteTarget - parent.zPosition
    }

    private func spawnFallbackBolt(parent: SKSpriteNode, angle: CGFloat) {
        let dist = effectRadius
        let endpoint = CGPoint(x: cos(angle) * dist, y: sin(angle) * dist)
        let perpX = -sin(angle)
        let perpY = cos(angle)

        let path = CGMutablePath()
        path.move(to: .zero)
        let segmentCount = Int.random(in: 4...6)
        let maxJitter = max(8, dist * 0.15)
        for i in 1..<segmentCount {
            let t = CGFloat(i) / CGFloat(segmentCount)
            let baseX = endpoint.x * t
            let baseY = endpoint.y * t
            let jitter = CGFloat.random(in: -maxJitter...maxJitter)
            path.addLine(to: CGPoint(x: baseX + perpX * jitter,
                                      y: baseY + perpY * jitter))
        }
        path.addLine(to: endpoint)

        let bolt = SKShapeNode(path: path)
        bolt.strokeColor = UIColor(red: 1.0, green: 0.45, blue: 0.95, alpha: 1.0)
        bolt.fillColor = .clear
        bolt.lineWidth = 1.5
        bolt.glowWidth = 2.5
        bolt.alpha = 0.95
        bolt.zPosition = relativeZPos(under: parent, offset: -1)
        parent.addChild(bolt)
        bolt.run(SKAction.sequence([
            SKAction.fadeOut(withDuration: 0.12),
            SKAction.removeFromParent()
        ]))
    }

    override func didHit() {
        isHit = true

        let physicBody = component(ofType: GeometryComponent.self)?.geometryNode.physicsBody
        physicBody?.contactTestBitMask = 0
        physicBody?.categoryBitMask = 0

        if let spriteNode = component(ofType: SpriteComponent.self)?.spriteNode {
            let flash = SKSpriteNode(color: .magenta, size: CGSize(width: 28, height: 28))
            flash.position = spriteNode.position
            flash.zPosition = (spriteNode.scene as? InPlaySKScene)?.isNightWave == true ? Constants.NightWave.nightEffectZPosition : 55
            flash.alpha = 0.9
            spriteNode.scene?.addChild(flash)

            let expand = SKAction.scale(to: 2.5, duration: 0.2)
            let fade = SKAction.fadeOut(withDuration: 0.2)
            flash.run(SKAction.sequence([SKAction.group([expand, fade]), SKAction.removeFromParent()]))

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
