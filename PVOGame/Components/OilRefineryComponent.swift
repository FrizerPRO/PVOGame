//
//  OilRefineryComponent.swift
//  PVOGame
//

import GameplayKit
import SpriteKit

class OilRefineryComponent: GKComponent {
    private(set) var maxHP: Int
    private(set) var currentHP: Int
    private(set) var isDestroyed: Bool = false

    private var healthBarBackground: SKSpriteNode?
    private var healthBarFill: SKSpriteNode?

    private var incomeTimer: TimeInterval = 0

    var incomeAmount: Int {
        Constants.OilRefinery.incomeAmount
    }

    var targetPriority: CGFloat {
        Constants.OilRefinery.targetPriority
    }

    override init() {
        self.maxHP = Constants.OilRefinery.baseHP
        self.currentHP = Constants.OilRefinery.baseHP
        super.init()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func update(deltaTime seconds: TimeInterval) {
        guard !isDestroyed else { return }
        guard let scene = entity?.component(ofType: SpriteComponent.self)?.spriteNode.scene as? InPlaySKScene,
              scene.currentPhase == .combat else { return }
        guard let stats = (entity as? TowerEntity)?.stats, !stats.isDisabled else { return }

        incomeTimer += seconds
        if incomeTimer >= Constants.OilRefinery.incomeInterval {
            incomeTimer -= Constants.OilRefinery.incomeInterval
            scene.economyManager.earn(incomeAmount)
            scene.updateHUD()
            showIncomeLabel(in: scene)
        }
    }

    private func showIncomeLabel(in scene: InPlaySKScene) {
        guard let sprite = entity?.component(ofType: SpriteComponent.self)?.spriteNode else { return }
        scene.showRefineryIncomeLabel(incomeAmount, at: sprite.position)
    }

    func setupHealthBar(on parent: SKSpriteNode, size: CGFloat) {
        let barWidth: CGFloat = size - 4
        let barHeight: CGFloat = 3

        let bg = SKSpriteNode(color: UIColor(white: 0.2, alpha: 0.8), size: CGSize(width: barWidth, height: barHeight))
        bg.position = CGPoint(x: 0, y: size / 2 + 4)
        bg.zPosition = 30
        parent.addChild(bg)
        healthBarBackground = bg

        let fill = SKSpriteNode(color: .green, size: CGSize(width: barWidth, height: barHeight))
        fill.anchorPoint = CGPoint(x: 0, y: 0.5)
        fill.position = CGPoint(x: -barWidth / 2, y: size / 2 + 4)
        fill.zPosition = 31
        parent.addChild(fill)
        healthBarFill = fill
    }

    @discardableResult
    func takeDamage(_ amount: Int) -> Bool {
        guard !isDestroyed else { return false }
        currentHP = max(0, currentHP - amount)
        updateHealthBar()
        flashDamage()
        if currentHP <= 0 {
            isDestroyed = true
            showDestroyedState()
            return true
        }
        return false
    }

    private func updateHealthBar() {
        guard let fill = healthBarFill, let bg = healthBarBackground else { return }
        let ratio = CGFloat(currentHP) / CGFloat(maxHP)
        fill.size.width = bg.size.width * ratio
        fill.color = ratio > 0.5 ? .green : (ratio > 0.25 ? .yellow : .red)
    }

    private func flashDamage() {
        guard let sprite = entity?.component(ofType: SpriteComponent.self)?.spriteNode else { return }
        sprite.run(SKAction.sequence([
            SKAction.colorize(with: .red, colorBlendFactor: 0.8, duration: 0.05),
            SKAction.colorize(withColorBlendFactor: 0, duration: 0.2)
        ]))
    }

    private func showDestroyedState() {
        guard let sprite = entity?.component(ofType: SpriteComponent.self)?.spriteNode else { return }
        sprite.run(SKAction.colorize(with: .darkGray, colorBlendFactor: 0.9, duration: 0.3))
        healthBarBackground?.isHidden = true
        healthBarFill?.isHidden = true
    }
}
