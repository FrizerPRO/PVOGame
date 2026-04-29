//
//  OrlanDroneEntity.swift
//  PVOGame
//
//  Orlan-10 — reconnaissance/spotter drone.
//  Does not attack. Searches for PVO towers with a rotating camera.
//  When a tower enters the camera FOV, orbits around it and boosts
//  nearby enemy drones to 3x speed. Retreats when no combat drones remain.
//

import Foundation
import GameplayKit
import SpriteKit

final class OrlanDroneEntity: AttackDroneEntity {

    override var isJammableByEW: Bool { false }

    // MARK: - Phase

    private enum Phase {
        case searching
        case orbiting
        case retreating
    }

    // MARK: - Properties

    private var phase: Phase = .searching
    private var velocity: CGVector = .zero
    private var currentPatrolTarget: CGPoint = .zero
    private var currentHeading: CGFloat = -.pi / 2  // facing down initially
    private let patrolSpeed: CGFloat = Constants.Orlan.speed
    /// Max angular velocity (rad/s) — smooth arcs instead of sharp turns.
    private let turnRate: CGFloat = 1.2
    private var patrolRegion: CGRect = .zero
    private var replanAccumulator: TimeInterval = 0
    private let replanInterval: TimeInterval = 4.0

    // Camera — no physical sprite; only the FOV cone represents the scanning sensor
    // (sensor is mounted on the drone's belly, so the cone renders below the drone body).
    // Rotation is tracked in WORLD space: the gyro-stabilized sensor keeps pointing in its
    // own direction regardless of how the drone maneuvers. The cone sprite lives as a
    // child of the drone body (for free position tracking), so at render time we cancel
    // out the drone's zRotation to keep the cone world-oriented.
    private var fovConeNode: SKSpriteNode?
    private var cameraWorldAngle: CGFloat = -.pi / 2
    private var towerCheckAccumulator: TimeInterval = 0
    private let towerCheckInterval: TimeInterval = 0.25
    /// Once true, the cone has been moved off the drone body (becoming its sibling)
    /// so the drone's yaw no longer feeds into the cone's visual rotation.
    private var hasDetachedCone = false

    // FOV tint palette — desaturated, semi-realistic (muted cyan/amber/grey)
    // rather than pure yellow/red/grey, which read as arcade UI.
    private static let searchColor  = UIColor(red: 0.37, green: 0.66, blue: 0.72, alpha: 1.0)
    private static let alertColor   = UIColor(red: 0.79, green: 0.54, blue: 0.24, alpha: 1.0)
    private static let retreatColor = UIColor(white: 0.55, alpha: 1.0)
    private static let coneBlendFactor: CGFloat = 0.85

    // Orbit
    private weak var orbitTarget: TowerEntity?
    private var orbitAngle: CGFloat = 0

    // Last tower we headed toward during search — used to prevent the Orlan
    // from picking the same nearest tower every time pickPatrolPoint() runs,
    // which would stall it at one tower if the camera happens not to face it.
    private weak var lastVisitedTower: TowerEntity?

    // Lancet spawning while orbiting
    private var lancetSpawnTimer: TimeInterval = 0
    private var lancetsRemaining: Int = Constants.Orlan.lancetAmmo
    private let spawnedLancets = NSHashTable<LancetDroneEntity>.weakObjects()

