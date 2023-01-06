//
//  RotationComponent.swift
//  PVOGame
//
//  Created by Frizer on 05.12.2022.
//

import UIKit
import GameplayKit
import SpriteKit
class RotationComponent: GKComponent {
    let spriteComponent: SpriteComponent
    var speed: CGFloat
    init(spriteComponent: SpriteComponent, speed: CGFloat){
        self.spriteComponent = spriteComponent
        self.speed = speed
        super.init()
    }
    
    func rotate(directon: Direction, deltaTime: TimeInterval,speed: CGFloat){
        let angle: CGFloat;
        switch directon {
        case .RIGHT:
            angle = speed * deltaTime
        case .LEFT:
            angle = -speed * deltaTime
        }
        spriteComponent.rotate(angle: angle)
    }
    func rotate(tap: CGPoint, deltaTime: TimeInterval){
        var rightTap = tap
        if tap.y < spriteComponent.spriteNode.position.y{
            if let view = spriteComponent.spriteNode.scene?.view{
                rightTap = CGPoint(x: view.frame.width/2,y: view.frame.height)
            }
        }
        let v1 = CGVector(dx: cos(self.spriteComponent.spriteNode.zRotation), dy: sin(self.spriteComponent.spriteNode.zRotation))
        let v2 = CGVector(dx: rightTap.x - self.spriteComponent.spriteNode.position.x, dy: rightTap.y - self.spriteComponent.spriteNode.position.y)
        let angle = atan2(v2.dy, v2.dx) - atan2(v1.dy, v1.dx) - .pi/2
        //print(angle)
        let direction: Direction
        switch angle {
        case ..<0:
            direction = .LEFT
        default:
            direction = .RIGHT
        }
        var templeSpeed = speed
        if abs(angle) < .pi / 180 * speed {
            templeSpeed = abs(angle) / deltaTime
        }
        rotate(directon: direction, deltaTime: deltaTime,speed: templeSpeed)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
