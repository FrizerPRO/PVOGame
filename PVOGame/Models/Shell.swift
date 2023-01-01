//
//  Shell.swift
//  PVOGame
//
//  Created by Frizer on 02.12.2022.
//

import Foundation
import GameplayKit

protocol Shell: GKEntity{
    var damage: Int{
        get
    }
    init(damage: Int,imageName: String)
}

extension Shell{
    func getDamage()->Int{
        damage;
    }
}
