//
//  TowerPlacementManager.swift
//  PVOGame
//

import SpriteKit

class TowerPlacementManager {
    private weak var scene: InPlaySKScene?
    private(set) var selectedTowerType: TowerType?
    private var previewNode: SKSpriteNode?
    private var previewRangeNode: SKShapeNode?
    var towers = [TowerEntity]()

    init(scene: InPlaySKScene) {
        self.scene = scene
    }

    func selectTowerType(_ type: TowerType?) {
        selectedTowerType = type
        clearPreview()
    }

    func showPreview(at gridPos: (row: Int, col: Int)) {
        guard let scene, let type = selectedTowerType else { return }
        clearPreview()

        let footprint = type.footprint
        let anchor = clampedAnchor(from: gridPos, footprint: footprint, in: scene.gridMap)
        let worldPos = scene.gridMap.worldPosition(forRow: anchor.row, col: anchor.col, footprint: footprint)
        let canPlace = scene.gridMap.canPlaceTower(atRow: anchor.row, col: anchor.col, footprint: footprint)

        let towerColor = type.color

        let previewSize = CGSize(
            width: Constants.SpriteSize.towerPreview * CGFloat(footprint.cols),
            height: Constants.SpriteSize.towerPreview * CGFloat(footprint.rows)
        )
        let preview = SKSpriteNode(color: canPlace ? towerColor.withAlphaComponent(0.5) : .red.withAlphaComponent(0.5),
                                    size: previewSize)
        preview.position = worldPos
        preview.zPosition = 30
        scene.addChild(preview)
        previewNode = preview

        var previewRange = type.baseRange
        // HighGround range bonus applies to preview too
        let terrainCell = scene.gridMap.cell(atRow: anchor.row, col: anchor.col)
        let onHighGround = terrainCell?.terrain == .highGround
        if onHighGround {
            previewRange *= Constants.TerrainZone.highGroundRangeMultiplier
        }

        let rangeCircle: SKShapeNode
        if !onHighGround {
            let occludedPath = scene.gridMap.rangePathWithOcclusion(radius: previewRange, towerWorldPos: worldPos, towerOnHighGround: false)
            rangeCircle = SKShapeNode(path: occludedPath)
            rangeCircle.position = worldPos
        } else {
            rangeCircle = SKShapeNode(circleOfRadius: previewRange)
            rangeCircle.position = worldPos
        }
        rangeCircle.strokeColor = canPlace ? towerColor.withAlphaComponent(0.3) : .red.withAlphaComponent(0.3)
        rangeCircle.fillColor = canPlace ? towerColor.withAlphaComponent(0.05) : .red.withAlphaComponent(0.05)
        rangeCircle.lineWidth = 1
        rangeCircle.zPosition = 21
        scene.addChild(rangeCircle)
        previewRangeNode = rangeCircle
    }

    func clearPreview() {
        previewNode?.removeFromParent()
        previewNode = nil
        previewRangeNode?.removeFromParent()
        previewRangeNode = nil
    }

    @discardableResult
    func placeTower(at gridPos: (row: Int, col: Int), economy: EconomyManager) -> TowerEntity? {
        guard let scene, let type = selectedTowerType else { return nil }
        let footprint = type.footprint
        let anchor = clampedAnchor(from: gridPos, footprint: footprint, in: scene.gridMap)
        guard scene.gridMap.canPlaceTower(atRow: anchor.row, col: anchor.col, footprint: footprint) else { return nil }
        guard economy.canAfford(type.cost) else { return nil }

        let worldPos = scene.gridMap.worldPosition(forRow: anchor.row, col: anchor.col, footprint: footprint)
        let tower = TowerEntity(towerType: type, at: (anchor.row, anchor.col), worldPosition: worldPos)

        // Terrain zone bonus: high ground gives +20% range
        if let cell = scene.gridMap.cell(atRow: anchor.row, col: anchor.col),
           cell.terrain == .highGround,
           let stats = tower.component(ofType: TowerStatsComponent.self) {
            stats.range *= Constants.TerrainZone.highGroundRangeMultiplier
        }

        scene.gridMap.placeTower(ObjectIdentifier(tower), atRow: anchor.row, col: anchor.col, footprint: footprint)
        economy.spend(type.cost)

        if let spriteNode = tower.component(ofType: SpriteComponent.self)?.spriteNode {
            spriteNode.removeFromParent()
            scene.addChild(spriteNode)
        }
        towers.append(tower)
        scene.entities.append(tower)
        clearPreview()

        // Trigger placement animation (bounce + radar spin / EW pulse start)
        tower.component(ofType: TowerAnimationComponent.self)?.onTowerPlaced()

        return tower
    }

