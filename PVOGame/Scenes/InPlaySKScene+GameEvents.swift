//
//  InPlaySKScene+GameEvents.swift
//  PVOGame
//

import SpriteKit
import GameplayKit

extension InPlaySKScene {

    // MARK: - Game Events

    func onDroneDestroyed(drone: AttackDroneEntity? = nil) {
        guard currentPhase == .combat else { return }
        if let drone, !activeDrones.contains(drone) { return }

        // Wreckage + screen shake for significant kills
        if let drone,
           let spriteNode = drone.component(ofType: SpriteComponent.self)?.spriteNode {
            spawnWreckage(at: spriteNode.position, rotation: spriteNode.zRotation, size: spriteNode.size)
            spawnKillExplosion(at: spriteNode.position, for: drone)
            if drone is HeavyDroneEntity || drone is CruiseMissileEntity {
                screenShake(intensity: 6, duration: 0.25)
            }
        }

        // Track stats for wave summary
        waveKills += 1
        if let drone {
            let typeName = Self.droneTypeName(drone)
            waveKillsByType[typeName, default: 0] += 1
        }

        let scoreDelta: Int
        let resourceDelta: Int
        if drone is OrlanDroneEntity {
            scoreDelta = Constants.Orlan.scorePerKill
            resourceDelta = Constants.Orlan.reward
        } else if drone is LancetDroneEntity {
            scoreDelta = Constants.Lancet.scorePerKill
            resourceDelta = Constants.Lancet.reward
        } else if drone is ShahedDroneEntity {
            scoreDelta = Constants.Shahed.scorePerKill
            resourceDelta = Constants.Shahed.reward
        } else if drone is KamikazeDroneEntity {
            scoreDelta = Constants.Kamikaze.scorePerKill
            resourceDelta = Constants.Kamikaze.reward
        } else if drone is EWDroneEntity {
            scoreDelta = Constants.EW.ewDroneScore
            resourceDelta = Constants.EW.ewDroneReward
        } else if drone is HeavyDroneEntity {
            scoreDelta = Constants.AdvancedEnemies.heavyDroneScore
            resourceDelta = Constants.AdvancedEnemies.heavyDroneReward
        } else if drone is CruiseMissileEntity {
            scoreDelta = Constants.AdvancedEnemies.cruiseMissileScore
            resourceDelta = Constants.AdvancedEnemies.cruiseMissileReward
        } else if drone is HarmMissileEntity {
            scoreDelta = Constants.GameBalance.scorePerHarmMissile
            resourceDelta = Constants.GameBalance.resourcesPerHarmMissileKill
        } else if drone is EnemyMissileEntity {
            scoreDelta = Constants.GameBalance.scorePerMissile
            resourceDelta = Constants.GameBalance.resourcesPerMissileKill
        } else if drone is MineLayerDroneEntity {
            scoreDelta = Constants.GameBalance.scorePerMineLayerDrone
            resourceDelta = Constants.TowerDefense.resourcesPerMineLayerKill
        } else {
            scoreDelta = Constants.GameBalance.scorePerDrone
            resourceDelta = Constants.TowerDefense.resourcesPerDroneKill
        }
        score += scoreDelta
        dronesDestroyed += 1
        economyManager.earn(resourceDelta)

        // Show reward label at kill position
        if let pos = drone?.component(ofType: SpriteComponent.self)?.spriteNode.position {
            showKillRewardLabel(resourceDelta, at: pos)
        }

        updateHUD()
    }

    func onDroneReachedHQ(drone: AttackDroneEntity? = nil) {
        guard currentPhase == .combat else { return }
        if let drone {
            if drone.isHit { return }
            if !activeDrones.contains(drone) { return }
        }
        // Track leaked drones for wave summary
        waveLeaked += 1
        if let drone {
            let typeName = Self.droneTypeName(drone)
            waveLeakedByType[typeName, default: 0] += 1
        }
        // Shield blocks all HQ damage
        if militaryAidManager.isShieldActive {
            // Visual: shield flash on absorb
            if let shieldNode = childNode(withName: "//hqShield") {
                shieldNode.run(SKAction.sequence([
                    SKAction.scale(to: 1.4, duration: 0.1),
                    SKAction.scale(to: 1.0, duration: 0.2)
                ]))
            }
            return
        }
        if drone is KamikazeDroneEntity {
            lives -= Constants.Kamikaze.hqDamage
            if let pos = drone?.component(ofType: SpriteComponent.self)?.spriteNode.position {
                spawnBombExplosion(at: pos)
            }
            screenShake(intensity: 5, duration: 0.2)
        } else if drone is CruiseMissileEntity {
            lives -= Constants.AdvancedEnemies.cruiseMissileHQDamage
            if let pos = drone?.component(ofType: SpriteComponent.self)?.spriteNode.position {
                spawnBombExplosion(at: pos)
            }
            screenShake(intensity: 8, duration: 0.3)
        } else if drone is EnemyMissileEntity {
            lives -= Constants.GameBalance.enemyMissileHQDamage
            if let pos = drone?.component(ofType: SpriteComponent.self)?.spriteNode.position {
                spawnBombExplosion(at: pos)
            }
            screenShake(intensity: 6, duration: 0.25)
        } else if drone is ShahedDroneEntity {
            // Shahed-136 is a 50kg-warhead loitering munition — when it reaches
            // HQ it actually detonates. Without this branch it leaks silently
            // (no boom, no shake) which makes the impact invisible.
            lives -= 1
            if let pos = drone?.component(ofType: SpriteComponent.self)?.spriteNode.position {
                spawnBombExplosion(at: pos)
            }
            screenShake(intensity: 4, duration: 0.2)
        } else {
            lives -= 1
        }
        if selectedLevel.infiniteLives { lives = max(lives, 1) }
        if let drone {
            logEnemyReachedTarget(enemy: Self.droneTypeName(drone), target: "HQ")
        }
        updateHUD()
        if lives <= 0 {
            triggerGameOver()
        }
    }

