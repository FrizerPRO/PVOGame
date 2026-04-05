//
//  InPlaySKScene+GameFlow.swift
//  PVOGame
//

import SpriteKit

extension InPlaySKScene {
    // MARK: - Night Wave

    func transitionToNight() {
        guard !isNightWave else { return }
        isNightWave = true

        let overlay = SKSpriteNode(color: .black, size: frame.size)
        overlay.alpha = 0
        overlay.position = CGPoint(x: frame.midX, y: frame.midY)
        overlay.zPosition = 90  // under HUD
        overlay.name = "nightOverlay"
        addChild(overlay)
        nightOverlay = overlay

        overlay.run(SKAction.fadeAlpha(to: Constants.NightWave.overlayAlpha, duration: Constants.NightWave.transitionDuration))

        // Block tower placement
        towerPlacement?.selectTowerType(nil)
        conveyorBelt.deselect()
        conveyorBelt.setNightMode(true)

        // Create radar indicator dots
        updateRadarNightDots()
    }

    func transitionToDay() {
        guard isNightWave else { return }
        isNightWave = false

        if let overlay = nightOverlay {
            overlay.run(SKAction.sequence([
                SKAction.fadeOut(withDuration: Constants.NightWave.transitionDuration),
                SKAction.removeFromParent()
            ]))
            nightOverlay = nil
        }

        // Restore tower placement
        conveyorBelt.setNightMode(false)

        // Remove radar dots
        for (_, dot) in radarNightDots {
            dot.removeFromParent()
        }
        radarNightDots.removeAll()
    }

    /// Returns whether the given world-space point is within any active radar's coverage zone.
    /// Only meaningful during night waves; returns true during day.
    func isPositionInRadarCoverage(_ point: CGPoint) -> Bool {
        guard isNightWave else { return true }
        for (radarPos, rangeSq) in activeRadars {
            let dx = point.x - radarPos.x
            let dy = point.y - radarPos.y
            if dx * dx + dy * dy <= rangeSq {
                return true
            }
        }
        return false
    }

    /// Update blinking green dots at radar positions during night.
    func updateRadarNightDots() {
        guard isNightWave, let towerPlacement else { return }

        var currentIDs = Set<ObjectIdentifier>()
        for tower in towerPlacement.towers {
            guard let stats = tower.stats, stats.towerType == .radar, !stats.isDisabled else { continue }
            let id = ObjectIdentifier(tower)
            currentIDs.insert(id)

            if radarNightDots[id] == nil {
                let dot = SKSpriteNode(color: .green, size: CGSize(width: 6, height: 6))
                dot.position = tower.worldPosition
                dot.zPosition = Constants.NightWave.nightEffectZPosition
                dot.alpha = 0.2
                addChild(dot)

                let pulse = SKAction.sequence([
                    SKAction.fadeAlpha(to: 1.0, duration: 1.0),
                    SKAction.fadeAlpha(to: 0.2, duration: 1.0)
                ])
                dot.run(SKAction.repeatForever(pulse))
                radarNightDots[id] = dot
            }
        }

        // Remove dots for destroyed/disabled radars
        for (id, dot) in radarNightDots where !currentIDs.contains(id) {
            dot.removeFromParent()
            radarNightDots.removeValue(forKey: id)
        }
    }

    // MARK: - EW Jamming

    /// Returns the jamming accuracy multiplier for a tower (1.0 if not jammed).
    /// Uses per-frame cached jamming set for O(1) lookup.
    func ewJammingMultiplier(for tower: TowerEntity) -> CGFloat {
        jammedTowerIDs.contains(ObjectIdentifier(tower))
            ? Constants.EW.ewDroneAccuracyMultiplier : 1.0
    }

    // MARK: - Game Flow

