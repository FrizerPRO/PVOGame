//
//  TowerEntity.swift
//  PVOGame
//

import UIKit
import GameplayKit
import SpriteKit

class TowerEntity: GKEntity {
    let towerType: TowerType
    private var timeSinceLastShot: TimeInterval = 0
    private(set) var currentTarget: AttackDroneEntity?
    private var rangeIndicator: SKShapeNode?
    private var wasDisabled = false
    private var smokeEmitter: SKNode?

    // Multi-layer sprite nodes (nil when fallback colored squares are used)
    private(set) var turretNode: SKSpriteNode?
    private(set) var muzzleNode: SKSpriteNode?

    // Magazine visual indicators
    private var ammoDots: [SKShapeNode] = []
    private var reloadArc: SKShapeNode?

    init(towerType: TowerType, at gridPosition: (row: Int, col: Int), worldPosition: CGPoint) {
        self.towerType = towerType
        super.init()

        let cellBase: CGFloat = Constants.SpriteSize.towerBase
        let footprint = towerType.footprint
        let footprintSize = CGSize(
            width: cellBase * CGFloat(footprint.cols),
            height: cellBase * CGFloat(footprint.rows)
        )
        let cache = AnimationTextureCache.shared
        let towerTex = cache.towerTextures[towerType]
        // Visible sprite size: prefer the aspect-preserving override when the
        // texture has been cropped to its content bbox; otherwise fall back to
        // the full footprint rectangle.
        let renderSize = towerTex?.baseRenderSize ?? footprintSize

        // Base sprite: use texture if available, otherwise fall back to colored square
        let spriteComponent: SpriteComponent
        if let baseTex = towerTex?.base {
            spriteComponent = SpriteComponent(color: .white, size: renderSize)
            spriteComponent.spriteNode.texture = baseTex
        } else {
            spriteComponent = SpriteComponent(color: towerType.color, size: renderSize)
        }
        spriteComponent.spriteNode.position = worldPosition
        spriteComponent.spriteNode.zPosition = 25
        addComponent(spriteComponent)

        // Turret / launcher / antenna / soldier child node
        if let turretTex = towerTex?.turret {
            let turret = SKSpriteNode(texture: turretTex, size: towerTex!.turretSize)
            turret.anchorPoint = towerTex!.turretAnchor
            turret.zPosition = 2  // above base
            turret.position = towerTex!.turretPosition
            spriteComponent.spriteNode.addChild(turret)
            self.turretNode = turret

            // Muzzle flash child (gun towers only)
            if let muzzleTex = towerTex?.muzzle {
                let muzzle = SKSpriteNode(texture: muzzleTex, size: towerTex!.muzzleSize)
                muzzle.zPosition = 3  // above turret
                muzzle.position = towerTex!.muzzleOffsetLeft  // default position
                muzzle.isHidden = true
                turret.addChild(muzzle)
                self.muzzleNode = muzzle
            }
        }

        // Physics body covers the grid footprint (not the visible sprite) so
        // bomb/HARM hits register on any cell the tower occupies, even when the
        // visible sprite is narrower due to aspect-preserving letterboxing.
        let body = SKPhysicsBody(rectangleOf: footprintSize)
        body.categoryBitMask = Constants.towerBitMask
        body.contactTestBitMask = Constants.mineBombBitMask
        body.collisionBitMask = 0
        body.isDynamic = false
        spriteComponent.spriteNode.physicsBody = body
        spriteComponent.spriteNode.userData = ["tower": self]

        addComponent(GridPositionComponent(
            row: gridPosition.row, col: gridPosition.col,
            rowSpan: footprint.rows, colSpan: footprint.cols
        ))

        addComponent(TowerStatsComponent(
            towerType: towerType,
            range: towerType.baseRange,
            fireRate: towerType.baseFireRate,
            damage: towerType.baseDamage,
            reachableAltitudes: towerType.reachableAltitudes,
            cost: towerType.cost
        ))

        addComponent(TowerTargetingComponent())
        addComponent(TowerRotationComponent())

        // Animation component
        let animComp = TowerAnimationComponent(towerType: towerType)
        animComp.turretNode = turretNode
        animComp.muzzleNode = muzzleNode
        addComponent(animComp)

        // EW tower: add EW component
        if towerType == .ewTower {
            addComponent(EWTowerComponent())
        }

        // Radar tower: add radar component (night-only range circle + drone spots)
        if towerType == .radar {
            addComponent(RadarComponent())
        }

        // Oil refinery: add refinery component with health bar
        if towerType == .oilRefinery {
            let refineryComp = OilRefineryComponent()
            addComponent(refineryComp)
            refineryComp.setupHealthBar(on: spriteComponent.spriteNode, size: footprintSize.width)
        }

        // Magazine towers: ammo dots created after tech buffs are applied via rebuildAmmoDots()
        if let capacity = towerType.magazineCapacity {
            setupAmmoDots(count: capacity, on: spriteComponent.spriteNode)
        }
    }

