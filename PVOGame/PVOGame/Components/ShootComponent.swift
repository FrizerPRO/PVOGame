//
//  ShootComponent.swift
//  PVOGame
//
//  Created by Frizer on 26.12.2022.
//

import UIKit
import GameplayKit

class ShootComponent: GKComponent {
    
    public func shoot(vector: CGVector){
        if let bullet = entity?.component(ofType: GeometryComponent.self){
            var newVector = vector
            if let bullet = entity as? BulletEntity{
                newVector.dx = CGFloat(bullet.startImpact) * newVector.dx
                newVector.dy = CGFloat(bullet.startImpact) * abs(newVector.dy)
            }
            bullet.applyImpulse(newVector)
        }
    }
}