    func showMainMenu() {
        currentPhase = .mainMenu
        hudNode?.isHidden = true
        conveyorBelt.removeUI()
        startWaveButton?.isHidden = true
        speedButton?.isHidden = true
        settingsButton?.isHidden = true

        let overlay = SKNode()
        overlay.name = "mainMenuOverlay"
        overlay.zPosition = 100
        addChild(overlay)

        let bg = SKSpriteNode(color: UIColor.black.withAlphaComponent(0.7), size: frame.size)
        bg.position = CGPoint(x: frame.midX, y: frame.midY)
        overlay.addChild(bg)

        let title = SKLabelNode(fontNamed: Constants.GameBalance.hudFontName)
        title.text = "PVO TOWER DEFENSE"
        title.fontSize = 28
        title.fontColor = .white
        title.position = CGPoint(x: frame.midX, y: frame.midY + 100)
        overlay.addChild(title)

        // Campaign button
        let campaignBtn = SKSpriteNode(color: .systemBlue, size: CGSize(width: 200, height: 50))
        campaignBtn.position = CGPoint(x: frame.midX, y: frame.midY + 10)
        campaignBtn.name = "campaignButton"
        overlay.addChild(campaignBtn)

        let campaignLabel = SKLabelNode(fontNamed: Constants.GameBalance.hudFontName)
        campaignLabel.text = "КАМПАНИЯ"
        campaignLabel.fontSize = 20
        campaignLabel.fontColor = .white
        campaignLabel.verticalAlignmentMode = .center
        campaignLabel.name = "campaignButton"
        campaignBtn.addChild(campaignLabel)

        // Stars counter
        let stars = CampaignManager.shared.totalStars()
        if stars > 0 {
            let starsLabel = SKLabelNode(fontNamed: Constants.GameBalance.hudFontName)
            starsLabel.text = "\(stars) \u{2605}"
            starsLabel.fontSize = 14
            starsLabel.fontColor = .systemYellow
            starsLabel.position = CGPoint(x: frame.midX, y: frame.midY - 20)
            overlay.addChild(starsLabel)
        }

        // Endless button
        let endlessBtn = SKSpriteNode(color: .systemGreen, size: CGSize(width: 200, height: 50))
        endlessBtn.position = CGPoint(x: frame.midX, y: frame.midY - 60)
        endlessBtn.name = "startGameButton"
        overlay.addChild(endlessBtn)

        let endlessLabel = SKLabelNode(fontNamed: Constants.GameBalance.hudFontName)
        endlessLabel.text = "ENDLESS"
        endlessLabel.fontSize = 20
        endlessLabel.fontColor = .white
        endlessLabel.verticalAlignmentMode = .center
        endlessLabel.name = "startGameButton"
        endlessBtn.addChild(endlessLabel)

    }

    // MARK: - Level Selection

