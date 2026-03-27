//
//  TowerSynergyManager.swift
//  PVOGame
//
//  Echeloned PVO synergy system with prominent visual feedback.
//  Glowing auras, pulsing connection lines, and floating labels.
//

import SpriteKit

class TowerSynergyManager {

    // All synergy visual nodes (for cleanup)
    private var visualNodes: [SKNode] = []

    // Active buff state per tower
    private var appliedBonuses: [ObjectIdentifier: [String]] = [:]

    /// Recalculate all synergies. Call when towers are placed, sold, or upgraded.
    func recalculate(towers: [TowerEntity], in scene: SKScene) {
        clearAllVisuals()
        revertAllBonuses(towers: towers)

        for tower in towers {
            guard let gridPos = tower.component(ofType: GridPositionComponent.self),
                  let stats = tower.stats else { continue }

            let neighborEntities = findNeighborEntities(of: tower, in: towers)
            let neighborTypes = neighborEntities.compactMap { $0.stats?.towerType }

            // 1. Radar + SAM/Interceptor: Target Designation (+20% range)
            if stats.towerType == .samLauncher || stats.towerType == .interceptor {
                let radarNeighbor = neighborEntities.first { $0.stats?.towerType == .radar }
                if let radar = radarNeighbor {
                    stats.range *= 1.2
                    recordBonus(tower, "radarDesignation")
                    showConnectionLine(from: tower, to: radar, color: .systemYellow, in: scene)
                    showAura(on: tower, color: .systemYellow, in: scene)
                    showSynergyLabel(on: tower, text: "ЦЕЛЕУКАЗАНИЕ", color: .systemYellow, in: scene)
                }
            }

            // 2. Two same SAMs adjacent: Cross-Engagement (+10% fire rate)
            if stats.towerType == .samLauncher || stats.towerType == .interceptor {
                let sameNeighbor = neighborEntities.first { $0.stats?.towerType == stats.towerType }
                if let partner = sameNeighbor {
                    stats.fireRate *= 1.1
                    recordBonus(tower, "crossEngagement")
                    showConnectionLine(from: tower, to: partner, color: .systemOrange, in: scene)
                    showAura(on: tower, color: .systemOrange, in: scene)
                }
            }

            // 3. Gun + SAM: Echelon Optimization (+10% fire rate to gun)
            if stats.towerType == .autocannon || stats.towerType == .ciws {
                let samNeighbor = neighborEntities.first {
                    $0.stats?.towerType == .samLauncher || $0.stats?.towerType == .interceptor
                }
                if let sam = samNeighbor {
                    stats.fireRate *= 1.1
                    recordBonus(tower, "echelonOptimization")
                    showConnectionLine(from: tower, to: sam, color: .systemGreen, in: scene)
                    showAura(on: tower, color: .systemGreen, in: scene)
                }
            }

            // 4. EW + CIWS: Jamming Protection (+15% range)
            if stats.towerType == .ciws {
                let ewNeighbor = neighborEntities.first { $0.stats?.towerType == .ewTower }
                if let ew = ewNeighbor {
                    stats.range *= 1.15
                    recordBonus(tower, "jammingProtection")
                    showConnectionLine(from: tower, to: ew, color: .systemTeal, in: scene)
                    showAura(on: tower, color: .systemTeal, in: scene)
                    showSynergyLabel(on: tower, text: "ПОМЕХОЗАЩИТА", color: .systemTeal, in: scene)
                }
            }

            // 5. 3 guns in line: Crossfire (+1 damage)
            if stats.towerType == .autocannon || stats.towerType == .ciws {
                if isInGunLine(tower: tower, gridPos: gridPos, towers: towers) {
                    stats.damage += 1
                    recordBonus(tower, "crossfire")
                    showAura(on: tower, color: .systemRed, in: scene)
                    showSynergyLabel(on: tower, text: "КИНЖАЛЬНЫЙ", color: .systemRed, in: scene)
                }
            }
        }

        // 6. PVO Umbrella (global bonus)
        checkUmbrellaBonus(towers: towers, in: scene)
    }

    // MARK: - Visuals

