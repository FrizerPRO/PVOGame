//
//  SettlementEntity.swift
//  PVOGame
//

import UIKit
import GameplayKit
import SpriteKit

enum SettlementType: String, CaseIterable {
    case village
    case town
    case factory
    case farm
    case depot

    var displayName: String {
        switch self {
        case .village:  return "Село"
        case .town:     return "Місто"
        case .factory:  return "Завод"
        case .farm:     return "Ферма"
        case .depot:    return "Склад"
        }
    }

    var color: UIColor {
        switch self {
        case .village:  return UIColor(red: 0.55, green: 0.35, blue: 0.20, alpha: 1)
        case .town:     return UIColor(red: 0.75, green: 0.70, blue: 0.60, alpha: 1)
        case .factory:  return UIColor(red: 0.50, green: 0.50, blue: 0.55, alpha: 1)
        case .farm:     return UIColor(red: 0.35, green: 0.55, blue: 0.25, alpha: 1)
        case .depot:    return UIColor(red: 0.70, green: 0.45, blue: 0.20, alpha: 1)
        }
    }

    var spriteName: String {
        switch self {
        case .village:  return "settlement_village"
        case .town:     return "settlement_town"
        case .factory:  return "settlement_factory"
        case .farm:     return "settlement_farm"
        case .depot:    return "settlement_depot"
        }
    }

    var iconLetter: String {
        switch self {
        case .village:  return "С"
        case .town:     return "М"
        case .factory:  return "З"
        case .farm:     return "Ф"
        case .depot:    return "Д"
        }
    }
}

class SettlementEntity: GKEntity {
    /// All settlements occupy a 2×2 grid footprint. Anchor (gridRow, gridCol)
    /// is the top-left cell of this footprint.
    static let footprint: (rows: Int, cols: Int) = (rows: 2, cols: 2)

    let settlementType: SettlementType
    private(set) var level: Int = 1
    private(set) var maxHP: Int
    private(set) var currentHP: Int
    private(set) var isDestroyed: Bool = false
    let gridRow: Int
    let gridCol: Int

    private var healthBarBackground: SKSpriteNode?
    private var healthBarFill: SKSpriteNode?
    private var levelLabel: SKLabelNode?

