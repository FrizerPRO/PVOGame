//
//  ExitMenu.swift
//  PVOGame
//
//  Created by Frizer on 12.03.2023.
//

import SpriteKit

class ExitMenu: SKSpriteNode {
    var cancelButton = SKSpriteNode()
    var exitButton = SKSpriteNode()
    init(size: CGSize) {
        super.init(texture: nil, color: .black, size: size)
        self.name = Constants.exitMenuName
        initBackground()
        initCancelButton()
        initExitButton()
    }
    func initBackground(){
        self.drawBorder(color: .green, width: 10)
    }
    func initCancelButton(){
        cancelButton = SKSpriteNode(color: .gray, size: CGSize(width: self.frame.width/5, height: self.frame.width/10))
        cancelButton.name = Constants.cancelExitFromGameButtonName
        cancelButton.drawBorder(color: .green, width: 5)
        cancelButton.position = CGPoint(x: -self.frame.width / 6, y: -self.frame.height / 6)
        addChild(cancelButton)
    }
    
    func initExitButton(){
        exitButton = SKSpriteNode(color: .red, size: CGSize(width: self.frame.width/5, height: self.frame.width/10))
        exitButton.name = Constants.exitFromGameButtonName
        exitButton.drawBorder(color: .green, width: 5)
        exitButton.position = CGPoint(x: self.frame.width / 6, y: -self.frame.height / 6)
        addChild(exitButton)
    }
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
}
