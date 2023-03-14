//
//  PistolGun.swift
//  PVOGame
//
//  Created by Frizer on 13.03.2023.
//

import SpriteKit

class PistolGun: GunEntity {
    init(_ view: UIView, shell: Shell){
        super.init(imageName: "PistolGun", shell: shell, shootingSpeed: 500, rotateSpeed: 5, label: "Pistol")
        if let spriteComponent = component(ofType: SpriteComponent.self){
            spriteComponent.spriteNode.size = CGSize(
                width: spriteComponent.spriteNode.frame.width/view.frame.size.width*70, height: spriteComponent.spriteNode.frame.height/view.frame.size.width*70)
            addComponent(RotationComponent(spriteComponent: spriteComponent, speed: rotateSpeed))
            spriteComponent.spriteNode.position = CGPoint(x: view.frame.size.width/2, y:20)
        }

    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
