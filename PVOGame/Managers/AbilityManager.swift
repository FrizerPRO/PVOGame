//
//  AbilityManager.swift
//  PVOGame
//

import SpriteKit

class AbilityManager {
    private(set) var fighterButton: AbilityButton?
    private(set) var barrageButton: AbilityButton?
    private(set) var reloadButton: AbilityButton?

    private weak var scene: InPlaySKScene?
    var activeTargetAbility: AbilityButton.AbilityType?

    func setup(in scene: InPlaySKScene) {
        self.scene = scene
        let btnSize = Constants.Abilities.abilityButtonSize
        let spacing: CGFloat = 16
        let safeBottom: CGFloat = scene.view?.safeAreaInsets.bottom ?? 0

        // Horizontal row above the tower palette (palette is at safeBottom + 42)
        let yPos: CGFloat = safeBottom + 95
        let totalWidth = btnSize * 3 + spacing * 2
        let startX = scene.frame.width - totalWidth / 2 - 12  // right-aligned group

        let fighter = AbilityButton(type: .fighter, position: CGPoint(x: startX - (btnSize + spacing), y: yPos))
        let barrage = AbilityButton(type: .barrage, position: CGPoint(x: startX, y: yPos))
        let reload = AbilityButton(type: .reload, position: CGPoint(x: startX + (btnSize + spacing), y: yPos))

        scene.addChild(fighter)
        scene.addChild(barrage)
        scene.addChild(reload)

        fighterButton = fighter
        barrageButton = barrage
        reloadButton = reload
    }

    func removeButtons() {
        fighterButton?.removeFromParent()
        barrageButton?.removeFromParent()
        reloadButton?.removeFromParent()
        fighterButton = nil
        barrageButton = nil
        reloadButton = nil
        activeTargetAbility = nil
    }

    func setHidden(_ hidden: Bool) {
        fighterButton?.isHidden = hidden
        barrageButton?.isHidden = hidden
        reloadButton?.isHidden = hidden
    }

    func update(deltaTime: TimeInterval) {
        fighterButton?.update(deltaTime: deltaTime)
        barrageButton?.update(deltaTime: deltaTime)
        reloadButton?.update(deltaTime: deltaTime)
    }

    func handleTap(at location: CGPoint) -> Bool {
        guard let scene else { return false }

        // Check if tapping an ability button
        if let fighter = fighterButton, fighter.containsTouch(location) && !fighter.isOnCooldown {
            activateFighter(in: scene)
            return true
        }
        if let barrage = barrageButton, barrage.containsTouch(location) && !barrage.isOnCooldown {
            if barrage.isWaitingForTarget {
                barrage.setWaitingForTarget(false)
                activeTargetAbility = nil
            } else {
                barrage.setWaitingForTarget(true)
                reloadButton?.setWaitingForTarget(false)
                activeTargetAbility = .barrage
            }
            return true
        }
        if let reload = reloadButton, reload.containsTouch(location) && !reload.isOnCooldown {
            if reload.isWaitingForTarget {
                reload.setWaitingForTarget(false)
                activeTargetAbility = nil
            } else {
                reload.setWaitingForTarget(true)
                barrageButton?.setWaitingForTarget(false)
                activeTargetAbility = .reload
            }
            return true
        }

        // Handle target selection
        if let activeAbility = activeTargetAbility {
            switch activeAbility {
            case .barrage:
                activateBarrage(at: location, in: scene)
                barrageButton?.setWaitingForTarget(false)
                activeTargetAbility = nil
                return true
            case .reload:
                activateReload(at: location, in: scene)
                reloadButton?.setWaitingForTarget(false)
                activeTargetAbility = nil
                return true
            default:
                break
            }
        }

        return false
    }

    // MARK: - Abilities

    private func activateFighter(in scene: InPlaySKScene) {
        fighterButton?.activate()

        let fighter = FighterEntity(sceneFrame: scene.frame)
        let startX: CGFloat = -50
        let endX: CGFloat = scene.frame.width + 50
        let flyY: CGFloat = scene.frame.height * 0.6

        guard let spriteNode = fighter.component(ofType: SpriteComponent.self)?.spriteNode else { return }
        spriteNode.position = CGPoint(x: startX, y: flyY)
        spriteNode.zPosition = Constants.Abilities.fighterZPosition
        scene.addChild(spriteNode)

        let flyAcross = SKAction.moveTo(x: endX, duration: Constants.Abilities.fighterFlyDuration)
        flyAcross.timingMode = .easeInEaseOut

        // Kill up to N targets along the path
        var killsRemaining = Constants.Abilities.fighterMaxKills
        let killCheck = SKAction.repeat(SKAction.sequence([
            SKAction.wait(forDuration: Constants.Abilities.fighterFlyDuration / Double(Constants.Abilities.fighterMaxKills + 1)),
            SKAction.run { [weak scene, weak spriteNode] in
                guard let scene, let spriteNode, killsRemaining > 0 else { return }
                let fighterPos = spriteNode.position
                // Find closest enemy
                let closest = scene.activeDronesForTowers
                    .filter { !$0.isHit }
                    .min(by: {
                        let da = hypot(($0.component(ofType: SpriteComponent.self)?.spriteNode.position.x ?? 0) - fighterPos.x,
                                       ($0.component(ofType: SpriteComponent.self)?.spriteNode.position.y ?? 0) - fighterPos.y)
                        let db = hypot(($1.component(ofType: SpriteComponent.self)?.spriteNode.position.x ?? 0) - fighterPos.x,
                                       ($1.component(ofType: SpriteComponent.self)?.spriteNode.position.y ?? 0) - fighterPos.y)
                        return da < db
                    })
                if let target = closest,
                   let targetPos = target.component(ofType: SpriteComponent.self)?.spriteNode.position {
                    let dist = hypot(targetPos.x - fighterPos.x, targetPos.y - fighterPos.y)
                    if dist < 120 {
                        // Mini rocket VFX
                        let rocket = SKSpriteNode(color: .white, size: CGSize(width: 3, height: 8))
                        rocket.position = fighterPos
                        rocket.zPosition = Constants.Abilities.fighterZPosition - 1
                        scene.addChild(rocket)
                        let move = SKAction.move(to: targetPos, duration: 0.15)
                        rocket.run(SKAction.sequence([move, SKAction.removeFromParent()]))

                        target.takeDamage(target.health)
                        if target.isHit {
                            scene.onDroneDestroyed(drone: target)
                        }
                        killsRemaining -= 1
                    }
                }
            }
        ]), count: Constants.Abilities.fighterMaxKills)

        spriteNode.run(SKAction.group([flyAcross, killCheck])) {
            spriteNode.removeFromParent()
        }
    }

