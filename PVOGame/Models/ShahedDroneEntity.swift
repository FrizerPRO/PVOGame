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

        if let spriteNode = drone.component(ofType: SpriteComponent.self)?.spriteNode {
            // Use generated texture if available, otherwise fallback to colored square
            if let tex = AnimationTextureCache.shared.droneTextures["drone_shahed"] {
                spriteNode.texture = tex
                spriteNode.color = .white
                spriteNode.colorBlendFactor = 0
            } else {
                spriteNode.color = UIColor(white: 0.7, alpha: 1)
                spriteNode.colorBlendFactor = 1.0
            }
            spriteNode.size = CGSize(width: Constants.SpriteSize.shahed, height: Constants.SpriteSize.shahed)

            // Spinning propeller at the rear
            let propeller = SKSpriteNode(color: UIColor(white: 0.25, alpha: 1), size: CGSize(width: 6, height: 2))
            propeller.position = CGPoint(x: 0, y: -9) // rear of drone
            propeller.zPosition = 1
            let spin = SKAction.repeatForever(SKAction.rotate(byAngle: .pi * 2, duration: 0.15))
            propeller.run(spin)
            spriteNode.addChild(propeller)
        }

        drone.addNavLights(wingspan: 18)

        return drone
    }
}
