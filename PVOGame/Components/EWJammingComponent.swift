//
//  EWJammingComponent.swift
//  PVOGame
//

import GameplayKit
import SpriteKit

/// Applied to enemy EW drones. Tracks jamming state.
class EWJammingComponent: GKComponent {
    let jamRadius: CGFloat
    let accuracyMultiplier: CGFloat
    let turnRateMultiplier: CGFloat

    init(
        jamRadius: CGFloat = Constants.EW.ewDroneJamRadius,
        accuracyMultiplier: CGFloat = Constants.EW.ewDroneAccuracyMultiplier,
        turnRateMultiplier: CGFloat = Constants.EW.ewDroneTurnRateMultiplier
    ) {
        self.jamRadius = jamRadius
        self.accuracyMultiplier = accuracyMultiplier
        self.turnRateMultiplier = turnRateMultiplier
        super.init()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
