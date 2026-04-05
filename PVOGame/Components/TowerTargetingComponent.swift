//
//  TowerTargetingComponent.swift
//  PVOGame
//

import GameplayKit
import SpriteKit

class TowerTargetingComponent: GKComponent {
    private(set) weak var currentTarget: AttackDroneEntity?
    private var fireCooldown: TimeInterval = 0

    static let poolTracerTexture: SKTexture = {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1))
        let image = renderer.image { ctx in
            UIColor.white.setFill()
            ctx.cgContext.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        return SKTexture(image: image)
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
            currentTarget = nil; return
        }
        if stats.isReloading {
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
                // Notify animation component that target is lost
                (entity as? TowerEntity)?.component(ofType: TowerAnimationComponent.self)?.onTargetLost()
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
        if didFire {
            fireCooldown = 1.0 / stats.fireRate
        } else {
            // Fire control rejected the shot — drop target so we re-evaluate next frame
            currentTarget = nil
            fireCooldown = 0.15
        }
    }

    private func isInRange(_ drone: AttackDroneEntity, towerPos: CGPoint, stats: TowerStatsComponent) -> Bool {
        guard let dronePos = drone.component(ofType: SpriteComponent.self)?.spriteNode.position else { return false }
        let dx = dronePos.x - towerPos.x
        let dy = dronePos.y - towerPos.y
        let distSq = dx * dx + dy * dy

        // Range check: always use full range
        guard distSq <= stats.range * stats.range else { return false }

        // HighGround LOS: towers below highGround can't see drones behind it
        if let tower = entity as? TowerEntity,
           let gridPos = tower.component(ofType: GridPositionComponent.self),
           let scene = tower.component(ofType: SpriteComponent.self)?.spriteNode.scene as? InPlaySKScene,
           let gridMap = scene.gridMap {
            let onHigh = gridMap.cell(atRow: gridPos.row, col: gridPos.col)?.terrain == .highGround
            if gridMap.isLineOfSightBlocked(from: towerPos, to: dronePos, towerOnHighGround: onHigh) {
                return false
            }
        }

        // Night radar gate: gun-based AA and IR-guided ПЗРК require radar coverage at night
        if stats.towerType == .autocannon || stats.towerType == .ciws
            || stats.towerType == .gepard || stats.towerType == .pzrk {
            if let tower = entity as? TowerEntity,
               let scene = tower.component(ofType: SpriteComponent.self)?.spriteNode.scene as? InPlaySKScene,
               scene.isNightWave {
                guard scene.isPositionInRadarCoverage(dronePos) else { return false }
            }
        }

        // Check altitude compatibility
        if let altComp = drone.component(ofType: AltitudeComponent.self) {
            if stats.reachableAltitudes.contains(altComp.altitude) {
                return true
            }
            return false
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

            // Missile alert: rocket towers hold fire for missiles, skip non-missile targets
            if isRocketTower && scene.isMissileAlertActive && !(drone is EnemyMissileEntity) && !(drone is HarmMissileEntity) {
                continue
            }

            // Ammo reservation: rocket towers save rounds for incoming missiles
            if isRocketTower && scene.isMissileAlertActive && !(drone is EnemyMissileEntity) && !(drone is HarmMissileEntity) {
                if let ammo = stats.magazineAmmo {
                    let reserved = stats.towerType == .samLauncher ? 2 : 1
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

            // Rocket towers: spread fire across targets
            if isRocketTower {
                let isMissileTarget = drone is EnemyMissileEntity || drone is HarmMissileEntity
                if scene.isDroneOverkilled(drone) {
                    if isMissileTarget {
                        // Missiles are fast — rocket may miss, so only deprioritize
                        score -= 10000
                    } else {
                        continue  // Slow drone: enough rockets already en route
                    }
                } else if scene.isDroneReservedByRocket(drone) {
                    score -= 10000
                }
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
        let animComp = (entity as? TowerEntity)?.component(ofType: TowerAnimationComponent.self)

        switch stats.towerType {
        case .autocannon, .ciws:
            fireBullet(from: towerPos, toward: targetPos, in: scene, stats: stats)
            animComp?.onBulletFired()
            return true
        case .samLauncher:
            let fired = fireRocket(from: towerPos, toward: targetPos, in: scene, spec: Constants.GameBalance.standardRocketSpec)
            if fired { stats.consumeAmmo(); animComp?.onRocketFired() }
            return fired
        case .interceptor:
            let fired = fireRocket(from: towerPos, toward: targetPos, in: scene, spec: Constants.GameBalance.interceptorRocketBaseSpec)
            if fired { stats.consumeAmmo(); animComp?.onRocketFired() }
            return fired
        case .radar:
            return false
        case .ewTower:
            return false  // EW tower doesn't fire; effects handled by EWTowerComponent
        case .pzrk:
            let fired = fireRocket(from: towerPos, toward: targetPos, in: scene, spec: Constants.GameBalance.interceptorRocketBaseSpec)
            if fired { stats.consumeAmmo(); animComp?.onRocketFired() }
            return fired
        case .gepard:
            fireBullet(from: towerPos, toward: targetPos, in: scene, stats: stats)
            animComp?.onBulletFired()
            return true
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
        var accuracy = stats.towerType.accuracy(against: targetAltitude)
        if let tower = entity as? TowerEntity,
           let scene = tower.component(ofType: SpriteComponent.self)?.spriteNode.scene as? InPlaySKScene {
            // Apply EW jamming debuff
            accuracy *= scene.ewJammingMultiplier(for: tower)
        }
        let isHit = CGFloat.random(in: 0...1) < min(accuracy, 1.0)

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

            // Hit tracer (recycled from pool)
            let tdx = target.x - origin.x
            let tdy = target.y - origin.y
            let length = sqrt(tdx * tdx + tdy * tdy)
            let nightMode = scene.isNightWave
            let tracer = scene.acquireTracer()
            tracer.size = CGSize(width: nightMode ? 1.5 : 1.0, height: length)
            tracer.color = nightMode ? .red : (stats.towerType == .ciws ? .orange : .yellow)
            tracer.colorBlendFactor = 1.0
            tracer.alpha = nightMode ? 0.9 : 0.6
            tracer.zPosition = nightMode ? Constants.NightWave.nightEffectZPosition : 42
            tracer.position = CGPoint(x: (origin.x + target.x) * 0.5, y: (origin.y + target.y) * 0.5)
            tracer.zRotation = atan2(tdy, tdx) - .pi / 2
            scene.addChild(tracer)
            tracer.run(SKAction.sequence([
                SKAction.fadeOut(withDuration: 0.12),
                SKAction.run { [weak scene, weak tracer] in
                    guard let scene, let tracer else { return }
                    scene.releaseTracer(tracer)
                }
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

            let mdx = missEnd.x - origin.x
            let mdy = missEnd.y - origin.y
            let mLength = sqrt(mdx * mdx + mdy * mdy)
            let nightMode = scene.isNightWave
            let tracer = scene.acquireTracer()
            tracer.size = CGSize(width: nightMode ? 1.0 : 0.8, height: mLength)
            tracer.color = nightMode ? .red : (stats.towerType == .ciws ? .orange : .yellow)
            tracer.colorBlendFactor = 1.0
            tracer.alpha = nightMode ? 0.5 : 0.3
            tracer.zPosition = nightMode ? Constants.NightWave.nightEffectZPosition : 42
            tracer.position = CGPoint(x: (origin.x + missEnd.x) * 0.5, y: (origin.y + missEnd.y) * 0.5)
            tracer.zRotation = atan2(mdy, mdx) - .pi / 2
            scene.addChild(tracer)
            tracer.run(SKAction.sequence([
                SKAction.fadeOut(withDuration: 0.1),
                SKAction.run { [weak scene, weak tracer] in
                    guard let scene, let tracer else { return }
                    scene.releaseTracer(tracer)
                }
            ]))
        }
    }

    @discardableResult
    private func fireRocket(from origin: CGPoint, toward target: CGPoint, in scene: InPlaySKScene, spec: Constants.GameBalance.RocketSpec) -> Bool {
        // Ask fire control for a deconflicted target point
        var finalTarget = scene.bestRocketTargetPoint(
            preferredPoint: target,
            origin: origin,
            radius: spec.maxFlightDistance,
            influenceRadius: spec.blastRadius,
            reservingActiveRocketImpacts: true,
            excludingRocket: nil,
            projectileSpeed: spec.initialSpeed,
            projectileAcceleration: spec.acceleration,
            projectileMaxSpeed: spec.maxSpeed
        )

        // Fallback: retry without reservations if the target isn't already overkilled
        if finalTarget == nil,
           let currentDrone = currentTarget,
           !scene.isDroneOverkilled(currentDrone) {
            finalTarget = scene.bestRocketTargetPoint(
                preferredPoint: target,
                origin: origin,
                radius: spec.maxFlightDistance,
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

        // Add rocket to scene stationary (no configureFlight yet)
        scene.addEntity(rocket)

        // Ignition flame at launcher
        let flame: SKSpriteNode
        if let flameTex = AnimationTextureCache.shared.flameGlow {
            flame = SKSpriteNode(texture: flameTex, size: CGSize(width: 14, height: 14))
        } else {
            flame = SKSpriteNode(color: .orange, size: CGSize(width: 14, height: 14))
        }
        flame.position = origin
        flame.zPosition = scene.isNightWave
            ? Constants.NightWave.nightEffectZPosition : 44
        flame.alpha = 0.9
        scene.addChild(flame)
        flame.run(SKAction.sequence([
            SKAction.group([
                SKAction.scale(to: 2.2, duration: 0.08),
                SKAction.colorize(with: .white, colorBlendFactor: 0.6, duration: 0.04)
            ]),
            SKAction.group([
                SKAction.scale(to: 1.8, duration: 0.07),
                SKAction.fadeOut(withDuration: 0.10)
            ]),
            SKAction.removeFromParent()
        ]))

        // Dwell on launcher, then launch
        let launchDelay: TimeInterval = 0.12
        rocketSprite.run(SKAction.sequence([
            SKAction.wait(forDuration: launchDelay),
            SKAction.run { [weak rocket] in
                rocket?.configureFlight(
                    targetPoint: finalTarget,
                    initialSpeed: spec.initialSpeed,
                    climbsWhenNoTargets: false
                )
            }
        ]))

        // Launch smoke VFX
        spawnLaunchSmoke(at: origin, in: scene)

        // Register with fire control immediately so other towers see this reservation
        scene.updateRocketReservation(for: rocket, targetPoint: finalTarget)
        return true
    }

    private func spawnLaunchSmoke(at position: CGPoint, in scene: SKScene) {
        let smokeTex = AnimationTextureCache.shared.smokePuffGray ?? AnimationTextureCache.shared.smokePuff
        for i in 0..<3 {
            let puff: SKSpriteNode
            if let tex = smokeTex {
                puff = SKSpriteNode(texture: tex, size: CGSize(width: 10, height: 10))
                puff.alpha = 0.6
            } else {
                puff = SKSpriteNode(color: UIColor.gray.withAlphaComponent(0.6), size: CGSize(width: 10, height: 10))
            }
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
