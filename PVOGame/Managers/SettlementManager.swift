//
//  SettlementManager.swift
//  PVOGame
//

import SpriteKit

class SettlementManager {
    private weak var scene: InPlaySKScene?
    private(set) var settlements: [SettlementEntity] = []

    init(scene: InPlaySKScene) {
        self.scene = scene
    }

    func generateAndPlace(on gridMap: GridMap, gridLayer: SKNode, count: Int) {
        let positions = gridMap.generateSettlementPositions(count: count)
        let types = SettlementType.allCases.shuffled()

        for (index, pos) in positions.enumerated() {
            let type = types[index % types.count]
            let worldPos = gridMap.worldPosition(forRow: pos.row, col: pos.col)
            let settlement = SettlementEntity(type: type, gridRow: pos.row, gridCol: pos.col, worldPosition: worldPos)

            gridMap.placeSettlement(ObjectIdentifier(settlement), atRow: pos.row, col: pos.col)

            if let sprite = settlement.component(ofType: SpriteComponent.self)?.spriteNode {
                gridLayer.addChild(sprite)
            }

            settlements.append(settlement)
        }
    }

    func aliveSettlements() -> [SettlementEntity] {
        settlements.filter { !$0.isDestroyed }
    }

    @discardableResult
    func damageSettlement(_ settlement: SettlementEntity, amount: Int) -> Bool {
        return settlement.takeDamage(amount)
    }

    @discardableResult
    func upgradeSettlement(_ settlement: SettlementEntity) -> Bool {
        return settlement.upgrade()
    }

    func totalWaveIncome() -> Int {
        aliveSettlements().reduce(0) { $0 + $1.incomePerWave }
    }

    func settlement(atRow row: Int, col: Int) -> SettlementEntity? {
        settlements.first { $0.gridRow == row && $0.gridCol == col && !$0.isDestroyed }
    }

    // MARK: - Drone Targeting

    func assignTarget(towers: [TowerEntity]) -> SettlementEntity? {
        let alive = aliveSettlements()
        guard !alive.isEmpty else { return nil }

        if CGFloat.random(in: 0...1) < Constants.Settlement.strategicTargetingChance {
            return mostAttractiveSettlement(alive: alive, towers: towers)
        } else {
            return alive.randomElement()
        }
    }

    private func mostAttractiveSettlement(alive: [SettlementEntity], towers: [TowerEntity]) -> SettlementEntity? {
        var bestScore: CGFloat = -1
        var bestSettlement: SettlementEntity?

        for settlement in alive {
            let defenseScore = defenseScoreFor(settlement: settlement, towers: towers)
            let attractiveness = settlement.targetPriority / (1.0 + defenseScore)
            if attractiveness > bestScore {
                bestScore = attractiveness
                bestSettlement = settlement
            }
        }

        return bestSettlement
    }

    private func defenseScoreFor(settlement: SettlementEntity, towers: [TowerEntity]) -> CGFloat {
        guard let scene = scene, let gridMap = scene.gridMap else { return 0 }

        let settlementPos = settlement.worldPosition
        var score: CGFloat = 0

        for tower in towers {
            guard let stats = tower.stats, !stats.isDisabled else { continue }
            let towerPos = tower.worldPosition
            let dist = hypot(towerPos.x - settlementPos.x, towerPos.y - settlementPos.y)
            let coverageRadius = gridMap.cellSize.width * 4
            if dist < coverageRadius {
                score += stats.fireRate * CGFloat(stats.damage)
            }
        }

        return score
    }

    func removeAll() {
        for settlement in settlements {
            settlement.component(ofType: SpriteComponent.self)?.spriteNode.removeFromParent()
        }
        settlements.removeAll()
    }
}
