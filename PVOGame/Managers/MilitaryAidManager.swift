//
//  MilitaryAidManager.swift
//  PVOGame
//
//  Roguelike upgrade picker — "Military Aid" between waves.
//  Every N waves the player picks 1 of 3 random upgrades.
//  ALL upgrades produce visible on-screen effects.
//

import SpriteKit

// MARK: - Upgrade Definition

enum MilitaryAidType: String, CaseIterable {
    case funding            // +200 DP (visible: HUD number jumps)
    case fortification      // HQ: +5 HP (visible: HUD number jumps)
    case airstrike          // Destroy 8 random drones on screen (visible: explosions)
    case repairAll          // Repair all disabled towers (visible: towers flash white)
    case shieldHQ           // HQ immune for 1 wave (visible: blue shield bubble)
    case reloadAll          // Instantly reload all magazines (visible: ammo dots refill)
    case slowField          // Slow all current enemies 60% for 10s (visible: enemies crawl)
    case bonusWave          // Spawn 5 bonus reward drones — easy kills worth 50 DP each

    var title: String {
        switch self {
        case .funding:          return "ФИНАНСИРОВАНИЕ"
        case .fortification:    return "ФОРТИФИКАЦИЯ"
        case .airstrike:        return "АВИАУДАР"
        case .repairAll:        return "РЕМОНТ"
        case .shieldHQ:         return "ЩИТ ШТАБА"
        case .reloadAll:        return "ПЕРЕЗАРЯДКА"
        case .slowField:        return "РЭБ-ПОДАВЛЕНИЕ"
        case .bonusWave:        return "ЛЁГКИЕ ЦЕЛИ"
        }
    }

    var description: String {
        switch self {
        case .funding:          return "Мгновенно +200 DP"
        case .fortification:    return "Штаб получает +5 HP"
        case .airstrike:        return "Уничтожить 8 врагов на экране"
        case .repairAll:        return "Починить все повреждённые башни"
        case .shieldHQ:         return "Штаб неуязвим 1 волну"
        case .reloadAll:        return "Мгновенно перезарядить все ЗРК"
        case .slowField:        return "Замедлить всех врагов на 10с"
        case .bonusWave:        return "5 бонусных дронов (по 50 DP)"
        }
    }

    var color: UIColor {
        switch self {
        case .funding:          return .systemYellow
        case .fortification:    return .systemBlue
        case .airstrike:        return .systemRed
        case .repairAll:        return .systemGreen
        case .shieldHQ:         return .systemCyan
        case .reloadAll:        return .systemOrange
        case .slowField:        return .systemPurple
        case .bonusWave:        return .systemYellow
        }
    }
}

// MARK: - Manager

class MilitaryAidManager {

    static let aidInterval = 3  // offer aid every N waves

    /// Currently offered options (shown in UI)
    var currentOptions: [MilitaryAidType] = []

    /// Shield state (tracked by scene)
    private(set) var isShieldActive = false

    func shouldOfferAid(afterWave wave: Int) -> Bool {
        wave > 0 && wave % MilitaryAidManager.aidInterval == 0
    }

    func generateOptions() -> [MilitaryAidType] {
        let shuffled = MilitaryAidType.allCases.shuffled()
        currentOptions = Array(shuffled.prefix(3))
        return currentOptions
    }

    func activateShield() { isShieldActive = true }
    func deactivateShield() { isShieldActive = false }

    func reset() {
        currentOptions = []
        isShieldActive = false
    }

    /// No cumulative buffs — all effects are immediate/visual
    func applyBuffsToNewTower(_ stats: TowerStatsComponent) {
        // No persistent stat buffs in the new system
    }
}