    func sellTower(_ tower: TowerEntity, economy: EconomyManager) {
        guard let gridPos = tower.component(ofType: GridPositionComponent.self),
              let stats = tower.stats else { return }

        economy.earn(stats.sellValue)
        scene?.gridMap.removeTower(atRow: gridPos.row, col: gridPos.col,
                                   footprint: (rows: gridPos.rowSpan, cols: gridPos.colSpan))
        tower.component(ofType: SpriteComponent.self)?.spriteNode.removeFromParent()
        tower.hideRangeIndicator()
        towers.removeAll { $0 === tower }
        if let idx = scene?.entities.firstIndex(of: tower) {
            scene?.entities.remove(at: idx)
        }
    }

    func removeAllTowers() {
        for tower in towers {
            if let gridPos = tower.component(ofType: GridPositionComponent.self) {
                scene?.gridMap.removeTower(atRow: gridPos.row, col: gridPos.col,
                                           footprint: (rows: gridPos.rowSpan, cols: gridPos.colSpan))
            }
            tower.component(ofType: SpriteComponent.self)?.spriteNode.removeFromParent()
            tower.hideRangeIndicator()
        }
        towers.removeAll()
    }

    // MARK: - Drag Preview

    private static let radiiSampleCount = 72

    /// Current polar radii of the drag range shape (for smooth interpolation).
    private var currentRadii: [CGFloat] = []

    /// Create a persistent drag preview. Range circle is a child of sprite — moves with it.
    func createDragPreview(type: TowerType, at gridPos: (row: Int, col: Int)) -> (sprite: SKSpriteNode, range: SKShapeNode)? {
        guard let scene else { return nil }
        let footprint = type.footprint
        let anchor = clampedAnchor(from: gridPos, footprint: footprint, in: scene.gridMap)
        let worldPos = scene.gridMap.worldPosition(forRow: anchor.row, col: anchor.col, footprint: footprint)
        let canPlace = scene.gridMap.canPlaceTower(atRow: anchor.row, col: anchor.col, footprint: footprint)
        let affordable = scene.economyManager.canAfford(type.cost)
        let valid = canPlace && affordable

        let color = valid ? type.color.withAlphaComponent(0.5) : UIColor.red.withAlphaComponent(0.5)
        let sprite = SKSpriteNode(color: color,
                                   size: CGSize(width: Constants.SpriteSize.towerPreview * CGFloat(footprint.cols),
                                                height: Constants.SpriteSize.towerPreview * CGFloat(footprint.rows)))
        sprite.position = worldPos
        sprite.zPosition = 110
        scene.addChild(sprite)

        let range = effectiveRange(type: type, gridPos: anchor)
        let onHighGround = scene.gridMap.cell(atRow: anchor.row, col: anchor.col)?.terrain == .highGround
        currentRadii = scene.gridMap.occlusionRadii(
            from: worldPos, radius: range,
            towerOnHighGround: onHighGround,
            sampleCount: Self.radiiSampleCount)

        let path = GridMap.pathFromRadii(currentRadii)
        let rangeNode = SKShapeNode(path: path)
        rangeNode.position = .zero
        let tintColor: UIColor = valid ? type.color : .red
        rangeNode.strokeColor = tintColor.withAlphaComponent(0.3)
        rangeNode.fillColor = tintColor.withAlphaComponent(0.05)
        rangeNode.lineWidth = 1
        rangeNode.zPosition = -1
        sprite.addChild(rangeNode)

        return (sprite, rangeNode)
    }

    /// Create drag preview at an arbitrary world point (when outside grid).
    func createDragPreviewFreeform(type: TowerType, at worldPos: CGPoint) -> (sprite: SKSpriteNode, range: SKShapeNode)? {
        guard let scene else { return nil }
        let footprint = type.footprint
        let color = UIColor.red.withAlphaComponent(0.5)
        let sprite = SKSpriteNode(color: color,
                                   size: CGSize(width: Constants.SpriteSize.towerPreview * CGFloat(footprint.cols),
                                                height: Constants.SpriteSize.towerPreview * CGFloat(footprint.rows)))
        sprite.position = worldPos
        sprite.zPosition = 110
        scene.addChild(sprite)

        currentRadii = [CGFloat](repeating: type.baseRange, count: Self.radiiSampleCount)
        let path = GridMap.pathFromRadii(currentRadii)
        let rangeNode = SKShapeNode(path: path)
        rangeNode.position = .zero
        rangeNode.strokeColor = UIColor.red.withAlphaComponent(0.3)
        rangeNode.fillColor = UIColor.red.withAlphaComponent(0.05)
        rangeNode.lineWidth = 1
        rangeNode.zPosition = -1
        rangeNode.alpha = 0.3
        sprite.addChild(rangeNode)

        return (sprite, rangeNode)
    }

