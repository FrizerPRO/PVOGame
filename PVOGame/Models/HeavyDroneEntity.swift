//
//  HeavyDroneEntity.swift
//  PVOGame
//

import Foundation
import GameplayKit
import SpriteKit

final class HeavyDroneEntity: AttackDroneEntity {

    override var isBossType: Bool { true }

    private(set) var armorPoints: Int = Constants.AdvancedEnemies.heavyDroneArmor
    private var bombsRemaining: Int = Constants.AdvancedEnemies.heavyDroneBombCount
    private var hasBombed = false
    private var exitMode = false
    private var velocity: CGVector = .zero
    private var waypointIndex = 0
    private var waypoints: [CGPoint] = []

    init(sceneFrame: CGRect, flightPath: DroneFlightPath) {
        self.waypoints = flightPath.waypoints
        let flyingPath = flightPath.toFlyingPath()
        super.init(
            damage: 1,
            speed: Constants.AdvancedEnemies.heavyDroneSpeed,
            imageName: "Drone",
            flyingPath: flyingPath
        )
        removeComponent(ofType: FlyingProjectileComponent.self)
        configureHealth(Constants.AdvancedEnemies.heavyDroneHealth)

        // Large hexacopter drone sprite
        let spriteScale = Constants.AdvancedEnemies.heavyDroneSpriteScale
        if let spriteNode = component(ofType: SpriteComponent.self)?.spriteNode {
            spriteNode.size = CGSize(width: Constants.SpriteSize.heavyDroneBase * spriteScale, height: Constants.SpriteSize.heavyDroneBase * spriteScale)
            // TODO: HeavyDroneEntity uses placeholder "Drone" sprite until it gets a distinct role
            spriteNode.color = UIColor(red: 0.23, green: 0.23, blue: 0.23, alpha: 1)
            spriteNode.colorBlendFactor = 1.0

            // 6 spinning propellers at arm tips (hexacopter layout)
            let armLength: CGFloat = 12 * spriteScale
            let propSize = CGSize(width: 7 * spriteScale, height: 2 * spriteScale)
            for i in 0..<6 {
                let angle = CGFloat(i) * (.pi / 3) - .pi / 2 // start from top
                let pos = CGPoint(x: cos(angle) * armLength, y: sin(angle) * armLength)
                let prop = SKSpriteNode(color: UIColor(white: 0.2, alpha: 0.8), size: propSize)
                prop.position = pos
                prop.zPosition = 1
                let spin = SKAction.repeatForever(SKAction.rotate(byAngle: .pi * 2, duration: 0.12))
                prop.run(spin)
                spriteNode.addChild(prop)
            }
        }

        addNavLights(wingspan: 28 * spriteScale)
    }

