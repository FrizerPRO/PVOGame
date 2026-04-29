//
//  InPlaySKScene+Effects.swift
//  PVOGame
//

import SpriteKit
import UIKit

enum ExplosionTier {
    case none, small, medium, large

    var radius: CGFloat {
        switch self {
        case .none:   return 0
        case .small:  return Constants.Explosion.smallRadius
        case .medium: return Constants.Explosion.mediumRadius
        case .large:  return Constants.Explosion.largeRadius
        }
    }
}

enum InvalidPlacementReason {
    case insufficientFunds(needed: Int, have: Int)
    case invalidCell
    case offGrid
}

enum ExplosionAssets {
    /// Soft radial gradient: opaque white at center, fading to fully
    /// transparent at 75 % of the sprite radius. The remaining 25 % border
    /// is pure transparent so scaled-up sprites never show a square edge.
    static let puffTexture: SKTexture = {
        let size = CGSize(width: 128, height: 128)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            let cg = ctx.cgContext
            let colors = [
                UIColor(white: 1.0, alpha: 1.0).cgColor,
                UIColor(white: 1.0, alpha: 0.0).cgColor
            ] as CFArray
            let space = CGColorSpaceCreateDeviceRGB()
            let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0.0, 1.0])!
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            cg.drawRadialGradient(
                gradient,
                startCenter: center, startRadius: 0,
                endCenter: center, endRadius: size.width * 0.375,
                options: []
            )
        }
        let tex = SKTexture(image: image)
        tex.filteringMode = .linear
        return tex
    }()

}

extension InPlaySKScene {
    // MARK: - Screen Shake

    func screenShake(intensity: CGFloat = 4, duration: TimeInterval = 0.2) {
        guard childNode(withName: "//cameraShakeNode") == nil else { return }
        let shakeNode = SKNode()
        shakeNode.name = "cameraShakeNode"

        let steps = Int(duration / 0.02)
        var actions = [SKAction]()
        for i in 0..<steps {
            let decay = CGFloat(1.0 - Double(i) / Double(steps))
            let dx = CGFloat.random(in: -intensity...intensity) * decay
            let dy = CGFloat.random(in: -intensity...intensity) * decay
            actions.append(SKAction.moveBy(x: dx, y: dy, duration: 0.02))
        }
        actions.append(SKAction.move(to: .zero, duration: 0.02))

        // Move all children via a wrapper — avoid moving the scene itself
        let wrapper = childNode(withName: "//shakeWrapper")
        let target: SKNode = wrapper ?? self
        target.run(SKAction.sequence(actions), withKey: "cameraShake")
    }

    // MARK: - Refinery Income Display

    func showRefineryIncomeLabel(_ amount: Int, at position: CGPoint) {
        let label = SKLabelNode(fontNamed: Constants.GameBalance.hudFontName)
        label.text = "+\(amount)"
        label.fontSize = 14
        label.fontColor = .green
        label.position = CGPoint(x: position.x, y: position.y + 24)
        label.zPosition = 96
        label.setScale(0.6)
        addChild(label)

        label.run(SKAction.sequence([
            SKAction.group([
                SKAction.scale(to: 1.2, duration: 0.25),
                SKAction.fadeIn(withDuration: 0.1)
            ]),
            SKAction.scale(to: 1.0, duration: 0.15),
            SKAction.wait(forDuration: 0.6),
            SKAction.fadeOut(withDuration: 0.3),
            SKAction.removeFromParent()
        ]))
    }

    // MARK: - Kill Reward Display

    func showKillRewardLabel(_ amount: Int, at position: CGPoint) {
        // Each kill gets its own independent label so simultaneous kills don't
        // yank the previous "+N" off-screen — every drone leaves its own number
        // floating up from the spot where it died.
        let label = SKLabelNode(fontNamed: Constants.GameBalance.hudFontName)
        label.text = "+\(amount)"
        label.fontSize = 16
        label.fontColor = .yellow
        label.position = CGPoint(x: position.x, y: position.y + 20)
        label.zPosition = 96
        label.alpha = 1.0
        addChild(label)

        label.run(SKAction.sequence([
            SKAction.group([
                SKAction.moveBy(x: 0, y: 30, duration: 0.6),
                SKAction.sequence([
                    SKAction.scale(to: 1.3, duration: 0.1),
                    SKAction.scale(to: 1.0, duration: 0.1)
                ]),
                SKAction.sequence([
                    SKAction.wait(forDuration: 0.4),
                    SKAction.fadeOut(withDuration: 0.2)
                ])
            ]),
            SKAction.removeFromParent()
        ]))
    }

