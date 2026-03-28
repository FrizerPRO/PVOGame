//
//  EWTowerComponent.swift
//  PVOGame
//

import GameplayKit
import SpriteKit

/// Applied to player EW towers. Slows enemies and can intercept FPV kamikaze drones.
class EWTowerComponent: GKComponent {
    var slowMultiplier: CGFloat
    var fpvKillChance: CGFloat
    let fpvKillInterval: TimeInterval
    private var fpvKillTimer: TimeInterval = 0
    private var pulseTimer: TimeInterval = 0

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
              !stats.isDisabled,
              let towerPos = tower.component(ofType: SpriteComponent.self)?.spriteNode.position,
              let scene = tower.component(ofType: SpriteComponent.self)?.spriteNode.scene as? InPlaySKScene,
              scene.currentPhase == .combat
        else { return }

        let range = stats.range

        // Visual pulse
        pulseTimer += seconds
        if pulseTimer >= 2.0 {
            pulseTimer = 0
            spawnEWPulse(at: towerPos, range: range, in: scene)
        }

        // FPV interception
        fpvKillTimer += seconds
        if fpvKillTimer >= fpvKillInterval {
            fpvKillTimer = 0
            for drone in scene.activeDronesForTowers {
                guard let kamikaze = drone as? KamikazeDroneEntity, !kamikaze.isHit else { continue }
                guard let dronePos = kamikaze.component(ofType: SpriteComponent.self)?.spriteNode.position else { continue }
                let dx = dronePos.x - towerPos.x
                let dy = dronePos.y - towerPos.y
                if dx * dx + dy * dy <= range * range {
                    if CGFloat.random(in: 0...1) < fpvKillChance {
                        kamikaze.takeDamage(kamikaze.health)
                        if kamikaze.isHit {
                            scene.onDroneDestroyed(drone: kamikaze)
                        }
                        break  // One kill per interval
                    }
                }
            }
        }
    }

    private func spawnEWPulse(at position: CGPoint, range: CGFloat, in scene: SKScene) {
        let ring = SKShapeNode(circleOfRadius: 10)
        ring.strokeColor = UIColor.cyan.withAlphaComponent(0.4)
        ring.fillColor = UIColor.cyan.withAlphaComponent(0.05)
        ring.lineWidth = 1.5
        ring.position = position
        ring.zPosition = 23
        scene.addChild(ring)

        let expand = SKAction.scale(to: range / 10, duration: 1.0)
        expand.timingMode = .easeOut
        let fade = SKAction.fadeOut(withDuration: 1.0)
        ring.run(SKAction.sequence([
            SKAction.group([expand, fade]),
            SKAction.removeFromParent()
        ]))
    }
}
