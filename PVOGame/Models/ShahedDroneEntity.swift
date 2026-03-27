//
//  ShahedDroneEntity.swift
//  PVOGame
//
//  Shahed-136 (Geran-2) — slow, cheap kamikaze drone.
//  Follows standard flight paths. Purpose: overwhelm PVO with quantity.
//  Based on real Iranian-made Shahed-136 used en masse in Ukraine.
//

import Foundation
import GameplayKit

final class ShahedDroneEntity: AttackDroneEntity {

    required init(damage: CGFloat, speed: CGFloat, imageName: String, flyingPath: FlyingPath) {
        super.init(damage: damage, speed: speed, imageName: imageName, flyingPath: flyingPath)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Factory: create a Shahed with proper visuals.
    static func create(flyingPath: FlyingPath) -> ShahedDroneEntity {
        let drone = ShahedDroneEntity(
            damage: 1,
            speed: Constants.Shahed.speed,
            imageName: "Drone",
            flyingPath: flyingPath
        )
        drone.configureHealth(Constants.Shahed.health)

        // Olive/dark color to distinguish from regular drones
        if let spriteNode = drone.component(ofType: SpriteComponent.self)?.spriteNode {
            spriteNode.color = UIColor(red: 0.35, green: 0.4, blue: 0.2, alpha: 1)
            spriteNode.colorBlendFactor = 1.0
            spriteNode.size = CGSize(width: 22, height: 22)  // slightly smaller — cheap drone
        }

        return drone
    }
}