    func onDroneReachedSettlement(drone: AttackDroneEntity, settlement: SettlementEntity) {
        guard currentPhase == .combat else { return }
        guard !drone.isHit else { return }

        // Shield blocks all damage
        if militaryAidManager.isShieldActive {
            if let shieldNode = childNode(withName: "//hqShield") {
                shieldNode.run(SKAction.sequence([
                    SKAction.scale(to: 1.4, duration: 0.1),
                    SKAction.scale(to: 1.0, duration: 0.2)
                ]))
            }
            return
        }

        // Track for wave summary
        waveLeaked += 1
        waveSettlementHits += 1
        let typeName = Self.droneTypeName(drone)
        waveLeakedByType[typeName, default: 0] += 1

        // Damage settlement
        let wasDestroyed = settlementManager?.damageSettlement(settlement, amount: 1) ?? false
        logEnemyReachedTarget(enemy: typeName, target: "Settlement")

        // Reduce global lives based on drone type
        if drone is KamikazeDroneEntity {
            lives -= Constants.Settlement.kamikazeDamageToLives
        } else if drone is CruiseMissileEntity {
            lives -= Constants.Settlement.cruiseMissileDamageToLives
        } else {
            lives -= Constants.Settlement.droneDamageToLives
        }

        spawnBombExplosion(at: settlement.worldPosition)
        screenShake(intensity: 5, duration: 0.2)

        if wasDestroyed {
            onSettlementDestroyed(settlement)
        }

        if selectedLevel.infiniteLives { lives = max(lives, 1) }
        updateHUD()
        if lives <= 0 {
            triggerGameOver()
        }
    }

    func onSettlementDestroyed(_ settlement: SettlementEntity) {
        // Retarget all drones that were heading to this settlement
        retargetDronesFrom(destroyedSettlement: settlement)
    }

    // MARK: - Oil Refinery Events

    func onDroneReachedRefinery(drone: AttackDroneEntity, refinery: TowerEntity) {
        guard currentPhase == .combat else { return }
        guard !drone.isHit else { return }

        if militaryAidManager.isShieldActive {
            if let shieldNode = childNode(withName: "//hqShield") {
                shieldNode.run(SKAction.sequence([
                    SKAction.scale(to: 1.4, duration: 0.1),
                    SKAction.scale(to: 1.0, duration: 0.2)
                ]))
            }
            return
        }

        waveLeaked += 1
        let typeName = Self.droneTypeName(drone)
        waveLeakedByType[typeName, default: 0] += 1

        // Refinery hits damage the refinery building only — they do NOT cost
        // player lives. Losing the refinery is already a harsh economic
        // punishment (steady income gone), no need to stack HQ damage on top.
        let refineryComp = refinery.component(ofType: OilRefineryComponent.self)
        let wasDestroyed = refineryComp?.takeDamage(1) ?? false
        logEnemyReachedTarget(enemy: typeName, target: "Refinery")

        spawnBombExplosion(at: refinery.worldPosition)
        screenShake(intensity: 5, duration: 0.2)

        if wasDestroyed {
            onRefineryDestroyed(refinery)
        }

        updateHUD()
    }

    func onRefineryDestroyed(_ refinery: TowerEntity) {
        retargetDronesFromRefinery(refinery)
    }

    func retargetDronesFromRefinery(_ refinery: TowerEntity) {
        guard gridMap != nil else { return }
        let hqPoint = comboHQPoint()

        // Find other alive refineries
        let aliveRefineries = (towerPlacement?.towers ?? []).filter {
            $0.towerType == .oilRefinery
            && $0 !== refinery
            && !($0.component(ofType: OilRefineryComponent.self)?.isDestroyed ?? true)
            && !($0.stats?.isDisabled ?? true)
        }
        let aliveSettlements = settlementManager?.aliveSettlements() ?? []

        for drone in activeDrones {
            guard !drone.isHit, drone.targetRefinery === refinery else { continue }
            guard let dronePos = drone.component(ofType: SpriteComponent.self)?.spriteNode.position else { continue }

            // Try nearest alive refinery first
            let nearestRefinery = aliveRefineries.min(by: { a, b in
                let distA = hypot(dronePos.x - a.worldPosition.x, dronePos.y - a.worldPosition.y)
                let distB = hypot(dronePos.x - b.worldPosition.x, dronePos.y - b.worldPosition.y)
                return distA < distB
            })

            if let newRefinery = nearestRefinery {
                drone.targetRefinery = newRefinery
                drone.targetSettlement = nil
                let waypoints = generateSettlementPath(
                    from: dronePos, through: newRefinery.worldPosition, to: hqPoint
                )
                drone.retargetPath(waypoints: waypoints)
            } else if let newSettlement = aliveSettlements.min(by: { a, b in
                let distA = hypot(dronePos.x - a.worldPosition.x, dronePos.y - a.worldPosition.y)
                let distB = hypot(dronePos.x - b.worldPosition.x, dronePos.y - b.worldPosition.y)
                return distA < distB
            }) {
                drone.targetRefinery = nil
                drone.targetSettlement = newSettlement
                let waypoints = generateSettlementPath(
                    from: dronePos, through: newSettlement.worldPosition, to: hqPoint
                )
                drone.retargetPath(waypoints: waypoints)
            } else {
                drone.targetRefinery = nil
                drone.targetSettlement = nil
                let waypoints = generateSettlementPath(from: dronePos, to: hqPoint)
                drone.retargetPath(waypoints: waypoints)
            }
        }
    }

    func retargetDronesFrom(destroyedSettlement: SettlementEntity) {
        guard gridMap != nil else { return }
        let hqPoint = comboHQPoint()

        let aliveSettlements = settlementManager?.aliveSettlements() ?? []

        for drone in activeDrones {
            guard !drone.isHit, drone.targetSettlement === destroyedSettlement else { continue }
            guard let dronePos = drone.component(ofType: SpriteComponent.self)?.spriteNode.position else { continue }

            // Find nearest alive settlement
            let nearest = aliveSettlements.min(by: { a, b in
                let distA = hypot(dronePos.x - a.worldPosition.x, dronePos.y - a.worldPosition.y)
                let distB = hypot(dronePos.x - b.worldPosition.x, dronePos.y - b.worldPosition.y)
                return distA < distB
            })

            if let newTarget = nearest {
                drone.targetSettlement = newTarget
                // Rebuild path: current position → new settlement → HQ
                let waypoints = generateSettlementPath(
                    from: dronePos, through: newTarget.worldPosition, to: hqPoint
                )
                drone.retargetPath(waypoints: waypoints)
            } else {
                // No alive settlements — fly straight to HQ
                drone.targetSettlement = nil
                let waypoints = generateSettlementPath(from: dronePos, to: hqPoint)
                drone.retargetPath(waypoints: waypoints)
            }
        }
    }

    func onMineReachedGround(_ mine: MineBombEntity) {
        let pos = mine.component(ofType: SpriteComponent.self)?.spriteNode.position ?? .zero
        spawnRocketBlast(at: pos, radius: Constants.GameBalance.mineBombBlastRadius, damage: 1)
        removeEntity(mine)
    }

    func onMineShotInAir(_ mine: MineBombEntity) {
        removeEntity(mine)
    }

