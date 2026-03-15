//
//  TowerTargetingComponent.swift
//  PVOGame
//

import GameplayKit
import SpriteKit

class TowerTargetingComponent: GKComponent {
    private(set) weak var currentTarget: AttackDroneEntity?
    private var fireCooldown: TimeInterval = 0

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override init() {
        super.init()
    }

    override func update(deltaTime seconds: TimeInterval) {
        guard let tower = entity as? TowerEntity,
              let stats = tower.component(ofType: TowerStatsComponent.self),
              let towerPos = tower.component(ofType: SpriteComponent.self)?.spriteNode.position,
              let scene = tower.component(ofType: SpriteComponent.self)?.spriteNode.scene as? InPlaySKScene,
              stats.fireRate > 0
        else { return }

        if stats.isDisabled { currentTarget = nil; return }
        if scene.currentPhase != .combat { return }

        fireCooldown = max(0, fireCooldown - seconds)

        // Validate current target
        if let target = currentTarget {
            if target.isHit || !isInRange(target, towerPos: towerPos, stats: stats) {
                let wasKill = target.isHit
                currentTarget = nil
                // Quick re-engagement after kill: cut remaining cooldown
                if wasKill {
                    fireCooldown = min(fireCooldown, 0.1)
                }
            }
        }

        // Acquire new target if needed
        if currentTarget == nil {
            currentTarget = findBestTarget(in: scene, towerPos: towerPos, stats: stats)
        }

        // Fire at target
        guard let target = currentTarget, fireCooldown <= 0 else { return }
        guard let targetPos = target.component(ofType: SpriteComponent.self)?.spriteNode.position else { return }

        let didFire = fire(from: towerPos, toward: targetPos, in: scene, stats: stats)
        fireCooldown = didFire ? (1.0 / stats.fireRate) : 0.1
    }

    private func isInRange(_ drone: AttackDroneEntity, towerPos: CGPoint, stats: TowerStatsComponent) -> Bool {
        guard let dronePos = drone.component(ofType: SpriteComponent.self)?.spriteNode.position else { return false }
        let dx = dronePos.x - towerPos.x
        let dy = dronePos.y - towerPos.y
        let distSq = dx * dx + dy * dy
        guard distSq <= stats.range * stats.range else { return false }

        // Check altitude compatibility
        if let altComp = drone.component(ofType: AltitudeComponent.self) {
            return stats.reachableAltitudes.contains(altComp.altitude)
        }
        return stats.reachableAltitudes.contains(.low)
    }

    private func findBestTarget(in scene: InPlaySKScene, towerPos: CGPoint, stats: TowerStatsComponent) -> AttackDroneEntity? {
        let isRocketTower = stats.towerType == .samLauncher || stats.towerType == .interceptor
        var bestDrone: AttackDroneEntity?
        var bestScore: CGFloat = -.greatestFiniteMagnitude

        for drone in scene.activeDronesForTowers where !drone.isHit {
            guard isInRange(drone, towerPos: towerPos, stats: stats) else { continue }
            guard let dronePos = drone.component(ofType: SpriteComponent.self)?.spriteNode.position else { continue }

            // Score: prefer drones closer to base (lower Y = closer to HQ at bottom)
            var score = -dronePos.y

            // Rocket towers: strongly deprioritize drones already reserved by other rockets
            if isRocketTower && scene.isDroneReservedByRocket(drone) {
                score -= 10000
            }

            if score > bestScore {
                bestScore = score
                bestDrone = drone
            }
        }
        return bestDrone
    }

    @discardableResult
    private func fire(from towerPos: CGPoint, toward targetPos: CGPoint, in scene: InPlaySKScene, stats: TowerStatsComponent) -> Bool {
        switch stats.towerType {
        case .autocannon, .ciws:
            fireBullet(from: towerPos, toward: targetPos, in: scene, stats: stats)
            return true
        case .samLauncher:
            return fireRocket(from: towerPos, toward: targetPos, in: scene, spec: Constants.GameBalance.standardRocketSpec)
        case .interceptor:
            return fireRocket(from: towerPos, toward: targetPos, in: scene, spec: Constants.GameBalance.interceptorRocketBaseSpec)
        case .radar:
            return false
        }
    }

