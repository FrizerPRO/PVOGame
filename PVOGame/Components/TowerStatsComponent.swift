//
//  TowerStatsComponent.swift
//  PVOGame
//

import UIKit
import GameplayKit
import CoreGraphics

class TowerStatsComponent: GKComponent {
    let towerType: TowerType
    var level: Int = 1
    var range: CGFloat
    var fireRate: CGFloat
    var damage: Int
    var reachableAltitudes: Set<DroneAltitude>
    var cost: Int
    var sellValue: Int { Int(CGFloat(cost) * Constants.TowerDefense.sellRefundPercent) }

    // Durability system
    let maxDurability: Int
    let repairTime: TimeInterval
    private(set) var durability: Int
    private var repairTimer: TimeInterval = 0
    var isDisabled: Bool { durability <= 0 }

    // Magazine system (S-300 only)
    let magazineCapacity: Int?
    let magazineReloadTime: TimeInterval?
    private(set) var magazineAmmo: Int?
    private var magazineReloadTimer: TimeInterval = 0
    var isReloading: Bool { magazineAmmo != nil && magazineAmmo! <= 0 }
    var reloadProgress: CGFloat {
        guard let reloadTime = magazineReloadTime, reloadTime > 0, isReloading else { return 0 }
        return CGFloat(min(magazineReloadTimer / reloadTime, 1.0))
    }

    init(
        towerType: TowerType,
        range: CGFloat,
        fireRate: CGFloat,
        damage: Int,
        reachableAltitudes: Set<DroneAltitude>,
        cost: Int
    ) {
        self.towerType = towerType
        self.range = range
        self.fireRate = fireRate
        self.damage = damage
        self.reachableAltitudes = reachableAltitudes
        self.cost = cost
        self.maxDurability = towerType.baseDurability
        self.repairTime = towerType.baseRepairTime
        self.durability = towerType.baseDurability
        self.magazineCapacity = towerType.magazineCapacity
        self.magazineReloadTime = towerType.magazineReloadTime
        self.magazineAmmo = towerType.magazineCapacity
        super.init()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func takeBombDamage(_ amount: Int) {
        durability = max(0, durability - amount)
        repairTimer = 0
    }

    func fullRepair() {
        durability = maxDurability
        repairTimer = 0
    }

    func updateRepair(deltaTime: TimeInterval) {
        guard isDisabled else { return }
        repairTimer += deltaTime
        if repairTimer >= repairTime {
            durability = maxDurability
            repairTimer = 0
        }
    }

    // MARK: - Magazine

    @discardableResult
    func consumeAmmo() -> Bool {
        guard var ammo = magazineAmmo, ammo > 0 else { return false }
        ammo -= 1
        magazineAmmo = ammo
        if ammo <= 0 {
            magazineReloadTimer = 0
        }
        return true
    }

    func updateMagazineReload(deltaTime: TimeInterval) {
        guard isReloading, let reloadTime = magazineReloadTime else { return }
        magazineReloadTimer += deltaTime
        if magazineReloadTimer >= reloadTime {
            magazineAmmo = magazineCapacity
            magazineReloadTimer = 0
        }
    }

    func replenishMagazine() {
        guard magazineCapacity != nil else { return }
        magazineAmmo = magazineCapacity
        magazineReloadTimer = 0
    }

    @discardableResult
    func upgrade() -> Int {
        guard level < 3 else { return 0 }
        let upgradeCost = Int(CGFloat(cost) * Constants.TowerDefense.upgradeCostMultiplier)
        level += 1
        switch level {
        case 2:
            range *= 1.25
            fireRate *= 1.3
        case 3:
            range *= 1.2
            damage += 1
            if towerType == .autocannon {
                reachableAltitudes.insert(.high)
            }
        default:
            break
        }
        cost += upgradeCost
        return upgradeCost
    }
}

enum TowerType: String, CaseIterable {
    case autocannon
    case ciws
    case samLauncher
    case interceptor
    case radar

    var displayName: String {
        switch self {
        case .autocannon: return "ZU"
        case .ciws: return "ZRPK"
        case .samLauncher: return "S-300"
        case .interceptor: return "PRCH"
        case .radar: return "RLS"
        }
    }

    var cost: Int {
        switch self {
        case .autocannon: return Constants.TowerDefense.autocannonCost
        case .ciws: return Constants.TowerDefense.ciwsCost
        case .samLauncher: return Constants.TowerDefense.samCost
        case .interceptor: return Constants.TowerDefense.interceptorCost
        case .radar: return Constants.TowerDefense.radarCost
        }
    }

    var baseRange: CGFloat {
        switch self {
        case .autocannon: return 120
        case .ciws: return 80
        case .samLauncher: return 400
        case .interceptor: return 300
        case .radar: return 130
        }
    }

    var baseFireRate: CGFloat {
        switch self {
        case .autocannon: return 8
        case .ciws: return 20
        case .samLauncher: return 1.0
        case .interceptor: return 2
        case .radar: return 0
        }
    }

    var baseDamage: Int {
        switch self {
        case .autocannon: return 1
        case .ciws: return 1
        case .samLauncher: return 3
        case .interceptor: return 2
        case .radar: return 0
        }
    }

    var reachableAltitudes: Set<DroneAltitude> {
        switch self {
        case .autocannon: return [.low, .medium, .micro]
        case .ciws: return [.low, .micro, .cruise]
        case .samLauncher: return [.low, .medium, .high, .ballistic]
        case .interceptor: return [.low, .medium, .high, .ballistic]
        case .radar: return []
        }
    }

    var baseDurability: Int {
        switch self {
        case .autocannon: return 3
        case .ciws: return 2
        case .samLauncher: return 1
        case .interceptor: return 1
        case .radar: return 1
        }
    }

    var baseRepairTime: TimeInterval {
        switch self {
        case .autocannon: return 8
        case .ciws: return 10
        case .samLauncher: return 15
        case .interceptor: return 12
        case .radar: return 12
        }
    }

    var magazineCapacity: Int? {
        switch self {
        case .samLauncher: return 6
        case .interceptor: return 8
        default: return nil
        }
    }

    var magazineReloadTime: TimeInterval? {
        switch self {
        case .samLauncher: return 8.0
        case .interceptor: return 5.0
        default: return nil
        }
    }

    /// Ствольные системы физически наводятся на цель.
    /// Ракетные (С-300, перехватчик) — вертикальный пуск, наведение ракетой.
    var tracksTarget: Bool {
        switch self {
        case .autocannon, .ciws: return true
        case .samLauncher, .interceptor, .radar: return false
        }
    }

    func accuracy(against altitude: DroneAltitude) -> CGFloat {
        switch self {
        case .autocannon:
            return altitude == .micro ? 0.05 : 0.70
        case .ciws:
            if altitude == .micro { return 0.15 }
            if altitude == .cruise { return 0.30 }
            return 0.90
        default:
            return 1.0
        }
    }

    var color: UIColor {
        switch self {
        case .autocannon: return .systemGreen
        case .ciws: return .systemOrange
        case .samLauncher: return .systemRed
        case .interceptor: return .systemCyan
        case .radar: return .systemYellow
        }
    }
}
