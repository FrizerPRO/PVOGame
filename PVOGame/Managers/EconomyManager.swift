//
//  EconomyManager.swift
//  PVOGame
//

import Foundation

class EconomyManager {
    private(set) var resources: Int

    init(startingResources: Int = Constants.TowerDefense.startingResources) {
        self.resources = startingResources
    }

    func canAfford(_ cost: Int) -> Bool {
        resources >= cost
    }

    @discardableResult
    func spend(_ amount: Int) -> Bool {
        guard canAfford(amount) else { return false }
        resources -= amount
        return true
    }

    func earn(_ amount: Int) {
        resources += max(0, amount)
    }

    func reset(to amount: Int) {
        resources = amount
    }
}