    func onMineHitDrone(_ mine: MineBombEntity, drone: AttackDroneEntity) {
        if !drone.isHit {
            drone.takeDamage(1)
            if drone.isHit {
                onDroneDestroyed(drone: drone)
            }
        }
        removeEntity(mine)
    }

    func triggerGameOver() {
        currentPhase = .gameOver
        cleanupOffscreenIndicator()
        settingsButton?.isHidden = true
        startWaveButton?.isHidden = true
        speedButton?.isHidden = true
        showGameOverOverlay()
    }

    func showGameOverOverlay() {
        // Record final wave result if in combat
        if waveKills > 0 || waveLeaked > 0 {
            let livesLost = waveLivesAtStart - max(lives, 0)
            gameWaveResults.append((wave: waveManager?.currentWave ?? 0, kills: waveKills, leaked: waveLeaked, livesLost: livesLost))
            for (type, count) in waveKillsByType { gameTotalKillsByType[type, default: 0] += count }
            for (type, count) in waveLeakedByType { gameTotalLeakedByType[type, default: 0] += count }
        }

        let overlay = SKNode()
        overlay.name = "gameOverOverlay"
        overlay.zPosition = 100
        addChild(overlay)

        let bg = SKSpriteNode(color: UIColor.black.withAlphaComponent(0.85), size: frame.size)
        bg.position = CGPoint(x: frame.midX, y: frame.midY)
        overlay.addChild(bg)

        var yPos = frame.midY + 220

        // Title
        let title = SKLabelNode(fontNamed: Constants.GameBalance.hudFontName)
        title.text = "ОБОРОНА ПРОВАЛЕНА"
        title.fontSize = 32
        title.fontColor = .red
        title.position = CGPoint(x: frame.midX, y: yPos)
        overlay.addChild(title)
        yPos -= 40

        // Basic stats
        let statsLines = [
            "Очки: \(score)",
            "Волна: \(waveManager?.currentWave ?? 0)",
            "Уничтожено: \(dronesDestroyed)"
        ]
        for text in statsLines {
            let label = SKLabelNode(fontNamed: Constants.GameBalance.hudFontName)
            label.text = text
            label.fontSize = 16
            label.fontColor = .white
            label.position = CGPoint(x: frame.midX, y: yPos)
            overlay.addChild(label)
            yPos -= 22
        }
        yPos -= 10

        // Wave timeline (colored dots)
        if !gameWaveResults.isEmpty {
            let timelineLabel = SKLabelNode(fontNamed: Constants.GameBalance.hudFontName)
            timelineLabel.text = "ТАЙМЛАЙН ВОЛН"
            timelineLabel.fontSize = 13
            timelineLabel.fontColor = UIColor(white: 0.7, alpha: 1)
            timelineLabel.position = CGPoint(x: frame.midX, y: yPos)
            overlay.addChild(timelineLabel)
            yPos -= 20

            let dotSize: CGFloat = 12
            let spacing: CGFloat = 4
            let totalWidth = CGFloat(gameWaveResults.count) * (dotSize + spacing) - spacing
            let startX = frame.midX - totalWidth / 2
            for (i, result) in gameWaveResults.enumerated() {
                let color: UIColor
                if result.livesLost == 0 && result.leaked == 0 {
                    color = .green
                } else if result.livesLost <= 2 {
                    color = .yellow
                } else {
                    color = .red
                }
                let dot = SKSpriteNode(color: color, size: CGSize(width: dotSize, height: dotSize))
                dot.position = CGPoint(x: startX + CGFloat(i) * (dotSize + spacing) + dotSize / 2, y: yPos)
                overlay.addChild(dot)

                // Wave number below dot
                let numLabel = SKLabelNode(fontNamed: Constants.GameBalance.hudFontName)
                numLabel.text = "\(result.wave)"
                numLabel.fontSize = 8
                numLabel.fontColor = UIColor(white: 0.5, alpha: 1)
                numLabel.position = CGPoint(x: dot.position.x, y: yPos - 12)
                overlay.addChild(numLabel)
            }
            yPos -= 30
        }

        // What leaked
        if !gameTotalLeakedByType.isEmpty {
            yPos -= 5
            let leakedTitle = SKLabelNode(fontNamed: Constants.GameBalance.hudFontName)
            leakedTitle.text = "ПРОРВАВШИЕСЯ УГРОЗЫ"
            leakedTitle.fontSize = 13
            leakedTitle.fontColor = UIColor(white: 0.7, alpha: 1)
            leakedTitle.position = CGPoint(x: frame.midX, y: yPos)
            overlay.addChild(leakedTitle)
            yPos -= 18

            let sorted = gameTotalLeakedByType.sorted { $0.value > $1.value }
            for entry in sorted.prefix(4) {
                let label = SKLabelNode(fontNamed: Constants.GameBalance.hudFontName)
                label.text = "\(entry.key): \(entry.value)"
                label.fontSize = 14
                label.fontColor = UIColor(red: 1, green: 0.6, blue: 0.4, alpha: 1)
                label.position = CGPoint(x: frame.midX, y: yPos)
                overlay.addChild(label)
                yPos -= 18
            }
        }

        // Contextual tip
        yPos -= 10
        let tip = generateContextualTip()
        let tipLabel = SKLabelNode(fontNamed: Constants.GameBalance.hudFontName)
        tipLabel.text = tip
        tipLabel.fontSize = 12
        tipLabel.fontColor = UIColor(red: 0.6, green: 0.85, blue: 1, alpha: 1)
        tipLabel.numberOfLines = 2
        tipLabel.preferredMaxLayoutWidth = frame.width - 60
        tipLabel.position = CGPoint(x: frame.midX, y: yPos)
        overlay.addChild(tipLabel)
        yPos -= 40

        // Buttons
        let restartBtn = SKSpriteNode(color: .darkGray, size: CGSize(width: 180, height: 44))
        restartBtn.position = CGPoint(x: frame.midX, y: yPos)
        restartBtn.name = "playAgainButton"
        overlay.addChild(restartBtn)

        let restartLabel = SKLabelNode(fontNamed: Constants.GameBalance.hudFontName)
        restartLabel.text = "Играть снова"
        restartLabel.fontSize = 18
        restartLabel.fontColor = .green
        restartLabel.verticalAlignmentMode = .center
        restartLabel.name = "playAgainButton"
        restartBtn.addChild(restartLabel)

        let menuBtn = SKSpriteNode(color: .systemRed, size: CGSize(width: 180, height: 44))
        menuBtn.position = CGPoint(x: frame.midX, y: yPos - 55)
        menuBtn.name = "menuButton_gameOver"
        overlay.addChild(menuBtn)

        let menuLabel = SKLabelNode(fontNamed: Constants.GameBalance.hudFontName)
        menuLabel.text = "Меню"
        menuLabel.fontSize = 18
        menuLabel.fontColor = .white
        menuLabel.verticalAlignmentMode = .center
        menuLabel.name = "menuButton_gameOver"
        menuBtn.addChild(menuLabel)
    }

