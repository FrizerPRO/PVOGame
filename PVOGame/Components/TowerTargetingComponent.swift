//
//  TowerTargetingComponent.swift
//  PVOGame
//

import GameplayKit
import SpriteKit

class TowerTargetingComponent: GKComponent {
    private(set) weak var currentTarget: AttackDroneEntity?
    private var fireCooldown: TimeInterval = 0

    private static let tracerTexture: SKTexture = {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1))
        let image = renderer.image { ctx in
            UIColor.white.setFill()
            ctx.cgContext.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        return SKTexture(image: image)
    }()

    private static let hitTracerAction: SKAction = {
        SKAction.sequence([SKAction.fadeOut(withDuration: 0.12), SKAction.removeFromParent()])
    }()

    private static let missTracerAction: SKAction = {
        SKAction.sequence([SKAction.fadeOut(withDuration: 0.1), SKAction.removeFromParent()])
    }()

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

        // Always tick timers regardless of tower state
        fireCooldown = max(0, fireCooldown - seconds)
        stats.updateMagazineReload(deltaTime: seconds)

        if stats.isDisabled {
            if (stats.towerType == .samLauncher || stats.towerType == .interceptor) {
                let hasMissiles = scene.activeDronesForTowers.contains(where: { ($0 is EnemyMissileEntity || $0 is HarmMissileEntity) && !$0.isHit })
                if hasMissiles { print("[TOWER] \(stats.towerType.displayName) DISABLED while missiles present") }
            }
            currentTarget = nil; return
        }
        if stats.isReloading {
            if (stats.towerType == .samLauncher || stats.towerType == .interceptor) {
                let hasMissiles = scene.activeDronesForTowers.contains(where: { ($0 is EnemyMissileEntity || $0 is HarmMissileEntity) && !$0.isHit })
                if hasMissiles { print("[TOWER] \(stats.towerType.displayName) RELOADING (ammo=\(stats.magazineAmmo ?? -1) progress=\(String(format: "%.0f%%", stats.reloadProgress * 100))) while missiles present") }
            }
            currentTarget = nil; return
        }
        if scene.currentPhase != .combat { return }

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

        // DEBUG: log missile visibility for rocket towers
        let droneList = scene.activeDronesForTowers.filter { !$0.isHit }
        if isRocketTower && droneList.contains(where: { $0 is EnemyMissileEntity || $0 is HarmMissileEntity }) {
            print("[TARGET] \(stats.towerType.displayName) at (\(Int(towerPos.x)),\(Int(towerPos.y))): \(droneList.count) alive, \(droneList.filter { $0 is EnemyMissileEntity }.count) missiles, ammo=\(stats.magazineAmmo ?? -1) reloading=\(stats.isReloading) disabled=\(stats.isDisabled) cooldown=\(String(format: "%.2f", fireCooldown)) alertActive=\(scene.isMissileAlertActive)")
        }

        for drone in scene.activeDronesForTowers where !drone.isHit {
            guard isInRange(drone, towerPos: towerPos, stats: stats) else {
                // DEBUG: log WHY not in range for missiles
                if isRocketTower && (drone is EnemyMissileEntity || drone is HarmMissileEntity) {
                    let dronePos = drone.component(ofType: SpriteComponent.self)?.spriteNode.position ?? .zero
                    let dist = hypot(dronePos.x - towerPos.x, dronePos.y - towerPos.y)
                    let alt = drone.component(ofType: AltitudeComponent.self)?.altitude
                    print("[TARGET] SKIP missile at \(dronePos) dist=\(Int(dist)) range=\(Int(stats.range)) alt=\(String(describing: alt)) reachable=\(stats.reachableAltitudes)")
                }
                continue
            }
            guard let dronePos = drone.component(ofType: SpriteComponent.self)?.spriteNode.position else { continue }

            // Log missile in range for rocket towers
            if isRocketTower && (drone is EnemyMissileEntity || drone is HarmMissileEntity) {
                let score = -dronePos.y + 5000
                print("[TARGET] MISSILE IN RANGE at (\(Int(dronePos.x)),\(Int(dronePos.y))) dist=\(Int(hypot(dronePos.x - towerPos.x, dronePos.y - towerPos.y))) score=\(Int(score)) overkilled=\(scene.isDroneOverkilled(drone)) reserved=\(scene.isDroneReservedByRocket(drone))")
            }

            // Missile alert: rocket towers hold fire for missiles, skip non-missile targets
            if isRocketTower && scene.isMissileAlertActive && !(drone is EnemyMissileEntity) && !(drone is HarmMissileEntity) {
                continue
            }

            // Ammo reservation: rocket towers save rounds for incoming missiles
            if isRocketTower && scene.waveHasPendingMissiles && !(drone is EnemyMissileEntity) && !(drone is HarmMissileEntity) {
                if let ammo = stats.magazineAmmo {
                    let reserved = stats.towerType == .samLauncher ? 4 : 3
                    if ammo <= reserved { continue }
                }
            }

            // Score: prefer drones closer to base (lower Y = closer to HQ at bottom)
            var score = -dronePos.y

            // Rocket towers: strongly prioritize enemy missiles (including HARMs)
            if isRocketTower && (drone is EnemyMissileEntity || drone is HarmMissileEntity) {
                score += 5000
            }

            // CIWS: prioritize HARM missiles targeting towers
            if stats.towerType == .ciws && drone is HarmMissileEntity {
                score += 3000
            }

            // Rocket towers: deprioritize overkilled/reserved drones to spread fire
            if isRocketTower {
                if scene.isDroneOverkilled(drone) {
                    score -= 20000
                } else if scene.isDroneReservedByRocket(drone) {
                    score -= 10000
                }
            }

            if score > bestScore {
                bestScore = score
                bestDrone = drone
            }
        }
        // DEBUG: log result for rocket towers (only when missiles present to avoid spam)
        if isRocketTower && (bestDrone != nil || droneList.contains(where: { $0 is EnemyMissileEntity || $0 is HarmMissileEntity })) {
            print("[TARGET] \(stats.towerType.displayName) bestTarget=\(bestDrone != nil ? String(describing: type(of: bestDrone!)) : "nil") score=\(bestScore)")
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
            let fired = fireRocket(from: towerPos, toward: targetPos, in: scene, spec: Constants.GameBalance.standardRocketSpec)
            if fired { stats.consumeAmmo() }
            return fired
        case .interceptor:
            let fired = fireRocket(from: towerPos, toward: targetPos, in: scene, spec: Constants.GameBalance.interceptorRocketBaseSpec)
            if fired { stats.consumeAmmo() }
            return fired
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

            // Hit tracer (SKSpriteNode batches unlike SKShapeNode)
            let tdx = target.x - origin.x
            let tdy = target.y - origin.y
            let length = sqrt(tdx * tdx + tdy * tdy)
            let tracer = SKSpriteNode(texture: Self.tracerTexture)
            tracer.size = CGSize(width: 1.0, height: length)
            tracer.color = stats.towerType == .ciws ? .orange : .yellow
            tracer.colorBlendFactor = 1.0
            tracer.alpha = 0.6
            tracer.zPosition = 42
            tracer.position = CGPoint(x: (origin.x + target.x) * 0.5, y: (origin.y + target.y) * 0.5)
            tracer.zRotation = atan2(tdy, tdx) - .pi / 2
            scene.addChild(tracer)
            tracer.run(Self.hitTracerAction)
        } else {
            // Miss tracer — angular deviation, no BulletEntity
            let spreadAngle = CGFloat.random(in: -0.35...0.35) // ±~20°
            let missAngle = angle + spreadAngle
            let missLength = stats.range * 1.2
            let missEnd = CGPoint(
                x: origin.x + cos(missAngle + .pi / 2) * missLength,
                y: origin.y + sin(missAngle + .pi / 2) * missLength
            )

            let mdx = missEnd.x - origin.x
            let mdy = missEnd.y - origin.y
            let mLength = sqrt(mdx * mdx + mdy * mdy)
            let tracer = SKSpriteNode(texture: Self.tracerTexture)
            tracer.size = CGSize(width: 0.8, height: mLength)
            tracer.color = stats.towerType == .ciws ? .orange : .yellow
            tracer.colorBlendFactor = 1.0
            tracer.alpha = 0.3
            tracer.zPosition = 42
            tracer.position = CGPoint(x: (origin.x + missEnd.x) * 0.5, y: (origin.y + missEnd.y) * 0.5)
            tracer.zRotation = atan2(mdy, mdx) - .pi / 2
            scene.addChild(tracer)
            tracer.run(Self.missTracerAction)
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

        // DEBUG: log planLaunch result
        print("[FIRE] planLaunch result: \(finalTarget != nil ? "\(finalTarget!)" : "nil")")

        // Fallback: retry without reservations, but only if the target drone
        // is NOT overkilled (i.e. existing rockets aren't enough to kill it).
        if finalTarget == nil,
           currentTarget != nil {
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
            print("[FIRE] fallback planLaunch result: \(finalTarget != nil ? "\(finalTarget!)" : "nil")")
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
