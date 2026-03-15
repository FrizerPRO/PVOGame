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
    private(set) var towers = [TowerEntity]()

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

        let worldPos = scene.gridMap.worldPosition(forRow: gridPos.row, col: gridPos.col)
        let canPlace = scene.gridMap.canPlaceTower(atRow: gridPos.row, col: gridPos.col)

        let preview = SKSpriteNode(color: canPlace ? type.color.withAlphaComponent(0.5) : .red.withAlphaComponent(0.5),
                                    size: CGSize(width: 28, height: 28))
        preview.position = worldPos
        preview.zPosition = 30
        scene.addChild(preview)
        previewNode = preview

        let rangeCircle = SKShapeNode(circleOfRadius: type.baseRange)
        rangeCircle.strokeColor = canPlace ? type.color.withAlphaComponent(0.3) : .red.withAlphaComponent(0.3)
        rangeCircle.fillColor = canPlace ? type.color.withAlphaComponent(0.05) : .red.withAlphaComponent(0.05)
        rangeCircle.lineWidth = 1
        rangeCircle.zPosition = 21
        rangeCircle.position = worldPos
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
        guard scene.gridMap.canPlaceTower(atRow: gridPos.row, col: gridPos.col) else { return nil }
        guard economy.canAfford(type.cost) else { return nil }

        let worldPos = scene.gridMap.worldPosition(forRow: gridPos.row, col: gridPos.col)
        let tower = TowerEntity(towerType: type, at: (gridPos.row, gridPos.col), worldPosition: worldPos)

        scene.gridMap.placeTower(ObjectIdentifier(tower), atRow: gridPos.row, col: gridPos.col)
        economy.spend(type.cost)

        if let spriteNode = tower.component(ofType: SpriteComponent.self)?.spriteNode {
            spriteNode.removeFromParent()
            scene.addChild(spriteNode)
        }
        towers.append(tower)
        scene.entities.append(tower)
        clearPreview()
        return tower
    }

    func sellTower(_ tower: TowerEntity, economy: EconomyManager) {
        guard let gridPos = tower.component(ofType: GridPositionComponent.self),
              let stats = tower.stats else { return }

        economy.earn(stats.sellValue)
        scene?.gridMap.removeTower(atRow: gridPos.row, col: gridPos.col)
        tower.component(ofType: SpriteComponent.self)?.spriteNode.removeFromParent()
        tower.hideRangeIndicator()
        towers.removeAll { $0 === tower }
        if let idx = scene?.entities.firstIndex(of: tower) {
            scene?.entities.remove(at: idx)
        }
    }

    func upgradeTower(_ tower: TowerEntity, economy: EconomyManager) -> Bool {
        guard let stats = tower.stats, stats.level < 3 else { return false }
        let upgradeCost = Int(CGFloat(stats.cost) * Constants.TowerDefense.upgradeCostMultiplier)
        guard economy.canAfford(upgradeCost) else { return false }
        economy.spend(upgradeCost)
        stats.upgrade()

        // Visual feedback — color saturation increases with level
        if let sprite = tower.component(ofType: SpriteComponent.self)?.spriteNode {
            let scale: CGFloat = 1.0 + CGFloat(stats.level - 1) * 0.15
            sprite.setScale(scale)
        }
        return true
    }

    func removeAllTowers() {
        for tower in towers {
            if let gridPos = tower.component(ofType: GridPositionComponent.self) {
                scene?.gridMap.removeTower(atRow: gridPos.row, col: gridPos.col)
            }
            tower.component(ofType: SpriteComponent.self)?.spriteNode.removeFromParent()
            tower.hideRangeIndicator()
        }
        towers.removeAll()
    }

    func towerAt(gridPos: (row: Int, col: Int)) -> TowerEntity? {
        towers.first { tower in
            guard let gp = tower.component(ofType: GridPositionComponent.self) else { return false }
            return gp.row == gridPos.row && gp.col == gridPos.col
        }
    }
}
