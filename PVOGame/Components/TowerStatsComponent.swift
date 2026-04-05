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
    private(set) var maxDurability: Int
    var repairTime: TimeInterval
    private(set) var durability: Int
    private var repairTimer: TimeInterval = 0
    var isDisabled: Bool { durability <= 0 }

    // Magazine system (S-300 / Interceptor)
    private(set) var magazineCapacity: Int?
    private(set) var magazineReloadTime: TimeInterval?
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

    // MARK: - Military Aid Buffs

    func addMagazineCapacity(_ bonus: Int) {
        guard let cap = magazineCapacity else { return }
        let newCap = cap + bonus
        magazineCapacity = newCap
        // Also add ammo to current magazine (if not reloading)
        if let ammo = magazineAmmo, ammo > 0 {
            magazineAmmo = ammo + bonus
        }
    }

    func applyReloadMultiplier(_ multiplier: CGFloat) {
        guard let t = magazineReloadTime else { return }
        magazineReloadTime = t * TimeInterval(multiplier)
    }

    func addMaxDurability(_ bonus: Int) {
        maxDurability += bonus
        durability += bonus
    }

}

enum TowerType: String, CaseIterable {
    case autocannon
    case ciws
    case samLauncher
    case interceptor
    case radar
    case ewTower
    case pzrk       // ПЗРК Stinger/Igla — cheap single-missile launcher
    case gepard      // Flakpanzer Gepard — 35mm twin autocannon, cruise-capable

    var displayName: String {
        switch self {
        case .autocannon: return "ZU"
        case .ciws: return "ZRPK"
        case .samLauncher: return "S-300"
        case .interceptor: return "PRCH"
        case .radar: return "RLS"
        case .ewTower: return "REW"
        case .pzrk: return "PZRK"
        case .gepard: return "GEPD"
        }
    }

    var cost: Int {
        switch self {
        case .autocannon: return Constants.TowerDefense.autocannonCost
        case .ciws: return Constants.TowerDefense.ciwsCost
        case .samLauncher: return Constants.TowerDefense.samCost
        case .interceptor: return Constants.TowerDefense.interceptorCost
        case .radar: return Constants.TowerDefense.radarCost
        case .ewTower: return Constants.EW.ewTowerCost
        case .pzrk: return Constants.TowerDefense.pzrkCost
        case .gepard: return Constants.TowerDefense.gepardCost
        }
    }

    var baseRange: CGFloat {
        switch self {
        case .autocannon: return 120
        case .ciws: return 80
        case .samLauncher: return Constants.GameBalance.standardRocketSpec.maxFlightDistance
        case .interceptor: return Constants.GameBalance.interceptorRocketBaseSpec.maxFlightDistance
        case .radar: return 130
        case .ewTower: return Constants.EW.ewTowerRange
        case .pzrk: return 80  // short detection range; missile chases further
        case .gepard: return 100
        }
    }

    var baseFireRate: CGFloat {
        switch self {
        case .autocannon: return 8
        case .ciws: return 20
        case .samLauncher: return 1.0
        case .interceptor: return 2
        case .radar: return 0
        case .ewTower: return 0
        case .pzrk: return 1.0
        case .gepard: return 12
        }
    }

    var baseDamage: Int {
        switch self {
        case .autocannon: return 1
        case .ciws: return 1
        case .samLauncher: return 3
        case .interceptor: return 2
        case .radar: return 0
        case .ewTower: return 0
        case .pzrk: return 2
        case .gepard: return 1
        }
    }

    var reachableAltitudes: Set<DroneAltitude> {
        switch self {
        case .autocannon: return [.low, .medium, .micro]
        case .ciws: return [.low, .micro, .cruise]
        case .samLauncher: return [.low, .medium, .high, .ballistic, .cruise]
        case .interceptor: return [.low, .medium, .high, .ballistic, .cruise]
        case .radar: return []
        case .ewTower: return []
        case .pzrk: return [.low, .medium]
        case .gepard: return [.low, .medium, .cruise]
        }
    }

    var baseDurability: Int {
        switch self {
        case .autocannon: return 3
        case .ciws: return 2
        case .samLauncher: return 1
        case .interceptor: return 1
        case .radar: return 1
        case .ewTower: return 2
        case .pzrk: return 1
        case .gepard: return 2
        }
    }

    var baseRepairTime: TimeInterval {
        switch self {
        case .autocannon: return 8
        case .ciws: return 10
        case .samLauncher: return 15
        case .interceptor: return 12
        case .radar: return 12
        case .ewTower: return 10
        case .pzrk: return 6
        case .gepard: return 10
        }
    }

    var magazineCapacity: Int? {
        switch self {
        case .samLauncher: return 6
        case .interceptor: return 8
        case .pzrk: return 1
        default: return nil
        }
    }

    var magazineReloadTime: TimeInterval? {
        switch self {
        case .samLauncher: return 8.0
        case .interceptor: return 5.0
        case .pzrk: return 12.0
        default: return nil
        }
    }

    /// Ствольные системы физически наводятся на цель.
    /// Ракетные (С-300, перехватчик, ПЗРК) — вертикальный пуск, наведение ракетой.
    var tracksTarget: Bool {
        switch self {
        case .autocannon, .ciws, .gepard: return true
        case .samLauncher, .interceptor, .pzrk, .radar, .ewTower: return false
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
        case .gepard:
            if altitude == .micro { return 0.10 }
            if altitude == .cruise { return 0.60 }
            return 0.85
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
        case .ewTower: return .systemTeal
        case .pzrk: return .systemBrown
        case .gepard: return .systemIndigo
        }
    }
}