    required init(damage: CGFloat, speed: CGFloat, imageName: String, flyingPath: FlyingPath) {
        super.init(damage: damage, speed: speed, imageName: imageName, flyingPath: flyingPath)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Public API

    /// Exposes the spotted tower info for frame cache integration (speed boost).
    var spottedTowerInfo: (id: ObjectIdentifier, position: CGPoint)? {
        guard case .orbiting = phase,
              let tower = orbitTarget,
              !(tower.stats?.isDisabled ?? true) else { return nil }
        return (ObjectIdentifier(tower), tower.worldPosition)
    }

    // MARK: - Factory

    static func create(sceneFrame: CGRect) -> OrlanDroneEntity {
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
        let drone = OrlanDroneEntity(
            damage: 0,
            speed: Constants.Orlan.speed,
            imageName: "Drone",
            flyingPath: dummyPath
        )
        drone.removeComponent(ofType: FlyingProjectileComponent.self)
        drone.configureHealth(Constants.Orlan.health)

        if let spriteNode = drone.component(ofType: SpriteComponent.self)?.spriteNode {
            spriteNode.size = CGSize(width: Constants.SpriteSize.orlan, height: Constants.SpriteSize.orlan)
            if let tex = AnimationTextureCache.shared.droneTextures["drone_orlan"] {
                spriteNode.texture = tex
                spriteNode.color = .white
                spriteNode.colorBlendFactor = 0
            } else {
                spriteNode.color = UIColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1)
                spriteNode.colorBlendFactor = 1.0
            }
        }

        drone.addNavLights(wingspan: 16)

        // Orlan is a recon drone — it does not collide with ground/HQ.
        if let body = drone.component(ofType: GeometryComponent.self)?.geometryNode.physicsBody {
            body.contactTestBitMask = Constants.bulletBitMask  // bullets only, no groundBitMask
        }

        // Patrol region: keep Orlan away from screen edges and the HQ bottom strip.
        drone.patrolRegion = CGRect(
            x: sceneFrame.width * 0.12,
            y: sceneFrame.height * 0.35,
            width: sceneFrame.width * 0.76,
            height: sceneFrame.height * 0.50
        )

        drone.setupCamera()

        return drone
    }

    // MARK: - FOV Cone Setup

    private func setupCamera() {
        guard let spriteNode = component(ofType: SpriteComponent.self)?.spriteNode else { return }

        // FOV cone — radial-gradient pie-slice sprite, tinted at runtime.
        // Attached as a child of the drone body at negative zPosition so it renders
        // BELOW the drone sprite (the real sensor is belly-mounted on the Orlan).
        // The cone rotates independently of the drone's heading via cameraWorldAngle.
        let cone = SKSpriteNode(texture: OrlanDroneEntity.buildConeTexture(),
                                color: Self.searchColor, size: .zero)
        cone.size = CGSize(width: Constants.Orlan.cameraRange * 2,
                           height: Constants.Orlan.cameraRange * 2)
        cone.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        // Partial blend preserves some of the raw texture's neutrality — the tinted
        // colour stays desaturated instead of reading as a flat primary.
        cone.colorBlendFactor = Self.coneBlendFactor
        cone.alpha = 1.0
        cone.zPosition = -3
        spriteNode.addChild(cone)
        fovConeNode = cone
    }

    /// Generates the FOV wedge texture: radial gradient inside a pie-slice, brightest
    /// at the apex (the sensor) and fading to near-nothing at the arc. A single
    /// hairline on the outer arc preserves just enough edge definition to read the
    /// detection range without the hard UI-style outline the old texture had.
    /// Colored at runtime via the sprite's `color` + `colorBlendFactor`.
    private static var _cachedConeTexture: SKTexture?
    private static func buildConeTexture() -> SKTexture {
        if let cached = _cachedConeTexture { return cached }

        let range = Constants.Orlan.cameraRange
        let size = Int(range * 2)
        let center = CGPoint(x: CGFloat(size) / 2, y: CGFloat(size) / 2)
        let halfFOV = Constants.Orlan.cameraFOV / 2

        UIGraphicsBeginImageContextWithOptions(CGSize(width: size, height: size), false, 2.0)
        defer { UIGraphicsEndImageContext() }

        guard let ctx = UIGraphicsGetCurrentContext() else {
            let tex = SKTexture(imageNamed: "")
            _cachedConeTexture = tex
            return tex
        }

        // Pie-slice geometry: apex at center, arc opens toward the image top (+Y in
        // SpriteKit local space). In UIKit's y-down context "up" is -pi/2; we sweep
        // counter-clockwise (clockwise: false) so the arc goes the SHORT way through
        // the top, giving a 90° wedge rather than the 270° complement.
        let cgCenter: CGFloat = -.pi / 2
        let startAngle = cgCenter + halfFOV
        let endAngle = cgCenter - halfFOV
        let arcRadius = range - 1

        let wedge = UIBezierPath()
        wedge.move(to: center)
        wedge.addArc(withCenter: center, radius: arcRadius,
                     startAngle: startAngle, endAngle: endAngle, clockwise: false)
        wedge.close()

        // Radial gradient clipped to the wedge: brightest near the apex, nearly
        // invisible at the outer arc. Gives the zone a soft falloff that reads as a
        // physical sensor cone rather than a flat UI overlay.
        ctx.saveGState()
        wedge.addClip()
        let gradientColors = [
            UIColor.white.withAlphaComponent(0.28).cgColor,
            UIColor.white.withAlphaComponent(0.10).cgColor,
            UIColor.white.withAlphaComponent(0.02).cgColor
        ] as CFArray
        let gradientLocations: [CGFloat] = [0.0, 0.7, 1.0]
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                     colors: gradientColors,
                                     locations: gradientLocations) {
            ctx.drawRadialGradient(gradient,
                                   startCenter: center, startRadius: 0,
                                   endCenter: center, endRadius: arcRadius,
                                   options: [])
        }
        ctx.restoreGState()

