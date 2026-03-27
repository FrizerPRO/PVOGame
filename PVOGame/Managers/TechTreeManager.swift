//
//  TechTreeManager.swift
//  PVOGame
//
//  Persistent tech tree — spend stars earned in campaign to unlock
//  permanent upgrades across 5 branches, 3 tiers each.
//

import Foundation
import CoreGraphics

// MARK: - Tech Node Definition

struct TechNode {
    let id: String
    let branch: TechBranch
    let tier: Int          // 1, 2, 3
    let cost: Int          // stars required
    let name: String
    let description: String
}

enum TechBranch: String, CaseIterable {
    case guns       // Ствольные системы
    case rockets    // Ракетные системы
    case ew         // РЭБ / Радар
    case command    // Командование
    case economy    // Экономика

    var displayName: String {
        switch self {
        case .guns:     return "СТВОЛЬНЫЕ"
        case .rockets:  return "РАКЕТНЫЕ"
        case .ew:       return "РЭБ/РАДАР"
        case .command:  return "КОМАНДОВАНИЕ"
        case .economy:  return "ЭКОНОМИКА"
        }
    }

    var color: String {
        switch self {
        case .guns:     return "green"
        case .rockets:  return "red"
        case .ew:       return "yellow"
        case .command:  return "blue"
        case .economy:  return "orange"
        }
    }
}

// MARK: - Manager

class TechTreeManager {

    static let shared = TechTreeManager()

    private let unlockedKey = "techtree_unlocked"

    // All tech nodes
    let nodes: [TechNode] = [
        // Guns branch
        TechNode(id: "guns_1", branch: .guns, tier: 1, cost: 2, name: "+15% скорострельность",
                 description: "Ствольные ПВО стреляют на 15% быстрее"),
        TechNode(id: "guns_2", branch: .guns, tier: 2, cost: 4, name: "+10% точность",
                 description: "Базовая точность ствольных +10%"),
        TechNode(id: "guns_3", branch: .guns, tier: 3, cost: 6, name: "+1 урон",
                 description: "Ствольные системы наносят +1 урон"),

        // Rockets branch
        TechNode(id: "rockets_1", branch: .rockets, tier: 1, cost: 2, name: "+1 ракета",
                 description: "Магазин ЗРК увеличен на 1"),
        TechNode(id: "rockets_2", branch: .rockets, tier: 2, cost: 4, name: "-20% перезарядка",
                 description: "Магазины перезаряжаются на 20% быстрее"),
        TechNode(id: "rockets_3", branch: .rockets, tier: 3, cost: 6, name: "+15% дальность ЗРК",
                 description: "Все ракетные системы +15% дальность"),

        // EW/Radar branch
        TechNode(id: "ew_1", branch: .ew, tier: 1, cost: 2, name: "+25% радиус РЛС",
                 description: "Радары обнаруживают дальше"),
        TechNode(id: "ew_2", branch: .ew, tier: 2, cost: 4, name: "+15% шанс FPV",
                 description: "РЭБ перехватывает FPV с шансом 40%"),
        TechNode(id: "ew_3", branch: .ew, tier: 3, cost: 6, name: "+20% радиус РЭБ",
                 description: "РЭБ-башня замедляет в большем радиусе"),

        // Command branch
        TechNode(id: "cmd_1", branch: .command, tier: 1, cost: 2, name: "+3 HP штаба",
                 description: "Штаб начинает с 23 HP"),
        TechNode(id: "cmd_2", branch: .command, tier: 2, cost: 4, name: "Быстрый ремонт",
                 description: "Башни ремонтируются на 30% быстрее"),
        TechNode(id: "cmd_3", branch: .command, tier: 3, cost: 6, name: "+1 прочность",
                 description: "Все башни получают +1 прочность"),

        // Economy branch
        TechNode(id: "econ_1", branch: .economy, tier: 1, cost: 2, name: "+50 стартовых DP",
                 description: "Начальные DP увеличены до 550"),
        TechNode(id: "econ_2", branch: .economy, tier: 2, cost: 4, name: "+25% за убийства",
                 description: "Награды за уничтожение +25%"),
        TechNode(id: "econ_3", branch: .economy, tier: 3, cost: 6, name: "+50 за волну",
                 description: "Бонус за завершение волны: 150 DP"),
    ]