    private func showConnectionLine(from towerA: TowerEntity, to towerB: TowerEntity,
                                     color: UIColor, in scene: SKScene) {
        let posA = towerA.worldPosition
        let posB = towerB.worldPosition

        let path = CGMutablePath()
        path.move(to: posA)
        path.addLine(to: posB)

        let line = SKShapeNode(path: path)
        line.strokeColor = color.withAlphaComponent(0.6)
        line.lineWidth = 2.0
        line.zPosition = 20
        line.name = "synergyLine"

        // Dashed pattern
        let dashed = path.copy(dashingWithPhase: 0, lengths: [6, 4])
        line.path = dashed

        // Pulse animation
        line.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.fadeAlpha(to: 0.25, duration: 0.8),
            SKAction.fadeAlpha(to: 0.7, duration: 0.8),
        ])))

        scene.addChild(line)
        visualNodes.append(line)
    }

    private func showAura(on tower: TowerEntity, color: UIColor, in scene: SKScene) {
        guard let spriteNode = tower.component(ofType: SpriteComponent.self)?.spriteNode else { return }

        let aura = SKShapeNode(circleOfRadius: 20)
        aura.strokeColor = color.withAlphaComponent(0.5)
        aura.fillColor = color.withAlphaComponent(0.08)
        aura.lineWidth = 1.5
        aura.zPosition = 23
        aura.name = "synergyAura"

        // Pulse
        aura.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.scale(to: 1.15, duration: 1.0),
            SKAction.scale(to: 0.9, duration: 1.0),
        ])))

        spriteNode.addChild(aura)
        visualNodes.append(aura)
    }

    private func showSynergyLabel(on tower: TowerEntity, text: String, color: UIColor, in scene: SKScene) {
        guard let spriteNode = tower.component(ofType: SpriteComponent.self)?.spriteNode else { return }

        let label = SKLabelNode(fontNamed: Constants.GameBalance.hudFontName)
        label.text = text
        label.fontSize = 7
        label.fontColor = color
        label.position = CGPoint(x: 0, y: 20)
        label.zPosition = 36
        label.name = "synergyLabel"

        spriteNode.addChild(label)
        visualNodes.append(label)
    }

    private func clearAllVisuals() {
        for node in visualNodes {
            node.removeFromParent()
        }
        visualNodes.removeAll()
    }

    // MARK: - Neighbor Detection

    private func findNeighborEntities(of tower: TowerEntity, in towers: [TowerEntity]) -> [TowerEntity] {
        guard let gridPos = tower.component(ofType: GridPositionComponent.self) else { return [] }
        return towers.filter { other in
            guard other !== tower,
                  let otherPos = other.component(ofType: GridPositionComponent.self) else { return false }
            return abs(gridPos.row - otherPos.row) <= 1 && abs(gridPos.col - otherPos.col) <= 1
        }
    }

    // MARK: - Gun Line Detection

    private func isInGunLine(tower: TowerEntity, gridPos: GridPositionComponent, towers: [TowerEntity]) -> Bool {
        let gunTowers = towers.compactMap { t -> (row: Int, col: Int)? in
            guard let gp = t.component(ofType: GridPositionComponent.self),
                  let stats = t.stats,
                  stats.towerType == .autocannon || stats.towerType == .ciws else { return nil }
            return (gp.row, gp.col)
        }

        let directions = [(0, 1), (1, 0), (1, 1), (1, -1)]
        let r = gridPos.row
        let c = gridPos.col

        for (dr, dc) in directions {
            var count = 1
            for sign in [-1, 1] {
                var step = 1
                while gunTowers.contains(where: { $0.row == r + dr * sign * step && $0.col == c + dc * sign * step }) {
                    count += 1
                    step += 1
                }
            }
            if count >= 3 { return true }
        }
        return false
    }

    // MARK: - PVO Umbrella Bonus

    private func checkUmbrellaBonus(towers: [TowerEntity], in scene: SKScene) {
        let types = Set(towers.compactMap { $0.stats?.towerType })
        let hasLongRange = types.contains(.samLauncher)
        let hasMediumRange = types.contains(.interceptor)
        let hasGun = types.contains(.autocannon) || types.contains(.ciws)
        let hasRadar = types.contains(.radar)
        let hasEW = types.contains(.ewTower)

        guard hasLongRange && hasMediumRange && hasGun && hasRadar && hasEW else { return }

        // +10% to all combat tower stats
        for tower in towers {
            guard let stats = tower.stats else { continue }
            guard stats.towerType != .radar && stats.towerType != .ewTower else { continue }
            if !(appliedBonuses[ObjectIdentifier(tower)]?.contains("umbrella") ?? false) {
                stats.range *= 1.1
                stats.fireRate *= 1.1
                recordBonus(tower, "umbrella")
                showAura(on: tower, color: .systemPurple, in: scene)
            }
        }

        // Big floating label
        let label = SKLabelNode(fontNamed: Constants.GameBalance.hudFontName)
        label.text = "ЗОНТИК ПВО"
        label.fontSize = 10
        label.fontColor = .systemPurple
        label.position = CGPoint(x: scene.frame.midX, y: scene.frame.height - 60)
        label.zPosition = 95
        label.name = "umbrellaLabel"
        label.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.fadeAlpha(to: 0.4, duration: 1.5),
            SKAction.fadeAlpha(to: 1.0, duration: 1.5),
        ])))
        scene.addChild(label)
        visualNodes.append(label)
    }

    // MARK: - Bonus Tracking

    private func recordBonus(_ tower: TowerEntity, _ bonusName: String) {
        let id = ObjectIdentifier(tower)
        var existing = appliedBonuses[id] ?? []
        existing.append(bonusName)
        appliedBonuses[id] = existing
    }

    private func revertAllBonuses(towers: [TowerEntity]) {
        for tower in towers {
            guard let stats = tower.stats else { continue }
            let type = stats.towerType
            var range = type.baseRange
            var fireRate = type.baseFireRate
            var damage = type.baseDamage

            switch stats.level {
            case 2:
                range *= 1.25
                fireRate *= 1.3
            case 3:
                range *= 1.25 * 1.2
                fireRate *= 1.3
                damage += 1
            default:
                break
            }

            stats.range = range
            stats.fireRate = fireRate
            stats.damage = damage
        }
        appliedBonuses.removeAll()
    }

    func reset() {
        clearAllVisuals()
        appliedBonuses.removeAll()
    }

    /// Get active synergy names for a tower (for UI display)
    func activeSynergies(for tower: TowerEntity) -> [String] {
        let bonuses = appliedBonuses[ObjectIdentifier(tower)] ?? []
        return bonuses.map { bonusName in
            switch bonusName {
            case "radarDesignation": return "Целеуказание"
            case "crossEngagement": return "Перекрёстное сопровождение"
            case "echelonOptimization": return "Эшелон ближней зоны"
            case "jammingProtection": return "Помехозащита"
            case "crossfire": return "Кинжальный огонь"
            case "umbrella": return "Зонтик ПВО"
            default: return bonusName
            }
        }
    }
}
