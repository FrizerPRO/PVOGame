//
//  GeometryComponent.swift
//  PVOGame
//
//  Created by Frizer on 02.12.2022.
//

import UIKit
import GameplayKit
class GeometryComponent: GKComponent {
    /// A reference to the box in the scene that the entity controls.
    let geometryNode: SKSpriteNode
    
    // MARK: Initialization
    
    init(geometryNode: SKSpriteNode) {
        self.geometryNode = geometryNode
        super.init()
            geometryNode.physicsBody = SKPhysicsBody(rectangleOf: geometryNode.frame.size)
        geometryNode.physicsBody?.mass = 1
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: Methods
    
    /// Applies an upward impulse to the entity's box node, causing it to jump.
    func applyImpulse(_ vector: CGVector) {
        geometryNode.physicsBody?.applyImpulse(vector)
    }
}
