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
    private var nextLightningDelay: TimeInterval = 0.9
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
            nextLightningDelay = TimeInterval.random(in: 0.6...1.4)
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

    /// Spawns several copies of the SAME bolt sprite around the drone at
    /// well-separated angles, so the drone looks surrounded by an electrical
    /// crackle of one variety. The sprite type is picked at random per
    /// discharge, so different discharges show different bolt families
    /// (jagged / forked / branching / twin). All bolts are parented to the
    /// drone so they follow its motion and scaled UNIFORMLY to keep native
    /// PNG proportions. Fades out over ~0.18s.
    private func spawnEWLightning(at spriteNode: SKSpriteNode) {
        let textures = AnimationTextureCache.shared.ewBoltTextures
        guard let texture = textures.randomElement() else {
            let angle = CGFloat.random(in: 0..<(.pi * 2))
            spawnFallbackBolt(parent: spriteNode, angle: angle)
            applyLightningDamage(at: spriteNode)
            return
        }

        // Several copies of the SAME sprite, distributed evenly around the
        // drone with a small per-bolt jitter so they don't look mechanically
        // symmetric.
        let count = Int.random(in: 4...5)
        let baseAngle = CGFloat.random(in: 0..<(.pi * 2))
        let angularStep = (2 * .pi) / CGFloat(count)

        var angles: [CGFloat] = []
        for i in 0..<count {
            let angle = baseAngle + angularStep * CGFloat(i)
                + CGFloat.random(in: -0.25...0.25)
            spawnSingleBolt(at: spriteNode, texture: texture, angle: angle)
            angles.append(angle)
        }

        applyLightningDamage(at: spriteNode)
    }

    /// Each discharge damages active towers inside the EW effect radius.
    private func applyLightningDamage(at spriteNode: SKSpriteNode) {
        guard let scene = spriteNode.scene as? InPlaySKScene,
              let towerPlacement = scene.towerPlacement else { return }
        let dronePos = spriteNode.position
        let radiusSq = effectRadius * effectRadius

        for tower in towerPlacement.towers {
            guard let stats = tower.stats, !stats.isDisabled else { continue }
            let towerPos = tower.worldPosition
            let dx = towerPos.x - dronePos.x
            let dy = towerPos.y - dronePos.y
            guard dx * dx + dy * dy <= radiusSq else { continue }
            tower.takeBombDamage(Constants.EW.ewLightningTowerDamage)
        }
    }

    private func spawnSingleBolt(at spriteNode: SKSpriteNode,
                                  texture: SKTexture, angle: CGFloat) {
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
