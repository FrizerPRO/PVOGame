//
//  ConveyorBeltManager.swift
//  PVOGame
//
//  PvZ-style conveyor belt for tower selection.
//  Cards appear periodically with weighted random selection.
//  Timer shown as radar sweep on the next empty slot.
//  Cards always compact to the left (no gaps).
//

import SpriteKit

class ConveyorBeltManager {

    static let slotCount = 5
    static let buildInterval: TimeInterval = 2.5
    static let combatInterval: TimeInterval = 5.0

    private static let weights: [(TowerType, Int)] = [
        (.pzrk, 10),
        (.autocannon, 8),
        (.gepard, 6),
        (.ciws, 5),
        (.interceptor, 4),
        (.samLauncher, 2),
        (.radar, 5),
        (.ewTower, 4),
    ]

    private var availableTowers: [TowerType] = TowerType.allCases
    private var guaranteedQueue: [TowerType] = []

    private(set) var slots: [TowerType?] = Array(repeating: nil, count: slotCount)
    private var spawnTimer: TimeInterval = 0
    private var selectedSlot: Int? = nil

    // Visual nodes
    private var slotNodes: [SKSpriteNode] = []
    private var cardNodes: [SKNode?] = Array(repeating: nil, count: slotCount)
    private var radarSweep: SKShapeNode?
    private var radarSweepSlot: Int = -1
    private weak var container: SKNode?
    private var slotSize: CGFloat = 56

    var selectedTowerType: TowerType? {
        guard let idx = selectedSlot else { return nil }
        return slots[idx]
    }

    // MARK: - Setup UI

    func setup(in scene: SKScene, safeBottom: CGFloat) {
        // Always clean up previous state first (fixes ghost visuals)
        removeUI()

        let node = SKNode()
        node.zPosition = 95
        scene.addChild(node)
        container = node

        // Reset all state
        slots = Array(repeating: nil, count: ConveyorBeltManager.slotCount)
        selectedSlot = nil
        spawnTimer = 0

        slotSize = min(56, (scene.frame.width - 40) / CGFloat(ConveyorBeltManager.slotCount) - 8)
        let spacing: CGFloat = 8
        let totalWidth = CGFloat(ConveyorBeltManager.slotCount) * slotSize
            + CGFloat(ConveyorBeltManager.slotCount - 1) * spacing
        let startX = (scene.frame.width - totalWidth) / 2 + slotSize / 2
        let yPos: CGFloat = safeBottom + 42

        slotNodes.removeAll()
        cardNodes = Array(repeating: nil, count: ConveyorBeltManager.slotCount)

        for i in 0..<ConveyorBeltManager.slotCount {
            let x = startX + CGFloat(i) * (slotSize + spacing)
            let bg = SKSpriteNode(color: UIColor.darkGray.withAlphaComponent(0.5),
                                  size: CGSize(width: slotSize, height: slotSize))
            bg.position = CGPoint(x: x, y: yPos)
            bg.name = "conveyorSlot_\(i)"
            node.addChild(bg)
            slotNodes.append(bg)
        }

        // Pre-fill some slots at game start
        for _ in 0..<3 {
            addRandomCard()
        }
    }

    func removeUI() {
        // Remove all running actions on cards to prevent ghost animations
        for card in cardNodes {
            card?.removeAllActions()
            card?.removeFromParent()
        }
        cardNodes = Array(repeating: nil, count: ConveyorBeltManager.slotCount)

        radarSweep?.removeFromParent()
        radarSweep = nil
        radarSweepSlot = -1

        container?.removeAllActions()
        container?.removeAllChildren()
        container?.removeFromParent()
        container = nil
        slotNodes.removeAll()
    }

    // MARK: - Update

    func update(deltaTime: TimeInterval, isBuildPhase: Bool) {
        let interval = isBuildPhase ? ConveyorBeltManager.buildInterval : ConveyorBeltManager.combatInterval

        let hasEmptySlot = slots.contains(where: { $0 == nil })
        if hasEmptySlot {
            spawnTimer += deltaTime

            let progress = CGFloat(spawnTimer / interval)
            updateRadarSweep(progress: min(progress, 1.0))

            if spawnTimer >= interval {
                spawnTimer = 0
                addRandomCard()
            }
        } else {
            removeRadarSweep()
        }
    }

    // MARK: - Radar Sweep Timer

