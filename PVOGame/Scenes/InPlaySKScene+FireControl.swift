//
//  InPlaySKScene+FireControl.swift
//  PVOGame
//

import SpriteKit

extension InPlaySKScene {

    // MARK: - Fire Control (for rocket towers)

    func bestRocketTargetPoint(
        preferredPoint: CGPoint? = nil,
        origin: CGPoint? = nil,
        radius: CGFloat? = nil,
        influenceRadius: CGFloat? = nil,
        reservingActiveRocketImpacts: Bool = false,
        excludingRocket: RocketEntity? = nil,
        projectileSpeed: CGFloat? = nil,
        projectileAcceleration: CGFloat? = nil,
        projectileMaxSpeed: CGFloat? = nil
    ) -> CGPoint? {
        syncFireControlState()
        let spec = Constants.GameBalance.standardRocketSpec
        let profile = FireControlState.PlanningProfile(
            blastRadius: max(0, influenceRadius ?? spec.blastRadius),
            maxRange: radius,
            nominalSpeed: max(120, projectileSpeed ?? spec.initialSpeed),
            acceleration: projectileAcceleration ?? spec.acceleration,
            maxSpeed: projectileMaxSpeed ?? spec.maxSpeed
        )
        return fireControl.planLaunch(
            preferredPoint: preferredPoint,
            origin: origin,
            reservingAssignments: reservingActiveRocketImpacts,
            excludingRocketID: excludingRocket.map { ObjectIdentifier($0) },
            profile: profile
        )?.targetPoint
    }

    func updateRocketReservation(for rocket: RocketEntity, targetPoint: CGPoint? = nil) {
        syncFireControlState()
        let rocketID = ObjectIdentifier(rocket)
        let target = targetPoint ?? rocket.guidanceTargetPointForDisplay
        let launchOrigin = rocket.component(ofType: SpriteComponent.self)?.spriteNode.position
        fireControl.upsertAssignment(
            rocketID: rocketID,
            spec: rocket.spec,
            targetPoint: target,
            launchOrigin: launchOrigin,
            currentTime: elapsedGameplayTime
        )
    }

    func isDroneReservedByRocket(_ drone: AttackDroneEntity) -> Bool {
        syncFireControlState()
        return fireControl.isDroneReservedByRocket(ObjectIdentifier(drone))
    }

    func isDroneOverkilled(_ drone: AttackDroneEntity) -> Bool {
        syncFireControlState()
        return fireControl.isDroneOverkilled(ObjectIdentifier(drone))
    }

    /// Returns true and increments budget if a rocket is allowed to retarget this frame.
    func consumeRetargetBudget() -> Bool {
        guard rocketRetargetBudget < maxRetargetsPerFrame else { return false }
        rocketRetargetBudget += 1
        return true
    }

    func onRocketDetonated(_ rocket: RocketEntity, at position: CGPoint, blastRadius: CGFloat) {
        fireControl.lockAssignmentForImpact(
            rocketID: ObjectIdentifier(rocket),
            impactPoint: position,
            impactRadius: blastRadius,
            currentTime: elapsedGameplayTime,
            lockDuration: 0.25
        )
    }