    /// Animate drag preview to a new grid cell. Range morphs smoothly via polar interpolation.
    func updateDragPreview(sprite: SKSpriteNode, range: SKShapeNode,
                           type: TowerType, to gridPos: (row: Int, col: Int),
                           duration: TimeInterval) {
        guard let scene else { return }
        let footprint = type.footprint
        let anchor = clampedAnchor(from: gridPos, footprint: footprint, in: scene.gridMap)
        let worldPos = scene.gridMap.worldPosition(forRow: anchor.row, col: anchor.col, footprint: footprint)
        let canPlace = scene.gridMap.canPlaceTower(atRow: anchor.row, col: anchor.col, footprint: footprint)
        let affordable = scene.economyManager.canAfford(type.cost)
        let valid = canPlace && affordable

        // Update sprite color
        sprite.color = valid ? type.color.withAlphaComponent(0.5) : UIColor.red.withAlphaComponent(0.5)

        // Animate sprite to cell center — range follows as child
        sprite.removeAllActions()
        let moveAction = SKAction.move(to: worldPos, duration: duration)
        moveAction.timingMode = .easeOut
        sprite.run(moveAction)

        // Compute target polar radii for the new cell
        let newEffective = effectiveRange(type: type, gridPos: anchor)
        let onHighGround = scene.gridMap.cell(atRow: anchor.row, col: anchor.col)?.terrain == .highGround
        let targetRadii = scene.gridMap.occlusionRadii(
            from: worldPos, radius: newEffective,
            towerOnHighGround: onHighGround,
            sampleCount: Self.radiiSampleCount)

        let startRadii = currentRadii
        currentRadii = targetRadii

        // Update colors
        let tintColor: UIColor = valid ? type.color : .red
        range.strokeColor = tintColor.withAlphaComponent(0.3)
        range.fillColor = tintColor.withAlphaComponent(0.05)
        range.alpha = 1.0

        // Morph path frame-by-frame: interpolate each polar radius from old → new
        range.removeAllActions()
        let count = Self.radiiSampleCount
        let morphAction = SKAction.customAction(withDuration: duration) { node, elapsed in
            guard let shapeNode = node as? SKShapeNode else { return }
            let t = min(CGFloat(elapsed) / CGFloat(duration), 1.0)
            // Ease-out
            let eased = 1.0 - (1.0 - t) * (1.0 - t)
            var interpolated = [CGFloat](repeating: 0, count: count)
            for i in 0..<count {
                interpolated[i] = startRadii[i] + (targetRadii[i] - startRadii[i]) * eased
            }
            shapeNode.path = GridMap.pathFromRadii(interpolated)
        }
        range.run(morphAction)
    }

    /// Move drag preview to follow finger when outside the grid.
    func moveDragPreviewFreeform(sprite: SKSpriteNode, range: SKShapeNode, to worldPos: CGPoint) {
        sprite.removeAllActions()
        sprite.position = worldPos
        sprite.color = UIColor.red.withAlphaComponent(0.5)

        range.removeAllActions()
        range.alpha = 0.3
    }

    /// Compute the effective range for a tower type at a given grid position.
    private func effectiveRange(type: TowerType, gridPos: (row: Int, col: Int)) -> CGFloat {
        var range = type.baseRange
        if let cell = scene?.gridMap.cell(atRow: gridPos.row, col: gridPos.col),
           cell.terrain == .highGround {
            range *= Constants.TerrainZone.highGroundRangeMultiplier
        }
        return range
    }

    func towerAt(gridPos: (row: Int, col: Int)) -> TowerEntity? {
        towers.first { tower in
            guard let gp = tower.component(ofType: GridPositionComponent.self) else { return false }
            return gp.contains(row: gridPos.row, col: gridPos.col)
        }
    }

    /// Slide a multi-cell footprint inward so it never overflows the grid.
    /// The anchor is the top-left cell of the footprint.
    static func clampedAnchor(row: Int, col: Int,
                              footprint: (rows: Int, cols: Int),
                              in gridMap: GridMap) -> (row: Int, col: Int) {
        let clampedCol = max(0, min(col, gridMap.cols - footprint.cols))
        let clampedRow = max(0, min(row, gridMap.rows - footprint.rows))
        return (clampedRow, clampedCol)
    }

    private func clampedAnchor(from gridPos: (row: Int, col: Int),
                                footprint: (rows: Int, cols: Int),
                                in gridMap: GridMap) -> (row: Int, col: Int) {
        Self.clampedAnchor(row: gridPos.row, col: gridPos.col, footprint: footprint, in: gridMap)
    }
}