    private func updateRadarSweep(progress: CGFloat) {
        guard let nextEmpty = slots.firstIndex(where: { $0 == nil }),
              nextEmpty < slotNodes.count else {
            removeRadarSweep()
            return
        }

        let parent = slotNodes[nextEmpty]

        if radarSweepSlot != nextEmpty {
            removeRadarSweep()
            radarSweepSlot = nextEmpty
        }

        let radius = slotSize / 2 - 3
        let startAngle: CGFloat = -.pi / 2
        let endAngle = startAngle + progress * 2 * .pi

        let path = UIBezierPath(arcCenter: .zero, radius: radius,
                                startAngle: startAngle, endAngle: endAngle,
                                clockwise: true)

        if radarSweep == nil {
            let sweep = SKShapeNode()
            sweep.strokeColor = UIColor.systemGreen.withAlphaComponent(0.6)
            sweep.lineWidth = 3
            sweep.fillColor = .clear
            sweep.zPosition = 10
            sweep.lineCap = .round
            parent.addChild(sweep)
            radarSweep = sweep
        }

        radarSweep?.path = path.cgPath
        parent.color = UIColor.systemGreen.withAlphaComponent(0.08 + 0.12 * progress)
    }

    private func removeRadarSweep() {
        radarSweep?.removeFromParent()
        radarSweep = nil
        if radarSweepSlot >= 0 && radarSweepSlot < slotNodes.count {
            slotNodes[radarSweepSlot].color = UIColor.darkGray.withAlphaComponent(0.5)
        }
        radarSweepSlot = -1
    }

    // MARK: - Card Management

    private func addRandomCard() {
        guard let emptyIdx = slots.firstIndex(where: { $0 == nil }) else { return }

        removeRadarSweep()

        let type: TowerType
        if !guaranteedQueue.isEmpty {
            type = guaranteedQueue.removeFirst()
        } else {
            type = weightedRandom()
        }
        slots[emptyIdx] = type
        createCardVisual(at: emptyIdx, type: type)
    }

    func setAvailableTowers(_ towers: [TowerType]) {
        self.availableTowers = towers
    }

    func setGuaranteedTowers(_ towers: [TowerType]) {
        self.guaranteedQueue = towers
    }

    private func weightedRandom() -> TowerType {
        let filtered = ConveyorBeltManager.weights.filter { availableTowers.contains($0.0) }
        guard !filtered.isEmpty else { return .autocannon }
        let totalWeight = filtered.reduce(0) { $0 + $1.1 }
        var roll = Int.random(in: 0..<totalWeight)
        for (type, weight) in filtered {
            roll -= weight
            if roll < 0 { return type }
        }
        return filtered[0].0
    }

    private func createCardVisual(at index: Int, type: TowerType) {
        guard index < slotNodes.count else { return }
        let parent = slotNodes[index]

        cardNodes[index]?.removeAllActions()
        cardNodes[index]?.removeFromParent()

        parent.color = UIColor.darkGray.withAlphaComponent(0.5)

        let card = SKNode()
        card.name = "conveyorCard_\(index)"

        let iconSize = slotSize - 16
        let icon = SKSpriteNode(color: type.color, size: CGSize(width: iconSize, height: iconSize))
        icon.name = "conveyorCard_\(index)"
        card.addChild(icon)

        let nameLabel = SKLabelNode(fontNamed: Constants.GameBalance.hudFontName)
        nameLabel.text = type.displayName
        nameLabel.fontSize = 8
        nameLabel.fontColor = .white
        nameLabel.position = CGPoint(x: 0, y: iconSize / 2 + 3)
        nameLabel.verticalAlignmentMode = .bottom
        nameLabel.name = "conveyorCard_\(index)"
        card.addChild(nameLabel)

        let costLabel = SKLabelNode(fontNamed: Constants.GameBalance.hudFontName)
        costLabel.text = "\(type.cost)"
        costLabel.fontSize = 10
        costLabel.fontColor = .systemYellow
        costLabel.position = CGPoint(x: 0, y: -iconSize / 2 - 2)
        costLabel.verticalAlignmentMode = .top
        costLabel.name = "conveyorCard_\(index)"
        card.addChild(costLabel)

        // Slide-in animation
        card.alpha = 0
        card.position = CGPoint(x: -30, y: 0)
        parent.addChild(card)
        card.run(SKAction.group([
            SKAction.fadeIn(withDuration: 0.2),
            SKAction.moveTo(x: 0, duration: 0.2)
        ]))

        cardNodes[index] = card
    }

    /// Rebuild all card names after compacting (so tap detection works with new indices)
    private func updateCardNames() {
        for (i, card) in cardNodes.enumerated() {
            guard let card else { continue }
            card.name = "conveyorCard_\(i)"
            card.enumerateChildNodes(withName: "*") { child, _ in
                if child.name?.hasPrefix("conveyorCard_") == true {
                    child.name = "conveyorCard_\(i)"
                }
            }
        }
    }

    // MARK: - Compact (shift cards left, no gaps)