    // MARK: - Drone Wreckage

    func spawnWreckage(at position: CGPoint, rotation: CGFloat, size: CGSize) {
        let wreck = SKSpriteNode(color: UIColor(white: 0.2, alpha: 0.8), size: CGSize(width: size.width * 0.6, height: size.height * 0.6))
        wreck.position = position
        wreck.zRotation = rotation + CGFloat.random(in: -0.3...0.3)
        wreck.zPosition = 8 // just above ground
        wreck.alpha = 0.7
        addChild(wreck)

        // Fade out over 4 seconds
        wreck.run(SKAction.sequence([
            SKAction.wait(forDuration: 2.0),
            SKAction.fadeOut(withDuration: 2.0),
            SKAction.removeFromParent()
        ]))
    }

    // MARK: - Kill Explosion FX

    func spawnKillExplosion(at position: CGPoint, for drone: AttackDroneEntity) {
        let tier = Self.explosionTier(for: drone)
        guard tier != .none else { return }

        let radius = tier.radius
        let zPos = Constants.Explosion.zPosition

        // Atlas-based frame animation if available — takes over entirely.
        // The atlas frames already contain the hot core, expanding smoke ring
        // and dissipating smoke, so the programmatic core+ring shape effects
        // would just visually clash. Shape fallback below is used only when
        // the tier's atlas is empty (currently: small tier).
        let cache = AnimationTextureCache.shared
        let frames: [SKTexture]
        let holds: [TimeInterval]
        switch tier {
        case .small:  frames = cache.smallExplosion;  holds = cache.smallExplosionHolds
        case .medium: frames = cache.mediumExplosion; holds = cache.mediumExplosionHolds
        case .large:  frames = cache.largeExplosion;  holds = cache.largeExplosionHolds
        case .none:   frames = [];                    holds = []
        }
        if !frames.isEmpty {
            let diameter = radius * 4.5  // bigger than the damage radius so the fireball
                                         // reads clearly; atlas frames have padding around
                                         // the effect, so scale compensates
            let node = acquireExplosionNode()
            node.texture = frames[0]
            node.size = CGSize(width: diameter, height: diameter)
            node.position = position
            node.zPosition = zPos + 0.1
            node.color = .white
            node.colorBlendFactor = 0
            node.alpha = 1.0
            node.setScale(1.0)
            addChild(node)
            // Timing comes from the cache, which already accounts for the
            // flash / peak / settle cadence and halves hold durations when
            // intermediate half-step frames (f1_5, f2_5, f3_5) are present.
            // Uses per-frame timePerFrame via a manual sequence because
            // SKAction.animate only takes a uniform timing.
            var actions: [SKAction] = []
            for (idx, tex) in frames.enumerated() {
                let hold = idx < holds.count ? holds[idx] : 0.04
                actions.append(SKAction.setTexture(tex))
                actions.append(SKAction.wait(forDuration: hold))
            }
            actions.append(SKAction.run { [weak self, weak node] in
                guard let self, let node else { return }
                self.releaseExplosionNode(node)
            })
            node.run(SKAction.sequence(actions))
        } else {
            // Shape fallback — keep the old core+ring look when no atlas frames
            // are available for this tier, otherwise the kill is completely
            // visual-less.
            let core = SKShapeNode(circleOfRadius: radius)
            core.fillColor = UIColor(red: 1.0, green: 0.95, blue: 0.4, alpha: 1.0)
            core.strokeColor = .clear
            core.blendMode = .add
            core.position = position
            core.zPosition = zPos + 0.3
            core.setScale(0.4)
            addChild(core)
            core.run(SKAction.sequence([
                SKAction.scale(to: 1.0, duration: Constants.Explosion.coreGrowDuration),
                SKAction.group([
                    SKAction.scale(to: 0.7, duration: Constants.Explosion.coreFadeDuration),
                    SKAction.fadeOut(withDuration: Constants.Explosion.coreFadeDuration),
                    SKAction.colorize(with: UIColor(red: 0.9, green: 0.2, blue: 0.0, alpha: 1.0),
                                      colorBlendFactor: 1.0,
                                      duration: Constants.Explosion.coreFadeDuration)
                ]),
                SKAction.removeFromParent()
            ]))

            let ring = SKShapeNode(circleOfRadius: radius)
            ring.fillColor = .clear
            ring.strokeColor = UIColor(red: 1.0, green: 0.55, blue: 0.1, alpha: 1.0)
            ring.lineWidth = 1.5
            ring.blendMode = .add
            ring.position = position
            ring.zPosition = zPos + 0.2
            ring.setScale(0.3)
            addChild(ring)
            ring.run(SKAction.sequence([
                SKAction.group([
                    SKAction.scale(to: 1.3, duration: Constants.Explosion.ringDuration),
                    SKAction.fadeOut(withDuration: Constants.Explosion.ringDuration)
                ]),
                SKAction.removeFromParent()
            ]))
        }

        // Night reveal — record an NightHole entry that the overlay's
        // fragment shader will read, temporarily fading overlay alpha to
        // zero inside a circle at this blast position. The scene (ground,
        // wreckage, towers, nearby drones) becomes visible there for the
        // life of the hole.
        if isNightWave {
            let holeRadius = radius * Constants.Explosion.nightHoleRadiusMultiplier
            let lifetime = Constants.Explosion.nightHoleHold + Constants.Explosion.nightHoleFadeOut
            let now = lastUpdateTime
            if nightHoles.count >= NightHole.maxHoles {
                nightHoles.removeFirst()
            }
            nightHoles.append(
                NightHole(
                    position: position,
                    radius: holeRadius,
                    spawnTime: now,
                    lifetime: lifetime
                )
            )

        }
    }

