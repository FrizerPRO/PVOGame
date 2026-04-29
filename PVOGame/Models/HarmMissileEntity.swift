//
//  HarmMissileEntity.swift
//  PVOGame
//

import Foundation
import GameplayKit
import SpriteKit

final class HarmMissileEntity: AttackDroneEntity {

    override var isJammableByEW: Bool { false }

    weak var targetTower: TowerEntity?
    private var targetPoint: CGPoint = .zero
    private var velocity: CGVector = .zero
    private var smokeAccumulator: TimeInterval = 0
    private var nightFlameNode: SKSpriteNode?
    private var cruiseSpeed: CGFloat = 0
    private var initialDistanceToTarget: CGFloat = 0
    private var inTerminalDive: Bool = false


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
            speed: Constants.GameBalance.harmMissileBaseSpeed,
            imageName: "Bullet",
            flyingPath: dummyPath
        )
        removeComponent(ofType: FlyingProjectileComponent.self)

        // HARM flies NOE/terrain-masked: only gun-based AA can engage it.
        addComponent(AltitudeComponent(altitude: .micro))

        // HARM anti-radiation missile sprite
        if let spriteNode = component(ofType: SpriteComponent.self)?.spriteNode {
            spriteNode.size = Constants.SpriteSize.harmMissile
            if let tex = AnimationTextureCache.shared.projectileTextures["missile_harm"] {
                spriteNode.texture = tex
                spriteNode.color = .white
                spriteNode.colorBlendFactor = 0
            } else {
                spriteNode.color = UIColor(red: 0.4, green: 0.5, blue: 0.35, alpha: 1)
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

    func configureFlight(from spawnPoint: CGPoint, toTower tower: TowerEntity, speed missileSpeed: CGFloat) {
        self.targetTower = tower
        self.speed = missileSpeed
        self.cruiseSpeed = missileSpeed
        self.inTerminalDive = false

        // Target the tower's position
        if let towerPos = tower.component(ofType: SpriteComponent.self)?.spriteNode.position {
            self.targetPoint = towerPos
        }

        if let spriteNode = component(ofType: SpriteComponent.self)?.spriteNode {
            spriteNode.position = spawnPoint
        }

        let dx = targetPoint.x - spawnPoint.x
        let dy = targetPoint.y - spawnPoint.y
        let dist = sqrt(dx * dx + dy * dy)
        guard dist > 0 else { return }
        self.initialDistanceToTarget = dist

        let dirX = dx / dist
        let dirY = dy / dist
        velocity = CGVector(dx: dirX * missileSpeed, dy: dirY * missileSpeed)

        // Rotate sprite to face direction of travel
        if let spriteNode = component(ofType: SpriteComponent.self)?.spriteNode {
            spriteNode.zRotation = atan2(dy, dx) - .pi / 2
        }
    }

    override func update(deltaTime seconds: TimeInterval) {
        guard !isHit else { return }
        guard let spriteNode = component(ofType: SpriteComponent.self)?.spriteNode else { return }

        // Terminal dive: on the last N% of the path, boost speed along the current heading.
        let dxToTarget = targetPoint.x - spriteNode.position.x
        let dyToTarget = targetPoint.y - spriteNode.position.y
        let distToTarget = sqrt(dxToTarget * dxToTarget + dyToTarget * dyToTarget)
        if !inTerminalDive,
           initialDistanceToTarget > 0,
           distToTarget / initialDistanceToTarget <= Constants.GameBalance.harmTerminalDiveFraction {
            inTerminalDive = true
            let currentHeading = atan2(velocity.dy, velocity.dx)
            let boosted = cruiseSpeed * Constants.GameBalance.harmTerminalDiveBoost
            velocity = CGVector(dx: cos(currentHeading) * boosted, dy: sin(currentHeading) * boosted)
        }

        // Move
        spriteNode.position.x += velocity.dx * CGFloat(seconds)
        spriteNode.position.y += velocity.dy * CGFloat(seconds)

        // Check proximity to target — impact
        let dx = spriteNode.position.x - targetPoint.x
        let dy = spriteNode.position.y - targetPoint.y
        let dist = sqrt(dx * dx + dy * dy)
        if dist < 15 {
            (spriteNode.scene as? InPlaySKScene)?.onHarmHitTower(harm: self)
            reachedDestination()
            return
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
            spriteNode.color = UIColor(red: 0.4, green: 0.5, blue: 0.35, alpha: 1)
            if let flame = nightFlameNode { flame.removeFromParent(); nightFlameNode = nil }

            // Day smoke puffs
            smokeAccumulator += seconds
            if smokeAccumulator >= 0.1, let scene = spriteNode.scene {
                smokeAccumulator = 0

                let tailOffset = CGPoint(x: 0, y: -spriteNode.size.height * 0.55)
                var tailPoint = spriteNode.convert(tailOffset, to: scene)
                tailPoint.x += CGFloat.random(in: -1.5...1.5)
                tailPoint.y += CGFloat.random(in: -1.5...1.5)

                let puff = gameScene?.acquireSmokePuff() ?? SKSpriteNode(texture: Self.smokePuffTexture)
                puff.size = CGSize(width: 5, height: 5)
                puff.position = tailPoint
                puff.zPosition = 40
                puff.color = UIColor(white: 0.85, alpha: 0.9)
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

    override func didHit() {
        isHit = true

        let physicBody = component(ofType: GeometryComponent.self)?.geometryNode.physicsBody
        physicBody?.contactTestBitMask = 0
        physicBody?.categoryBitMask = 0

        // Orange explosion flash
        if let spriteNode = component(ofType: SpriteComponent.self)?.spriteNode {
            let flash = SKShapeNode(circleOfRadius: 12)
            flash.fillColor = .orange
            flash.strokeColor = .clear
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
        // Explosion VFX at impact point
        if let spriteNode = component(ofType: SpriteComponent.self)?.spriteNode,
           let scene = spriteNode.scene {
            let flash = SKShapeNode(circleOfRadius: 9)
            flash.fillColor = .orange
            flash.strokeColor = .clear
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
