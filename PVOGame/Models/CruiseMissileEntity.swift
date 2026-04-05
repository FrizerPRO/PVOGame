//
//  CruiseMissileEntity.swift
//  PVOGame
//

import Foundation
import GameplayKit
import SpriteKit

final class CruiseMissileEntity: AttackDroneEntity {

    override var isBossType: Bool { true }

    private var targetPoint: CGPoint = .zero
    private var velocity: CGVector = .zero
    private var smokeAccumulator: TimeInterval = 0
    private var nightFlameNode: SKSpriteNode?
    private var isDiving = false
    private var diveTimer: TimeInterval = 0

    private static let smokePuffTexture: SKTexture = {
        let diameter: CGFloat = 14
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: diameter, height: diameter))
        let image = renderer.image { ctx in
            UIColor.white.setFill()
            ctx.cgContext.fillEllipse(in: CGRect(x: 0, y: 0, width: diameter, height: diameter))
        }
        return SKTexture(image: image)
    }()

    private static let smokePuffAction: SKAction = {
        let expand = SKAction.scale(to: 2.0, duration: 0.4)
        let fade = SKAction.fadeOut(withDuration: 0.4)
        return SKAction.sequence([
            SKAction.group([expand, fade]),
            SKAction.removeFromParent()
        ])
    }()

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
            damage: 1,
            speed: Constants.AdvancedEnemies.cruiseMissileMinSpeed,
            imageName: "Bullet",
            flyingPath: dummyPath
        )
        removeComponent(ofType: FlyingProjectileComponent.self)
        configureHealth(Constants.AdvancedEnemies.cruiseMissileHealth)

        // Gray cruise missile sprite
        if let spriteNode = component(ofType: SpriteComponent.self)?.spriteNode {
            spriteNode.size = Constants.SpriteSize.cruiseMissile
            if let tex = AnimationTextureCache.shared.projectileTextures["missile_cruise"] {
                spriteNode.texture = tex
                spriteNode.color = .white
                spriteNode.colorBlendFactor = 0
            } else {
                spriteNode.color = UIColor(white: 0.55, alpha: 1)
                spriteNode.colorBlendFactor = 1.0
            }
        }
    }

    required init(damage: CGFloat, speed: CGFloat, imageName: String, flyingPath: FlyingPath) {
        super.init(damage: damage, speed: speed, imageName: imageName, flyingPath: flyingPath)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configureFlight(from spawnPoint: CGPoint, to target: CGPoint, speed missileSpeed: CGFloat) {
        self.targetPoint = target
        self.speed = missileSpeed

        if let spriteNode = component(ofType: SpriteComponent.self)?.spriteNode {
            spriteNode.position = spawnPoint
        }

        let dx = target.x - spawnPoint.x
        let dy = target.y - spawnPoint.y
        let dist = sqrt(dx * dx + dy * dy)
        guard dist > 0 else { return }

        // Generate zig-zag waypoint deviation
        let dirX = dx / dist
        let dirY = dy / dist
        velocity = CGVector(dx: dirX * missileSpeed, dy: dirY * missileSpeed)

        if let spriteNode = component(ofType: SpriteComponent.self)?.spriteNode {
            spriteNode.zRotation = atan2(dy, dx) - .pi / 2
        }
    }

    override func update(deltaTime seconds: TimeInterval) {
        guard !isHit else { return }
        guard let spriteNode = component(ofType: SpriteComponent.self)?.spriteNode else { return }

        // Dive timer
        if isDiving {
            diveTimer -= seconds
            if diveTimer <= 0 {
                isDiving = false
                // Restore cruise altitude
                if let altComp = component(ofType: AltitudeComponent.self) {
                    altComp.altitude = .cruise
                }
            }
        }

        // Continuous arc-based steering
        let currentAngle = atan2(velocity.dy, velocity.dx)
        var desiredAngle = atan2(targetPoint.y - spriteNode.position.y,
                                 targetPoint.x - spriteNode.position.x)

        // Evasion: if rocket nearby, steer perpendicular to dodge
        if let scene = spriteNode.scene as? InPlaySKScene {
            let evasionRadius = Constants.AdvancedEnemies.cruiseMissileEvasionRadius
            for rocket in scene.entities.compactMap({ $0 as? RocketEntity }) {
                guard let rocketPos = rocket.component(ofType: SpriteComponent.self)?.spriteNode.position else { continue }
                let rdx = rocketPos.x - spriteNode.position.x
                let rdy = rocketPos.y - spriteNode.position.y
                if rdx * rdx + rdy * rdy < evasionRadius * evasionRadius {
                    let rocketAngle = atan2(rdy, rdx)
                    let perpLeft = rocketAngle + .pi / 2
                    let perpRight = rocketAngle - .pi / 2
                    desiredAngle = abs(angleDiff(currentAngle, perpLeft)) < abs(angleDiff(currentAngle, perpRight))
                        ? perpLeft : perpRight
                    break
                }
            }
        }

        // Apply turn rate limit
        let maxTurn = Constants.AdvancedEnemies.cruiseMissileTurnRate * CGFloat(seconds)
        let diff = angleDiff(currentAngle, desiredAngle)
        let clampedDiff = max(-maxTurn, min(maxTurn, diff))
        var newAngle = currentAngle + clampedDiff

        // Constraint: velocity.y must always be negative (flying downward toward HQ)
        // Clamp angle to [-π, 0] range (lower half-plane)
        let candidateDy = sin(newAngle)
        if candidateDy > 0 {
            // Would fly upward — clamp to horizontal
            newAngle = velocity.dx >= 0 ? 0 : .pi
        }

        let currentSpeed = sqrt(velocity.dx * velocity.dx + velocity.dy * velocity.dy)
        velocity = CGVector(dx: cos(newAngle) * currentSpeed, dy: sin(newAngle) * currentSpeed)

        // Move
        spriteNode.position.x += velocity.dx * CGFloat(seconds)
        spriteNode.position.y += velocity.dy * CGFloat(seconds)

        // Update rotation to match velocity
        spriteNode.zRotation = atan2(velocity.dy, velocity.dx) - .pi / 2

        // Random dive near towers
        if !isDiving, let scene = spriteNode.scene as? InPlaySKScene {
            if let towerPlacement = scene.towerPlacement {
                for tower in towerPlacement.towers {
                    guard let stats = tower.stats, !stats.isDisabled else { continue }
                    let tPos = tower.worldPosition
                    let dx = tPos.x - spriteNode.position.x
                    let dy = tPos.y - spriteNode.position.y
                    if dx * dx + dy * dy < stats.range * stats.range * 0.5 {
                        if CGFloat.random(in: 0...1) < Constants.AdvancedEnemies.cruiseMissileDiveChance * CGFloat(seconds) {
                            isDiving = true
                            diveTimer = Constants.AdvancedEnemies.cruiseMissileDiveDuration
                            if let altComp = component(ofType: AltitudeComponent.self) {
                                altComp.altitude = .low
                            }
                        }
                        break
                    }
                }
            }
        }

        // Night mode: persistent flame, no puffs
        let gameScene = spriteNode.scene as? InPlaySKScene
        let nightMode = gameScene?.isNightWave == true

        if nightMode {
            spriteNode.color = .clear
            if nightFlameNode == nil {
                let flameTex = AnimationTextureCache.shared.flameGlow ?? Self.smokePuffTexture
                let flame = SKSpriteNode(texture: flameTex)
                flame.size = CGSize(width: 6, height: 6)
                flame.color = UIColor(red: 1, green: 0.35, blue: 0.1, alpha: 1)
                flame.colorBlendFactor = AnimationTextureCache.shared.flameGlow != nil ? 0 : 1.0
                flame.alpha = 0.85
                flame.position = CGPoint(x: 0, y: -spriteNode.size.height * 0.55)
                flame.zPosition = Constants.NightWave.nightEffectZPosition - spriteNode.zPosition
                spriteNode.addChild(flame)
                let flicker = SKAction.sequence([
                    SKAction.group([SKAction.fadeAlpha(to: 0.5, duration: 0.08), SKAction.scale(to: 0.85, duration: 0.08)]),
                    SKAction.group([SKAction.fadeAlpha(to: 0.9, duration: 0.06), SKAction.scale(to: 1.15, duration: 0.06)]),
                    SKAction.group([SKAction.fadeAlpha(to: 0.6, duration: 0.10), SKAction.scale(to: 0.9, duration: 0.10)]),
                    SKAction.group([SKAction.fadeAlpha(to: 0.85, duration: 0.06), SKAction.scale(to: 1.05, duration: 0.06)])
                ])
                flame.run(SKAction.repeatForever(flicker))
                nightFlameNode = flame
            }
        } else {
            spriteNode.color = UIColor(white: 0.55, alpha: 1)
            if let flame = nightFlameNode { flame.removeFromParent(); nightFlameNode = nil }

            // Day smoke trail
            smokeAccumulator += seconds
            if smokeAccumulator >= 0.08, let scene = spriteNode.scene {
                smokeAccumulator = 0

                let tailOffset = CGPoint(x: 0, y: -spriteNode.size.height * 0.55)
                var tailPoint = spriteNode.convert(tailOffset, to: scene)
                tailPoint.x += CGFloat.random(in: -1.5...1.5)
                tailPoint.y += CGFloat.random(in: -1.5...1.5)

                let puff = gameScene?.acquireSmokePuff() ?? SKSpriteNode(texture: Self.smokePuffTexture)
                puff.size = CGSize(width: 5, height: 5)
                puff.position = tailPoint
                puff.zPosition = 40
                puff.color = UIColor(white: 0.7, alpha: 0.8)
                puff.colorBlendFactor = 1.0
                puff.alpha = 0.5
                scene.addChild(puff)
                puff.run(SKAction.sequence([
                    SKAction.group([SKAction.scale(to: 2.0, duration: 0.4), SKAction.fadeOut(withDuration: 0.4)]),
                    SKAction.run { [weak gameScene, weak puff] in
                        guard let gameScene, let puff else { return }
                        gameScene.releaseSmokePuff(puff)
                    }
                ]))
            }
        }
    }

    private func angleDiff(_ from: CGFloat, _ to: CGFloat) -> CGFloat {
        var diff = to - from
        while diff > .pi { diff -= 2 * .pi }
        while diff < -.pi { diff += 2 * .pi }
        return diff
    }

    override func didHit() {
        isHit = true

        let physicBody = component(ofType: GeometryComponent.self)?.geometryNode.physicsBody
        physicBody?.contactTestBitMask = 0
        physicBody?.categoryBitMask = 0

        if let spriteNode = component(ofType: SpriteComponent.self)?.spriteNode {
            let flash = SKSpriteNode(color: .orange, size: CGSize(width: 24, height: 24))
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
        if let spriteNode = component(ofType: SpriteComponent.self)?.spriteNode,
           let scene = spriteNode.scene {
            let flash = SKSpriteNode(color: .orange, size: CGSize(width: 20, height: 20))
            flash.position = spriteNode.position
            flash.zPosition = (scene as? InPlaySKScene)?.isNightWave == true ? Constants.NightWave.nightEffectZPosition : 50
            flash.alpha = 0.7
            scene.addChild(flash)
            let expand = SKAction.scale(to: 2.0, duration: 0.15)
            let fade = SKAction.fadeOut(withDuration: 0.15)
            flash.run(SKAction.sequence([SKAction.group([expand, fade]), SKAction.removeFromParent()]))
        }
        removeFromParent()
    }
}
