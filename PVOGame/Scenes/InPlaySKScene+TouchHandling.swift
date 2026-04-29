//
//  InPlaySKScene+TouchHandling.swift
//  PVOGame
//

import SpriteKit

extension InPlaySKScene {

    // MARK: - Drag State

    struct DragState {
        let slotIndex: Int
        let towerType: TowerType
        let startLocation: CGPoint
        var isDragActive: Bool = false
        var currentGridPos: (row: Int, col: Int)?
        var previewNode: SKSpriteNode?
        var rangeNode: SKShapeNode?
    }

    // NOTE: stored properties dragState, dragThreshold, cellSnapDuration,
    //       selectedTower, selectedSettlement remain in InPlaySKScene.swift

    func cancelDrag() {
        guard let state = dragState else { return }
        if state.isDragActive {
            conveyorBelt.restoreCard(at: state.slotIndex)
            state.previewNode?.removeAllActions()
            state.previewNode?.removeFromParent()
            state.rangeNode?.removeAllActions()
            state.rangeNode?.removeFromParent()
        }
        dragState = nil
    }

    // MARK: - Touch Handling

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)
        let touchedNode = atPoint(location)

        switch currentPhase {
        case .mainMenu:
            if touchedNode.name == "startGameButton" {
                selectedLevel = LevelDefinition.level1
                selectedCampaignLevelId = nil
                startGame()
            } else if touchedNode.name == "campaignButton" {
                showLevelSelect()
            } else if let name = touchedNode.name, name.hasPrefix("levelCard_") {
                if let idx = Int(name.replacingOccurrences(of: "levelCard_", with: "")) {
                    let campaign = CampaignManager.shared
                    let level = campaign.levels[idx]
                    selectedLevel = level.definition
                    selectedCampaignLevelId = level.id
                    startGame()
                }
            } else if touchedNode.name == "levelSelectBack" {
                enumerateChildNodes(withName: "//levelSelectOverlay") { node, _ in
                    node.removeFromParent()
                }
                showMainMenu()
            }

        case .gameOver:
            if touchedNode.name == "playAgainButton" {
                playAgain()
            } else if touchedNode.name == "menuButton_gameOver" {
                enumerateChildNodes(withName: "//gameOverOverlay") { node, _ in
                    node.removeFromParent()
                }
                stopGame()
                showMainMenu()
            } else if touchedNode.name == "victoryNextButton" {
                enumerateChildNodes(withName: "//victoryOverlay") { node, _ in
                    node.removeFromParent()
                }
                stopGame()
                // Start next campaign level
                if let currentId = selectedCampaignLevelId,
                   let currentIdx = CampaignManager.shared.levels.firstIndex(where: { $0.id == currentId }),
                   currentIdx + 1 < CampaignManager.shared.levels.count {
                    let nextLevel = CampaignManager.shared.levels[currentIdx + 1]
                    selectedLevel = nextLevel.definition
                    selectedCampaignLevelId = nextLevel.id
                    startGame()
                }
            } else if touchedNode.name == "victoryMenuButton" {
                enumerateChildNodes(withName: "//victoryOverlay") { node, _ in
                    node.removeFromParent()
                }
                stopGame()
                showMainMenu()
                showLevelSelect()
            }

        case .build:
            // Military Aid card selection
            if hasMilitaryAidOverlay, let name = touchedNode.name, name.hasPrefix("aidCard_") {
                if let idx = Int(name.replacingOccurrences(of: "aidCard_", with: "")) {
                    handleMilitaryAidSelection(cardIndex: idx)
                }
                return
            }
            // Block other interactions while aid overlay is shown
            if hasMilitaryAidOverlay { return }

            // Check start wave button (build phase only)
            if touchedNode.name == "startWaveButton" {
                let earlyBonus = Int(interWaveCountdown * 2)
                if earlyBonus > 0 {
                    economyManager.earn(earlyBonus)
                }
                interWaveCountdown = 0
                startCombatPhase()
                return
            }

            // Drag initiation: touch on conveyor card
            if !isNightWave, let slotIdx = conveyorBelt.slotIndex(at: location, in: self),
               let towerType = conveyorBelt.towerType(at: slotIdx) {
                cancelDrag()
                dragState = DragState(slotIndex: slotIdx, towerType: towerType, startLocation: location)
                return
            }
            handleTowerInteraction(touchedNode: touchedNode, location: location)

        case .combat:
            if abilityManager.handleTap(at: location) { return }

            // Drag initiation: touch on conveyor card
            if !isNightWave, let slotIdx = conveyorBelt.slotIndex(at: location, in: self),
               let towerType = conveyorBelt.towerType(at: slotIdx) {
                cancelDrag()
                dragState = DragState(slotIndex: slotIdx, towerType: towerType, startLocation: location)
                return
            }
            handleTowerInteraction(touchedNode: touchedNode, location: location)

        case .waveComplete:
            break
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesMoved(touches, with: event)
        guard let touch = touches.first, var state = dragState else { return }
        let location = touch.location(in: self)

        if !state.isDragActive {
            // Check if finger moved far enough to activate drag
            let dx = location.x - state.startLocation.x
            let dy = location.y - state.startLocation.y
            let distance = sqrt(dx * dx + dy * dy)
            guard distance >= dragThreshold else { return }

            // Activate drag
            state.isDragActive = true
            conveyorBelt.deselect()
            towerPlacement.selectTowerType(nil)
            towerPlacement.clearPreview()
            conveyorBelt.grayOutCard(at: state.slotIndex)

            // Create preview at nearest grid cell or at finger position
            if let gridPos = gridMap.gridPosition(for: location) {
                if let preview = towerPlacement.createDragPreview(type: state.towerType, at: gridPos) {
                    state.previewNode = preview.sprite
                    state.rangeNode = preview.range
                    state.currentGridPos = gridPos
                }
            } else {
                if let preview = towerPlacement.createDragPreviewFreeform(type: state.towerType, at: location) {
                    state.previewNode = preview.sprite
                    state.rangeNode = preview.range
                    state.currentGridPos = nil
                }
            }
            dragState = state
            return
        }

        // Drag is active — update preview position
        if let gridPos = gridMap.gridPosition(for: location) {
            // On the grid — snap to cells
            let sameCell = state.currentGridPos.map { $0.row == gridPos.row && $0.col == gridPos.col } ?? false
            if !sameCell, let sprite = state.previewNode, let range = state.rangeNode {
                towerPlacement.updateDragPreview(
                    sprite: sprite, range: range,
                    type: state.towerType, to: gridPos,
                    duration: cellSnapDuration)
                state.currentGridPos = gridPos
                dragState = state
            }
        } else {
            // Outside grid — follow finger
            if let sprite = state.previewNode, let range = state.rangeNode {
                towerPlacement.moveDragPreviewFreeform(sprite: sprite, range: range, to: location)
                state.currentGridPos = nil
                dragState = state
            }
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)

        guard let state = dragState else { return }

        if !state.isDragActive {
            // Was a tap, not a drag — forward to existing tap logic
            dragState = nil
            let touchedNode = atPoint(location)
            if conveyorBelt.handleTap(nodeName: touchedNode.name) {
                towerPlacement.selectTowerType(conveyorBelt.selectedTowerType)
                towerPlacement.clearPreview()
            } else {
                handleTowerInteraction(touchedNode: touchedNode, location: location)
            }
            return
        }

        // Drag was active — attempt placement or cancel
        let towerType = state.towerType
        let footprint = towerType.footprint

        if let gridPos = state.currentGridPos {
            let anchor = TowerPlacementManager.clampedAnchor(
                row: gridPos.row, col: gridPos.col, footprint: footprint, in: gridMap)
            let cellOk = gridMap.canPlaceTower(atRow: anchor.row, col: anchor.col, footprint: footprint)
            let affordable = economyManager.canAfford(towerType.cost)
            if cellOk && affordable {
                // Place the tower
                towerPlacement.selectTowerType(towerType)
                if towerPlacement.placeTower(at: gridPos, economy: economyManager) != nil {
                    conveyorBelt.consumeCard(at: state.slotIndex)
                    towerPlacement.selectTowerType(nil)
                    synergyManager.recalculate(towers: towerPlacement.towers, in: self)
                    updateHUD()
                } else {
                    conveyorBelt.restoreCard(at: state.slotIndex)
                    towerPlacement.selectTowerType(nil)
                }
                state.previewNode?.removeAllActions()
                state.previewNode?.removeFromParent()
                state.rangeNode?.removeAllActions()
                state.rangeNode?.removeFromParent()
                dragState = nil
                return
            }
        }

        do {
            // Invalid placement — determine reason for feedback.
            // Order matters: off-grid dominates, then cell-level issues,
            // then affordability (only surfaced when the cell itself was fine).
            let reason: InvalidPlacementReason
            let feedbackPos: CGPoint
            if let gridPos = state.currentGridPos {
                let anchor = TowerPlacementManager.clampedAnchor(
                    row: gridPos.row, col: gridPos.col, footprint: footprint, in: gridMap)
                feedbackPos = gridMap.worldPosition(forRow: anchor.row, col: anchor.col, footprint: footprint)
                if !gridMap.canPlaceTower(atRow: anchor.row, col: anchor.col, footprint: footprint) {
                    reason = .invalidCell
                } else {
                    reason = .insufficientFunds(needed: towerType.cost, have: economyManager.resources)
                }
            } else {
                feedbackPos = state.previewNode?.position ?? location
                reason = .offGrid
            }

            showInvalidPlacementFeedback(reason: reason, at: feedbackPos)
            shakeAndFadeOutPreview(sprite: state.previewNode, range: state.rangeNode)
            conveyorBelt.restoreCard(at: state.slotIndex)
            conveyorBelt.shakeCard(at: state.slotIndex)
            triggerErrorHaptic()
        }

        dragState = nil
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        cancelDrag()
    }

    func handleTowerInteraction(touchedNode: SKNode, location: CGPoint) {
        // Speed button
        if touchedNode.name == "speedButton" || touchedNode.parent?.name == "speedButton" {
            toggleGameSpeed()
            return
        }

        // Settlement upgrade button
        if touchedNode.name == "settlementUpgradeButton" || touchedNode.parent?.name == "settlementUpgradeButton" {
            if let settlement = selectedSettlement {
                let cost = settlement.upgradeCost
                if economyManager.canAfford(cost) {
                    economyManager.spend(cost)
                    settlementManager?.upgradeSettlement(settlement)
                    dismissSettlementActionPanel()
                    updateHUD()
                }
            }
            return
        }

        // Sell button
        if touchedNode.name == "sellButton" || touchedNode.parent?.name == "sellButton" {
            if let tower = selectedTower {
                let wasRefinery = tower.towerType == .oilRefinery
                towerPlacement.sellTower(tower, economy: economyManager)
                if wasRefinery {
                    retargetDronesFromRefinery(tower)
                }
                selectedTower = nil
                dismissTowerActionPanel()
                synergyManager.recalculate(towers: towerPlacement.towers, in: self)
                updateHUD()
            }
            return
        }

        // Conveyor belt card selection
        if conveyorBelt.handleTap(nodeName: touchedNode.name) {
            towerPlacement.selectTowerType(conveyorBelt.selectedTowerType)
            towerPlacement.clearPreview()
            return
        }

        // Grid tap for tower placement or tower info
        dismissSettlementActionPanel()
        if let gridPos = gridMap.gridPosition(for: location) {
            if let selectedType = towerPlacement.selectedTowerType, !isNightWave {
                let footprint = selectedType.footprint
                let anchor = TowerPlacementManager.clampedAnchor(
                    row: gridPos.row, col: gridPos.col, footprint: footprint, in: gridMap)
                if gridMap.canPlaceTower(atRow: anchor.row, col: anchor.col, footprint: footprint) {
                    if towerPlacement.placeTower(at: gridPos, economy: economyManager) != nil {
                        conveyorBelt.consumeSelected()
                        towerPlacement.selectTowerType(nil)
                        synergyManager.recalculate(towers: towerPlacement.towers, in: self)
                    }
                    updateHUD()
                }
            } else {
                if let tower = towerPlacement.towerAt(gridPos: gridPos) {
                    handleTowerTap(tower)
                } else if let settlement = settlementManager?.settlement(atRow: gridPos.row, col: gridPos.col) {
                    handleSettlementTap(settlement)
                }
            }
        }
    }

    func handleSettlementTap(_ settlement: SettlementEntity) {
        guard currentPhase == .build else { return }

        // Dismiss any tower/settlement panel
        selectedTower?.hideRangeIndicator()
        selectedTower = nil
        dismissTowerActionPanel()
        dismissSettlementActionPanel()

        if selectedSettlement === settlement {
            selectedSettlement = nil
            return
        }

        selectedSettlement = settlement
        showSettlementActions(settlement)
    }

    func showSettlementActions(_ settlement: SettlementEntity) {
        dismissSettlementActionPanel()

        let pos = settlement.worldPosition

        let panel = SKNode()
        panel.name = "settlementActionPanel"
        panel.zPosition = 97
        panel.position = CGPoint(x: pos.x, y: pos.y + 45)

        // Info label
        let infoLabel = SKLabelNode(fontNamed: Constants.GameBalance.hudFontName)
        infoLabel.text = "\(settlement.settlementType.displayName) Lv\(settlement.level) +\(settlement.incomePerWave)/wave"
        infoLabel.fontSize = 9
        infoLabel.fontColor = .white
        infoLabel.verticalAlignmentMode = .center
        infoLabel.position = CGPoint(x: 0, y: 16)
        panel.addChild(infoLabel)

        // Upgrade button (if can upgrade)
        if settlement.canUpgrade {
            let cost = settlement.upgradeCost
            let canAfford = economyManager.canAfford(cost)
            let upgradeBtn = SKSpriteNode(
                color: canAfford ? .systemGreen : .gray,
                size: CGSize(width: 80, height: 24)
            )
            upgradeBtn.name = "settlementUpgradeButton"
            upgradeBtn.position = .zero
            let upgradeLabel = SKLabelNode(fontNamed: Constants.GameBalance.hudFontName)
            upgradeLabel.text = "UP Lv\(settlement.level + 1): \(cost)"
            upgradeLabel.fontSize = 10
            upgradeLabel.fontColor = .white
            upgradeLabel.verticalAlignmentMode = .center
            upgradeLabel.name = "settlementUpgradeButton"
            upgradeBtn.addChild(upgradeLabel)
            panel.addChild(upgradeBtn)
        } else if settlement.isDestroyed {
            let destroyedLabel = SKLabelNode(fontNamed: Constants.GameBalance.hudFontName)
            destroyedLabel.text = "ЗНИЩЕНО"
            destroyedLabel.fontSize = 10
            destroyedLabel.fontColor = .red
            destroyedLabel.verticalAlignmentMode = .center
            panel.addChild(destroyedLabel)
        } else {
            let maxLabel = SKLabelNode(fontNamed: Constants.GameBalance.hudFontName)
            maxLabel.text = "MAX"
            maxLabel.fontSize = 10
            maxLabel.fontColor = .yellow
            maxLabel.verticalAlignmentMode = .center
            panel.addChild(maxLabel)
        }

        addChild(panel)

        panel.run(SKAction.sequence([
            SKAction.wait(forDuration: 5),
            SKAction.removeFromParent()
        ]))
    }

    func dismissSettlementActionPanel() {
        selectedSettlement = nil
        enumerateChildNodes(withName: "//settlementActionPanel") { node, _ in
            node.removeFromParent()
        }
    }

    func handleTowerTap(_ tower: TowerEntity) {
        // Deselect previous
        selectedTower?.hideRangeIndicator()
        dismissTowerActionPanel()

        if selectedTower === tower {
            selectedTower = nil
            return
        }

        selectedTower = tower
        tower.showRangeIndicator()
        showTowerActions(tower)
    }

    func showTowerActions(_ tower: TowerEntity) {
        // Remove existing action panel
        enumerateChildNodes(withName: "//towerActionPanel") { node, _ in
            node.removeFromParent()
        }

        guard let stats = tower.stats else { return }
        let pos = tower.worldPosition

        let panel = SKNode()
        panel.name = "towerActionPanel"
        panel.zPosition = 97
        panel.position = CGPoint(x: pos.x, y: pos.y + 45)

        let sellBtn = SKSpriteNode(color: .systemRed, size: CGSize(width: 60, height: 24))
        sellBtn.name = "sellButton"
        sellBtn.position = .zero
        let sellLabel = SKLabelNode(fontNamed: Constants.GameBalance.hudFontName)
        sellLabel.text = "SELL \(stats.sellValue)"
        sellLabel.fontSize = 10
        sellLabel.fontColor = .white
        sellLabel.verticalAlignmentMode = .center
        sellLabel.name = "sellButton"
        sellBtn.addChild(sellLabel)
        panel.addChild(sellBtn)

        addChild(panel)

        // Auto-dismiss after a delay
        panel.run(SKAction.sequence([
            SKAction.wait(forDuration: 5),
            SKAction.removeFromParent()
        ]))
    }

    func dismissTowerActionPanel() {
        enumerateChildNodes(withName: "//towerActionPanel") { node, _ in
            node.removeFromParent()
        }
    }
}