    // MARK: - Progress

    func isUnlocked(_ nodeId: String) -> Bool {
        let unlocked = UserDefaults.standard.stringArray(forKey: unlockedKey) ?? []
        return unlocked.contains(nodeId)
    }

    func canUnlock(_ nodeId: String) -> Bool {
        guard let node = nodes.first(where: { $0.id == nodeId }) else { return false }
        if isUnlocked(nodeId) { return false }

        // Check prerequisite (previous tier in same branch)
        if node.tier > 1 {
            let prevTier = node.tier - 1
            let prevNode = nodes.first { $0.branch == node.branch && $0.tier == prevTier }
            if let prev = prevNode, !isUnlocked(prev.id) { return false }
        }

        // Check star cost
        return availableStars() >= node.cost
    }

    func unlock(_ nodeId: String) -> Bool {
        guard canUnlock(nodeId) else { return false }
        var unlocked = UserDefaults.standard.stringArray(forKey: unlockedKey) ?? []
        unlocked.append(nodeId)
        UserDefaults.standard.set(unlocked, forKey: unlockedKey)
        return true
    }

    func availableStars() -> Int {
        let total = CampaignManager.shared.totalStars()
        let spent = spentStars()
        return total - spent
    }

    func spentStars() -> Int {
        let unlocked = UserDefaults.standard.stringArray(forKey: unlockedKey) ?? []
        return unlocked.compactMap { id in
            nodes.first { $0.id == id }?.cost
        }.reduce(0, +)
    }

    // MARK: - Apply Buffs

    /// Apply all unlocked tech bonuses to game parameters at game start.
    /// Returns a struct with all modifiers.
    func activeBuffs() -> TechBuffs {
        var buffs = TechBuffs()
        let unlocked = UserDefaults.standard.stringArray(forKey: unlockedKey) ?? []

        for nodeId in unlocked {
            switch nodeId {
            case "guns_1": buffs.gunFireRateMultiplier *= 1.15
            case "guns_2": buffs.gunAccuracyBonus += 0.10
            case "guns_3": buffs.gunDamageBonus += 1
            case "rockets_1": buffs.rocketMagazineBonus += 1
            case "rockets_2": buffs.rocketReloadMultiplier *= 0.8
            case "rockets_3": buffs.rocketRangeMultiplier *= 1.15
            case "ew_1": buffs.radarRangeMultiplier *= 1.25
            case "ew_2": buffs.ewFPVChanceBonus += 0.15
            case "ew_3": buffs.ewRangeMultiplier *= 1.2
            case "cmd_1": buffs.hqHPBonus += 3
            case "cmd_2": buffs.repairTimeMultiplier *= 0.7
            case "cmd_3": buffs.durabilityBonus += 1
            case "econ_1": buffs.startingDPBonus += 50
            case "econ_2": buffs.killRewardMultiplier *= 1.25
            case "econ_3": buffs.waveCompletionBonus += 50
            default: break
            }
        }
        return buffs
    }

    func resetProgress() {
        UserDefaults.standard.removeObject(forKey: unlockedKey)
    }
}

// MARK: - Buff Container

struct TechBuffs {
    // Guns
    var gunFireRateMultiplier: CGFloat = 1.0
    var gunAccuracyBonus: CGFloat = 0.0
    var gunDamageBonus: Int = 0
    // Rockets
    var rocketMagazineBonus: Int = 0
    var rocketReloadMultiplier: CGFloat = 1.0
    var rocketRangeMultiplier: CGFloat = 1.0
    // EW/Radar
    var radarRangeMultiplier: CGFloat = 1.0
    var ewFPVChanceBonus: CGFloat = 0.0
    var ewRangeMultiplier: CGFloat = 1.0
    // Command
    var hqHPBonus: Int = 0
    var repairTimeMultiplier: CGFloat = 1.0
    var durabilityBonus: Int = 0
    // Economy
    var startingDPBonus: Int = 0
    var killRewardMultiplier: CGFloat = 1.0
    var waveCompletionBonus: Int = 0
}
