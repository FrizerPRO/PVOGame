//
//  InPlaySKScene+HUD.swift
//  PVOGame
//

import SpriteKit

extension InPlaySKScene {
    // MARK: - HUD

    func setupHUD() {
        let hud = SKNode()
        hud.zPosition = 95
        addChild(hud)
        hudNode = hud

        let fontSize = Constants.GameBalance.hudFontSize
        let fontName = Constants.GameBalance.hudFontName
        let yPos = frame.height - safeTop - 36

        let rLabel = SKLabelNode(fontNamed: fontName)
        rLabel.fontSize = fontSize
        rLabel.fontColor = .systemGreen
        rLabel.horizontalAlignmentMode = .left
        rLabel.position = CGPoint(x: 28, y: yPos)
        hud.addChild(rLabel)
        resourceLabel = rLabel

        let wLabel = SKLabelNode(fontNamed: fontName)
        wLabel.fontSize = fontSize
        wLabel.fontColor = .white
        wLabel.horizontalAlignmentMode = .center
        wLabel.position = CGPoint(x: frame.width / 2, y: yPos)
        hud.addChild(wLabel)
        waveLabel = wLabel

        let lLabel = SKLabelNode(fontNamed: fontName)
        lLabel.fontSize = fontSize
        lLabel.fontColor = .systemRed
        lLabel.horizontalAlignmentMode = .right
        lLabel.position = CGPoint(x: frame.width - 28, y: yPos)
        hud.addChild(lLabel)
        livesLabel = lLabel

        // Start Wave button
        let btnWidth: CGFloat = 240
        let btnHeight: CGFloat = 40
        let btn = SKSpriteNode(color: UIColor.systemGreen.withAlphaComponent(0.8), size: CGSize(width: btnWidth, height: btnHeight))
        btn.position = CGPoint(x: frame.width / 2, y: yPos - 40)
        btn.zPosition = 96
        btn.name = "startWaveButton"
        btn.isHidden = true
        addChild(btn)
        startWaveButton = btn

        let btnLabel = SKLabelNode(fontNamed: fontName)
        btnLabel.text = "START WAVE"
        btnLabel.fontSize = 16
        btnLabel.fontColor = .white
        btnLabel.verticalAlignmentMode = .center
        btnLabel.name = "startWaveButton"
        btn.addChild(btnLabel)
        startWaveLabel = btnLabel

        // Speed toggle button
        let speedBtnSize: CGFloat = 32
        let speedBtn = SKSpriteNode(color: UIColor.darkGray.withAlphaComponent(0.8), size: CGSize(width: speedBtnSize, height: speedBtnSize))
        speedBtn.position = CGPoint(x: frame.width - 40, y: yPos - 40)
        speedBtn.zPosition = 96
        speedBtn.name = "speedButton"
        speedBtn.isHidden = true
        addChild(speedBtn)
        speedButton = speedBtn

        let spdLabel = SKLabelNode(fontNamed: fontName)
        spdLabel.text = "\u{25B6}"
        spdLabel.fontSize = 14
        spdLabel.fontColor = .white
        spdLabel.verticalAlignmentMode = .center
        spdLabel.name = "speedButton"
        speedBtn.addChild(spdLabel)
        speedLabel = spdLabel
    }

    func updateHUD() {
        resourceLabel?.text = "DP: \(economyManager?.resources ?? 0)"
        waveLabel?.text = "Wave \(waveManager?.currentWave ?? 0)"
        livesLabel?.text = "HP: \(lives)"
    }

    // MARK: - Debug Wave Info