    func showLevelSelect() {
        enumerateChildNodes(withName: "//mainMenuOverlay") { node, _ in
            node.removeFromParent()
        }

        let overlay = SKNode()
        overlay.name = "levelSelectOverlay"
        overlay.zPosition = 100
        addChild(overlay)

        let bg = SKSpriteNode(color: UIColor.black.withAlphaComponent(0.8), size: frame.size)
        bg.position = CGPoint(x: frame.midX, y: frame.midY)
        overlay.addChild(bg)

        let title = SKLabelNode(fontNamed: Constants.GameBalance.hudFontName)
        title.text = "CAMPAIGN"
        title.fontSize = 24
        title.fontColor = .white
        title.position = CGPoint(x: frame.midX, y: frame.height - 80 - safeTop)
        overlay.addChild(title)

        let campaign = CampaignManager.shared
        let levels = campaign.levels
        let cardHeight: CGFloat = 48
        let spacing: CGFloat = 8
        let startY = frame.height - 120 - safeTop

        for (i, level) in levels.enumerated() {
            let y = startY - CGFloat(i) * (cardHeight + spacing)
            let unlocked = campaign.isUnlocked(level.id)
            let completed = campaign.isCompleted(level.id)
            let stars = campaign.stars(for: level.id)

            let card = SKSpriteNode(
                color: unlocked ? UIColor.darkGray.withAlphaComponent(0.85) : UIColor.darkGray.withAlphaComponent(0.35),
                size: CGSize(width: frame.width - 40, height: cardHeight)
            )
            card.position = CGPoint(x: frame.midX, y: y)
            card.name = unlocked ? "levelCard_\(i)" : nil
            overlay.addChild(card)

            // Level number
            let numLabel = SKLabelNode(fontNamed: Constants.GameBalance.hudFontName)
            numLabel.text = "\(i + 1)."
            numLabel.fontSize = 14
            numLabel.fontColor = unlocked ? .white : .gray
            numLabel.position = CGPoint(x: -card.size.width / 2 + 20, y: 6)
            numLabel.horizontalAlignmentMode = .left
            numLabel.verticalAlignmentMode = .center
            numLabel.name = card.name
            card.addChild(numLabel)

            // Level name
            let nameLabel = SKLabelNode(fontNamed: Constants.GameBalance.hudFontName)
            nameLabel.text = unlocked ? level.name : "???"
            nameLabel.fontSize = 12
            nameLabel.fontColor = unlocked ? .white : .gray
            nameLabel.position = CGPoint(x: -card.size.width / 2 + 44, y: 6)
            nameLabel.horizontalAlignmentMode = .left
            nameLabel.verticalAlignmentMode = .center
            nameLabel.name = card.name
            card.addChild(nameLabel)

            // Subtitle
            let subLabel = SKLabelNode(fontNamed: Constants.GameBalance.hudFontName)
            subLabel.text = unlocked ? level.subtitle : ""
            subLabel.fontSize = 9
            subLabel.fontColor = UIColor.white.withAlphaComponent(0.5)
            subLabel.position = CGPoint(x: -card.size.width / 2 + 44, y: -8)
            subLabel.horizontalAlignmentMode = .left
            subLabel.verticalAlignmentMode = .center
            card.addChild(subLabel)

            // Stars
            if completed {
                let starsText = String(repeating: "\u{2605}", count: stars) + String(repeating: "\u{2606}", count: 3 - stars)
                let starsLabel = SKLabelNode(fontNamed: Constants.GameBalance.hudFontName)
                starsLabel.text = starsText
                starsLabel.fontSize = 14
                starsLabel.fontColor = .systemYellow
                starsLabel.position = CGPoint(x: card.size.width / 2 - 40, y: 0)
                starsLabel.verticalAlignmentMode = .center
                starsLabel.name = card.name
                card.addChild(starsLabel)
            } else if !unlocked {
                let lockLabel = SKLabelNode(fontNamed: Constants.GameBalance.hudFontName)
                lockLabel.text = "LOCKED"
                lockLabel.fontSize = 10
                lockLabel.fontColor = .gray
                lockLabel.position = CGPoint(x: card.size.width / 2 - 40, y: 0)
                lockLabel.verticalAlignmentMode = .center
                card.addChild(lockLabel)
            }
        }

        // Back button
        let backBtn = SKSpriteNode(color: .systemRed, size: CGSize(width: 120, height: 40))
        backBtn.position = CGPoint(x: frame.midX, y: startY - CGFloat(levels.count) * (cardHeight + spacing) - 20)
        backBtn.name = "levelSelectBack"
        overlay.addChild(backBtn)

        let backLabel = SKLabelNode(fontNamed: Constants.GameBalance.hudFontName)
        backLabel.text = "BACK"
        backLabel.fontSize = 16
        backLabel.fontColor = .white
        backLabel.verticalAlignmentMode = .center
        backLabel.name = "levelSelectBack"
        backBtn.addChild(backLabel)
    }

