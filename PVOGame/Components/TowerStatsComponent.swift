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
