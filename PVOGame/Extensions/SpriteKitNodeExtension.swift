import SpriteKit

extension SKSpriteNode {
    func drawBorder(color: UIColor, width: CGFloat) {
        let shapeNode = SKShapeNode(rect: frame)
        shapeNode.fillColor = .clear
        shapeNode.strokeColor = color
        shapeNode.lineWidth = width
        shapeNode.zPosition = 1
        shapeNode.name = name
        addChild(shapeNode)
    }
}
