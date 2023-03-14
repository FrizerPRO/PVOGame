//
//  MenuButton.swift
//  PVOGame
//
//  Created by Frizer on 12.03.2023.
//

import SpriteKit

class MenuButton: SKSpriteNode {
    init(size: CGSize) {
        super.init(texture: nil, color: .black, size: size)
        self.name = Constants.menuButtonName
        initBackground()
    }
    func initBackground(){
        self.drawBorder(color: .green, width: 5)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