    required init(damage: CGFloat, speed: CGFloat, imageName: String, flyingPath: FlyingPath) {
        super.init(damage: damage, speed: speed, imageName: imageName, flyingPath: flyingPath)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Armor system: bullets blocked if armor > 0, rockets pierce
    override func takeDamage(_ amount: Int) {
        guard !isHit else { return }
        health = max(0, health - amount)
        if health <= 0 {
            didHit()
        } else {
            // White hit flash — restores damage tint after
            if let spriteNode = component(ofType: SpriteComponent.self)?.spriteNode {
                spriteNode.removeAction(forKey: "hitFlash")
                let savedColor = spriteNode.color
                let savedBlend = spriteNode.colorBlendFactor
                let flash = SKAction.sequence([
                    SKAction.colorize(with: .white, colorBlendFactor: 1.0, duration: 0.03),
                    SKAction.colorize(with: savedColor, colorBlendFactor: savedBlend, duration: 0.08)
                ])
                spriteNode.run(flash, withKey: "hitFlash")
            }
            updateDamageVisuals()
        }
        updateHPBar()
    }

    func takeBulletDamage(_ amount: Int) {
        if armorPoints > 0 {
            armorPoints -= 1
            // Armor absorbs bullet — sparks VFX
            if let spriteNode = component(ofType: SpriteComponent.self)?.spriteNode,
               let scene = spriteNode.scene {
                let spark = SKSpriteNode(color: .yellow, size: CGSize(width: 6, height: 6))
                spark.position = spriteNode.position
                spark.zPosition = (scene as? InPlaySKScene)?.isNightWave == true ? Constants.NightWave.nightEffectZPosition : 55
                scene.addChild(spark)
                spark.run(SKAction.sequence([
                    SKAction.fadeOut(withDuration: 0.15),
                    SKAction.removeFromParent()
                ]))
            }
            return  // No HP damage
        }
        takeDamage(amount)
    }

    override func update(deltaTime seconds: TimeInterval) {
        guard !isHit else { return }
        guard let spriteNode = component(ofType: SpriteComponent.self)?.spriteNode else { return }

        if exitMode {
            // Fly upward after bombing
            spriteNode.position.x += velocity.dx * CGFloat(seconds)
            spriteNode.position.y += velocity.dy * CGFloat(seconds)
            return
        }

        // Follow waypoints
        guard waypointIndex < waypoints.count else {
            // Reached end
            return
        }

        let target = waypoints[waypointIndex]
        let dx = target.x - spriteNode.position.x
        let dy = target.y - spriteNode.position.y
        let dist = sqrt(dx * dx + dy * dy)

        let currentSpeed = speed
        if dist < currentSpeed * CGFloat(seconds) + 5 {
            spriteNode.position = target
            waypointIndex += 1

            // Attempt bomb drop at midpoint
            if !hasBombed && waypointIndex >= waypoints.count / 2 {
                attemptBombDrop(from: spriteNode)
            }
        } else {
            let dirX = dx / dist
            let dirY = dy / dist
            spriteNode.position.x += dirX * currentSpeed * CGFloat(seconds)
            spriteNode.position.y += dirY * currentSpeed * CGFloat(seconds)
            spriteNode.zRotation = atan2(dy, dx) - .pi / 2
        }
    }

    private func attemptBombDrop(from spriteNode: SKSpriteNode) {
        guard let scene = spriteNode.scene as? InPlaySKScene else { return }
        hasBombed = true

        // Find nearest tower to bomb
        let bombPos = spriteNode.position
        let nearestTower = scene.towerPlacement?.towers
            .filter { !($0.stats?.isDisabled ?? true) }
            .min(by: {
                let da = hypot($0.worldPosition.x - bombPos.x, $0.worldPosition.y - bombPos.y)
                let db = hypot($1.worldPosition.x - bombPos.x, $1.worldPosition.y - bombPos.y)
                return da < db
            })

        for i in 0..<bombsRemaining {
            let delay = TimeInterval(i) * 0.3
            scene.run(SKAction.sequence([
                SKAction.wait(forDuration: delay),
                SKAction.run { [weak self, weak scene, weak nearestTower] in
                    guard let self, let scene, !self.isHit else { return }
                    let bomb = MineBombEntity()
                    let pos = self.component(ofType: SpriteComponent.self)?.spriteNode.position ?? bombPos
                    bomb.place(at: pos)
                    bomb.configureForTDBombing(target: nearestTower)
                    bomb.configureOrigin(isFromCrashedDrone: false, sourceDrone: self)
                    scene.addEntity(bomb)
                }
            ]))
        }

        // Enter exit mode after bombing
        scene.run(SKAction.sequence([
            SKAction.wait(forDuration: TimeInterval(bombsRemaining) * 0.3 + 0.5),
            SKAction.run { [weak self] in
                self?.enterExitMode()
            }
        ]))
    }

    private func enterExitMode() {
        exitMode = true
        speed = Constants.AdvancedEnemies.heavyDroneExitSpeed
        // Fly upward and off-screen
        velocity = CGVector(dx: 0, dy: speed)
        if let spriteNode = component(ofType: SpriteComponent.self)?.spriteNode {
            spriteNode.zRotation = .pi / 2 - .pi / 2  // Face up
        }
    }

    override func didHit() {
        isHit = true

        let physicBody = component(ofType: GeometryComponent.self)?.geometryNode.physicsBody
        physicBody?.contactTestBitMask = 0
        physicBody?.categoryBitMask = 0

        if let spriteNode = component(ofType: SpriteComponent.self)?.spriteNode {
            let flash = SKSpriteNode(color: .orange, size: CGSize(width: 32, height: 32))
            flash.position = spriteNode.position
            flash.zPosition = (spriteNode.scene as? InPlaySKScene)?.isNightWave == true ? Constants.NightWave.nightEffectZPosition : 55
            flash.alpha = 0.9
            spriteNode.scene?.addChild(flash)

            let expand = SKAction.scale(to: 3.0, duration: 0.25)
            let fade = SKAction.fadeOut(withDuration: 0.25)
            flash.run(SKAction.sequence([SKAction.group([expand, fade]), SKAction.removeFromParent()]))

            spriteNode.run(SKAction.sequence([
                SKAction.fadeOut(withDuration: 0.15),
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