    private static func explosionTier(for drone: AttackDroneEntity) -> ExplosionTier {
        if drone is SwarmDroneEntity { return .none }
        if drone is HeavyDroneEntity || drone is CruiseMissileEntity { return .large }
        if drone is ShahedDroneEntity
            || drone is OrlanDroneEntity
            || drone is EWDroneEntity
            || drone is EnemyMissileEntity
            || drone is MineLayerDroneEntity {
            return .medium
        }
        if drone is KamikazeDroneEntity
            || drone is LancetDroneEntity
            || drone is HarmMissileEntity {
            return .small
        }
        // Plain AttackDroneEntity (the weakest "дрон") — no explosion
        return .none
    }

    // MARK: - Valley Speed Boost

    func applyValleySpeedBoost(deltaTime: TimeInterval) {
        guard let gridMap else { return }
        let boostFraction = Constants.TerrainZone.valleySpeedMultiplier - 1.0
        for drone in aliveDrones {
            guard let spriteNode = drone.component(ofType: SpriteComponent.self)?.spriteNode else { continue }
            guard let gridPos = gridMap.gridPosition(for: spriteNode.position) else { continue }
            guard let cell = gridMap.cell(atRow: gridPos.row, col: gridPos.col), cell.terrain == .valley else { continue }
            // Extra displacement in drone's heading direction
            let angle = spriteNode.zRotation + .pi / 2
            let extraSpeed: CGFloat = 50 * boostFraction // base push
            let extra = extraSpeed * CGFloat(deltaTime)
            spriteNode.position.x += cos(angle) * extra
            spriteNode.position.y += sin(angle) * extra
        }
    }

    // MARK: - Cleanup