    init(type: SettlementType, gridRow: Int, gridCol: Int,
         worldPosition: CGPoint, cellSize: CGFloat) {
        self.settlementType = type
        self.gridRow = gridRow
        self.gridCol = gridCol
        self.maxHP = Constants.Settlement.baseHP
        self.currentHP = Constants.Settlement.baseHP
        super.init()

        // Sprite size MUST equal the actual grid footprint (cellSize × footprint
        // dims). Using a hardcoded constant would mismatch the dynamic cellSize
        // computed from screen width, leaving a visible gap between the sprite
        // and the cells the settlement actually claims for placement blocking.
        let fp = Self.footprint
        let size = CGSize(width: cellSize * CGFloat(fp.cols),
                          height: cellSize * CGFloat(fp.rows))
        let spriteComponent: SpriteComponent
        if UIImage(named: type.spriteName) != nil {
            spriteComponent = SpriteComponent(imageName: type.spriteName)
            spriteComponent.spriteNode.size = size
        } else {
            spriteComponent = SpriteComponent(color: type.color, size: size)
            // Fallback icon letter when sprite asset is unavailable
            let label = SKLabelNode(text: type.iconLetter)
            label.fontName = "Menlo-Bold"
            label.fontSize = 14
            label.fontColor = .white
            label.verticalAlignmentMode = .center
            label.horizontalAlignmentMode = .center
            label.zPosition = 1
            spriteComponent.spriteNode.addChild(label)
        }
        spriteComponent.spriteNode.position = worldPosition
        spriteComponent.spriteNode.zPosition = Constants.Settlement.spriteZPosition
        addComponent(spriteComponent)

        addComponent(GridPositionComponent(
            row: gridRow, col: gridCol,
            rowSpan: fp.rows, colSpan: fp.cols
        ))

        // Health bar / level indicator sized by width of the footprint (sprite
        // is square, so width works for both axes).
        setupHealthBar(on: spriteComponent.spriteNode, size: size.width)
        setupLevelIndicator(on: spriteComponent.spriteNode, size: size.width)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var worldPosition: CGPoint {
        component(ofType: SpriteComponent.self)?.spriteNode.position ?? .zero
    }

    var incomePerWave: Int {
        switch level {
        case 1: return Constants.Settlement.level1Income
        case 2: return Constants.Settlement.level2Income
        case 3: return Constants.Settlement.level3Income
        default: return Constants.Settlement.level1Income
        }
    }

    var upgradeCost: Int {
        switch level {
        case 1: return Constants.Settlement.upgradeCostLevel2
        case 2: return Constants.Settlement.upgradeCostLevel3
        default: return 0
        }
    }

    var canUpgrade: Bool {
        level < 3 && !isDestroyed
    }

    var targetPriority: CGFloat {
        switch level {
        case 2: return Constants.Settlement.level2TargetPriorityMultiplier
        case 3: return Constants.Settlement.level3TargetPriorityMultiplier
        default: return 1.0
        }
    }

    // MARK: - Damage

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

    // MARK: - Upgrade

    @discardableResult
    func upgrade() -> Bool {
        guard canUpgrade else { return false }
        level += 1
        switch level {
        case 2:
            maxHP = Constants.Settlement.level2HP
            currentHP = maxHP
        case 3:
            maxHP = Constants.Settlement.level3HP
            currentHP = maxHP
        default:
            break
        }
        updateHealthBar()
        updateLevelVisual()
        updateSpriteForLevel()
        return true
    }

    // MARK: - Health Bar

    private func setupHealthBar(on parent: SKSpriteNode, size: CGFloat) {
        let barWidth: CGFloat = size - 4
        let barHeight: CGFloat = 3

        let bg = SKSpriteNode(color: UIColor(white: 0.2, alpha: 0.8), size: CGSize(width: barWidth, height: barHeight))
        bg.position = CGPoint(x: 0, y: size / 2 + 4)
        bg.zPosition = 1
        parent.addChild(bg)
        healthBarBackground = bg

        let fill = SKSpriteNode(color: .green, size: CGSize(width: barWidth, height: barHeight))
        fill.anchorPoint = CGPoint(x: 0, y: 0.5)
        fill.position = CGPoint(x: -barWidth / 2, y: size / 2 + 4)
        fill.zPosition = 2
        parent.addChild(fill)
        healthBarFill = fill
    }

    private func updateHealthBar() {
        guard let fill = healthBarFill, let bg = healthBarBackground else { return }
        let ratio = CGFloat(currentHP) / CGFloat(maxHP)
        fill.size.width = bg.size.width * ratio
        fill.color = ratio > 0.5 ? .green : (ratio > 0.25 ? .yellow : .red)
    }

    // MARK: - Level Indicator

    private func setupLevelIndicator(on parent: SKSpriteNode, size: CGFloat) {
        let label = SKLabelNode(text: "1")
        label.fontName = "Menlo-Bold"
        label.fontSize = 8
        label.fontColor = .white
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        label.position = CGPoint(x: size / 2 - 3, y: -size / 2 + 3)
        label.zPosition = 2
        parent.addChild(label)
        levelLabel = label
    }

    private func updateLevelVisual() {
        levelLabel?.text = "\(level)"
    }

    // MARK: - Visual Effects

    private func updateSpriteForLevel() {
        guard let sprite = component(ofType: SpriteComponent.self)?.spriteNode else { return }
        let scale: CGFloat = level == 2 ? 1.15 : (level == 3 ? 1.3 : 1.0)
        sprite.run(SKAction.scale(to: scale, duration: 0.3))

        if level >= 3 {
            sprite.run(SKAction.colorize(with: .yellow, colorBlendFactor: 0.2, duration: 0.3))
        }
    }

    private func flashDamage() {
        guard let sprite = component(ofType: SpriteComponent.self)?.spriteNode else { return }
        sprite.run(SKAction.sequence([
            SKAction.colorize(with: .red, colorBlendFactor: 0.8, duration: 0.05),
            SKAction.colorize(withColorBlendFactor: 0, duration: 0.2)
        ]))
    }

    private func showDestroyedState() {
        guard let sprite = component(ofType: SpriteComponent.self)?.spriteNode else { return }
        sprite.run(SKAction.colorize(with: .darkGray, colorBlendFactor: 0.9, duration: 0.3))
        healthBarBackground?.isHidden = true
        healthBarFill?.isHidden = true
        levelLabel?.isHidden = true
    }
}
