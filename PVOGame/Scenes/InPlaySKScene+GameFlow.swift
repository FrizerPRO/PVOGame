//
//  InPlaySKScene+GameFlow.swift
//  PVOGame
//

import SpriteKit
import simd

/// A transient bright circle on the night overlay. The overlay's fragment
/// shader reads up to `maxHoles` of these and knocks alpha to zero inside
/// each one, so the scene under the blast becomes visible for a moment.
struct NightHole {
    static let maxHoles = 8

    let position: CGPoint      // scene-space pixel position of the blast
    let radius: CGFloat        // falloff radius in scene-space pixels
    let spawnTime: TimeInterval
    let lifetime: TimeInterval

    /// Returns 0…1 strength at the given time: quick ramp-up, short hold,
    /// then fade-out over the rest of the lifetime.
    func strength(at now: TimeInterval) -> Float {
        let age = now - spawnTime
        if age < 0 { return 0 }
        if age >= lifetime { return 0 }
        let fadeIn: TimeInterval = 0.025
        let holdEnd: TimeInterval = fadeIn + Constants.Explosion.nightHoleHold
        if age < fadeIn { return Float(age / fadeIn) }
        if age < holdEnd { return 1.0 }
        let t = (age - holdEnd) / max(lifetime - holdEnd, 0.001)
        return Float(max(0.0, 1.0 - t))
    }
}

extension InPlaySKScene {
    // MARK: - Night Wave

    func transitionToNight() {
        guard !isNightWave else { return }
        isNightWave = true

        // Plain black overlay covering the whole scene. A fragment shader
        // discards pixels inside active "hole" circles so explosions can
        // reveal the ground, wreckage, towers and drones for a moment.
        let overlay = SKSpriteNode(color: .black, size: frame.size)
        overlay.position = CGPoint(x: frame.midX, y: frame.midY)
        overlay.alpha = 0
        overlay.zPosition = 90  // under HUD
        overlay.name = "nightOverlay"
        let shader = makeNightOverlayShader()
        overlay.shader = shader
        addChild(overlay)
        nightOverlay = overlay
        nightOverlayShader = shader
        nightHoles.removeAll()

        overlay.run(SKAction.fadeAlpha(to: Constants.NightWave.overlayAlpha, duration: Constants.NightWave.transitionDuration))

        // Block tower placement
        towerPlacement?.selectTowerType(nil)
        conveyorBelt.deselect()
        conveyorBelt.setNightMode(true)
    }

    func transitionToDay() {
        guard isNightWave else { return }
        isNightWave = false

        let overlay = nightOverlay
        nightOverlay = nil
        nightOverlayShader = nil
        nightHoles.removeAll()

        if let overlay = overlay {
            overlay.removeAllActions()
            overlay.run(SKAction.sequence([
                SKAction.fadeOut(withDuration: Constants.NightWave.transitionDuration),
                SKAction.removeFromParent()
            ]))
        }

        // Restore tower placement
        conveyorBelt.setNightMode(false)

        // Day = no radar blips. Clear so guns don't keep firing at last-known
        // night positions.
        nightBlips.removeAll()
    }

    // MARK: - Night Reveal Shader

    /// Builds the SKShader attached to the night overlay. The shader reads
    /// up to `NightHole.maxHoles` vec4 uniforms (`u_hole_0`…`u_hole_7`)
    /// encoded as `(uv_x, uv_y, uv_radius, strength)` in UV space 0…1
    /// across the sprite, and fades overlay alpha inside each hole. We
    /// avoid `u_sprite_size` (its units differ by backend/device) and
    /// avoid `SKDefaultShading()` (inconsistent for color-only sprites)
    /// in favor of explicit output and `v_color_mix` to honour the
    /// sprite's own alpha fade animation.
    func makeNightOverlayShader() -> SKShader {
        var body = """
        void main() {
            float maxHole = 0.0;
            vec4 h;
            vec2 delta;
            float d;
            float fall;
        """
        for i in 0..<NightHole.maxHoles {
            body += """

                h = u_hole_\(i);
                if (h.w > 0.0) {
                    delta = v_tex_coord - h.xy;
                    // Correct for sprite aspect ratio so the hole stays
                    // roughly circular on a portrait screen.
                    delta.y *= u_aspect;
                    d = length(delta);
                    fall = 1.0 - smoothstep(h.z * 0.35, h.z, d);
                    maxHole = max(maxHole, h.w * fall);
                }
            """
        }
        body += """

            float a = v_color_mix.a * (1.0 - clamp(maxHole, 0.0, 1.0));
            gl_FragColor = vec4(0.0, 0.0, 0.0, a);
        }
        """
        let shader = SKShader(source: body)
        var uniforms: [SKUniform] = (0..<NightHole.maxHoles).map { i in
            SKUniform(name: "u_hole_\(i)", vectorFloat4: SIMD4<Float>(0, 0, 0, 0))
        }
        let aspect: Float = Float(frame.height / max(frame.width, 1))
        uniforms.append(SKUniform(name: "u_aspect", float: aspect))
        shader.uniforms = uniforms
        return shader
    }

    /// Called every frame from the scene update loop. Drops expired holes
    /// and copies the currently active ones into the shader uniforms in
    /// UV space.
    func updateNightHoles(currentTime: TimeInterval) {
        guard isNightWave, let shader = nightOverlayShader else { return }

        // Drop expired holes.
        nightHoles.removeAll { currentTime - $0.spawnTime >= $0.lifetime }

        let width = max(frame.width, 1)
        let height = max(frame.height, 1)

        // Push up to maxHoles into the shader; zero out the rest.
        let active = nightHoles.suffix(NightHole.maxHoles)
        var idx = 0
        for hole in active {
            let strength = hole.strength(at: currentTime)
            shader.uniforms[idx].vectorFloat4Value = SIMD4<Float>(
                Float(hole.position.x / width),
                Float(hole.position.y / height),
                Float(hole.radius / width),
                strength
            )
            idx += 1
        }
        while idx < NightHole.maxHoles {
            shader.uniforms[idx].vectorFloat4Value = SIMD4<Float>(repeating: 0)
            idx += 1
        }
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

    // MARK: - Pre-placed Towers

    func placePrePlacedTowers() {
        guard let towerPlacement else { return }
        for def in selectedLevel.prePlacedTowers {
            let footprint = def.type.footprint
            guard gridMap.canPlaceTower(atRow: def.row, col: def.col, footprint: footprint) else { continue }
            let worldPos = gridMap.worldPosition(forRow: def.row, col: def.col, footprint: footprint)
            let tower = TowerEntity(towerType: def.type, at: (def.row, def.col), worldPosition: worldPos)
            if let cell = gridMap.cell(atRow: def.row, col: def.col),
               cell.terrain == .highGround,
               let stats = tower.component(ofType: TowerStatsComponent.self) {
                stats.range *= Constants.TerrainZone.highGroundRangeMultiplier
            }
            gridMap.placeTower(ObjectIdentifier(tower), atRow: def.row, col: def.col, footprint: footprint)
            if let spriteNode = tower.component(ofType: SpriteComponent.self)?.spriteNode {
                spriteNode.removeFromParent()
                addChild(spriteNode)
            }
            towerPlacement.towers.append(tower)
            entities.append(tower)
        }
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
        nightOverlayShader = nil
        nightHoles.removeAll()
        nightBlips.removeAll()

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
        conveyorBelt.instantMode = selectedLevel.instantConveyor
        conveyorBelt.setup(in: self, safeBottom: safeBottom)
        placePrePlacedTowers()
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