    private func activateBarrage(at location: CGPoint, in scene: InPlaySKScene) {
        barrageButton?.activate()

        // Place marker
        let marker = SKShapeNode(circleOfRadius: Constants.Abilities.barrageRadius)
        marker.strokeColor = .red
        marker.fillColor = UIColor.red.withAlphaComponent(0.1)
        marker.lineWidth = 2
        marker.position = location
        marker.zPosition = 50
        scene.addChild(marker)

        // Marker pulses then explosions
        let pulse = SKAction.sequence([
            SKAction.scale(to: 1.1, duration: 0.3),
            SKAction.scale(to: 0.9, duration: 0.3)
        ])
        marker.run(SKAction.sequence([
            SKAction.repeat(pulse, count: 3),
            SKAction.removeFromParent()
        ]))

        // Delayed explosions
        scene.run(SKAction.sequence([
            SKAction.wait(forDuration: Constants.Abilities.barrageDelay),
            SKAction.run { [weak scene] in
                guard let scene else { return }
                for i in 0..<Constants.Abilities.barrageExplosionCount {
                    let delay = TimeInterval(i) * 0.2
                    scene.run(SKAction.sequence([
                        SKAction.wait(forDuration: delay),
                        SKAction.run {
                            let angle = CGFloat.random(in: 0...(2 * .pi))
                            let dist = CGFloat.random(in: 0...Constants.Abilities.barrageRadius * 0.8)
                            let pos = CGPoint(
                                x: location.x + cos(angle) * dist,
                                y: location.y + sin(angle) * dist
                            )

                            // Flash
                            let flash = SKSpriteNode(color: .white, size: CGSize(width: 30, height: 30))
                            flash.position = pos
                            flash.zPosition = 55
                            scene.addChild(flash)
                            flash.run(SKAction.sequence([
                                SKAction.group([
                                    SKAction.scale(to: 3.0, duration: 0.2),
                                    SKAction.fadeOut(withDuration: 0.3)
                                ]),
                                SKAction.removeFromParent()
                            ]))

                            // Damage enemies in radius (not towers)
                            let blastRadius: CGFloat = 35
                            for drone in scene.activeDronesForTowers where !drone.isHit {
                                guard let dronePos = drone.component(ofType: SpriteComponent.self)?.spriteNode.position else { continue }
                                let dx = dronePos.x - pos.x
                                let dy = dronePos.y - pos.y
                                if dx * dx + dy * dy <= blastRadius * blastRadius {
                                    drone.takeDamage(Constants.Abilities.barrageDamage)
                                    if drone.isHit {
                                        scene.onDroneDestroyed(drone: drone)
                                    }
                                }
                            }
                        }
                    ]))
                }
            }
        ]))
    }

    private func activateReload(at location: CGPoint, in scene: InPlaySKScene) {
        // Find closest rocket-based tower
        guard let towerPlacement = scene.towerPlacement else { return }
        let reloadableTowers = towerPlacement.towers.filter {
            $0.towerType == .samLauncher || $0.towerType == .interceptor
        }
        guard let closestTower = reloadableTowers.min(by: {
            hypot($0.worldPosition.x - location.x, $0.worldPosition.y - location.y) <
            hypot($1.worldPosition.x - location.x, $1.worldPosition.y - location.y)
        }) else { return }

        let dist = hypot(closestTower.worldPosition.x - location.x, closestTower.worldPosition.y - location.y)
        guard dist < 60 else { return }  // Must tap near the tower

        reloadButton?.activate()
        closestTower.stats?.replenishMagazine()

        // Green flash VFX
        if let spriteNode = closestTower.component(ofType: SpriteComponent.self)?.spriteNode {
            let flash = SKSpriteNode(color: .green, size: CGSize(width: 40, height: 40))
            flash.position = .zero
            flash.zPosition = 30
            flash.alpha = 0.8
            spriteNode.addChild(flash)
            flash.run(SKAction.sequence([
                SKAction.group([
                    SKAction.scale(to: 2.0, duration: 0.3),
                    SKAction.fadeOut(withDuration: 0.3)
                ]),
                SKAction.removeFromParent()
            ]))
        }
    }
}