    static let blastTexture: SKTexture = {
        let d: CGFloat = 64
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: d, height: d))
        let image = renderer.image { ctx in
            UIColor.white.setFill()
            ctx.cgContext.fillEllipse(in: CGRect(x: 0, y: 0, width: d, height: d))
        }
        return SKTexture(image: image)
    }()

    func spawnRocketBlast(at position: CGPoint, radius: CGFloat, damage: Int = 1) {
        // Physics blast node (detects drone contacts)
        let blast = SKSpriteNode(texture: Self.blastTexture)
        blast.size = CGSize(width: radius * 2, height: radius * 2)
        blast.name = "rocketBlastNode"
        blast.position = position
        blast.zPosition = isNightWave ? Constants.NightWave.nightEffectZPosition : 50
        blast.userData = ["damage": damage]
        blast.color = UIColor.orange.withAlphaComponent(0.35)
        blast.colorBlendFactor = 1.0
        blast.physicsBody = SKPhysicsBody(circleOfRadius: radius)
        blast.physicsBody?.isDynamic = false
        blast.physicsBody?.categoryBitMask = Constants.rocketBlastBitMask
        blast.physicsBody?.contactTestBitMask = Constants.droneBitMask
        blast.physicsBody?.collisionBitMask = 0
        addChild(blast)

        let scale = SKAction.scale(to: 1.2, duration: 0.1)
        let fade = SKAction.fadeOut(withDuration: 0.15)
        let remove = SKAction.removeFromParent()
        blast.run(SKAction.sequence([SKAction.group([scale, fade]), remove]))

        // Visual explosion animation overlay sized to the blast radius so the
        // fireball actually reads — previously hardcoded 32pt was invisible.
        let frames = AnimationTextureCache.shared.mediumExplosion
        if !frames.isEmpty {
            let diameter = max(radius * 2.5, 60)
            let node = acquireExplosionNode()
            node.texture = frames[0]
            node.size = CGSize(width: diameter, height: diameter)
            node.color = .white
            node.colorBlendFactor = 0
            node.position = position
            node.zPosition = (isNightWave ? Constants.NightWave.nightEffectZPosition : 50) + 1
            node.alpha = 1.0
            node.setScale(1.0)
            addChild(node)
            // Same per-frame timing as spawnKillExplosion: quick flash on f1,
            // linger on f2/f3, faster settle. Keeping the two paths aligned
            // matters because a rocket hitting a drone fires BOTH: this
            // midair-blast animation AND the drone's kill explosion — if
            // their cadences differ the combined effect looks off-beat.
            let flashHold: TimeInterval  = 0.035
            let peakHold: TimeInterval   = 0.10
            let settleHold: TimeInterval = 0.04
            var actions: [SKAction] = []
            for (idx, tex) in frames.enumerated() {
                let hold: TimeInterval
                switch idx {
                case 0:    hold = flashHold
                case 1, 2: hold = peakHold
                default:   hold = settleHold
                }
                actions.append(SKAction.setTexture(tex))
                actions.append(SKAction.wait(forDuration: hold))
            }
            actions.append(SKAction.run { [weak self, weak node] in
                guard let self, let node else { return }
                self.releaseExplosionNode(node)
            })
            node.run(SKAction.sequence(actions))
        }
    }

    /// Rebuild per-frame caches from activeDrones in a single pass.
    func rebuildFrameCaches() {
        aliveDrones.removeAll(keepingCapacity: true)
        aliveNonMineLayerDrones.removeAll(keepingCapacity: true)
        aliveMissileCount = 0
        jammedTowerIDs.removeAll(keepingCapacity: true)

        // Collect active EW drone positions for jamming calculation
        var ewDronePositions = [(EWDroneEntity, CGPoint)]()

        for drone in activeDrones where !drone.isHit {
            aliveDrones.append(drone)
            if !(drone is MineLayerDroneEntity) {
                aliveNonMineLayerDrones.append(drone)
            }
            if drone is EnemyMissileEntity || drone is HarmMissileEntity {
                aliveMissileCount += 1
            }
            if let ewDrone = drone as? EWDroneEntity,
               let pos = ewDrone.component(ofType: SpriteComponent.self)?.spriteNode.position {
                ewDronePositions.append((ewDrone, pos))
            }
        }

        // Cache missile alert
        if waveManager?.missileWarningShown ?? false || waveManager?.harmWarningShown ?? false {
            cachedMissileAlertActive = true
        } else {
            cachedMissileAlertActive = aliveDrones.contains(where: { drone in
                guard (drone is EnemyMissileEntity || drone is HarmMissileEntity) else { return false }
                guard let pos = drone.component(ofType: SpriteComponent.self)?.spriteNode.position else { return false }
                return pos.y > -50 && pos.y < frame.height + 100
            })
        }

        // Cache active radar positions (only on night waves)
        activeRadars.removeAll(keepingCapacity: true)
        if isNightWave, let towerPlacement {
            for tower in towerPlacement.towers {
                guard let stats = tower.stats, stats.towerType == .radar, !stats.isDisabled else { continue }
                activeRadars.append((tower.worldPosition, stats.range * stats.range))
            }
        }

        // Cache EW jamming
        if !ewDronePositions.isEmpty, let towerPlacement {
            for tower in towerPlacement.towers {
                let towerPos = tower.worldPosition
                for (ewDrone, _) in ewDronePositions {
                    if ewDrone.isJamming(towerAt: towerPos) {
                        jammedTowerIDs.insert(ObjectIdentifier(tower))
                        break
                    }
                }
            }
        }

        // Cache Orlan-spotted towers and apply speed boost
        orlanSpottedTowers.removeAll(keepingCapacity: true)
        for drone in activeDrones where !drone.isHit {
            if let orlan = drone as? OrlanDroneEntity,
               let info = orlan.spottedTowerInfo {
                orlanSpottedTowers.append(info)
            }
        }

        if !orlanSpottedTowers.isEmpty {
            let boostRadiusSq = Constants.Orlan.boostRadius * Constants.Orlan.boostRadius
            for drone in aliveDrones {
                guard !(drone is OrlanDroneEntity), !(drone is EWDroneEntity) else { continue }
                guard let flight = drone.component(ofType: FlyingProjectileComponent.self),
                      let pos = drone.component(ofType: SpriteComponent.self)?.spriteNode.position else { continue }
                let nearSpotted = orlanSpottedTowers.contains { info in
                    let dx = pos.x - info.position.x
                    let dy = pos.y - info.position.y
                    return dx * dx + dy * dy <= boostRadiusSq
                }
                flight.maxSpeed = nearSpotted
                    ? Float(drone.speed * Constants.Orlan.speedBoostMultiplier)
                    : Float(drone.speed)
            }
        } else {
            // No Orlan spotting — ensure all drones at normal speed
            for drone in aliveDrones {
                guard let flight = drone.component(ofType: FlyingProjectileComponent.self) else { continue }
                flight.maxSpeed = Float(drone.speed)
            }
        }
    }

    // MARK: - Node Pools

    func acquireTracer() -> SKSpriteNode {
        if let tracer = tracerPool.popLast() {
            tracer.alpha = 1.0
            tracer.isHidden = false
            tracer.removeAllActions()
            return tracer
        }
        return SKSpriteNode(texture: TowerTargetingComponent.poolTracerTexture)
    }

    func releaseTracer(_ tracer: SKSpriteNode) {
        tracer.removeFromParent()
        if tracerPool.count < nodePoolCapacity {
            tracerPool.append(tracer)
        }
    }

    func acquireSmokePuff() -> SKSpriteNode {
        if let puff = smokePuffPool.popLast() {
            puff.alpha = 1.0
            puff.isHidden = false
            puff.setScale(1.0)
            puff.removeAllActions()
            return puff
        }
        let tex = AnimationTextureCache.shared.smokePuff ?? Self.sharedSmokePuffTexture
        return SKSpriteNode(texture: tex)
    }

    func releaseSmokePuff(_ puff: SKSpriteNode) {
        puff.removeFromParent()
        if smokePuffPool.count < nodePoolCapacity {
            smokePuffPool.append(puff)
        }
    }

    func acquireExplosionNode() -> SKSpriteNode {
        if let node = explosionPool.popLast() {
            node.alpha = 1.0
            node.isHidden = false
            node.setScale(1.0)
            node.removeAllActions()
            return node
        }
        return SKSpriteNode()
    }

    func releaseExplosionNode(_ node: SKSpriteNode) {
        node.removeFromParent()
        if explosionPool.count < nodePoolCapacity {
            explosionPool.append(node)
        }
    }

    static let sharedSmokePuffTexture: SKTexture = {
        let size: CGFloat = 18
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        let image = renderer.image { ctx in
            let rect = CGRect(x: 0, y: 0, width: size, height: size)
            ctx.cgContext.setFillColor(UIColor.white.cgColor)
            ctx.cgContext.fillEllipse(in: rect)
        }
        return SKTexture(image: image)
    }()

    func nearestAliveDrone(to point: CGPoint, maxDistance: CGFloat = 72) -> AttackDroneEntity? {
        var best: AttackDroneEntity?
        var bestDistSq: CGFloat = maxDistance * maxDistance
        for drone in aliveDrones {
            guard let pos = drone.component(ofType: SpriteComponent.self)?.spriteNode.position else { continue }
            let dx = pos.x - point.x
            let dy = pos.y - point.y
            let distSq = dx * dx + dy * dy
            if distSq < bestDistSq {
                bestDistSq = distSq
                best = drone
            }
        }
        return best
    }

    func syncFireControlState() {
        guard !fireControlSyncedThisFrame else { return }
        fireControlSyncedThisFrame = true
        let rocketsInFlightIDs = Set(activeRockets.map { ObjectIdentifier($0) })
        fireControl.syncAssignments(
            withActiveRocketIDs: rocketsInFlightIDs,
            currentTime: elapsedGameplayTime
        )
        fireControl.syncTracks(
            with: aliveNonMineLayerDrones,
            currentTime: elapsedGameplayTime,
            sceneHeight: frame.height
        )
    }
}
