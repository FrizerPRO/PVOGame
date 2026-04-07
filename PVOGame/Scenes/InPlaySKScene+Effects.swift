//
//  InPlaySKScene+Effects.swift
//  PVOGame
//

import SpriteKit

extension InPlaySKScene {
    // MARK: - Screen Shake

    func screenShake(intensity: CGFloat = 4, duration: TimeInterval = 0.2) {
        guard childNode(withName: "//cameraShakeNode") == nil else { return }
        let shakeNode = SKNode()
        shakeNode.name = "cameraShakeNode"

        let steps = Int(duration / 0.02)
        var actions = [SKAction]()
        for i in 0..<steps {
            let decay = CGFloat(1.0 - Double(i) / Double(steps))
            let dx = CGFloat.random(in: -intensity...intensity) * decay
            let dy = CGFloat.random(in: -intensity...intensity) * decay
            actions.append(SKAction.moveBy(x: dx, y: dy, duration: 0.02))
        }
        actions.append(SKAction.move(to: .zero, duration: 0.02))

        // Move all children via a wrapper — avoid moving the scene itself
        let wrapper = childNode(withName: "//shakeWrapper")
        let target: SKNode = wrapper ?? self
        target.run(SKAction.sequence(actions), withKey: "cameraShake")
    }

    // MARK: - Kill Combo Display

    func showComboLabel(count: Int, at position: CGPoint) {
        comboLabel?.removeFromParent()

        let label = SKLabelNode(fontNamed: Constants.GameBalance.hudFontName)
        label.text = "x\(count)"
        label.fontSize = count >= 20 ? 28 : (count >= 10 ? 24 : 18)
        label.fontColor = count >= 20 ? .red : (count >= 10 ? .orange : .yellow)
        label.position = CGPoint(x: position.x, y: position.y + 20)
        label.zPosition = 96
        label.alpha = 1.0
        addChild(label)
        comboLabel = label

        label.run(SKAction.sequence([
            SKAction.group([
                SKAction.moveBy(x: 0, y: 30, duration: 0.6),
                SKAction.sequence([
                    SKAction.scale(to: 1.3, duration: 0.1),
                    SKAction.scale(to: 1.0, duration: 0.1)
                ]),
                SKAction.sequence([
                    SKAction.wait(forDuration: 0.4),
                    SKAction.fadeOut(withDuration: 0.2)
                ])
            ]),
            SKAction.removeFromParent()
        ]))
    }

    func updateComboTimer(deltaTime: TimeInterval) {
        guard comboTimer > 0 else { return }
        comboTimer -= deltaTime
        if comboTimer <= 0 {
            comboCount = 0
            comboTimer = 0
        }
    }

    // MARK: - Slow Motion

    func triggerSlowMo(duration: TimeInterval, speed slowSpeed: CGFloat) {
        guard slowMoTimer <= 0 else { return }
        normalSpeed = gameSpeed
        slowMoTimer = duration

        self.speed = slowSpeed
        physicsWorld.speed = slowSpeed
    }

    func updateSlowMo(deltaTime: TimeInterval) {
        guard slowMoTimer > 0 else { return }
        slowMoTimer -= deltaTime
        if slowMoTimer <= 0 {
            slowMoTimer = 0
            self.speed = gameSpeed
            physicsWorld.speed = gameSpeed
        }
    }

    // MARK: - Drone Wreckage

    func spawnWreckage(at position: CGPoint, rotation: CGFloat, size: CGSize) {
        let wreck = SKSpriteNode(color: UIColor(white: 0.2, alpha: 0.8), size: CGSize(width: size.width * 0.6, height: size.height * 0.6))
        wreck.position = position
        wreck.zRotation = rotation + CGFloat.random(in: -0.3...0.3)
        wreck.zPosition = 8 // just above ground
        wreck.alpha = 0.7
        addChild(wreck)

        // Fade out over 4 seconds
        wreck.run(SKAction.sequence([
            SKAction.wait(forDuration: 2.0),
            SKAction.fadeOut(withDuration: 2.0),
            SKAction.removeFromParent()
        ]))
    }

    // MARK: - Valley Speed Boost

    func applyValleySpeedBoost(deltaTime: TimeInterval) {
        guard let gridMap else { return }
        let boostFraction = Constants.TerrainZone.valleySpeedMultiplier - 1.0
        for drone in aliveDrones {
            guard let spriteNode = drone.component(ofType: SpriteComponent.self)?.spriteNode else { continue }
            guard let gridPos = gridMap.gridPosition(for: spriteNode.position) else { continue }
            guard let cell = gridMap.cell(atRow: gridPos.row, col: gridPos.col), cell.terrain == .valley else { continue }
            // Extra displacement in drone's heading direction
            let angle = spriteNode.zRotation + .pi / 2
            let extraSpeed: CGFloat = 50 * boostFraction // base push
            let extra = extraSpeed * CGFloat(deltaTime)
            spriteNode.position.x += cos(angle) * extra
            spriteNode.position.y += sin(angle) * extra
        }
    }

    // MARK: - Cleanup

