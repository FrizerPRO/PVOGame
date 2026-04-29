//
//  EWDroneEntity.swift
//  PVOGame
//

import Foundation
import GameplayKit
import SpriteKit

final class EWDroneEntity: AttackDroneEntity {

    private var targetPoint: CGPoint = .zero
    private var velocity: CGVector = .zero
    private var jammingRingNode: SKShapeNode?
    private var jammingPulseTimer: TimeInterval = 0
    /// Randomized delay until next jamming lightning bolt.
    private var nextLightningDelay: TimeInterval = 0.9
    /// Periodic radial corona burst overlay timer.
    private var burstTimer: TimeInterval = 0
    private var nextBurstDelay: TimeInterval = 2.2

    let jamRadius: CGFloat = Constants.EW.ewDroneJamRadius

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
            damage: 0,
            speed: Constants.EW.ewDroneSpeed,
            imageName: "Drone",
            flyingPath: dummyPath
        )
        removeComponent(ofType: FlyingProjectileComponent.self)
        configureHealth(Constants.EW.ewDroneHealth)

        // Purple/magenta EW drone
        if let spriteNode = component(ofType: SpriteComponent.self)?.spriteNode {
            spriteNode.size = CGSize(width: Constants.SpriteSize.ewDrone, height: Constants.SpriteSize.ewDrone)
            if let tex = AnimationTextureCache.shared.droneTextures["drone_ew"] {
                spriteNode.texture = tex
                spriteNode.color = .white
                spriteNode.colorBlendFactor = 0
            } else {
                spriteNode.color = UIColor(red: 0.6, green: 0.2, blue: 0.8, alpha: 1)
                spriteNode.colorBlendFactor = 1.0
            }
        }

        addNavLights(wingspan: 20)
    }

    required init(damage: CGFloat, speed: CGFloat, imageName: String, flyingPath: FlyingPath) {
        super.init(damage: damage, speed: speed, imageName: imageName, flyingPath: flyingPath)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configureFlight(from spawnPoint: CGPoint, to target: CGPoint, speed ewSpeed: CGFloat) {
        self.targetPoint = target
        self.speed = ewSpeed

        if let spriteNode = component(ofType: SpriteComponent.self)?.spriteNode {
            spriteNode.position = spawnPoint
        }

        let dx = target.x - spawnPoint.x
        let dy = target.y - spawnPoint.y
        let dist = sqrt(dx * dx + dy * dy)
        guard dist > 0 else { return }

        let dirX = dx / dist
        let dirY = dy / dist
        velocity = CGVector(dx: dirX * ewSpeed, dy: dirY * ewSpeed)

        if let spriteNode = component(ofType: SpriteComponent.self)?.spriteNode {
            spriteNode.zRotation = atan2(dy, dx) - .pi / 2
        }
    }

    override func update(deltaTime seconds: TimeInterval) {
        guard !isHit else { return }
        guard let spriteNode = component(ofType: SpriteComponent.self)?.spriteNode else { return }

        spriteNode.position.x += velocity.dx * CGFloat(seconds)
        spriteNode.position.y += velocity.dy * CGFloat(seconds)

        // Crackling jamming lightning instead of expanding ring
        jammingPulseTimer += seconds
        if jammingPulseTimer >= nextLightningDelay {
            jammingPulseTimer = 0
            nextLightningDelay = TimeInterval.random(in: 0.6...1.4)
            spawnJammingLightning(at: spriteNode)
        }

        burstTimer += seconds
        if burstTimer >= nextBurstDelay {
            burstTimer = 0
            nextBurstDelay = TimeInterval.random(in: 1.8...2.8)
            spawnJammingBurst(at: spriteNode)
        }
    }

    /// Spawns several copies of the SAME bolt sprite around the drone at
    /// well-separated angles, so the drone looks surrounded by an electrical
    /// crackle of one variety. The sprite type is picked at random per
    /// discharge, so different discharges show different bolt families
    /// (jagged / forked / branching / twin). All bolts are parented to the
    /// drone so they follow its motion and scaled UNIFORMLY to keep native
    /// PNG proportions. Fades out over ~0.18s.
    private func spawnJammingLightning(at spriteNode: SKSpriteNode) {
        let textures = AnimationTextureCache.shared.ewBoltTextures
        guard let texture = textures.randomElement() else {
            let angle = CGFloat.random(in: 0..<(.pi * 2))
            spawnFallbackBolt(parent: spriteNode, angle: angle)
            applyLightningDamage(at: spriteNode, angles: [angle], boltLength: jamRadius)
            return
        }

        // Several copies of the SAME sprite, distributed evenly around the
        // drone with a small per-bolt jitter so they don't look mechanically
        // symmetric.
        let count = Int.random(in: 4...5)
        let baseAngle = CGFloat.random(in: 0..<(.pi * 2))
        let angularStep = (2 * .pi) / CGFloat(count)

        var angles: [CGFloat] = []
        for i in 0..<count {
            let angle = baseAngle + angularStep * CGFloat(i)
                + CGFloat.random(in: -0.25...0.25)
            spawnSingleBolt(at: spriteNode, texture: texture, angle: angle)
            angles.append(angle)
        }

        let texSize = texture.size()
        let scale = (jamRadius / 1.5) / max(texSize.width, texSize.height)
        applyLightningDamage(at: spriteNode, angles: angles,
                             boltLength: texSize.height * scale)
    }

    /// For each bolt's drone-local angle, projects every tower onto the bolt
    /// segment in world space and damages the ones inside the hit corridor.
    /// Each tower can be struck at most once per discharge.
    private func applyLightningDamage(at spriteNode: SKSpriteNode,
                                       angles: [CGFloat],
                                       boltLength: CGFloat) {
        guard let scene = spriteNode.scene as? InPlaySKScene,
              let towerPlacement = scene.towerPlacement else { return }
        let dronePos = spriteNode.position
        let droneRot = spriteNode.zRotation
        let halfWidth = Constants.EW.ewLightningHitHalfWidth

        var struckIDs = Set<ObjectIdentifier>()
        for angle in angles {
            let worldAngle = angle + droneRot
            let dx = cos(worldAngle)
            let dy = sin(worldAngle)
            for tower in towerPlacement.towers {
                let id = ObjectIdentifier(tower)
                guard !struckIDs.contains(id) else { continue }
                guard let stats = tower.stats, !stats.isDisabled else { continue }
                let towerPos = tower.worldPosition
                let rx = towerPos.x - dronePos.x
                let ry = towerPos.y - dronePos.y
                let along = rx * dx + ry * dy
                guard along >= 0, along <= boltLength else { continue }
                let perp = abs(rx * (-dy) + ry * dx)
                guard perp <= halfWidth else { continue }
                struckIDs.insert(id)
                tower.takeBombDamage(Constants.EW.ewLightningTowerDamage)
            }
        }
    }

    private func spawnSingleBolt(at spriteNode: SKSpriteNode,
                                  texture: SKTexture, angle: CGFloat) {
        let bolt = SKSpriteNode(texture: texture)
        // Anchor at the top-center of the sprite so the drone sits at the
        // bolt's origin and the bolt extends outward in the rotation direction.
        bolt.anchorPoint = CGPoint(x: 0.5, y: 1.0)
        // Uniform scale: keep the PNG's native aspect ratio. Long axis of the
        // sprite lands at jamRadius / 1.5 ≈ 100 pt in scene units.
        let texSize = texture.size()
        let scale = (jamRadius / 1.5) / max(texSize.width, texSize.height)
        bolt.setScale(scale)
        bolt.position = .zero
        // Local -y → drone-local direction `angle` ⇒ zRotation = angle + π/2.
        bolt.zRotation = angle + .pi / 2
        bolt.alpha = 0.95
        bolt.blendMode = .add
        bolt.zPosition = relativeZPos(under: spriteNode, offset: -1)
        spriteNode.addChild(bolt)

        bolt.run(SKAction.sequence([
            SKAction.fadeOut(withDuration: 0.18),
            SKAction.removeFromParent()
        ]))
    }

    /// Radial corona burst centered on the drone — uses fx_ew_bolt_burst with
    /// its empty middle aligned over the drone silhouette. Parented to the
    /// drone so it travels with it; scaled uniformly to preserve the original
    /// 1:1 sprite proportions.
    private func spawnJammingBurst(at spriteNode: SKSpriteNode) {
        guard let texture = AnimationTextureCache.shared.ewBoltBurst else { return }
        let burst = SKSpriteNode(texture: texture)
        let texSize = texture.size()
        let scale = (jamRadius * 1.1 / 1.5) / max(texSize.width, texSize.height)
        burst.setScale(scale)
        burst.position = .zero
        burst.zRotation = CGFloat.random(in: 0..<(.pi * 2))
        burst.alpha = 0.0
        burst.blendMode = .add
        burst.zPosition = relativeZPos(under: spriteNode, offset: -1)
        spriteNode.addChild(burst)

        burst.run(SKAction.sequence([
            SKAction.fadeAlpha(to: 0.85, duration: 0.08),
            SKAction.fadeOut(withDuration: 0.32),
            SKAction.removeFromParent()
        ]))
    }

    /// SpriteKit applies child zPositions cumulatively — child world z =
    /// parent.zPosition + child.zPosition. Returns the relative zPosition that
    /// produces the desired absolute target (night-wave overlay or sibling +
    /// offset).
    private func relativeZPos(under parent: SKSpriteNode, offset: CGFloat) -> CGFloat {
        let isNight = (parent.scene as? InPlaySKScene)?.isNightWave == true
        let absoluteTarget = isNight
            ? Constants.NightWave.nightEffectZPosition
            : parent.zPosition + offset
        return absoluteTarget - parent.zPosition
    }

    private func spawnFallbackBolt(parent: SKSpriteNode, angle: CGFloat) {
        let dist = jamRadius
        let endpoint = CGPoint(x: cos(angle) * dist, y: sin(angle) * dist)
        let perpX = -sin(angle)
        let perpY = cos(angle)

        let path = CGMutablePath()
        path.move(to: .zero)
        let segmentCount = Int.random(in: 4...6)
        let maxJitter = max(8, dist * 0.15)
        for i in 1..<segmentCount {
            let t = CGFloat(i) / CGFloat(segmentCount)
            let baseX = endpoint.x * t
            let baseY = endpoint.y * t
            let jitter = CGFloat.random(in: -maxJitter...maxJitter)
            path.addLine(to: CGPoint(x: baseX + perpX * jitter,
                                      y: baseY + perpY * jitter))
        }
        path.addLine(to: endpoint)

        let bolt = SKShapeNode(path: path)
        bolt.strokeColor = UIColor(red: 1.0, green: 0.45, blue: 0.95, alpha: 1.0)
        bolt.fillColor = .clear
        bolt.lineWidth = 1.5
        bolt.glowWidth = 2.5
        bolt.alpha = 0.95
        bolt.zPosition = relativeZPos(under: parent, offset: -1)
        parent.addChild(bolt)
        bolt.run(SKAction.sequence([
            SKAction.fadeOut(withDuration: 0.12),
            SKAction.removeFromParent()
        ]))
    }

    /// Check if a tower at `towerPos` is within jamming range.
    func isJamming(towerAt towerPos: CGPoint) -> Bool {
        guard !isHit else { return false }
        guard let dronePos = component(ofType: SpriteComponent.self)?.spriteNode.position else { return false }
        let dx = dronePos.x - towerPos.x
        let dy = dronePos.y - towerPos.y
        return dx * dx + dy * dy <= jamRadius * jamRadius
    }

    override func didHit() {
        isHit = true
        jammingRingNode?.removeFromParent()

        let physicBody = component(ofType: GeometryComponent.self)?.geometryNode.physicsBody
        physicBody?.contactTestBitMask = 0
        physicBody?.categoryBitMask = 0

        if let spriteNode = component(ofType: SpriteComponent.self)?.spriteNode {
            let flash = SKSpriteNode(color: .magenta, size: CGSize(width: 28, height: 28))
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
        removeFromParent()
    }
}
