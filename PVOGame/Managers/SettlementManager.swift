//
//  SettlementManager.swift
//  PVOGame
//

import SpriteKit

enum DroneTargetResult {
    case settlement(SettlementEntity)
    case refinery(TowerEntity)
    case none
}

class SettlementManager {
    private weak var scene: InPlaySKScene?
    private(set) var settlements: [SettlementEntity] = []

    init(scene: InPlaySKScene) {
        self.scene = scene
    }

    func generateAndPlace(on gridMap: GridMap, gridLayer: SKNode, count: Int) {
        let footprint = SettlementEntity.footprint
        let positions = gridMap.generateSettlementPositions(count: count, footprint: footprint)
        let types = SettlementType.allCases.shuffled()

        for (index, pos) in positions.enumerated() {
            let type = types[index % types.count]
            // Settlement world position is the geometric center of its 2×2
            // footprint, not the anchor cell center.
            let worldPos = gridMap.worldPosition(forRow: pos.row, col: pos.col, footprint: footprint)
            let settlement = SettlementEntity(
                type: type,
                gridRow: pos.row, gridCol: pos.col,
                worldPosition: worldPos,
                cellSize: gridMap.cellSize.width
            )

            gridMap.placeSettlement(ObjectIdentifier(settlement),
                                    atRow: pos.row, col: pos.col, footprint: footprint)

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

    /// Find an alive settlement whose footprint contains the given cell — lets
    /// a tap on any of a 2×2 settlement's four cells select it.
    func settlement(atRow row: Int, col: Int) -> SettlementEntity? {
        settlements.first { s in
            guard !s.isDestroyed,
                  let gp = s.component(ofType: GridPositionComponent.self) else { return false }
            return gp.contains(row: row, col: col)
        }
    }

    // MARK: - Drone Targeting

    func assignTarget(towers: [TowerEntity]) -> DroneTargetResult {
        // Check alive refineries first (high priority targets)
        let refineries = towers.filter {
            $0.towerType == .oilRefinery
            && !($0.component(ofType: OilRefineryComponent.self)?.isDestroyed ?? true)
            && !($0.stats?.isDisabled ?? true)
        }
        if !refineries.isEmpty,
           CGFloat.random(in: 0...1) < Constants.OilRefinery.refineryTargetChance {
            if let best = mostAttractiveRefinery(refineries: refineries, towers: towers) {
                return .refinery(best)
            }
        }

        // Fall through to settlement targeting
        let alive = aliveSettlements()
        guard !alive.isEmpty else { return .none }

        if CGFloat.random(in: 0...1) < Constants.Settlement.strategicTargetingChance {
            if let s = mostAttractiveSettlement(alive: alive, towers: towers) {
                return .settlement(s)
            }
        }
        if let s = alive.randomElement() {
            return .settlement(s)
        }
        return .none
    }

    private func mostAttractiveRefinery(refineries: [TowerEntity], towers: [TowerEntity]) -> TowerEntity? {
        var bestScore: CGFloat = -1
        var bestRefinery: TowerEntity?

        for refinery in refineries {
            let defenseScore = defenseScoreForPosition(refinery.worldPosition, towers: towers)
            let priority = refinery.component(ofType: OilRefineryComponent.self)?.targetPriority ?? Constants.OilRefinery.targetPriority
            let attractiveness = priority / (1.0 + defenseScore)
            if attractiveness > bestScore {
                bestScore = attractiveness
                bestRefinery = refinery
            }
        }

        return bestRefinery
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
        defenseScoreForPosition(settlement.worldPosition, towers: towers)
    }

    private func defenseScoreForPosition(_ position: CGPoint, towers: [TowerEntity]) -> CGFloat {
        guard let scene = scene, let gridMap = scene.gridMap else { return 0 }

        var score: CGFloat = 0
        for tower in towers {
            guard let stats = tower.stats, !stats.isDisabled else { continue }
            let towerPos = tower.worldPosition
            let dist = hypot(towerPos.x - position.x, towerPos.y - position.y)
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