    func rebuildAmmoDots() {
        guard let spriteNode = component(ofType: SpriteComponent.self)?.spriteNode,
              let capacity = stats?.magazineCapacity else { return }
        for dot in ammoDots { dot.removeFromParent() }
        ammoDots.removeAll()
        setupAmmoDots(count: capacity, on: spriteNode)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var stats: TowerStatsComponent? {
        component(ofType: TowerStatsComponent.self)
    }

    var worldPosition: CGPoint {
        component(ofType: SpriteComponent.self)?.spriteNode.position ?? .zero
    }

    func showRangeIndicator() {
        guard let spriteNode = component(ofType: SpriteComponent.self)?.spriteNode,
              let scene = spriteNode.scene,
              let range = stats?.range,
              rangeIndicator == nil else { return }

        let towerColor = towerType.color
        let towerWorldPos = spriteNode.position

        // Check if tower is on highGround for LOS occlusion
        let onHighGround: Bool
        if let gridPos = component(ofType: GridPositionComponent.self),
           let gameScene = scene as? InPlaySKScene,
           let cell = gameScene.gridMap?.cell(atRow: gridPos.row, col: gridPos.col) {
            onHighGround = cell.terrain == .highGround
        } else {
            onHighGround = false
        }

        let circle: SKShapeNode
        if let gameScene = scene as? InPlaySKScene,
           let gridMap = gameScene.gridMap,
           !onHighGround {
            let occludedPath = gridMap.rangePathWithOcclusion(radius: range, towerWorldPos: towerWorldPos, towerOnHighGround: false)
            circle = SKShapeNode(path: occludedPath)
        } else {
            circle = SKShapeNode(circleOfRadius: range)
        }

        circle.strokeColor = towerColor.withAlphaComponent(0.4)
        circle.fillColor = towerColor.withAlphaComponent(0.08)
        circle.lineWidth = 1.5
        circle.zPosition = 22
        // Add to scene at tower world position — not as child of spriteNode, so it won't rotate
        circle.position = towerWorldPos
        let pattern: [CGFloat] = [6, 4]
        if let originalPath = circle.path {
            let dashed = originalPath.copy(dashingWithPhase: 0, lengths: pattern)
            circle.path = dashed
        }
        scene.addChild(circle)
        rangeIndicator = circle
    }

    func hideRangeIndicator() {
        rangeIndicator?.removeFromParent()
        rangeIndicator = nil
    }

    // MARK: - Durability

    func takeBombDamage(_ amount: Int) {
        guard let stats else { return }
        stats.takeBombDamage(amount)
        if stats.isDisabled {
            showDisabledEffect()
        }
    }

    func fullRepair() {
        guard let stats else { return }
        let wasDamaged = stats.isDisabled
        stats.fullRepair()
        if wasDamaged {
            hideDisabledEffect()
            wasDisabled = false
        }
    }

    private func showDisabledEffect() {
        guard let spriteNode = component(ofType: SpriteComponent.self)?.spriteNode else { return }
        spriteNode.colorBlendFactor = 0.7
        spriteNode.color = .darkGray
        turretNode?.colorBlendFactor = 0.7
        turretNode?.color = .darkGray

        // Notify animation component
        component(ofType: TowerAnimationComponent.self)?.onDisabled()

        let damageTex = AnimationTextureCache.shared.damageSmokeTexture
        if smokeEmitter == nil {
            let smoke = SKNode()
            smoke.name = "towerSmoke"
            let smokeAction = SKAction.repeatForever(SKAction.sequence([
                SKAction.run { [weak spriteNode, weak smoke, damageTex] in
                    guard spriteNode != nil, let smoke else { return }
                    let puff: SKSpriteNode
                    if let tex = damageTex {
                        puff = SKSpriteNode(texture: tex, size: CGSize(width: 8, height: 8))
                        puff.alpha = 0.5
                    } else {
                        puff = SKSpriteNode(color: UIColor.gray.withAlphaComponent(0.5), size: CGSize(width: 8, height: 8))
                    }
                    puff.position = CGPoint(
                        x: CGFloat.random(in: -6...6),
                        y: CGFloat.random(in: -2...4)
                    )
                    puff.zPosition = 30
                    smoke.addChild(puff)
                    let rise = SKAction.moveBy(x: CGFloat.random(in: -4...4), y: 18, duration: 0.8)
                    let fade = SKAction.fadeOut(withDuration: 0.8)
                    puff.run(SKAction.sequence([SKAction.group([rise, fade]), SKAction.removeFromParent()]))
                },
                SKAction.wait(forDuration: 0.25)
            ]))
            smoke.run(smokeAction, withKey: "smokeLoop")
            spriteNode.addChild(smoke)
            smokeEmitter = smoke
        }
        wasDisabled = true
    }

    private func hideDisabledEffect() {
        guard let spriteNode = component(ofType: SpriteComponent.self)?.spriteNode else { return }

        smokeEmitter?.removeAllActions()
        smokeEmitter?.removeFromParent()
        smokeEmitter = nil

        let hasTexture = AnimationTextureCache.shared.towerTextures[towerType]?.base != nil

        // Repair flash: white → original color
        let originalColor = towerType.color
        spriteNode.color = .white
        spriteNode.colorBlendFactor = 0
        turretNode?.colorBlendFactor = 0
        let flash = SKAction.sequence([
            SKAction.wait(forDuration: 0.15),
            SKAction.run { [weak spriteNode, weak self] in
                spriteNode?.color = hasTexture ? .white : originalColor
                spriteNode?.colorBlendFactor = 0
                self?.turretNode?.colorBlendFactor = 0
            }
        ])
        spriteNode.run(flash)

        // Notify animation component to restart persistent animations
        component(ofType: TowerAnimationComponent.self)?.onRepaired()
    }

    override func update(deltaTime seconds: TimeInterval) {
        super.update(deltaTime: seconds)
        guard let stats else { return }
        let wasDisabledBefore = stats.isDisabled
        stats.updateRepair(deltaTime: seconds)
        if wasDisabledBefore && !stats.isDisabled {
            hideDisabledEffect()
            wasDisabled = false
        }

        // Magazine visuals
        if towerType.magazineCapacity != nil {
            updateAmmoDots(stats: stats)
            updateReloadArc(stats: stats)
        }
    }

    // MARK: - Magazine Visuals

    private func setupAmmoDots(count: Int, on parent: SKNode) {
        let dotRadius: CGFloat = 2.5
        let spacing: CGFloat = 8
        let totalWidth = CGFloat(count - 1) * spacing
        let startX = -totalWidth / 2

        for i in 0..<count {
            let dot = SKShapeNode(circleOfRadius: dotRadius)
            dot.fillColor = .green
            dot.strokeColor = .clear
            dot.zPosition = 30
            dot.position = CGPoint(x: startX + CGFloat(i) * spacing, y: -18)
            parent.addChild(dot)
            ammoDots.append(dot)
        }
    }

    private func updateAmmoDots(stats: TowerStatsComponent) {
        guard let ammo = stats.magazineAmmo else { return }
        for (i, dot) in ammoDots.enumerated() {
            dot.fillColor = i < ammo ? .green : .darkGray
        }
    }

    private func updateReloadArc(stats: TowerStatsComponent) {
        guard let spriteNode = component(ofType: SpriteComponent.self)?.spriteNode else { return }

        if stats.isReloading {
            let progress = stats.reloadProgress
            let arcRadius: CGFloat = 16
            let startAngle: CGFloat = .pi / 2
            let endAngle = startAngle + progress * .pi * 2

            if reloadArc == nil {
                let arc = SKShapeNode()
                arc.strokeColor = .orange
                arc.lineWidth = 2.0
                arc.fillColor = .clear
                arc.zPosition = 31
                spriteNode.addChild(arc)
                reloadArc = arc
            }

            let path = UIBezierPath(arcCenter: .zero, radius: arcRadius, startAngle: startAngle, endAngle: endAngle, clockwise: true)
            reloadArc?.path = path.cgPath
        } else {
            reloadArc?.removeFromParent()
            reloadArc = nil
        }
    }
}