    func cleanupDrones() {
        guard currentPhase == .combat else { return }
        let snapshot = activeDrones

        let hqThreshold = gridMap.origin.y + gridMap.cellSize.height

        for drone in snapshot {
            guard let droneNode = drone.component(ofType: SpriteComponent.self)?.spriteNode else {
                removeEntity(drone)
                continue
            }
            if droneNode.parent == nil {
                removeEntity(drone)
                continue
            }

            // Check if drone reaches its target refinery
            if !drone.isHit, let refinery = drone.targetRefinery,
               let refineryComp = refinery.component(ofType: OilRefineryComponent.self),
               !refineryComp.isDestroyed,
               let refineryNode = refinery.component(ofType: SpriteComponent.self)?.spriteNode {
                let dist = hypot(droneNode.position.x - refineryNode.position.x,
                                 droneNode.position.y - refineryNode.position.y)
                let hitRadius = gridMap.cellSize.width * 1.5
                if dist < hitRadius {
                    onDroneReachedRefinery(drone: drone, refinery: refinery)
                    if drone is ShahedDroneEntity
                        || drone is KamikazeDroneEntity
                        || drone is LancetDroneEntity
                        || drone is EnemyMissileEntity
                        || drone is HarmMissileEntity
                        || drone is CruiseMissileEntity {
                        drone.didHit()
                        removeEntity(drone)
                        continue
                    }
                    drone.targetRefinery = nil
                }
            }

            // Check if drone passes through its target settlement (settlement is a waypoint, not endpoint)
            if !drone.isHit, let target = drone.targetSettlement, !target.isDestroyed {
                let targetPos = target.worldPosition
                let dist = hypot(droneNode.position.x - targetPos.x,
                                 droneNode.position.y - targetPos.y)
                let hitRadius = gridMap.cellSize.width * 1.5
                if dist < hitRadius {
                    onDroneReachedSettlement(drone: drone, settlement: target)
                    // Kamikaze-type enemies self-destruct on impact with settlement
                    if drone is ShahedDroneEntity
                        || drone is KamikazeDroneEntity
                        || drone is LancetDroneEntity
                        || drone is EnemyMissileEntity
                        || drone is HarmMissileEntity
                        || drone is CruiseMissileEntity {
                        drone.didHit()
                        removeEntity(drone)
                        continue
                    }
                    // Non-kamikaze drones: clear target, continue flying to HQ
                    drone.targetSettlement = nil
                }
            }

            // HARM missiles that pass their target just miss — no HQ damage
            if let harm = drone as? HarmMissileEntity, !drone.isHit, droneNode.position.y < hqThreshold {
                harm.reachedDestination()
                removeEntity(drone)
                continue
            }

            // Check if drone reached HQ area (bottom of map). Heavy drones
            // are excluded — they hunt towers, not HQ; if one ends up here
            // it's pathing pathology, not a legit HQ touchdown.
            if !drone.isHit && droneNode.position.y < hqThreshold && !(drone is HeavyDroneEntity) {
                onDroneReachedHQ(drone: drone)
                drone.reachedDestination()
                removeEntity(drone)
                continue
            }

            // Remove drones that went far off screen (ghost cleanup).
            // Heavy drones use a wider side envelope because their fixed-wing
            // recovery arcs can briefly leave the screen; only clean them up
            // if they are far out and still flying farther away.
            if drone is HeavyDroneEntity {
                if droneNode.position.y < -50 {
                    removeEntity(drone)
                    continue
                }
                let sideOutset = Constants.AdvancedEnemies.heavyDroneSideCleanupOutset
                let farLeft = droneNode.position.x < frame.minX - sideOutset
                let farRight = droneNode.position.x > frame.maxX + sideOutset
                let headingX = cos(droneNode.zRotation + .pi / 2)
                let movingFurtherOut = (farLeft && headingX < -0.05)
                    || (farRight && headingX > 0.05)
                if movingFurtherOut {
                    removeEntity(drone)
                    continue
                }
            } else if droneNode.position.y < -50 || droneNode.position.x < -100 || droneNode.position.x > frame.width + 100 {
                let noDamageTypes: Bool = drone is HarmMissileEntity || drone is EWDroneEntity
                if !drone.isHit && !noDamageTypes { onDroneReachedHQ(drone: drone) }
                removeEntity(drone)
                continue
            }
            if droneNode.position.y > frame.height + 300 {
                // Far above screen — silently remove without HQ damage
                removeEntity(drone)
                continue
            }

            // Update shadow in same pass (avoids separate iteration)
            if let shadow = drone.component(ofType: ShadowComponent.self),
               let altitude = drone.component(ofType: AltitudeComponent.self)?.altitude {
                shadow.updateShadow(dronePosition: droneNode.position, altitude: altitude)
            }
        }
    }

    func updateMineLayerOffscreenIndicator() {
        // Find first active mine layer that is off-screen
        let offscreenMiner = activeDrones.compactMap { $0 as? MineLayerDroneEntity }.first { miner in
            guard !miner.isHit,
                  let pos = miner.component(ofType: SpriteComponent.self)?.spriteNode.position
            else { return false }
            return pos.x < 0 || pos.x > frame.width
        }

        guard let miner = offscreenMiner,
              let dronePos = miner.component(ofType: SpriteComponent.self)?.spriteNode.position
        else {
            offscreenIndicator?.removeFromParent()
            offscreenIndicator = nil
            return
        }

        // Create indicator if needed
        if offscreenIndicator == nil {
            let node = SKNode()
            node.zPosition = 98

            let label = SKLabelNode(fontNamed: Constants.GameBalance.hudFontName)
            label.text = "!"
            label.fontSize = 20
            label.fontColor = .yellow
            label.verticalAlignmentMode = .center
            label.name = "offscreenLabel"
            node.addChild(label)

            // Triangle arrow
            let arrow = SKShapeNode()
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 0, y: 8))
            path.addLine(to: CGPoint(x: -6, y: -4))
            path.addLine(to: CGPoint(x: 6, y: -4))
            path.closeSubpath()
            arrow.path = path
            arrow.fillColor = .yellow
            arrow.strokeColor = .clear
            arrow.name = "offscreenArrow"
            arrow.position = CGPoint(x: 0, y: -16)
            node.addChild(arrow)