        // Hairline on the outer arc only — no stroke on the radial sides, so the
        // sides dissolve into the gradient and the cone doesn't outline the drone
        // body. The thin arc keeps the detection range legible.
        let arcOnly = UIBezierPath()
        arcOnly.addArc(withCenter: center, radius: arcRadius,
                       startAngle: startAngle, endAngle: endAngle, clockwise: false)
        UIColor.white.withAlphaComponent(0.25).setStroke()
        arcOnly.lineWidth = 1
        arcOnly.lineCapStyle = .round
        arcOnly.stroke()

        let image = UIGraphicsGetImageFromCurrentImageContext() ?? UIImage()
        let tex = SKTexture(image: image)
        _cachedConeTexture = tex
        return tex
    }

    // MARK: - Spawn

    func configureSpawn(at spawnPoint: CGPoint) {
        if let spriteNode = component(ofType: SpriteComponent.self)?.spriteNode {
            spriteNode.position = spawnPoint
        }
        currentPatrolTarget = pickPatrolPoint(from: spawnPoint, scene: nil)
        currentHeading = -.pi / 2
        velocity = CGVector(dx: cos(currentHeading) * patrolSpeed, dy: sin(currentHeading) * patrolSpeed)
    }

    // MARK: - Update

    override func update(deltaTime seconds: TimeInterval) {
        guard !isHit else { return }
        guard let spriteNode = component(ofType: SpriteComponent.self)?.spriteNode else { return }
        let scene = spriteNode.scene as? InPlaySKScene

        // On the first frame with a parent available, lift the cone out of the
        // drone body and reparent it as a sibling. This decouples the cone's
        // visual hierarchy from the drone's yaw: the body keeps rotating to face
        // its heading, but the cone no longer sits inside that rotating frame,
        // so the scan rate reads as constant to the viewer.
        if !hasDetachedCone,
           let cone = fovConeNode,
           cone.parent === spriteNode,
           let droneParent = spriteNode.parent {
            cone.removeFromParent()
            cone.zPosition = spriteNode.zPosition - 3  // preserve old below-body ordering
            droneParent.addChild(cone)
            hasDetachedCone = true
        }

        switch phase {
        case .searching:
            updateSearching(seconds, spriteNode: spriteNode, scene: scene)
        case .orbiting:
            updateOrbiting(seconds, spriteNode: spriteNode, scene: scene)
        case .retreating:
            updateRetreating(seconds, spriteNode: spriteNode, scene: scene)
        }

        // Keep Orlan inside the viewport during active phases so the player can
        // always see it. Retreat intentionally flies off the top of the screen
        // and must skip the clamp.
        if phase != .retreating, let scene = scene {
            stayWithinSceneBounds(spriteNode: spriteNode, scene: scene)
        }

        // Cone tracks the drone's position but not its rotation. At zRotation = 0
        // the texture points toward +Y (world angle π/2), so we subtract π/2 to
        // align "up" in the texture with cameraWorldAngle.
        fovConeNode?.position = spriteNode.position
        fovConeNode?.zRotation = cameraWorldAngle - .pi / 2
    }

    /// Hard-clamp Orlan's position inside the scene frame (with a margin) and
    /// redirect its heading toward the centre when clamped — subsequent frames
    /// naturally turn the drone inward instead of pinning it against the edge.
    /// Skips the clamp while the drone is still above the top of the screen so
    /// the initial spawn entry from (midX, height + 50) isn't yanked back.
    private func stayWithinSceneBounds(spriteNode: SKSpriteNode, scene: SKScene) {
        let bounds = scene.frame
        var pos = spriteNode.position

        if pos.y > bounds.maxY { return }

        let margin: CGFloat = 40
        var clamped = false
        if pos.x < bounds.minX + margin { pos.x = bounds.minX + margin; clamped = true }
        if pos.x > bounds.maxX - margin { pos.x = bounds.maxX - margin; clamped = true }
        if pos.y < bounds.minY + margin { pos.y = bounds.minY + margin; clamped = true }
        if pos.y > bounds.maxY - margin { pos.y = bounds.maxY - margin; clamped = true }

        if clamped {
            spriteNode.position = pos
            let toCenter = atan2(bounds.midY - pos.y, bounds.midX - pos.x)
            var delta = toCenter - currentHeading
            while delta > .pi { delta -= 2 * .pi }
            while delta < -.pi { delta += 2 * .pi }
            currentHeading += delta * 0.25
        }
    }

    // MARK: - Searching Phase

    private func updateSearching(_ dt: TimeInterval, spriteNode: SKSpriteNode, scene: InPlaySKScene?) {
        // Patrol movement (replan periodically)
        replanAccumulator += dt
        let reached = {
            let dx = self.currentPatrolTarget.x - spriteNode.position.x
            let dy = self.currentPatrolTarget.y - spriteNode.position.y
            return dx * dx + dy * dy < 30 * 30
        }()
        if reached || replanAccumulator >= replanInterval {
            currentPatrolTarget = pickPatrolPoint(from: spriteNode.position, scene: scene)
            replanAccumulator = 0
        }

        // Steer toward patrol target
        steerToward(currentPatrolTarget, from: spriteNode, dt: dt, speed: patrolSpeed)

        // Rotate camera while searching — world-space sweep, unaffected by drone maneuvering
        cameraWorldAngle += Constants.Orlan.cameraSearchRotationSpeed * CGFloat(dt)

        // Check for towers in camera FOV
        towerCheckAccumulator += dt
        if towerCheckAccumulator >= towerCheckInterval, let scene = scene {
            towerCheckAccumulator = 0
            if let tower = detectTowerInFOV(dronePos: spriteNode.position, scene: scene) {
                transitionToOrbiting(tower, dronePos: spriteNode.position)
                return
            }
        }
    }

    // MARK: - Orbiting Phase

    private func updateOrbiting(_ dt: TimeInterval, spriteNode: SKSpriteNode, scene: InPlaySKScene?) {
        // Check if tower is still alive
        guard let tower = orbitTarget, !(tower.stats?.isDisabled ?? true) else {
            transitionToSearching(from: spriteNode, scene: scene)
            return
        }

        let towerPos = tower.worldPosition

        // Orbit radius: normally cameraRange, but shrunk if the tower is close
        // to an edge so the orbit stays fully inside the scene (otherwise the
        // drone pins against the boundary clamp).
        var orbitDist = Constants.Orlan.cameraRange
        if let sceneBounds = scene?.frame {
            let edgeMargin: CGFloat = 40
            let maxRadius = min(
                min(towerPos.x - sceneBounds.minX, sceneBounds.maxX - towerPos.x),
                min(towerPos.y - sceneBounds.minY, sceneBounds.maxY - towerPos.y)
            ) - edgeMargin
            orbitDist = min(orbitDist, max(40, maxRadius))
        }

        // Steer along the orbit tangent (counterclockwise around the tower)
        // with a mild radial correction toward orbitDist. The previous
        // angular-lead algorithm pointed the drone at a chord of the circle,
        // which pulled it inward every frame — the drone spiralled toward the
        // tower and lost effective ground speed, making orbit feel slower than
        // patrol. Tangent-based steering holds a constant radius so the drone
        // moves at the full patrolSpeed around the circle.
        let dx = spriteNode.position.x - towerPos.x
        let dy = spriteNode.position.y - towerPos.y
        let currentRadius = max(sqrt(dx * dx + dy * dy), 1)
        let tangentDx = -dy / currentRadius
        let tangentDy = dx / currentRadius
        // Positive when drone is outside orbit (pull inward), negative when
        // inside (push outward). Combined with -dx/currentRadius (the inward
        // unit radial), the sign works out to always point toward orbitDist.
        let radialWeight = max(-0.6, min(0.6, (currentRadius - orbitDist) / orbitDist))
        let radialDx = -dx / currentRadius * radialWeight
        let radialDy = -dy / currentRadius * radialWeight
        let desiredPos = CGPoint(
            x: spriteNode.position.x + (tangentDx + radialDx) * 150,
            y: spriteNode.position.y + (tangentDy + radialDy) * 150
        )

        steerToward(desiredPos, from: spriteNode, dt: dt, speed: patrolSpeed)

        // Smoothly rotate camera toward tower in world space (not instant snap)
        let camDx = towerPos.x - spriteNode.position.x
        let camDy = towerPos.y - spriteNode.position.y
        let angleToTower = atan2(camDy, camDx)
        var camDelta = angleToTower - cameraWorldAngle
        while camDelta > .pi { camDelta -= 2 * .pi }
        while camDelta < -.pi { camDelta += 2 * .pi }
        let camMaxStep = Constants.Orlan.cameraSearchRotationSpeed * 2 * CGFloat(dt)
        cameraWorldAngle += max(-camMaxStep, min(camMaxStep, camDelta))

        // Spawn lancets periodically while orbiting
        if lancetsRemaining > 0 {
            lancetSpawnTimer -= dt
            if lancetSpawnTimer <= 0, let scene = scene {
                lancetSpawnTimer = Constants.Orlan.lancetSpawnInterval
                lancetsRemaining -= 1
                spawnLancetForTarget(tower, in: scene)
            }
        } else {
            // All lancets spent — retreat when none are still alive
            let aliveLancets = spawnedLancets.allObjects.filter { !$0.isHit }
            if aliveLancets.isEmpty {
                transitionToRetreating()
            }
        }
    }

    // MARK: - Retreating Phase

    private func updateRetreating(_ dt: TimeInterval, spriteNode: SKSpriteNode, scene: InPlaySKScene?) {
        let retreatTarget = CGPoint(x: spriteNode.position.x, y: (scene?.frame.height ?? 800) + 100)
        steerToward(retreatTarget, from: spriteNode, dt: dt, speed: Constants.Orlan.retreatSpeed)

        if spriteNode.position.y > (scene?.frame.height ?? 800) + 50 {
            fovConeNode?.removeFromParent()
            removeFromParent()
        }
    }

    private func transitionToRetreating() {
        phase = .retreating
        orbitTarget = nil

        fovConeNode?.removeAction(forKey: "pulse")
        fovConeNode?.removeAction(forKey: "colorize")
        fovConeNode?.run(SKAction.colorize(with: Self.retreatColor,
                                           colorBlendFactor: Self.coneBlendFactor,
                                           duration: 0.4),
                        withKey: "colorize")
        fovConeNode?.run(SKAction.fadeAlpha(to: 0.35, duration: 0.4))
    }

    // MARK: - Steering

    private func steerToward(_ target: CGPoint, from spriteNode: SKSpriteNode, dt: TimeInterval, speed: CGFloat) {
        let dx = target.x - spriteNode.position.x
        let dy = target.y - spriteNode.position.y
        if dx * dx + dy * dy > 0.01 {
            let desiredHeading = atan2(dy, dx)
            var delta = desiredHeading - currentHeading
            while delta > .pi { delta -= 2 * .pi }
            while delta < -.pi { delta += 2 * .pi }
            let maxStep = turnRate * CGFloat(dt)
            currentHeading += max(-maxStep, min(maxStep, delta))
        }

        velocity = CGVector(dx: cos(currentHeading) * speed, dy: sin(currentHeading) * speed)
        spriteNode.position.x += velocity.dx * CGFloat(dt)
        spriteNode.position.y += velocity.dy * CGFloat(dt)
        spriteNode.zRotation = currentHeading - .pi / 2
    }

    // MARK: - Tower Detection

    private func detectTowerInFOV(dronePos: CGPoint, scene: InPlaySKScene) -> TowerEntity? {
        guard let towers = scene.towerPlacement?.towers else { return nil }

        let rangeSq = Constants.Orlan.cameraRange * Constants.Orlan.cameraRange
        let halfFOV = Constants.Orlan.cameraFOV / 2

        var bestTower: TowerEntity?
        var bestDistSq: CGFloat = .greatestFiniteMagnitude

        for tower in towers {
            guard !(tower.stats?.isDisabled ?? true) else { continue }

            let dx = tower.worldPosition.x - dronePos.x
            let dy = tower.worldPosition.y - dronePos.y
            let distSq = dx * dx + dy * dy
            guard distSq <= rangeSq else { continue }

            let angleToTower = atan2(dy, dx)
            var angleDiff = angleToTower - cameraWorldAngle
            while angleDiff > .pi { angleDiff -= 2 * .pi }
            while angleDiff < -.pi { angleDiff += 2 * .pi }
            guard abs(angleDiff) <= halfFOV else { continue }

            if distSq < bestDistSq {
                bestDistSq = distSq
                bestTower = tower
            }
        }

        return bestTower
    }

    // MARK: - Phase Transitions

    private func transitionToOrbiting(_ tower: TowerEntity, dronePos: CGPoint) {
        phase = .orbiting
        orbitTarget = tower
        lancetSpawnTimer = Constants.Orlan.lancetSpawnInterval

        // Compute initial orbit angle from current position relative to tower
        let dx = dronePos.x - tower.worldPosition.x
        let dy = dronePos.y - tower.worldPosition.y
        orbitAngle = atan2(dy, dx)

        // Lock-on: fade to the alert tint and emit a few soft pulses. The colour
        // slide (vs. the old instant swap to pure red) keeps the transition calm
        // while the pulse gives the "target acquired" moment its weight.
        fovConeNode?.removeAction(forKey: "pulse")
        fovConeNode?.removeAction(forKey: "colorize")
        fovConeNode?.run(SKAction.colorize(with: Self.alertColor,
                                           colorBlendFactor: Self.coneBlendFactor,
                                           duration: 0.25),
                        withKey: "colorize")
        let alertPulse = SKAction.sequence([
            SKAction.fadeAlpha(to: 0.75, duration: 0.22),
            SKAction.fadeAlpha(to: 1.0, duration: 0.22),
        ])
        fovConeNode?.run(SKAction.sequence([
            SKAction.repeat(alertPulse, count: 3),
            SKAction.fadeAlpha(to: 1.0, duration: 0.1)
        ]), withKey: "pulse")
    }

    private func transitionToSearching(from spriteNode: SKSpriteNode, scene: InPlaySKScene?) {
        phase = .searching
        orbitTarget = nil

        // Searching: back to the neutral scan tint, no pulse — the world-space
        // rotation of the cone is itself the "active scan" signal.
        fovConeNode?.removeAction(forKey: "pulse")
        fovConeNode?.removeAction(forKey: "colorize")
        fovConeNode?.run(SKAction.colorize(with: Self.searchColor,
                                           colorBlendFactor: Self.coneBlendFactor,
                                           duration: 0.3),
                        withKey: "colorize")
        fovConeNode?.run(SKAction.fadeAlpha(to: 1.0, duration: 0.3))

        // Pick a new patrol target
        currentPatrolTarget = pickPatrolPoint(from: spriteNode.position, scene: scene)
        replanAccumulator = 0
    }

    // MARK: - Lancet Spawning

    private func spawnLancetForTarget(_ tower: TowerEntity, in scene: InPlaySKScene) {
        let spawnX = CGFloat.random(in: 40...(scene.frame.width - 40))
        let spawnY = scene.frame.height + CGFloat.random(in: 20...50)
        let spawnPoint = CGPoint(x: spawnX, y: spawnY)

        // Loiter near the target tower
        let loiterCenter = CGPoint(
            x: tower.worldPosition.x + CGFloat.random(in: -40...40),
            y: tower.worldPosition.y + CGFloat.random(in: 60...120)
        )

        let lancet = LancetDroneEntity(sceneFrame: scene.frame, scene: scene)
        lancet.assignTarget(tower)

        let altitude: DroneAltitude = .medium
        lancet.addComponent(AltitudeComponent(altitude: altitude))
        let shadow = ShadowComponent()
        lancet.addComponent(shadow)
        scene.shadowLayer?.addChild(shadow.shadowNode)

        if let spriteNode = lancet.component(ofType: SpriteComponent.self)?.spriteNode {
            let scale = altitude.droneVisualScale
            spriteNode.size = CGSize(width: 14 * scale, height: 16 * scale)
            spriteNode.zPosition = 61 + CGFloat(altitude.rawValue) * 5
        }

        lancet.configureFlight(from: spawnPoint, loiterAt: loiterCenter)

        spawnedLancets.add(lancet)
        scene.activeDrones.append(lancet)
        scene.addEntity(lancet)
    }

    // MARK: - Patrol Point Selection

    /// Pick the nearest active tower as the next patrol destination, skipping
    /// the one we just came from so the Orlan hops tower-to-tower rather than
    /// stalling on a single target the camera may be missing. When no towers
    /// are placed yet, fall back to the centre of the patrol region.
    private func pickPatrolPoint(from origin: CGPoint, scene: InPlaySKScene?) -> CGPoint {
        let towers = scene?.towerPlacement?.towers.filter { !(($0.stats?.isDisabled) ?? true) } ?? []

        guard !towers.isEmpty else {
            lastVisitedTower = nil
            return CGPoint(x: patrolRegion.midX, y: patrolRegion.midY)
        }

        let sorted = towers.sorted { a, b in
            let da = (a.worldPosition.x - origin.x) * (a.worldPosition.x - origin.x)
                   + (a.worldPosition.y - origin.y) * (a.worldPosition.y - origin.y)
            let db = (b.worldPosition.x - origin.x) * (b.worldPosition.x - origin.x)
                   + (b.worldPosition.y - origin.y) * (b.worldPosition.y - origin.y)
            return da < db
        }

        let next = sorted.first { $0 !== lastVisitedTower } ?? sorted[0]
        lastVisitedTower = next
        return next.worldPosition
    }

    // MARK: - Death

    override func didHit() {
        isHit = true
        orbitTarget = nil
        let physicBody = component(ofType: GeometryComponent.self)?.geometryNode.physicsBody
        physicBody?.contactTestBitMask = 0
        physicBody?.categoryBitMask = 0

        if let spriteNode = component(ofType: SpriteComponent.self)?.spriteNode {
            let flash = SKSpriteNode(color: .cyan, size: CGSize(width: 20, height: 20))
            flash.position = spriteNode.position
            flash.zPosition = 55
            flash.alpha = 0.8
            spriteNode.scene?.addChild(flash)
            let expand = SKAction.scale(to: 2.0, duration: 0.2)
            let fade = SKAction.fadeOut(withDuration: 0.15)
            flash.run(SKAction.sequence([SKAction.group([expand, fade]), SKAction.removeFromParent()]))

            spriteNode.run(SKAction.sequence([
                SKAction.fadeOut(withDuration: 0.1),
                SKAction.run { [weak self] in self?.removeFromParent() }
            ]))
        }

        // The detached cone lives next to the drone in scene space — fade and
        // remove it explicitly, since it's no longer a child of the drone body.
        if let cone = fovConeNode {
            cone.removeAllActions()
            cone.run(SKAction.sequence([
                SKAction.fadeOut(withDuration: 0.1),
                SKAction.removeFromParent()
            ]))
        }
    }

    override func reachedDestination() {
        // Orlan never reaches "destination" — it patrols until killed or retreats
    }
}