    func startGame() {
        enumerateChildNodes(withName: "//mainMenuOverlay") { node, _ in
            node.removeFromParent()
        }
        enumerateChildNodes(withName: "//levelSelectOverlay") { node, _ in
            node.removeFromParent()
        }

        currentPhase = .build
        score = 0
        dronesDestroyed = 0
        elapsedGameplayTime = 0
        fireControl.reset()

        // Reset game stats for recap
        gameWaveResults.removeAll()
        gameTotalKillsByType.removeAll()
        gameTotalLeakedByType.removeAll()

        // Force-remove night overlay (may still be fading from previous game)
        isNightWave = false
        nightOverlay?.removeAllActions()
        nightOverlay?.removeFromParent()
        nightOverlay = nil
        for (_, dot) in radarNightDots { dot.removeFromParent() }
        radarNightDots.removeAll()

        lives = Constants.TowerDefense.hqLives

        // Reload grid with selected level
        gridMap.loadLevel(selectedLevel)

        // Generate and place settlements
        settlementManager?.removeAll()
        settlementManager = SettlementManager(scene: self)
        if let gridLayer {
            settlementManager?.generateAndPlace(
                on: gridMap,
                gridLayer: gridLayer,
                count: selectedLevel.settlementCount
            )
        }

        economyManager.reset(to: selectedLevel.startingResources)
        waveManager = WaveManager(scene: self, level: selectedLevel)
        towerPlacement.removeAllTowers()
        militaryAidManager.reset()
        synergyManager.reset()

        // Remove any lingering aid overlay
        enumerateChildNodes(withName: "//militaryAidOverlay") { node, _ in
            node.removeFromParent()
        }

        // Clear any existing drones
        for drone in activeDrones {
            removeEntity(drone)
        }
        activeDrones.removeAll()
        activeRockets.removeAll()

        hudNode?.isHidden = false
        conveyorBelt.setSlotCount(selectedLevel.conveyorSlotCount)
        conveyorBelt.setAvailableTowers(selectedLevel.availableTowers)
        conveyorBelt.setGuaranteedTowers(selectedLevel.guaranteedTowers)
        conveyorBelt.setup(in: self, safeBottom: safeBottom)
        startWaveButton?.isHidden = false
        speedButton?.isHidden = false
        settingsButton?.isHidden = false

        // Setup ability buttons
        abilityManager.removeButtons()
        abilityManager.setup(in: self)

        gameSpeed = 1.0
        speedLabel?.text = "\u{25B6}"
        self.speed = gameSpeed
        physicsWorld.speed = gameSpeed

        interWaveCountdown = firstWaveCountdown
        updateStartWaveButton()

        // Show level name for campaign levels, then wave announcement
        if let levelId = selectedCampaignLevelId,
           let campaignLevel = CampaignManager.shared.levels.first(where: { $0.id == levelId }) {
            showLevelNameAnnouncement(name: campaignLevel.name) {
                self.showWaveAnnouncement(wave: self.waveManager.nextWaveNumber())
            }
        } else {
            showWaveAnnouncement(wave: waveManager.nextWaveNumber())
        }
        updateHUD()
    }

    func stopGame() {
        currentPhase = .mainMenu
        cleanupOffscreenIndicator()
        transitionToDay()

        for drone in activeDrones {
            removeEntity(drone)
        }
        activeDrones.removeAll()
        activeSwarmClouds.removeAll()

        let transientEntities = entities.filter { $0 is BulletEntity || $0 is MineBombEntity }
        for entity in transientEntities {
            removeEntity(entity)
        }
        activeRockets.removeAll()
        entityIdentifiers.removeAll()
        for entity in entities {
            entityIdentifiers.insert(ObjectIdentifier(entity))
        }

        towerPlacement.removeAllTowers()
        settlementManager?.removeAll()
        fireControl.reset()

        hudNode?.isHidden = true
        conveyorBelt.removeUI()
        startWaveButton?.isHidden = true
        speedButton?.isHidden = true
        settingsButton?.isHidden = true
        abilityManager.removeButtons()

        gameSpeed = 1.0
        speedLabel?.text = "\u{25B6}"
        self.speed = 1.0
        physicsWorld.speed = 1.0
    }

