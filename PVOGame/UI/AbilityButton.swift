//
//  AbilityButton.swift
//  PVOGame
//

import SpriteKit

class AbilityButton: SKNode {

    enum AbilityType {
        case fighter
        case barrage
        case reload
    }

    let abilityType: AbilityType
    let cooldown: TimeInterval
    private(set) var isOnCooldown = false
    private var cooldownRemaining: TimeInterval = 0

    private let background: SKSpriteNode
    private let icon: SKLabelNode
    private let cooldownOverlay: SKSpriteNode
    private let timerLabel: SKLabelNode

    var isWaitingForTarget = false  // For barrage/reload that need a second tap

    init(type: AbilityType, position: CGPoint) {
        self.abilityType = type
        let size = Constants.Abilities.abilityButtonSize

        switch type {
        case .fighter:
            self.cooldown = Constants.Abilities.fighterCooldown
        case .barrage:
            self.cooldown = Constants.Abilities.barrageCooldown
        case .reload:
            self.cooldown = Constants.Abilities.reloadCooldown
        }

        background = SKSpriteNode(color: UIColor.darkGray.withAlphaComponent(0.85), size: CGSize(width: size, height: size))
        background.zPosition = 0

        icon = SKLabelNode(fontNamed: Constants.GameBalance.hudFontName)
        icon.fontSize = 20
        icon.verticalAlignmentMode = .center
        icon.zPosition = 1
        switch type {
        case .fighter: icon.text = "\u{2708}"  // airplane
        case .barrage: icon.text = "\u{1F4A5}" // explosion
        case .reload:  icon.text = "\u{1F3AF}" // target/reload
        }

        cooldownOverlay = SKSpriteNode(color: UIColor.black.withAlphaComponent(0.6), size: CGSize(width: size, height: size))
        cooldownOverlay.zPosition = 2
        cooldownOverlay.isHidden = true

        timerLabel = SKLabelNode(fontNamed: Constants.GameBalance.hudFontName)
        timerLabel.fontSize = 14
        timerLabel.fontColor = .white
        timerLabel.verticalAlignmentMode = .center
        timerLabel.zPosition = 3
        timerLabel.isHidden = true

        super.init()

        self.position = position
        self.zPosition = Constants.Abilities.abilityButtonZPosition
        self.name = "ability_\(type)"

        addChild(background)
        addChild(icon)
        addChild(cooldownOverlay)
        addChild(timerLabel)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func activate() {
        guard !isOnCooldown else { return }
        isOnCooldown = true
        cooldownRemaining = cooldown
        cooldownOverlay.isHidden = false
        timerLabel.isHidden = false
        isWaitingForTarget = false
    }

    func update(deltaTime: TimeInterval) {
        guard isOnCooldown else { return }
        cooldownRemaining -= deltaTime
        if cooldownRemaining <= 0 {
            isOnCooldown = false
            cooldownRemaining = 0
            cooldownOverlay.isHidden = true
            timerLabel.isHidden = true
        } else {
            timerLabel.text = "\(Int(ceil(cooldownRemaining)))"
            let progress = CGFloat(cooldownRemaining / cooldown)
            let size = Constants.Abilities.abilityButtonSize
            cooldownOverlay.size = CGSize(width: size, height: size * progress)
            cooldownOverlay.position = CGPoint(x: 0, y: (size * (1 - progress)) / 2 - size / 2 + cooldownOverlay.size.height / 2)
        }

        // Highlight if waiting for target
        if isWaitingForTarget {
            background.color = UIColor.systemYellow.withAlphaComponent(0.8)
        } else if !isOnCooldown {
            background.color = UIColor.darkGray.withAlphaComponent(0.85)
        }
    }

    func setWaitingForTarget(_ waiting: Bool) {
        isWaitingForTarget = waiting
        if waiting {
            background.color = UIColor.systemYellow.withAlphaComponent(0.8)
        } else {
            background.color = UIColor.darkGray.withAlphaComponent(0.85)
        }
    }

    func containsTouch(_ point: CGPoint) -> Bool {
        let size = Constants.Abilities.abilityButtonSize
        let padding: CGFloat = 10
        let hitSize = size + padding * 2
        let rect = CGRect(
            x: position.x - hitSize / 2,
            y: position.y - hitSize / 2,
            width: hitSize,
            height: hitSize
        )
        return rect.contains(point)
    }
}
