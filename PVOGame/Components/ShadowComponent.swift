//
//  ShadowComponent.swift
//  PVOGame
//

import SpriteKit
import GameplayKit

class ShadowComponent: GKComponent {
    let shadowNode: SKSpriteNode
    private let baseSize: CGSize

    init(baseSize: CGSize = CGSize(width: 24, height: 12)) {
        self.baseSize = baseSize
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 32, height: 16))
        let image = renderer.image { ctx in
            UIColor.black.withAlphaComponent(0.35).setFill()
            ctx.cgContext.fillEllipse(in: CGRect(x: 0, y: 0, width: 32, height: 16))
        }
        shadowNode = SKSpriteNode(texture: SKTexture(image: image))
        shadowNode.size = baseSize
        shadowNode.zPosition = 5
        shadowNode.alpha = 0.4
        super.init()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateShadow(dronePosition: CGPoint, altitude: DroneAltitude) {
        let scale = altitude.shadowScale
        shadowNode.size = CGSize(
            width: baseSize.width * scale,
            height: baseSize.height * scale
        )
        shadowNode.position = CGPoint(
            x: dronePosition.x + altitude.shadowOffset.x,
            y: dronePosition.y + altitude.shadowOffset.y
        )
        shadowNode.alpha = 0.15 + 0.25 * scale
    }
}