    func startCombatPhase() {
        currentPhase = .combat
        startWaveButton?.isHidden = true
        fireControl.reset()
        pendingMissileSpawns = 0
        pendingHarmSpawns = 0
        pendingShahedSpawns = 0

        // Reset wave stats
        let livesAtStart = lives
        waveKills = 0
        waveLeaked = 0
        waveKillsByType.removeAll()
        waveLeakedByType.removeAll()
        waveSettlementHits = 0
        waveTowerKills.removeAll()
        waveTotalSpawned = 0
        // Store lives at wave start to compute loss
        waveLivesAtStart = livesAtStart

        // Repair all towers and replenish magazines at wave start
        towerPlacement.towers.forEach {
            $0.fullRepair()
            $0.stats?.replenishMagazine()
        }

        waveManager.startNextWave()

        // Night wave transition
        if waveManager.isCurrentWaveNight {
            transitionToNight()
        } else {
            transitionToDay()
        }

        updateHUD()
        debugKillLogLines.removeAll()
        debugKillLogLabel?.removeFromParent()
        showDebugWaveInfo()
    }

    func onWaveComplete() {
        currentPhase = .build
        cleanupOffscreenIndicator()
        transitionToDay()
        activeSwarmClouds.removeAll()
        let waveBonus = Constants.TowerDefense.waveCompletionBonus
        let settlementIncome = settlementManager?.totalWaveIncome() ?? 0
        economyManager.earn(waveBonus + settlementIncome)

        // Record wave results for game over recap
        let livesLost = waveLivesAtStart - lives
        gameWaveResults.append((wave: waveManager.currentWave, kills: waveKills, leaked: waveLeaked, livesLost: livesLost))
        for (type, count) in waveKillsByType {
            gameTotalKillsByType[type, default: 0] += count
        }
        for (type, count) in waveLeakedByType {
            gameTotalLeakedByType[type, default: 0] += count
        }

        // Deactivate shield if it was active
        if militaryAidManager.isShieldActive {
            militaryAidManager.deactivateShield()
            enumerateChildNodes(withName: "//hqShield") { node, _ in
                node.run(SKAction.sequence([
                    SKAction.fadeOut(withDuration: 0.5),
                    SKAction.removeFromParent()
                ]))
            }
        }

        // Check campaign victory
        if waveManager.isCampaignComplete && selectedCampaignLevelId != nil {
            showCampaignVictory()
            return
        }

        interWaveCountdown = normalWaveCountdown
        startWaveButton?.isHidden = false
        updateStartWaveButton()

        showWaveAnnouncement(wave: waveManager.nextWaveNumber())
        updateHUD()
    }

    func showCampaignVictory() {
        currentPhase = .gameOver  // reuse gameOver phase for blocking input

        // Award stars
        if let levelId = selectedCampaignLevelId {
            CampaignManager.shared.completeLevel(levelId, remainingHP: lives, maxHP: Constants.TowerDefense.hqLives)
        }
        let stars = CampaignManager.shared.stars(for: selectedCampaignLevelId ?? "")
        let starsText = String(repeating: "\u{2605}", count: stars) + String(repeating: "\u{2606}", count: 3 - stars)

        let overlay = SKNode()
        overlay.name = "victoryOverlay"
        overlay.zPosition = 100
        addChild(overlay)

        let bg = SKSpriteNode(color: UIColor.black.withAlphaComponent(0.75), size: frame.size)
        bg.position = CGPoint(x: frame.midX, y: frame.midY)
        overlay.addChild(bg)

        let title = SKLabelNode(fontNamed: Constants.GameBalance.hudFontName)
        title.text = "ПОБЕДА!"
        title.fontSize = 40
        title.fontColor = .systemGreen
        title.position = CGPoint(x: frame.midX, y: frame.midY + 80)
        overlay.addChild(title)

        let starsLabel = SKLabelNode(fontNamed: Constants.GameBalance.hudFontName)
        starsLabel.text = starsText
        starsLabel.fontSize = 36
        starsLabel.fontColor = .systemYellow
        starsLabel.position = CGPoint(x: frame.midX, y: frame.midY + 30)
        overlay.addChild(starsLabel)

        let stats = [
            "Score: \(score)",
            "HP: \(lives)/\(Constants.TowerDefense.hqLives)",
            "Drones: \(dronesDestroyed)"
        ]
        for (i, text) in stats.enumerated() {
            let label = SKLabelNode(fontNamed: Constants.GameBalance.hudFontName)
            label.text = text
            label.fontSize = 18
            label.fontColor = .white
            label.position = CGPoint(x: frame.midX, y: frame.midY - 20 - CGFloat(i * 28))
            overlay.addChild(label)
        }

        // Next level button (only if there IS a next level)
        if let currentId = selectedCampaignLevelId,
           let currentIdx = CampaignManager.shared.levels.firstIndex(where: { $0.id == currentId }),
           currentIdx + 1 < CampaignManager.shared.levels.count {
            let nextBtn = SKSpriteNode(color: .systemGreen, size: CGSize(width: 180, height: 44))
            nextBtn.position = CGPoint(x: frame.midX, y: frame.midY - 110)
            nextBtn.name = "victoryNextButton"
            overlay.addChild(nextBtn)

            let nextLabel = SKLabelNode(fontNamed: Constants.GameBalance.hudFontName)
            nextLabel.text = "NEXT"
            nextLabel.fontSize = 18
            nextLabel.fontColor = .white
            nextLabel.verticalAlignmentMode = .center
            nextLabel.name = "victoryNextButton"
            nextBtn.addChild(nextLabel)
        }

        let menuBtn = SKSpriteNode(color: .systemBlue, size: CGSize(width: 180, height: 44))
        menuBtn.position = CGPoint(x: frame.midX, y: frame.midY - 165)
        menuBtn.name = "victoryMenuButton"
        overlay.addChild(menuBtn)

        let menuLabel = SKLabelNode(fontNamed: Constants.GameBalance.hudFontName)
        menuLabel.text = "CAMPAIGN"
        menuLabel.fontSize = 18
        menuLabel.fontColor = .white
        menuLabel.verticalAlignmentMode = .center
        menuLabel.name = "victoryMenuButton"
        menuBtn.addChild(menuLabel)
    }