            // Pulse animation
            let scaleUp = SKAction.scale(to: 1.15, duration: 0.4)
            let scaleDown = SKAction.scale(to: 0.9, duration: 0.4)
            node.run(SKAction.repeatForever(SKAction.sequence([scaleUp, scaleDown])))

            addChild(node)
            offscreenIndicator = node
        }

        guard let indicator = offscreenIndicator else { return }

        // Position at screen edge, clamped Y
        let edgeMargin: CGFloat = 20
        let clampedY = min(max(dronePos.y, safeBottom + 30), frame.height - safeTop - 30)

        if dronePos.x < 0 {
            indicator.position = CGPoint(x: edgeMargin, y: clampedY)
            // Arrow points left
            if let arrow = indicator.childNode(withName: "offscreenArrow") {
                arrow.zRotation = .pi / 2
            }
        } else {
            indicator.position = CGPoint(x: frame.width - edgeMargin, y: clampedY)
            // Arrow points right
            if let arrow = indicator.childNode(withName: "offscreenArrow") {
                arrow.zRotation = -.pi / 2
            }
        }
    }

    func cleanupOffscreenIndicator() {
        offscreenIndicator?.removeFromParent()
        offscreenIndicator = nil
    }

    // MARK: - Invalid Placement Feedback

    func showInvalidPlacementFeedback(reason: InvalidPlacementReason, at position: CGPoint) {
        let text: String
        switch reason {
        case .insufficientFunds(let needed, let have):
            let missing = max(0, needed - have)
            text = "НЕТ СРЕДСТВ: +\(missing) DP"
        case .invalidCell:
            text = "ЗАНЯТО"
        case .offGrid:
            text = "ВНЕ ЗОНЫ"
        }

        let label = SKLabelNode(fontNamed: Constants.GameBalance.hudFontName)
        label.text = text
        label.fontSize = 12
        label.fontColor = UIColor(red: 1.0, green: 0.3, blue: 0.3, alpha: 1.0)
        label.position = CGPoint(x: position.x, y: position.y + 24)
        label.zPosition = 120
        label.setScale(0.8)
        label.alpha = 0
        addChild(label)

        label.run(SKAction.sequence([
            SKAction.group([
                SKAction.fadeIn(withDuration: 0.1),
                SKAction.scale(to: 1.2, duration: 0.1),
                SKAction.moveBy(x: 0, y: 6, duration: 0.1)
            ]),
            SKAction.scale(to: 1.0, duration: 0.1),
            SKAction.wait(forDuration: 0.5),
            SKAction.group([
                SKAction.fadeOut(withDuration: 0.25),
                SKAction.moveBy(x: 0, y: 12, duration: 0.25)
            ]),
            SKAction.removeFromParent()
        ]))
    }

    func shakeAndFadeOutPreview(sprite: SKSpriteNode?, range: SKShapeNode?) {
        range?.removeAllActions()

        guard let sprite else {
            range?.removeFromParent()
            return
        }

        sprite.removeAllActions()
        sprite.run(SKAction.sequence([
            SKAction.moveBy(x: -4, y: 0, duration: 0.03),
            SKAction.moveBy(x: 8, y: 0, duration: 0.04),
            SKAction.moveBy(x: -8, y: 0, duration: 0.04),
            SKAction.moveBy(x: 4, y: 0, duration: 0.03),
            SKAction.group([
                SKAction.fadeOut(withDuration: 0.15),
                SKAction.scale(to: 0.7, duration: 0.15)
            ]),
            SKAction.removeFromParent()
        ]))
    }

    func triggerErrorHaptic() {
        errorHaptic.notificationOccurred(.error)
        errorHaptic.prepare()
    }
}