    func generateContextualTip() -> String {
        // Analyze what leaked most and suggest counter
        let topLeaked = gameTotalLeakedByType.max(by: { $0.value < $1.value })?.key ?? ""
        switch topLeaked {
        case "Cruise":
            return "Совет: ЗРПК эффективен против крылатых ракет"
        case "FPV":
            return "Совет: РЭБ-башня замедляет FPV-дроны"
        case "Shahed":
            return "Совет: автопушки ЗУ хорошо работают по Шахедам"
        case "Heavy":
            return "Совет: С-300 пробивает броню тяжёлых дронов"
        case "Missile":
            return "Совет: перехватчики ПРЧ защищают от ракетных залпов"
        case "EW":
            return "Совет: уничтожайте РЭБ-дроны в первую очередь"
        default:
            if waveManager?.isCurrentWaveNight == true {
                return "Совет: ставьте РЛС для обнаружения целей ночью"
            }
            return "Совет: распределяйте башни для перекрытия всех направлений"
        }
    }

    func playAgain() {
        enumerateChildNodes(withName: "//gameOverOverlay") { node, _ in
            node.removeFromParent()
        }
        startGame()
    }

    var hasGameOverOverlay: Bool {
        childNode(withName: "//gameOverOverlay") != nil
    }

    // MARK: - Military Aid Overlay

    func showMilitaryAidOverlay() {
        let options = militaryAidManager.generateOptions()
        guard options.count == 3 else { return }

        let overlay = SKNode()
        overlay.name = "militaryAidOverlay"
        overlay.zPosition = 100
        addChild(overlay)

        // Semi-transparent background
        let bg = SKSpriteNode(color: UIColor.black.withAlphaComponent(0.7), size: frame.size)
        bg.position = CGPoint(x: frame.midX, y: frame.midY)
        overlay.addChild(bg)

        // Title
        let title = SKLabelNode(fontNamed: Constants.GameBalance.hudFontName)
        title.text = "ВОЕННАЯ ПОМОЩЬ"
        title.fontSize = 28
        title.fontColor = .systemYellow
        title.position = CGPoint(x: frame.midX, y: frame.midY + 180)
        overlay.addChild(title)

        let subtitle = SKLabelNode(fontNamed: Constants.GameBalance.hudFontName)
        subtitle.text = "Выберите усиление"
        subtitle.fontSize = 16
        subtitle.fontColor = UIColor.white.withAlphaComponent(0.7)
        subtitle.position = CGPoint(x: frame.midX, y: frame.midY + 152)
        overlay.addChild(subtitle)

        // 3 upgrade cards
        let cardWidth: CGFloat = min(frame.width * 0.28, 110)
        let cardHeight: CGFloat = 160
        let spacing: CGFloat = 10
        let totalWidth = cardWidth * 3 + spacing * 2
        let startX = frame.midX - totalWidth / 2 + cardWidth / 2

        for (i, upgrade) in options.enumerated() {
            let cardX = startX + CGFloat(i) * (cardWidth + spacing)
            let cardY = frame.midY - 10

            // Card background
            let card = SKSpriteNode(color: UIColor.darkGray.withAlphaComponent(0.85),
                                    size: CGSize(width: cardWidth, height: cardHeight))
            card.position = CGPoint(x: cardX, y: cardY)
            card.name = "aidCard_\(i)"
            overlay.addChild(card)

            // Color accent bar at top
            let accent = SKSpriteNode(color: upgrade.color,
                                      size: CGSize(width: cardWidth, height: 6))
            accent.position = CGPoint(x: 0, y: cardHeight / 2 - 3)
            accent.name = "aidCard_\(i)"
            card.addChild(accent)

            // Title
            let titleLabel = SKLabelNode(fontNamed: Constants.GameBalance.hudFontName)
            titleLabel.text = upgrade.title
            titleLabel.fontSize = 12
            titleLabel.fontColor = upgrade.color
            titleLabel.position = CGPoint(x: 0, y: cardHeight / 2 - 30)
            titleLabel.verticalAlignmentMode = .center
            titleLabel.name = "aidCard_\(i)"
            card.addChild(titleLabel)

            // Description (word-wrapped manually)
            let desc = upgrade.description
            let descLines = wrapText(desc, maxChars: 14)
            for (lineIdx, line) in descLines.enumerated() {
                let descLabel = SKLabelNode(fontNamed: Constants.GameBalance.hudFontName)
                descLabel.text = line
                descLabel.fontSize = 11
                descLabel.fontColor = .white
                descLabel.position = CGPoint(x: 0, y: 10 - CGFloat(lineIdx) * 16)
                descLabel.verticalAlignmentMode = .center
                descLabel.name = "aidCard_\(i)"
                card.addChild(descLabel)
            }

            // Appear animation
            card.setScale(0.5)
            card.alpha = 0
            let delay = SKAction.wait(forDuration: Double(i) * 0.12)
            let appear = SKAction.group([
                SKAction.scale(to: 1.0, duration: 0.25),
                SKAction.fadeIn(withDuration: 0.2)
            ])
            appear.timingMode = .easeOut
            card.run(SKAction.sequence([delay, appear]))
        }
    }

    func wrapText(_ text: String, maxChars: Int) -> [String] {
        let words = text.split(separator: " ")
        var lines: [String] = []
        var currentLine = ""
        for word in words {
            if currentLine.isEmpty {
                currentLine = String(word)
            } else if currentLine.count + 1 + word.count <= maxChars {
                currentLine += " " + word
            } else {
                lines.append(currentLine)
                currentLine = String(word)
            }
        }
        if !currentLine.isEmpty { lines.append(currentLine) }
        return lines
    }