    func updateStartWaveButton() {
        let bonus = Int(interWaveCountdown * 2)
        startWaveLabel?.text = bonus > 0 ? "EARLY START (+\(bonus) DP)" : "START WAVE"
    }

    func showLevelNameAnnouncement(name: String, completion: @escaping () -> Void) {
        let label = SKLabelNode(fontNamed: Constants.GameBalance.hudFontName)
        label.text = name
        label.fontSize = 30
        label.fontColor = .systemYellow
        label.position = CGPoint(x: frame.width / 2, y: frame.height / 2)
        label.zPosition = 96
        label.alpha = 0
        addChild(label)

        let fadeIn = SKAction.fadeIn(withDuration: 0.4)
        let wait = SKAction.wait(forDuration: 1.5)
        let fadeOut = SKAction.fadeOut(withDuration: 0.4)
        let remove = SKAction.removeFromParent()
        label.run(SKAction.sequence([fadeIn, wait, fadeOut, remove])) {
            completion()
        }
    }

    func showWaveAnnouncement(wave: Int) {
        let label = SKLabelNode(fontNamed: Constants.GameBalance.hudFontName)
        label.text = "Wave \(wave)"
        label.fontSize = 36
        label.fontColor = .white
        label.position = CGPoint(x: frame.width / 2, y: frame.height / 2)
        label.zPosition = 96
        label.alpha = 0
        addChild(label)

        let fadeIn = SKAction.fadeIn(withDuration: 0.3)
        let wait = SKAction.wait(forDuration: 1.0)
        let fadeOut = SKAction.fadeOut(withDuration: 0.3)
        let remove = SKAction.removeFromParent()
        label.run(SKAction.sequence([fadeIn, wait, fadeOut, remove]))
    }

    func toggleGameSpeed() {
        switch gameSpeed {
        case 1.0:  gameSpeed = 2.0
        case 2.0:  gameSpeed = 4.0
        default:   gameSpeed = 1.0
        }
        switch gameSpeed {
        case 2.0:  speedLabel?.text = "\u{25B6}\u{25B6}"
        case 4.0:  speedLabel?.text = "\u{25B6}\u{25B6}\u{25B6}"
        default:   speedLabel?.text = "\u{25B6}"
        }
        self.speed = gameSpeed
        physicsWorld.speed = gameSpeed
    }
}