    private func fireBullet(from origin: CGPoint, toward target: CGPoint, in scene: InPlaySKScene, stats: TowerStatsComponent) {
        // Determine accuracy based on target altitude
        let targetAltitude: DroneAltitude
        if let altComp = currentTarget?.component(ofType: AltitudeComponent.self) {
            targetAltitude = altComp.altitude
        } else {
            targetAltitude = .low
        }
        let accuracy = stats.towerType.accuracy(against: targetAltitude)
        let isHit = CGFloat.random(in: 0...1) < accuracy

        let dx = target.x - origin.x
        let dy = target.y - origin.y
        let angle = atan2(dy, dx) - .pi / 2

        if isHit {
            let bullet = BulletEntity(
                damage: stats.damage,
                startImpact: Constants.GameBalance.defaultBulletStartImpact,
                imageName: "Bullet"
            )
            guard let bulletSprite = bullet.component(ofType: SpriteComponent.self) else { return }
            bulletSprite.spriteNode.size = CGSize(width: 4, height: 4)
            bulletSprite.setPosition(position: origin)
            bulletSprite.spriteNode.zRotation = angle
            bulletSprite.spriteNode.zPosition = 45

            scene.addEntity(bullet)
            if let shootComp = bullet.component(ofType: ShootComponent.self) {
                let direction = CGVector(dx: cos(angle + .pi / 2), dy: sin(angle + .pi / 2))
                shootComp.shoot(vector: direction)
            }

            // Hit tracer
            let tracer = SKShapeNode()
            let path = CGMutablePath()
            path.move(to: origin)
            path.addLine(to: target)
            tracer.path = path
            tracer.strokeColor = stats.towerType == .ciws ? .orange : .yellow
            tracer.lineWidth = 1.0
            tracer.alpha = 0.6
            tracer.zPosition = 42
            scene.addChild(tracer)
            tracer.run(SKAction.sequence([
                SKAction.fadeOut(withDuration: 0.12),
                SKAction.removeFromParent()
            ]))
        } else {
            // Miss tracer — angular deviation, no BulletEntity
            let spreadAngle = CGFloat.random(in: -0.35...0.35) // ±~20°
            let missAngle = angle + spreadAngle
            let missLength = stats.range * 1.2
            let missEnd = CGPoint(
                x: origin.x + cos(missAngle + .pi / 2) * missLength,
                y: origin.y + sin(missAngle + .pi / 2) * missLength
            )

            let tracer = SKShapeNode()
            let path = CGMutablePath()
            path.move(to: origin)
            path.addLine(to: missEnd)
            tracer.path = path
            tracer.strokeColor = stats.towerType == .ciws ? .orange : .yellow
            tracer.lineWidth = 0.8
            tracer.alpha = 0.3
            tracer.zPosition = 42
            scene.addChild(tracer)
            tracer.run(SKAction.sequence([
                SKAction.fadeOut(withDuration: 0.1),
                SKAction.removeFromParent()
            ]))
        }
    }

    @discardableResult
    private func fireRocket(from origin: CGPoint, toward target: CGPoint, in scene: InPlaySKScene, spec: Constants.GameBalance.RocketSpec) -> Bool {
        // Ask fire control for a deconflicted target point
        var finalTarget = scene.bestRocketTargetPoint(
            preferredPoint: target,
            origin: origin,
            radius: nil,
            influenceRadius: spec.blastRadius,
            reservingActiveRocketImpacts: true,
            excludingRocket: nil,
            projectileSpeed: spec.initialSpeed,
            projectileAcceleration: spec.acceleration,
            projectileMaxSpeed: spec.maxSpeed
        )

        // Fallback: if deconfliction rejected all targets (e.g. last drone is
        // reserved by another in-flight rocket), retry without reservations so
        // multiple rockets can converge on a high-HP drone.
        if finalTarget == nil {
            finalTarget = scene.bestRocketTargetPoint(
                preferredPoint: target,
                origin: origin,
                radius: nil,
                influenceRadius: spec.blastRadius,
                reservingActiveRocketImpacts: false,
                excludingRocket: nil,
                projectileSpeed: spec.initialSpeed,
                projectileAcceleration: spec.acceleration,
                projectileMaxSpeed: spec.maxSpeed
            )
        }

        guard let finalTarget else { return false }

        let rocket = RocketEntity(spec: spec)
        guard let rocketSprite = rocket.component(ofType: SpriteComponent.self)?.spriteNode else { return false }
        rocketSprite.position = origin
        rocketSprite.zPosition = 45
        let dx = finalTarget.x - origin.x
        let dy = finalTarget.y - origin.y
        rocketSprite.zRotation = atan2(dy, dx) - .pi / 2
        rocket.configureFlight(
            targetPoint: finalTarget,
            initialSpeed: spec.initialSpeed,
            climbsWhenNoTargets: false
        )
        scene.addEntity(rocket)

        // Launch smoke VFX
        spawnLaunchSmoke(at: origin, in: scene)

        // Register with fire control immediately so other towers see this reservation
        scene.updateRocketReservation(for: rocket, targetPoint: finalTarget)
        return true
    }

    private func spawnLaunchSmoke(at position: CGPoint, in scene: SKScene) {
        for i in 0..<3 {
            let puff = SKSpriteNode(color: UIColor.gray.withAlphaComponent(0.6), size: CGSize(width: 10, height: 10))
            puff.position = position
            puff.zPosition = 24
            scene.addChild(puff)

            let delay = TimeInterval(i) * 0.06
            let dx = CGFloat.random(in: -8...8)
            let fall = SKAction.moveBy(x: dx, y: -25, duration: 0.5)
            fall.timingMode = .easeOut
            let fade = SKAction.fadeOut(withDuration: 0.5)
            let grow = SKAction.scale(to: 2.0, duration: 0.5)
            puff.run(SKAction.sequence([
                SKAction.wait(forDuration: delay),
                SKAction.group([fall, fade, grow]),
                SKAction.removeFromParent()
            ]))
        }
    }
}