    /// After removing a card, shift all cards to the right of it one position left
    /// with a smooth slide animation in world coordinates.
    private func compactSlots(removedAt idx: Int) {
        // Shift data
        for i in idx..<(ConveyorBeltManager.slotCount - 1) {
            slots[i] = slots[i + 1]
        }
        slots[ConveyorBeltManager.slotCount - 1] = nil

        // Animate visuals: each card slides from its old slot position to the new one
        let duration: TimeInterval = 0.25
        for i in idx..<(ConveyorBeltManager.slotCount - 1) {
            let card = cardNodes[i + 1]
            cardNodes[i + 1] = nil
            cardNodes[i] = card

            guard let card else { continue }

            // Calculate offset between old slot and new slot (in parent-local coords they're the same,
            // but since we reparent, we use the world position delta)
            let oldSlotPos = slotNodes[i + 1].position
            let newSlotPos = slotNodes[i].position
            let dx = oldSlotPos.x - newSlotPos.x  // how far right the card starts from its new parent

            card.removeAllActions()
            card.removeFromParent()
            card.position = CGPoint(x: dx, y: 0)  // place at old visual position relative to new parent
            card.alpha = 1
            card.setScale(1)
            slotNodes[i].addChild(card)

            // Smooth ease-out slide to center of new slot
            let slide = SKAction.moveTo(x: 0, duration: duration)
            slide.timingMode = .easeOut
            card.run(slide)
        }

        cardNodes[ConveyorBeltManager.slotCount - 1] = nil

        updateCardNames()

        for (i, node) in slotNodes.enumerated() {
            if slots[i] == nil {
                node.color = UIColor.darkGray.withAlphaComponent(0.5)
            }
        }
    }

    // MARK: - Selection

    func handleTap(nodeName: String?) -> Bool {
        guard let name = nodeName, name.hasPrefix("conveyorCard_") || name.hasPrefix("conveyorSlot_") else {
            return false
        }

        let prefix = name.hasPrefix("conveyorCard_") ? "conveyorCard_" : "conveyorSlot_"
        guard let idx = Int(name.replacingOccurrences(of: prefix, with: "")) else { return false }

        guard slots[idx] != nil else { return false }

        if selectedSlot == idx {
            deselect()
        } else {
            deselect()
            selectedSlot = idx
            if let card = cardNodes[idx] {
                card.run(SKAction.moveTo(y: 8, duration: 0.1))
            }
            slotNodes[idx].color = UIColor.white.withAlphaComponent(0.3)
        }
        return true
    }

    func deselect() {
        if let prev = selectedSlot {
            if let card = cardNodes[prev] {
                card.run(SKAction.moveTo(y: 0, duration: 0.1))
            }
            if prev < slotNodes.count {
                slotNodes[prev].color = UIColor.darkGray.withAlphaComponent(0.5)
            }
        }
        selectedSlot = nil
    }

    /// Consume the selected card (after tower placed). Returns the type that was consumed.
    @discardableResult
    func consumeSelected() -> TowerType? {
        guard let idx = selectedSlot, let type = slots[idx] else { return nil }
        selectedSlot = nil
        slots[idx] = nil

        // Animate consumed card: shrink + fly up, then remove
        if let card = cardNodes[idx] {
            card.removeAllActions()
            let flyUp = SKAction.moveBy(x: 0, y: 30, duration: 0.2)
            flyUp.timingMode = .easeIn
            let shrink = SKAction.scale(to: 0.3, duration: 0.2)
            let fade = SKAction.fadeOut(withDuration: 0.2)
            card.run(SKAction.sequence([
                SKAction.group([flyUp, shrink, fade]),
                SKAction.removeFromParent()
            ]))
        }
        cardNodes[idx] = nil

        if idx < slotNodes.count {
            slotNodes[idx].color = UIColor.darkGray.withAlphaComponent(0.5)
        }

        // Shift remaining cards left (starts after brief delay for visual clarity)
        compactSlots(removedAt: idx)

        return type
    }

    /// Discard a card (swipe or long press)
    func discardCard(at index: Int) {
        guard index < slots.count, slots[index] != nil else { return }
        if selectedSlot == index { selectedSlot = nil }

        cardNodes[index]?.removeAllActions()
        cardNodes[index]?.removeFromParent()
        cardNodes[index] = nil
        slots[index] = nil

        if index < slotNodes.count {
            slotNodes[index].color = UIColor.darkGray.withAlphaComponent(0.5)
        }

        compactSlots(removedAt: index)
    }

    // MARK: - Night mode

    func setNightMode(_ night: Bool) {
        container?.alpha = night ? 0.3 : 1.0
        if night { deselect() }
    }

    func reset() {
        slots = Array(repeating: nil, count: ConveyorBeltManager.slotCount)
        selectedSlot = nil
        spawnTimer = 0
        availableTowers = TowerType.allCases
        guaranteedQueue = []
        removeRadarSweep()
        for card in cardNodes {
            card?.removeAllActions()
            card?.removeFromParent()
        }
        cardNodes = Array(repeating: nil, count: ConveyorBeltManager.slotCount)
        for node in slotNodes {
            node.color = UIColor.darkGray.withAlphaComponent(0.5)
        }
    }
}