    func handleMilitaryAidSelection(cardIndex: Int) {
        let options = militaryAidManager.currentOptions
        guard cardIndex >= 0 && cardIndex < options.count else { return }

        let selected = options[cardIndex]
        applyMilitaryAid(selected)

        // Flash selected card, then dismiss overlay
        enumerateChildNodes(withName: "//militaryAidOverlay") { overlay, _ in
            overlay.enumerateChildNodes(withName: "aidCard_\(cardIndex)") { card, _ in
                if card is SKSpriteNode && card.parent === overlay {
                    card.run(SKAction.colorize(with: .white, colorBlendFactor: 0.5, duration: 0.15))
                }
            }
            let dismiss = SKAction.sequence([
                SKAction.wait(forDuration: 0.4),
                SKAction.fadeOut(withDuration: 0.2),
                SKAction.removeFromParent()
            ])
            overlay.run(dismiss) { [weak self] in
                self?.resumeAfterMilitaryAid()
            }
        }
        militaryAidManager.currentOptions = []
        updateHUD()
    }

    func applyMilitaryAid(_ type: MilitaryAidType) {
        switch type {
        case .funding:
            economyManager.earn(200)
            showAidFloatingText("+200 DP", color: .systemYellow)

        case .fortification:
            lives += 5
            showAidFloatingText("+5 HP", color: .systemBlue)

        case .airstrike:
            let targets = activeDrones.filter { !$0.isHit }.prefix(8)
            for drone in targets {
                drone.takeDamage(999)
                if let pos = drone.component(ofType: SpriteComponent.self)?.spriteNode.position {
                    spawnAirstrikeExplosion(at: pos)
                }
                onDroneDestroyed(drone: drone)
            }
            if targets.isEmpty {
                showAidFloatingText("НЕТ ЦЕЛЕЙ", color: .gray)
            }

        case .repairAll:
            for tower in towerPlacement.towers {
                guard let stats = tower.stats, stats.isDisabled else { continue }
                tower.fullRepair()
                // White flash on repaired tower
                if let sprite = tower.component(ofType: SpriteComponent.self)?.spriteNode {
                    let flash = SKSpriteNode(color: .white, size: CGSize(width: 36, height: 36))
                    flash.position = sprite.position
                    flash.zPosition = 40
                    addChild(flash)
                    flash.run(SKAction.sequence([
                        SKAction.fadeOut(withDuration: 0.5),
                        SKAction.removeFromParent()
                    ]))
                }
            }

        case .shieldHQ:
            militaryAidManager.activateShield()
            showShieldEffect()

        case .reloadAll:
            for tower in towerPlacement.towers {
                guard let stats = tower.stats else { continue }
                stats.replenishMagazine()
            }
            showAidFloatingText("ЗРК ПЕРЕЗАРЯЖЕНЫ", color: .systemOrange)

        case .slowField:
            for drone in activeDrones where !drone.isHit {
                drone.speed *= 0.4
                // Visual: blue tint on slowed drones
                if let sprite = drone.component(ofType: SpriteComponent.self)?.spriteNode {
                    sprite.run(SKAction.colorize(with: .cyan, colorBlendFactor: 0.4, duration: 0.2))
                }
            }
            // Revert after 10 seconds
            run(SKAction.sequence([
                SKAction.wait(forDuration: 10.0),
                SKAction.run { [weak self] in
                    guard let self else { return }
                    for drone in self.activeDrones where !drone.isHit {
                        drone.speed /= 0.4
                        if let sprite = drone.component(ofType: SpriteComponent.self)?.spriteNode {
                            sprite.run(SKAction.colorize(withColorBlendFactor: 0, duration: 0.3))
                        }
                    }
                }
            ]))
            showAidFloatingText("РЭБ АКТИВИРОВАНО", color: .systemPurple)

        case .bonusWave:
            for i in 0..<5 {
                run(SKAction.sequence([
                    SKAction.wait(forDuration: Double(i) * 0.5),
                    SKAction.run { [weak self] in self?.spawnBonusDrone() }
                ]))
            }
        }
    }

    func showAidFloatingText(_ text: String, color: UIColor) {
        let label = SKLabelNode(fontNamed: Constants.GameBalance.hudFontName)
        label.text = text
        label.fontSize = 24
        label.fontColor = color
        label.position = CGPoint(x: frame.midX, y: frame.midY - 60)
        label.zPosition = 99
        addChild(label)
        label.run(SKAction.sequence([
            SKAction.group([
                SKAction.moveBy(x: 0, y: 60, duration: 1.2),
                SKAction.sequence([
                    SKAction.wait(forDuration: 0.8),
                    SKAction.fadeOut(withDuration: 0.4)
                ])
            ]),
            SKAction.removeFromParent()
        ]))
    }

    func spawnAirstrikeExplosion(at pos: CGPoint) {
        let textures = AnimationTextureCache.shared.largeExplosion
        if !textures.isEmpty {
            let node = acquireExplosionNode()
            node.texture = textures[0]
            node.size = CGSize(width: 40, height: 40)
            node.color = .white
            node.colorBlendFactor = 0
            node.position = pos
            node.zPosition = 80
            node.alpha = 1.0
            node.setScale(1.0)
            addChild(node)
            node.run(SKAction.sequence([
                SKAction.animate(with: textures, timePerFrame: 0.057, resize: false, restore: false),
                SKAction.run { [weak self, weak node] in
                    guard let self, let node else { return }
                    self.releaseExplosionNode(node)
                }
            ]))
        } else {
            // Fallback: original colored square
            let flash = SKSpriteNode(color: .orange, size: CGSize(width: 30, height: 30))
            flash.position = pos
            flash.zPosition = 80
            addChild(flash)
            flash.run(SKAction.sequence([
                SKAction.group([
                    SKAction.scale(to: 3.0, duration: 0.25),
                    SKAction.fadeOut(withDuration: 0.3)
                ]),
                SKAction.removeFromParent()
            ]))
        }
    }