    func cleanupDrones() {
        guard currentPhase == .combat else { return }
        let snapshot = activeDrones

        let hqThreshold = gridMap.origin.y + gridMap.cellSize.height

        for drone in snapshot {
            guard let droneNode = drone.component(ofType: SpriteComponent.self)?.spriteNode else {
                removeEntity(drone)
                continue
            }
            if droneNode.parent == nil {
                removeEntity(drone)
                continue
            }

            // Check if drone passes through its target settlement (settlement is a waypoint, not endpoint)
            if !drone.isHit, let target = drone.targetSettlement, !target.isDestroyed {
                let targetPos = target.worldPosition
                let dist = hypot(droneNode.position.x - targetPos.x,
                                 droneNode.position.y - targetPos.y)
                let hitRadius = gridMap.cellSize.width * 1.5
                if dist < hitRadius {
                    onDroneReachedSettlement(drone: drone, settlement: target)
                    // Kamikaze-type enemies self-destruct on impact with settlement
                    if drone is ShahedDroneEntity
                        || drone is KamikazeDroneEntity
                        || drone is LancetDroneEntity
                        || drone is EnemyMissileEntity
                        || drone is HarmMissileEntity
                        || drone is CruiseMissileEntity {
                        drone.didHit()
                        removeEntity(drone)
                        continue
                    }
                    // Non-kamikaze drones: clear target, continue flying to HQ
                    drone.targetSettlement = nil
                }
            }

            // HARM missiles that pass their target just miss — no HQ damage
            if let harm = drone as? HarmMissileEntity, !drone.isHit, droneNode.position.y < hqThreshold {
                harm.reachedDestination()
                removeEntity(drone)
                continue
            }

            // Check if drone reached HQ area (bottom of map)
            if !drone.isHit && droneNode.position.y < hqThreshold {
                onDroneReachedHQ(drone: drone)
                drone.reachedDestination()
                removeEntity(drone)
                continue
            }

            // Remove drones that went far off screen (ghost cleanup)
            // Only drones that exit below or to the sides count as reaching HQ.
            // Drones above the screen are still approaching — never count as HQ damage.
            if droneNode.position.y < -50 || droneNode.position.x < -100 || droneNode.position.x > frame.width + 100 {
                let noDamageTypes: Bool = drone is HarmMissileEntity || drone is EWDroneEntity
                if !drone.isHit && !noDamageTypes { onDroneReachedHQ(drone: drone) }
                removeEntity(drone)
                continue
            }
            if droneNode.position.y > frame.height + 300 {
                // Far above screen — silently remove without HQ damage
                removeEntity(drone)
                continue
            }

            // Update shadow in same pass (avoids separate iteration)
            if let shadow = drone.component(ofType: ShadowComponent.self),
               let altitude = drone.component(ofType: AltitudeComponent.self)?.altitude {
                shadow.updateShadow(dronePosition: droneNode.position, altitude: altitude)
            }
        }
    }

    func updateMineLayerOffscreenIndicator() {
        // Find first active mine layer that is off-screen
        let offscreenMiner = activeDrones.compactMap { $0 as? MineLayerDroneEntity }.first { miner in
            guard !miner.isHit,
                  let pos = miner.component(ofType: SpriteComponent.self)?.spriteNode.position
            else { return false }
            return pos.x < 0 || pos.x > frame.width
        }

        guard let miner = offscreenMiner,
              let dronePos = miner.component(ofType: SpriteComponent.self)?.spriteNode.position
        else {
            offscreenIndicator?.removeFromParent()
            offscreenIndicator = nil
            return
        }

        // Create indicator if needed
        if offscreenIndicator == nil {
            let node = SKNode()
            node.zPosition = 98

            let label = SKLabelNode(fontNamed: Constants.GameBalance.hudFontName)
            label.text = "!"
            label.fontSize = 20
            label.fontColor = .yellow
            label.verticalAlignmentMode = .center
            label.name = "offscreenLabel"
            node.addChild(label)

            // Triangle arrow
            let arrow = SKShapeNode()
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 0, y: 8))
            path.addLine(to: CGPoint(x: -6, y: -4))
            path.addLine(to: CGPoint(x: 6, y: -4))
            path.closeSubpath()
            arrow.path = path
            arrow.fillColor = .yellow
            arrow.strokeColor = .clear
            arrow.name = "offscreenArrow"
            arrow.position = CGPoint(x: 0, y: -16)
            node.addChild(arrow)

            // Pulse animation
            let scaleUp = SKAction.scale(to: 1.15, duration: 0.4)
            let scaleDown = SKAction.scale(to: 0.9, duration: 0.4)
            node.run(SKAction.repeatForever(SKAction.sequence([scaleUp, scaleDown])))

            addChild(node)
            offscreenIndicator = node
        }

        guard let indicator = offscreenIndicator else { return }

        // Position at screen edge, clamped Y
        let edgeMargin: CGFloat = 20
        let clampedY = min(max(dronePos.y, safeBottom + 30), frame.height - safeTop - 30)

        if dronePos.x < 0 {
            indicator.position = CGPoint(x: edgeMargin, y: clampedY)
            // Arrow points left
            if let arrow = indicator.childNode(withName: "offscreenArrow") {
                arrow.zRotation = .pi / 2
            }
        } else {
            indicator.position = CGPoint(x: frame.width - edgeMargin, y: clampedY)
            // Arrow points right
            if let arrow = indicator.childNode(withName: "offscreenArrow") {
                arrow.zRotation = -.pi / 2
            }
        }
    }

    func cleanupOffscreenIndicator() {
        offscreenIndicator?.removeFromParent()
        offscreenIndicator = nil
    }
}