    func showDebugWaveInfo() {
        debugWaveInfoLabel?.removeFromParent()

        guard let waveDef = waveManager?.currentWaveDef else { return }

        var lines: [String] = []
        if waveDef.droneCount > 0 { lines.append("Shahed: \(waveDef.droneCount)") }
        if waveDef.shahedCount > 0 { lines.append("Shahed+: \(waveDef.shahedCount)") }
        if waveDef.kamikazeCount > 0 { lines.append("FPV: \(waveDef.kamikazeCount)") }
        if waveDef.mineLayerCount > 0 { lines.append("Bomber: \(waveDef.mineLayerCount)") }
        if waveDef.missileSalvoCount > 0 { lines.append("GRAD: \(waveDef.missileSalvoCount) salvo") }
        if waveDef.harmSalvoCount > 0 { lines.append("HARM: \(waveDef.harmSalvoCount) salvo") }
        if waveDef.cruiseMissileCount > 0 { lines.append("Cruise: \(waveDef.cruiseMissileCount)") }
        if waveDef.ewDroneCount > 0 { lines.append("EW: \(waveDef.ewDroneCount)") }
        if waveDef.heavyDroneCount > 0 { lines.append("Heavy: \(waveDef.heavyDroneCount)") }
        if waveDef.swarmCount > 0 { lines.append("Swarm: \(waveDef.swarmCount)") }
        if waveDef.lancetCount > 0 { lines.append("Lancet: \(waveDef.lancetCount)") }
        if waveDef.orlanCount > 0 { lines.append("Orlan: \(waveDef.orlanCount)") }
        if waveDef.isNight { lines.append("NIGHT") }

        let label = SKLabelNode(fontNamed: "Courier")
        label.numberOfLines = 0
        label.text = lines.joined(separator: "\n")
        label.fontSize = 10
        label.fontColor = .green
        label.horizontalAlignmentMode = .left
        label.verticalAlignmentMode = .top
        label.position = CGPoint(x: 8, y: frame.height - (safeTop + 85))
        label.zPosition = 200
        label.alpha = 0.8
        addChild(label)
        debugWaveInfoLabel = label

        // Removed on next wave start via debugWaveInfoLabel?.removeFromParent()
    }

    // MARK: - Debug Kill Log

    func logKill(weapon: String, enemy: String) {
        debugKillLogLines.append("\(weapon) → \(enemy)")
        if debugKillLogLines.count > 12 { debugKillLogLines.removeFirst() }
        updateDebugKillLog()
    }

    func logEnemyReachedTarget(enemy: String, target: String) {
        debugKillLogLines.append("⚠ \(enemy) → \(target)")
        if debugKillLogLines.count > 12 { debugKillLogLines.removeFirst() }
        updateDebugKillLog()
    }

    func updateDebugKillLog() {
        debugKillLogLabel?.removeFromParent()

        let label = SKLabelNode(fontNamed: "Courier")
        label.numberOfLines = 0
        label.text = debugKillLogLines.joined(separator: "\n")
        label.fontSize = 9
        label.fontColor = .yellow
        label.horizontalAlignmentMode = .right
        label.verticalAlignmentMode = .top
        label.position = CGPoint(x: frame.width - 8, y: frame.height - (safeTop + 85))
        label.zPosition = 200
        label.alpha = 0.85
        addChild(label)
        debugKillLogLabel = label
    }

    static func droneTypeName(_ drone: AttackDroneEntity) -> String {
        switch drone {
        case is ShahedDroneEntity: return "Shahed"
        case is OrlanDroneEntity: return "Orlan"
        case is KamikazeDroneEntity: return "FPV"
        case is EWDroneEntity: return "EW"
        case is HeavyDroneEntity: return "Heavy"
        case is LancetDroneEntity: return "Lancet"
        case is SwarmDroneEntity: return "Swarm"
        case is CruiseMissileEntity: return "Cruise"
        case is EnemyMissileEntity: return "GRAD"
        case is HarmMissileEntity: return "HARM"
        case is MineLayerDroneEntity: return "Bomber"
        default: return "Drone"
        }
    }

    static func shellTypeName(_ shell: Shell) -> String {
        if let rocket = shell as? RocketEntity {
            switch rocket.imageName {
            case let name where name.contains("sam"): return "S-300"
            case let name where name.contains("interceptor"): return "Patriot"
            case let name where name.contains("pzrk"): return "PZRK"
            default: return "Rocket"
            }
        }
        return "Gun"
    }

    // MARK: - Tower Palette

    func setupTowerPalette() {
        conveyorBelt.setup(in: self, safeBottom: safeBottom)
    }
}
