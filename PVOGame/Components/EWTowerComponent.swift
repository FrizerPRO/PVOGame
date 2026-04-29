//
//  EWTowerComponent.swift
//  PVOGame
//

import GameplayKit
import SpriteKit

/// Applied to player EW towers. Each tower locks onto AT MOST ONE jammable
/// drone in its range at a time. Priority: any KamikazeDroneEntity (since
/// FPV-kill is the real mechanical effect of EW) > nearest other jammable.
///
/// Visuals while active:
///  - A thin magenta lightning bolt from the tower to the chosen drone
///    (jittery polyline, refreshed at ~16 Hz for animated crackle).
///  - Small ragged spark segments parented to the chosen drone's sprite —
///    reads as "this electronic device is glitching".
///
/// FPV interception (the actual kill chance) only fires when the chosen
/// target is a KamikazeDroneEntity.
///
/// The jamming radius itself is not drawn permanently — it now uses the
/// standard tower-selection range indicator, shown when the player taps
/// the EW tower.
class EWTowerComponent: GKComponent {
    var slowMultiplier: CGFloat
    var fpvKillChance: CGFloat
    let fpvKillInterval: TimeInterval
    private var fpvKillTimer: TimeInterval = 0

    /// Single-target state. Reset whenever the locked drone leaves the zone,
    /// dies, or a higher-priority target appears.
    private var currentTargetID: ObjectIdentifier?
    /// Tower→drone lightning arc (parented to scene).
    private var currentBolt: SKShapeNode?
    /// Drone-local crackle (parented to the drone's sprite, follows it).
    private var currentSparks: SKShapeNode?

    /// Per-frame would look like noise; ~16 Hz reads as electrical crackle.
    private var boltRefreshTimer: TimeInterval = 0
    private var sparkRefreshTimer: TimeInterval = 0
    private let boltRefreshInterval: TimeInterval = 0.06
    private let sparkRefreshInterval: TimeInterval = 0.10

    private static let boltColor  = UIColor(red: 1.0, green: 0.45, blue: 0.95, alpha: 1.0)
    private static let sparkColor = UIColor(red: 1.0, green: 0.65, blue: 1.0,  alpha: 1.0)