    func showShieldEffect() {
        guard let gridMap else { return }
        let hqPos = gridMap.worldPosition(
            forRow: Constants.TowerDefense.gridRows - 1,
            col: Constants.TowerDefense.gridCols / 2
        )
        let shield = SKShapeNode(circleOfRadius: 40)
        shield.strokeColor = .cyan
        shield.fillColor = UIColor.cyan.withAlphaComponent(0.15)
        shield.lineWidth = 2
        shield.position = hqPos
        shield.zPosition = 90
        shield.name = "hqShield"
        addChild(shield)
        // Pulse animation
        shield.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.scale(to: 1.1, duration: 0.8),
            SKAction.scale(to: 0.95, duration: 0.8),
        ])))
    }

    /// Spawn a slow, visible bonus drone worth extra DP
    func spawnBonusDrone() {
        guard let gridMap else { return }
        let pathDefs = selectedLevel.dronePaths
        guard let pathDef = pathDefs.randomElement() else { return }
        let waypoints = pathDef.gridWaypoints.map { wp in
            gridMap.worldPosition(forRow: wp.row, col: wp.col)
        }
        guard !waypoints.isEmpty else { return }
        let jittered = waypoints.enumerated().map { i, wp -> CGPoint in
            if i == 0 { return CGPoint(x: wp.x + .random(in: -15...15), y: wp.y + 40) }
            if i == waypoints.count - 1 { return CGPoint(x: wp.x, y: wp.y) }
            return CGPoint(x: wp.x + .random(in: -10...10), y: wp.y + .random(in: -8...8))
        }
        let flightPath = DroneFlightPath(waypoints: jittered, altitude: .low, spawnEdge: pathDef.spawnEdge)
        let drone = AttackDroneEntity(damage: 1, speed: 30, imageName: "Drone", flyingPath: flightPath.toFlyingPath())
        drone.configureHealth(1)
        drone.addComponent(AltitudeComponent(altitude: .low))
        let shadow = ShadowComponent()
        drone.addComponent(shadow)
        shadowLayer?.addChild(shadow.shadowNode)
        // Gold color — bonus target
        if let sprite = drone.component(ofType: SpriteComponent.self)?.spriteNode {
            sprite.color = .systemYellow
            sprite.colorBlendFactor = 1.0
            sprite.size = CGSize(width: 26, height: 26)
            sprite.zPosition = 62
        }
        activeDrones.append(drone)
        addEntity(drone)
    }

    func resumeAfterMilitaryAid() {
        interWaveCountdown = normalWaveCountdown
        startWaveButton?.isHidden = false
        updateStartWaveButton()
    }

    var hasMilitaryAidOverlay: Bool {
        childNode(withName: "//militaryAidOverlay") != nil
    }

    // MARK: - Enemy Missile Salvo

    func showMissileWarning() {
        let warning = SKLabelNode(fontNamed: Constants.GameBalance.hudFontName)
        warning.text = "INCOMING"
        warning.fontSize = 32
        warning.fontColor = .red
        warning.position = CGPoint(x: frame.midX, y: frame.height - safeTop - 80)
        warning.zPosition = 97
        warning.alpha = 0
        warning.name = "missileWarning"
        addChild(warning)

        let fadeIn = SKAction.fadeIn(withDuration: 0.15)
        let pulse = SKAction.sequence([
            SKAction.scale(to: 1.15, duration: 0.3),
            SKAction.scale(to: 0.9, duration: 0.3)
        ])
        let pulseForever = SKAction.repeat(pulse, count: 3)
        let fadeOut = SKAction.fadeOut(withDuration: 0.3)
        let remove = SKAction.removeFromParent()
        warning.run(SKAction.sequence([fadeIn, pulseForever, fadeOut, remove]))

        // Red edge tint
        let tint = SKSpriteNode(color: UIColor.red.withAlphaComponent(0.15), size: frame.size)
        tint.position = CGPoint(x: frame.midX, y: frame.midY)
        tint.zPosition = 96
        tint.alpha = 0
        addChild(tint)
        tint.run(SKAction.sequence([
            SKAction.fadeAlpha(to: 0.3, duration: 0.2),
            SKAction.fadeOut(withDuration: 1.0),
            SKAction.removeFromParent()
        ]))
    }

    func spawnMissileSalvo(waveNumber: Int) {
        let gb = Constants.GameBalance.self
        let firstWave = gb.enemyMissileFirstWave
        let salvoSize = min(
            gb.enemyMissileBaseSalvoSize + (waveNumber - firstWave) / gb.enemyMissileSalvoGrowthInterval,
            gb.enemyMissileMaxSalvoSize
        )

        pendingMissileSpawns += salvoSize
        for i in 0..<salvoSize {
            let delay = TimeInterval(i) * gb.enemyMissileInSalvoInterval
            let spawnAction = SKAction.sequence([
                SKAction.wait(forDuration: delay),
                SKAction.run { [weak self] in
                    self?.spawnSingleMissile(waveNumber: waveNumber)
                }
            ])
            run(spawnAction)
        }
    }

    func spawnSingleMissile(waveNumber: Int) {
        pendingMissileSpawns = max(0, pendingMissileSpawns - 1)
        let gb = Constants.GameBalance.self
        let spawnX = CGFloat.random(in: 20...(frame.width - 20))
        let spawnY = frame.height + CGFloat.random(in: 30...50)
        let spawnPoint = CGPoint(x: spawnX, y: spawnY)

        // Target: random HQ-row point + scatter
        let hqCenter = comboHQPoint()

        let scatterAngle = CGFloat.random(in: 0...(2 * .pi))
        let scatterDist = CGFloat.random(in: 0...gb.enemyMissileScatterRadius)
        let target = CGPoint(
            x: hqCenter.x + cos(scatterAngle) * scatterDist,
            y: hqCenter.y + sin(scatterAngle) * scatterDist
        )

        let missileSpeed = gb.enemyMissileBaseSpeed + CGFloat.random(in: -gb.enemyMissileSpeedVariance...gb.enemyMissileSpeedVariance)

        let missile = EnemyMissileEntity(sceneFrame: frame)

        // Add altitude component
        missile.addComponent(AltitudeComponent(altitude: .ballistic))
        let shadow = ShadowComponent()
        missile.addComponent(shadow)
        shadowLayer?.addChild(shadow.shadowNode)

        // Scale and zPosition for ballistic altitude.
        // Base size lives in Constants.SpriteSize.enemyMissile — do NOT hardcode here.
        if let spriteNode = missile.component(ofType: SpriteComponent.self)?.spriteNode {
            let scale = DroneAltitude.ballistic.droneVisualScale
            let base = Constants.SpriteSize.enemyMissile
            spriteNode.size = CGSize(width: base.width * scale, height: base.height * scale)
            spriteNode.zPosition = 61 + CGFloat(DroneAltitude.ballistic.rawValue) * 5
        }

        missile.configureFlight(from: spawnPoint, to: target, speed: missileSpeed)

        activeDrones.append(missile)
        addEntity(missile)
    }

    // MARK: - HARM (Anti-Radiation) Missile

    func showHarmWarning() {
        let warning = SKLabelNode(fontNamed: Constants.GameBalance.hudFontName)
        warning.text = "ПРР"
        warning.fontSize = 32
        warning.fontColor = .yellow
        warning.position = CGPoint(x: frame.midX, y: frame.height - safeTop - 120)
        warning.zPosition = 97
        warning.alpha = 0
        warning.name = "harmWarning"
        addChild(warning)

        let fadeIn = SKAction.fadeIn(withDuration: 0.15)
        let pulse = SKAction.sequence([
            SKAction.scale(to: 1.15, duration: 0.3),
            SKAction.scale(to: 0.9, duration: 0.3)
        ])
        let pulseForever = SKAction.repeat(pulse, count: 3)
        let fadeOut = SKAction.fadeOut(withDuration: 0.3)
        let remove = SKAction.removeFromParent()
        warning.run(SKAction.sequence([fadeIn, pulseForever, fadeOut, remove]))

        // Amber edge tint
        let tint = SKSpriteNode(color: UIColor.yellow.withAlphaComponent(0.12), size: frame.size)
        tint.position = CGPoint(x: frame.midX, y: frame.midY)
        tint.zPosition = 96
        tint.alpha = 0
        addChild(tint)
        tint.run(SKAction.sequence([
            SKAction.fadeAlpha(to: 0.3, duration: 0.2),
            SKAction.fadeOut(withDuration: 1.0),
            SKAction.removeFromParent()
        ]))
    }

    func selectHarmTargets(salvoSize: Int) -> [TowerEntity] {
        // Filter radar-emitting towers that are not disabled and not concealed
        let radarEmitters = towerPlacement.towers.filter { tower in
            guard let stats = tower.stats, !stats.isDisabled else { return false }
            guard stats.towerType == .samLauncher || stats.towerType == .interceptor || stats.towerType == .radar else { return false }
            // Concealed terrain: tower invisible to HARM
            if let gridPos = tower.component(ofType: GridPositionComponent.self),
               let cell = gridMap?.cell(atRow: gridPos.row, col: gridPos.col),
               cell.terrain == .concealed {
                return false
            }
            return true
        }

        // Exclude towers already targeted by in-flight HARMs
        let alreadyTargeted = Set(activeDrones.compactMap { ($0 as? HarmMissileEntity)?.targetTower }.map { ObjectIdentifier($0) })
        let available = radarEmitters.filter { !alreadyTargeted.contains(ObjectIdentifier($0)) }

        guard !available.isEmpty else { return [] }

        // Sort by priority: S-300 > PRCH > RLS
        let sorted = available.sorted { a, b in
            let priorityA = harmTargetPriority(a)
            let priorityB = harmTargetPriority(b)
            return priorityA > priorityB
        }

        // Assign 1 HARM per unique tower first, then wrap around
        var targets = [TowerEntity]()
        for i in 0..<salvoSize {
            let index = i % sorted.count
            targets.append(sorted[index])
        }
        return targets
    }

    func harmTargetPriority(_ tower: TowerEntity) -> Int {
        guard let stats = tower.stats else { return 0 }
        switch stats.towerType {
        case .samLauncher: return 3
        case .interceptor: return 2
        case .radar: return 1
        default: return 0
        }
    }

    func spawnHarmSalvo(waveNumber: Int) {
        let gb = Constants.GameBalance.self
        let firstWave = gb.harmMissileFirstWave
        let salvoSize = min(
            gb.harmMissileBaseSalvoSize + (waveNumber - firstWave) / gb.harmMissileSalvoGrowthInterval,
            gb.harmMissileMaxSalvoSize
        )

        let targets = selectHarmTargets(salvoSize: salvoSize)
        guard !targets.isEmpty else { return }

        pendingHarmSpawns += targets.count
        for (i, tower) in targets.enumerated() {
            let delay = TimeInterval(i) * gb.harmMissileInSalvoInterval
            let spawnAction = SKAction.sequence([
                SKAction.wait(forDuration: delay),
                SKAction.run { [weak self, weak tower] in
                    guard let self, let tower else {
                        self?.pendingHarmSpawns = max(0, (self?.pendingHarmSpawns ?? 1) - 1)
                        return
                    }
                    self.spawnSingleHarm(targetTower: tower)
                }
            ])
            run(spawnAction)
        }
    }

    func spawnSingleHarm(targetTower tower: TowerEntity) {
        pendingHarmSpawns = max(0, pendingHarmSpawns - 1)

        // Re-check tower not disabled at spawn time
        if let stats = tower.stats, stats.isDisabled { return }

        let gb = Constants.GameBalance.self
        let spawnX = CGFloat.random(in: 20...(frame.width - 20))
        let spawnY = frame.height + CGFloat.random(in: 30...50)
        let spawnPoint = CGPoint(x: spawnX, y: spawnY)

        let missileSpeed = gb.harmMissileBaseSpeed + CGFloat.random(in: -gb.harmMissileSpeedVariance...gb.harmMissileSpeedVariance)

        let harm = HarmMissileEntity(sceneFrame: frame)

        // Add altitude component — cruise altitude
        harm.addComponent(AltitudeComponent(altitude: .cruise))
        let shadow = ShadowComponent()
        harm.addComponent(shadow)
        shadowLayer?.addChild(shadow.shadowNode)

        // Scale and zPosition for cruise altitude
        if let spriteNode = harm.component(ofType: SpriteComponent.self)?.spriteNode {
            let scale = DroneAltitude.cruise.droneVisualScale
            spriteNode.size = CGSize(width: 7 * scale, height: 20 * scale)
            spriteNode.zPosition = 61 + CGFloat(DroneAltitude.cruise.rawValue) * 5
        }

        harm.configureFlight(from: spawnPoint, toTower: tower, speed: missileSpeed)

        activeDrones.append(harm)
        addEntity(harm)
    }

    func onHarmHitTower(harm: HarmMissileEntity) {
        guard let tower = harm.targetTower,
              let stats = tower.stats else { return }
        tower.takeBombDamage(Constants.GameBalance.harmMissileTowerDamage)

        // Impact explosion VFX
        if let pos = harm.component(ofType: SpriteComponent.self)?.spriteNode.position {
            let flash = SKSpriteNode(color: .orange, size: CGSize(width: 20, height: 20))
            flash.position = pos
            flash.zPosition = isNightWave ? Constants.NightWave.nightEffectZPosition : 50
            flash.alpha = 0.8
            addChild(flash)
            let expand = SKAction.scale(to: 2.5, duration: 0.2)
            let fade = SKAction.fadeOut(withDuration: 0.2)
            flash.run(SKAction.sequence([SKAction.group([expand, fade]), SKAction.removeFromParent()]))
        }
    }

    // MARK: - Mine Layer / Bomber Drone

    func spawnMineLayer(health: Int) {
        guard let target = bestBombingTarget() else { return }
        let mineLayer = MineLayerDroneEntity(sceneFrame: frame)
        mineLayer.mineLayerDelegate = self
        mineLayer.configureHealth(health)

        // Set altitude to .micro
        mineLayer.addComponent(AltitudeComponent(altitude: .micro))
        let shadow = ShadowComponent()
        mineLayer.addComponent(shadow)
        shadowLayer?.addChild(shadow.shadowNode)

        // Scale for micro altitude
        if let spriteNode = mineLayer.component(ofType: SpriteComponent.self)?.spriteNode {
            let scale = DroneAltitude.micro.droneVisualScale
            spriteNode.size = CGSize(width: 30 * scale, height: 30 * scale)
            spriteNode.zPosition = 61 + CGFloat(DroneAltitude.micro.rawValue) * 5
        }

        mineLayer.beginCycleTD(in: frame, targetingTower: target)
        activeDrones.append(mineLayer)
        addEntity(mineLayer)
    }

    func bestBombingTarget(from dronePosition: CGPoint? = nil) -> TowerEntity? {
        guard let towerPlacement else { return nil }

        let from = dronePosition ?? CGPoint(x: frame.midX, y: frame.maxY)

        // Anti-micro gun towers: effective close-range defence against mine layers
        let antiMicroTypes: Set<TowerType> = [.autocannon, .ciws]

        // Collect cover zones from active gun towers that counter micro drones
        let coverZones: [(position: CGPoint, rangeSq: CGFloat)] = towerPlacement.towers.compactMap { tower in
            guard let stats = tower.stats,
                  !stats.isDisabled,
                  antiMicroTypes.contains(stats.towerType)
            else { return nil }
            return (position: tower.worldPosition, rangeSq: stats.range * stats.range)
        }

        func isCovered(_ candidate: TowerEntity) -> Bool {
            let pos = candidate.worldPosition
            for zone in coverZones {
                let dx = pos.x - zone.position.x
                let dy = pos.y - zone.position.y
                if dx * dx + dy * dy <= zone.rangeSq { return true }
            }
            return false
        }

        let priorityOrder: [TowerType] = [.samLauncher, .interceptor, .radar, .ciws, .autocannon]

        // Two-tier search: first try completely uncovered targets (safe to bomb),
        // and only fall back to covered targets if nothing uncovered remains.
        for tier in 0...1 {
            let allowCovered = tier == 1
            for type in priorityOrder {
                guard !antiMicroTypes.contains(type) else { continue }
                let eligible = towerPlacement.towers.filter { tower in
                    guard tower.towerType == type,
                          !(tower.stats?.isDisabled ?? true)
                    else { return false }
                    return allowCovered || !isCovered(tower)
                }
                guard !eligible.isEmpty else { continue }
                return eligible.min(by: { a, b in
                    squaredDistance(a.worldPosition, from) < squaredDistance(b.worldPosition, from)
                })
            }
        }
        return nil
    }

    func squaredDistance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = a.x - b.x
        let dy = a.y - b.y
        return dx * dx + dy * dy
    }

    func activeTowerThreats() -> [MineLayerDroneEntity.TowerThreatInfo] {
        guard let towerPlacement else { return [] }
        var threats = [MineLayerDroneEntity.TowerThreatInfo]()
        for tower in towerPlacement.towers {
            guard let stats = tower.stats,
                  (stats.towerType == .autocannon || stats.towerType == .ciws),
                  !stats.isDisabled,
                  let targeting = tower.component(ofType: TowerTargetingComponent.self),
                  targeting.currentTarget != nil
            else { continue }
            threats.append(MineLayerDroneEntity.TowerThreatInfo(
                position: tower.worldPosition,
                range: stats.range,
                id: ObjectIdentifier(tower)
            ))
        }
        return threats
    }

    /// Nearest active combat tower (AA / gun / radar / EW) to `origin`.
    /// Excludes `oilRefinery` by design — swarm drones and similar attackers
    /// target the defenders, not the economy building.
    func nearestCombatTower(from origin: CGPoint) -> TowerEntity? {
        guard let towerPlacement else { return nil }
        let combatTypes: Set<TowerType> = [
            .autocannon, .ciws, .samLauncher, .interceptor,
            .radar, .ewTower, .pzrk, .gepard
        ]
        let eligible = towerPlacement.towers.filter { tower in
            guard let stats = tower.stats,
                  !stats.isDisabled,
                  combatTypes.contains(stats.towerType)
            else { return false }
            return true
        }
        return eligible.min(by: { squaredDistance($0.worldPosition, origin) < squaredDistance($1.worldPosition, origin) })
    }

    func allTowerThreatZones() -> [MineLayerDroneEntity.TowerThreatInfo] {
        guard let towerPlacement else { return [] }
        var zones = [MineLayerDroneEntity.TowerThreatInfo]()
        for tower in towerPlacement.towers {
            guard let stats = tower.stats,
                  (stats.towerType == .autocannon || stats.towerType == .ciws),
                  !stats.isDisabled
            else { continue }
            zones.append(MineLayerDroneEntity.TowerThreatInfo(
                position: tower.worldPosition,
                range: stats.range,
                id: ObjectIdentifier(tower)
            ))
        }
        return zones
    }

    func onBombHitTower(_ mine: MineBombEntity, tower: TowerEntity) {
        tower.takeBombDamage(mine.damage)
        // Small explosion VFX
        let pos = mine.component(ofType: SpriteComponent.self)?.spriteNode.position ?? tower.worldPosition
        spawnBombExplosion(at: pos)
        removeEntity(mine)
    }

    func spawnBombExplosion(at position: CGPoint) {
        let textures = AnimationTextureCache.shared.smallExplosion
        if !textures.isEmpty {
            let node = acquireExplosionNode()
            node.texture = textures[0]
            node.size = CGSize(width: 21, height: 21)
            node.color = .white
            node.colorBlendFactor = 0
            node.position = position
            node.zPosition = isNightWave ? Constants.NightWave.nightEffectZPosition : 50
            node.alpha = 1.0
            node.setScale(1.0)
            addChild(node)
            node.run(SKAction.sequence([
                SKAction.animate(with: textures, timePerFrame: 0.05, resize: false, restore: false),
                SKAction.run { [weak self, weak node] in
                    guard let self, let node else { return }
                    self.releaseExplosionNode(node)
                }
            ]))
        } else {
            // Fallback: original colored square
            let flash = SKSpriteNode(color: .orange, size: CGSize(width: 16, height: 16))
            flash.position = position
            flash.zPosition = isNightWave ? Constants.NightWave.nightEffectZPosition : 50
            flash.alpha = 0.8
            addChild(flash)
            let expand = SKAction.scale(to: 2.0, duration: 0.15)
            let fade = SKAction.fadeOut(withDuration: 0.15)
            flash.run(SKAction.sequence([SKAction.group([expand, fade]), SKAction.removeFromParent()]))
        }
    }
}
