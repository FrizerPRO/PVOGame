//
//  flyingProjectile.swift
//  PVOGame
//
//  Created by Frizer on 03.01.2023.
//

import Foundation
import GameplayKit
public protocol FlyingProjectile: GKEntity, GKAgentDelegate{
    var damage: CGFloat{
        get
    }
    var speed: CGFloat{
        get
    }
    var imageName: String{
        get
    }
    var flyingPath: FlyingPath{
        get
    }
    init(damage: CGFloat,speed: CGFloat,imageName: String,flyingPath: FlyingPath)
    func didHit()
    func removeFromParent()
    func reachedDestination()
}