    init(
        slowMultiplier: CGFloat = Constants.EW.ewTowerSlowMultiplier,
        fpvKillChance: CGFloat = Constants.EW.ewTowerFPVKillChance,
        fpvKillInterval: TimeInterval = Constants.EW.ewTowerFPVKillInterval
    ) {
        self.slowMultiplier = slowMultiplier
        self.fpvKillChance = fpvKillChance
        self.fpvKillInterval = fpvKillInterval
        super.init()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func update(deltaTime seconds: TimeInterval) {
        guard let tower = entity as? TowerEntity,
              let stats = tower.component(ofType: TowerStatsComponent.self),
              let spriteNode = tower.component(ofType: SpriteComponent.self)?.spriteNode,
              let scene = spriteNode.scene as? InPlaySKScene
        else { return }

        // Disabled tower stops jamming — clear visuals and bail.
        if stats.isDisabled {
            tearDownVisuals()
            return
        }

        let towerPos = spriteNode.position
        let range = stats.range
        let rangeSq = range * range

        // Decide whether bolt/spark paths get rerolled this tick. Independent
        // sub-frame timers so they don't visually sync into one pulse.
        boltRefreshTimer += seconds
        let refreshBolt = boltRefreshTimer >= boltRefreshInterval
        if refreshBolt { boltRefreshTimer = 0 }
        sparkRefreshTimer += seconds
        let refreshSparks = sparkRefreshTimer >= sparkRefreshInterval
        if refreshSparks { sparkRefreshTimer = 0 }

        // Pick a single target — kamikaze if any, otherwise nearest jammable.
        guard let pick = pickOneTarget(towerPos: towerPos, rangeSq: rangeSq, in: scene) else {
            tearDownVisuals()
            return
        }
        let (drone, dronePos, droneSprite) = pick
        let droneID = ObjectIdentifier(drone)

        // Re-target if the chosen drone changed since last frame.
        if currentTargetID != droneID {
            tearDownVisuals()
            currentTargetID = droneID
        }

        // Tower→drone arc — repath every tick (the drone is moving anyway),
        // but only re-randomize the jitter at the slower refresh interval.
        let bolt: SKShapeNode
        if let existing = currentBolt {
            bolt = existing
        } else {
            bolt = SKShapeNode()
            bolt.strokeColor = Self.boltColor.withAlphaComponent(0.55)
            bolt.lineWidth = 1.2
            bolt.glowWidth = 1.0
            bolt.fillColor = .clear
            bolt.zPosition = 24
            scene.addChild(bolt)
            currentBolt = bolt
        }
        if refreshBolt || bolt.path == nil {
            bolt.path = Self.makeLightningPath(
                from: towerPos, to: dronePos,
                segments: 6, jitter: 8
            )
        } else {
            // Even when not re-randomizing the jitter, keep endpoints synced
            // so the bolt visibly follows the moving drone every frame.
            bolt.path = Self.makeLightningPath(
                from: towerPos, to: dronePos,
                segments: 6, jitter: 0
            )
        }

        // Drone-local crackle sparks — parented to droneSprite so they follow
        // the drone for free and dispose with it.
        let sparks: SKShapeNode
        if let existing = currentSparks, existing.parent === droneSprite {
            sparks = existing
        } else {
            currentSparks?.removeFromParent()
            sparks = SKShapeNode()
            sparks.strokeColor = Self.sparkColor.withAlphaComponent(0.80)
            sparks.lineWidth = 1.0
            sparks.glowWidth = 0.8
            sparks.fillColor = .clear
            sparks.zPosition = 1
            droneSprite.addChild(sparks)
            currentSparks = sparks
        }
        if refreshSparks || sparks.path == nil {
            sparks.path = Self.makeCracklePath(count: 3, baseLen: 4)
        }

        // FPV interception — only when the chosen target is itself a kamikaze.
        // The tower can only act on its single locked drone, so non-kamikaze
        // locks simply produce visuals without a kill attempt.
        guard scene.currentPhase == .combat else { return }
        fpvKillTimer += seconds
        if fpvKillTimer >= fpvKillInterval {
            fpvKillTimer = 0
            if let kamikaze = drone as? KamikazeDroneEntity,
               CGFloat.random(in: 0...1) < fpvKillChance {
                kamikaze.takeDamage(kamikaze.health)
                if kamikaze.isHit {
                    scene.onDroneDestroyed(drone: kamikaze)
                }
            }
        }
    }

    /// Picks at most one drone in zone:
    ///   1. KamikazeDroneEntity always wins over non-FPV targets (so the
    ///      tower's actual interception ability is never starved).
    ///   2. Within the same priority class, the closest drone wins.
    /// Returns nil when no jammable drone is in range.
    private func pickOneTarget(towerPos: CGPoint, rangeSq: CGFloat,
                                in scene: InPlaySKScene)
        -> (AttackDroneEntity, CGPoint, SKSpriteNode)?
    {
        var chosenDrone: AttackDroneEntity?
        var chosenSprite: SKSpriteNode?
        var chosenPos: CGPoint = .zero
        var chosenIsFpv = false
        var chosenDistSq = CGFloat.greatestFiniteMagnitude

        for drone in scene.activeDronesForTowers {
            guard !drone.isHit, drone.isJammableByEW,
                  let droneSprite = drone.component(ofType: SpriteComponent.self)?.spriteNode
            else { continue }
            let dronePos = droneSprite.position
            let dx = dronePos.x - towerPos.x
            let dy = dronePos.y - towerPos.y
            let distSq = dx * dx + dy * dy
            if distSq > rangeSq { continue }

            let isFpv = drone is KamikazeDroneEntity
            let beats: Bool
            if isFpv && !chosenIsFpv {
                beats = true                          // promote to FPV
            } else if isFpv == chosenIsFpv {
                beats = distSq < chosenDistSq        // tie-break by distance
            } else {
                beats = false                         // chosen is FPV, this isn't
            }

            if beats {
                chosenDrone = drone
                chosenSprite = droneSprite
                chosenPos = dronePos
                chosenIsFpv = isFpv
                chosenDistSq = distSq
            }
        }

        if let drone = chosenDrone, let sprite = chosenSprite {
            return (drone, chosenPos, sprite)
        }
        return nil
    }

    private func tearDownVisuals() {
        currentBolt?.removeFromParent()
        currentBolt = nil
        currentSparks?.removeFromParent()
        currentSparks = nil
        currentTargetID = nil
    }

    /// Zigzag polyline from `start` to `end` with random perpendicular offsets
    /// at each intermediate vertex. Re-rolled periodically to read as
    /// crackling lightning rather than a stable wire.
    private static func makeLightningPath(from start: CGPoint, to end: CGPoint,
                                           segments: Int, jitter: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.move(to: start)
        let dx = end.x - start.x
        let dy = end.y - start.y
        let len = sqrt(dx * dx + dy * dy)
        guard len > 0.5 else {
            path.addLine(to: end)
            return path
        }
        let perpX = -dy / len
        let perpY =  dx / len
        for i in 1..<segments {
            let t = CGFloat(i) / CGFloat(segments)
            let bx = start.x + dx * t
            let by = start.y + dy * t
            let off = jitter > 0 ? CGFloat.random(in: -jitter...jitter) : 0
            path.addLine(to: CGPoint(x: bx + perpX * off, y: by + perpY * off))
        }
        path.addLine(to: end)
        return path
    }

    /// Builds a few short ragged spark segments shooting outward from the
    /// origin, in random directions. Drawn relative to the drone's local
    /// coordinate frame (so it travels with the drone).
    private static func makeCracklePath(count: Int, baseLen: CGFloat) -> CGPath {
        let path = CGMutablePath()
        for _ in 0..<count {
            let baseAngle = CGFloat.random(in: 0..<(.pi * 2))
            let startR = CGFloat.random(in: 5...9)
            var current = CGPoint(x: cos(baseAngle) * startR, y: sin(baseAngle) * startR)
            path.move(to: current)
            let segs = Int.random(in: 2...3)
            var heading = baseAngle
            for _ in 0..<segs {
                heading += CGFloat.random(in: -.pi / 3 ... (.pi / 3))
                let l = CGFloat.random(in: baseLen * 0.7 ... baseLen * 1.4)
                let next = CGPoint(x: current.x + cos(heading) * l,
                                    y: current.y + sin(heading) * l)
                path.addLine(to: next)
                current = next
            }
        }
        return path
    }
}
