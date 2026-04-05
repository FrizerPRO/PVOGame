//
//  InPlaySKScene+DroneSpawning.swift
//  PVOGame
//

import SpriteKit
import GameplayKit

extension InPlaySKScene {

    // MARK: - Drone Spawning

    // TODO: AttackDroneEntity temporarily replaced by ShahedDroneEntity for all regular waves.
    // Restore AttackDroneEntity here once it gets a distinct gameplay role.
    func spawnDrone(flightPath: DroneFlightPath, altitude: DroneAltitude, targetSettlement: SettlementEntity? = nil) {
        let flyingPath = flightPath.toFlyingPath()
        let drone = ShahedDroneEntity.create(flyingPath: flyingPath)
        drone.targetSettlement = targetSettlement

        // Add altitude component
        drone.addComponent(AltitudeComponent(altitude: altitude))

        // Add shadow component
        let shadow = ShadowComponent()
        drone.addComponent(shadow)
        shadowLayer?.addChild(shadow.shadowNode)

        // Scale drone based on altitude
        if let spriteNode = drone.component(ofType: SpriteComponent.self)?.spriteNode {
            let baseSize: CGFloat = Constants.SpriteSize.shahed
            let scale = altitude.droneVisualScale
            spriteNode.size = CGSize(width: baseSize * scale, height: baseSize * scale)
            spriteNode.zPosition = 61 + CGFloat(altitude.rawValue) * 5
        }

        activeDrones.append(drone)
        addEntity(drone)
    }

    // MARK: - Shahed-136 Spawn

    func spawnShahed() {
        guard let gridMap else { return }

        // Assign target settlement
        let target = settlementManager?.assignTarget(
            towers: towerPlacement?.towers ?? []
        )

        // HQ is always the final destination
        let hqRow = Constants.TowerDefense.gridRows - 1
        let hqCol = Constants.TowerDefense.gridCols / 2
        let hqPoint = gridMap.worldPosition(forRow: hqRow, col: hqCol)

        // Random spawn from top
        let spawnPoint = CGPoint(
            x: CGFloat.random(in: 20...(frame.width - 20)),
            y: frame.height + CGFloat.random(in: 20...50)
        )

        // Path: spawn → through settlement → HQ
        let waypoints: [CGPoint]
        if let target {
            waypoints = generateSettlementPath(from: spawnPoint, through: target.worldPosition, to: hqPoint)
        } else {
            waypoints = generateSettlementPath(from: spawnPoint, to: hqPoint)
        }

        let altitude: DroneAltitude = .low
        let flightPath = DroneFlightPath(waypoints: waypoints, altitude: altitude, spawnEdge: .top)
        let flyingPath = flightPath.toFlyingPath()
        let drone = ShahedDroneEntity.create(flyingPath: flyingPath)
        drone.targetSettlement = target

        drone.addComponent(AltitudeComponent(altitude: altitude))
        let shadow = ShadowComponent()
        drone.addComponent(shadow)
        shadowLayer?.addChild(shadow.shadowNode)

        if let spriteNode = drone.component(ofType: SpriteComponent.self)?.spriteNode {
            spriteNode.zPosition = 61 + CGFloat(altitude.rawValue) * 5
        }

        activeDrones.append(drone)
        addEntity(drone)
        pendingShahedSpawns -= 1
    }

    // MARK: - Shahed Formation Spawning

    func spawnShahedFormation(count: Int, formation: ShahedFormation) {
        guard let gridMap else { return }

        let hqRow = Constants.TowerDefense.gridRows - 1
        let hqCol = Constants.TowerDefense.gridCols / 2
        let hqPoint = gridMap.worldPosition(forRow: hqRow, col: hqCol)

        // Formation center — keep away from edges so wings fit
        // centerY must stay below frame.height + 100 even with max offsets (ghost cleanup threshold)
        let centerX = CGFloat.random(in: 60...(frame.width - 60))
        let centerY = frame.height + 20
        let leaderSpawn = CGPoint(x: centerX, y: centerY)

        let offsets = shahedFormationOffsets(for: formation, count: count)

        // Shared target for the entire formation
        let target = settlementManager?.assignTarget(
            towers: towerPlacement?.towers ?? []
        )

        // Generate ONE reference path (leader) — shared jitter for all drones
        let referencePath: [CGPoint]
        if let target {
            referencePath = generateSettlementPath(from: leaderSpawn, through: target.worldPosition, to: hqPoint)
        } else {
            referencePath = generateSettlementPath(from: leaderSpawn, to: hqPoint)
        }

        let wpCount = referencePath.count

        pendingShahedSpawns += offsets.count

        for (i, offset) in offsets.enumerated() {
            // Apply formation offset to each waypoint, fading toward HQ
            // Add small per-drone jitter to intermediate waypoints for organic feel
            var waypoints = [CGPoint]()
            for (wpIdx, wp) in referencePath.enumerated() {
                let progress = CGFloat(wpIdx) / CGFloat(max(wpCount - 1, 1))
                let fade = min(1.0, max(0, (1.0 - progress) / 0.3))
                let isEdge = wpIdx == 0 || wpIdx == wpCount - 1
                let jitterX = isEdge ? CGFloat(0) : CGFloat.random(in: -6...6)
                let jitterY = isEdge ? CGFloat(0) : CGFloat.random(in: -4...4)
                waypoints.append(CGPoint(
                    x: min(max(wp.x + offset.x * fade + jitterX, 10), frame.width - 10),
                    y: wp.y + offset.y * fade + jitterY
                ))
            }
            // Final waypoint: always exact HQ, no offset
            waypoints[wpCount - 1] = hqPoint

            let altitude: DroneAltitude = .low
            let flightPath = DroneFlightPath(waypoints: waypoints, altitude: altitude, spawnEdge: .top)
            let flyingPath = flightPath.toFlyingPath()

            // Build CGPath for SKAction-based deterministic movement
            let cgPath = CGMutablePath()
            cgPath.move(to: waypoints[0])
            for wpIdx in 1..<waypoints.count {
                cgPath.addLine(to: waypoints[wpIdx])
            }

            let capturedPath = flyingPath
            let capturedCGPath = cgPath
            let capturedTarget = target
            let capturedWaypoints = waypoints
            let capturedSpeed = Constants.Shahed.speed

            run(SKAction.sequence([
                SKAction.wait(forDuration: TimeInterval(i) * Constants.Shahed.formationStagger),
                SKAction.run { [weak self] in
                    guard let self else { return }
                    let drone = ShahedDroneEntity.create(flyingPath: capturedPath)
                    drone.targetSettlement = capturedTarget
                    drone.isFormationFlight = true

                    // Disable GKAgent steering — SKAction drives position
                    if let flight = drone.component(ofType: FlyingProjectileComponent.self) {
                        flight.behavior = GKBehavior()
                        flight.maxSpeed = 0
                    }

                    drone.addComponent(AltitudeComponent(altitude: altitude))
                    let shadow = ShadowComponent()
                    drone.addComponent(shadow)
                    self.shadowLayer?.addChild(shadow.shadowNode)

                    if let spriteNode = drone.component(ofType: SpriteComponent.self)?.spriteNode {
                        spriteNode.zPosition = 61 + CGFloat(altitude.rawValue) * 5
                        spriteNode.position = capturedWaypoints[0]

                        // Initial rotation: face from wp[0] toward wp[1]
                        if capturedWaypoints.count >= 2 {
                            let dx = capturedWaypoints[1].x - capturedWaypoints[0].x
                            let dy = capturedWaypoints[1].y - capturedWaypoints[0].y
                            spriteNode.zRotation = atan2(dy, dx) - .pi / 2
                        }

                        // Deterministic path follow with per-drone speed
                        let followAction = SKAction.follow(
                            capturedCGPath,
                            asOffset: false,
                            orientToPath: false,
                            speed: capturedSpeed
                        )

                        // Track movement direction for rotation
                        var lastPos = capturedWaypoints[0]
                        let rotateAction = SKAction.customAction(withDuration: followAction.duration) { node, _ in
                            let dx = node.position.x - lastPos.x
                            let dy = node.position.y - lastPos.y
                            if dx * dx + dy * dy > 0.5 {
                                node.zRotation = atan2(dy, dx) - .pi / 2
                                lastPos = node.position
                            }
                        }

                        spriteNode.run(SKAction.group([followAction, rotateAction]))
                    }

                    self.activeDrones.append(drone)
                    self.addEntity(drone)
                    self.pendingShahedSpawns -= 1
                }
            ]))
        }
    }

    // MARK: - Shahed Formation Offset Calculators

    func shahedFormationOffsets(for formation: ShahedFormation, count: Int) -> [CGPoint] {
        switch formation {
        case .scattered:
            return (0..<count).map { _ in
                CGPoint(x: CGFloat.random(in: -80...80), y: CGFloat.random(in: -30...30))
            }
        case .chevron:
            return chevronOffsets(count: count)
        case .triangle:
            return triangleOffsets(count: count)
        case .tripleTriangle:
            return tripleTriangleOffsets(count: count)
        }
    }

    /// V-shape: leader at tip (front), wings extend back and outward
    /// Y positive = further above screen = behind leader when flying down
    func chevronOffsets(count: Int) -> [CGPoint] {
        let spacing = Constants.Shahed.formationSpacing
        var offsets = [CGPoint]()
        offsets.append(.zero) // leader at tip
        let maxDepth = CGFloat(count / 2)
        // Fit wings within screen width (±160 from center)
        let adaptiveSpacing = maxDepth > 0 ? min(spacing, 160 / maxDepth) : spacing
        for i in 1..<count {
            let depth = CGFloat((i + 1) / 2)
            let side: CGFloat = i % 2 == 0 ? -1 : 1
            offsets.append(CGPoint(
                x: side * depth * adaptiveSpacing,
                y: depth * adaptiveSpacing * 0.35  // shallow depth — V visible quickly
            ))
        }
        return offsets
    }

    /// Filled triangle: row 0 = 1 drone (tip), row 1 = 2, row 2 = 3, etc.
    func triangleOffsets(count: Int) -> [CGPoint] {
        let spacing = Constants.Shahed.formationSpacing
        var offsets = [CGPoint]()
        var placed = 0
        var row = 0
        while placed < count {
            let dronesInRow = row + 1
            let toPlace = min(dronesInRow, count - placed)
            let rowWidth = CGFloat(toPlace - 1) * spacing
            for col in 0..<toPlace {
                let x = -rowWidth / 2 + CGFloat(col) * spacing
                let y = CGFloat(row) * spacing * 0.4  // compact Y to stay within ghost cleanup threshold
                offsets.append(CGPoint(x: x, y: y))
                placed += 1
            }
            row += 1
        }
        return offsets
    }

    /// Three triangles: center, left, right
    func tripleTriangleOffsets(count: Int) -> [CGPoint] {
        let spacing = Constants.Shahed.formationSpacing
        let centerCount = count / 3 + count % 3
        let sideCount = count / 3

        var offsets = [CGPoint]()

        // Center triangle
        let center = triangleOffsets(count: centerCount)
        offsets.append(contentsOf: center)

        // Left triangle — offset left and slightly back
        let lateralOffset: CGFloat = min(120, frame.width * 0.28)
        let backOffset = spacing * 0.4  // small Y offset, stays within threshold
        let left = triangleOffsets(count: sideCount)
        for pt in left {
            offsets.append(CGPoint(x: pt.x - lateralOffset, y: pt.y + backOffset))
        }

        // Right triangle — offset right and slightly back
        let right = triangleOffsets(count: sideCount)
        for pt in right {
            offsets.append(CGPoint(x: pt.x + lateralOffset, y: pt.y + backOffset))
        }

        return offsets
    }

    // MARK: - Settlement Path Helpers

    /// Path: spawn → jitter → through settlement → jitter → HQ
    func generateSettlementPath(from start: CGPoint, through mid: CGPoint, to end: CGPoint) -> [CGPoint] {
        var points = [start]

        // 2 jitter waypoints: spawn → settlement
        for i in 1...2 {
            let t = CGFloat(i) / 3.0
            points.append(CGPoint(
                x: start.x + (mid.x - start.x) * t + CGFloat.random(in: -20...20),
                y: start.y + (mid.y - start.y) * t + CGFloat.random(in: -10...10)
            ))
        }

        // Settlement waypoint
        points.append(mid)

        // 2 jitter waypoints: settlement → HQ
        for i in 1...2 {
            let t = CGFloat(i) / 3.0
            points.append(CGPoint(
                x: mid.x + (end.x - mid.x) * t + CGFloat.random(in: -15...15),
                y: mid.y + (end.y - mid.y) * t + CGFloat.random(in: -8...8)
            ))
        }

        // HQ endpoint
        points.append(CGPoint(x: end.x + CGFloat.random(in: -5...5), y: end.y))
        return points
    }

    /// Direct path: spawn → jitter → HQ (no settlement target)
    func generateSettlementPath(from start: CGPoint, to end: CGPoint) -> [CGPoint] {
        var points = [start]
        for i in 1...3 {
            let t = CGFloat(i) / 4.0
            points.append(CGPoint(
                x: start.x + (end.x - start.x) * t + CGFloat.random(in: -15...15),
                y: start.y + (end.y - start.y) * t + CGFloat.random(in: -8...8)
            ))
        }
        points.append(CGPoint(x: end.x + CGFloat.random(in: -5...5), y: end.y))
        return points
    }

    // MARK: - Lancet Spawn

    func spawnLancet() {
        let spawnX = CGFloat.random(in: 40...(frame.width - 40))
        let spawnY = frame.height + CGFloat.random(in: 20...50)
        let spawnPoint = CGPoint(x: spawnX, y: spawnY)

        // Loiter above the tower cluster (mid-screen)
        let loiterY = frame.height * 0.55 + CGFloat.random(in: -40...40)
        let loiterX = CGFloat.random(in: 60...(frame.width - 60))
        let loiterCenter = CGPoint(x: loiterX, y: loiterY)

        let lancet = LancetDroneEntity(sceneFrame: frame, scene: self)

        let altitude: DroneAltitude = .medium
        lancet.addComponent(AltitudeComponent(altitude: altitude))
        let shadow = ShadowComponent()
        lancet.addComponent(shadow)
        shadowLayer?.addChild(shadow.shadowNode)

        if let spriteNode = lancet.component(ofType: SpriteComponent.self)?.spriteNode {
            let scale = altitude.droneVisualScale
            spriteNode.size = CGSize(width: 14 * scale, height: 16 * scale)
            spriteNode.zPosition = 61 + CGFloat(altitude.rawValue) * 5
        }

        lancet.configureFlight(from: spawnPoint, loiterAt: loiterCenter)

        activeDrones.append(lancet)
        addEntity(lancet)
    }

    // MARK: - Orlan-10 Spawn

    func spawnOrlan() {
        let spawnX = CGFloat.random(in: 60...(frame.width - 60))
        let spawnY = frame.height + 30
        let spawnPoint = CGPoint(x: spawnX, y: spawnY)

        let orlan = OrlanDroneEntity.create(sceneFrame: frame)

        let altitude: DroneAltitude = .high
        orlan.addComponent(AltitudeComponent(altitude: altitude))
        let shadow = ShadowComponent()
        orlan.addComponent(shadow)
        shadowLayer?.addChild(shadow.shadowNode)

        if let spriteNode = orlan.component(ofType: SpriteComponent.self)?.spriteNode {
            let scale = altitude.droneVisualScale
            spriteNode.size = CGSize(width: 20 * scale, height: 20 * scale)
            spriteNode.zPosition = 61 + CGFloat(altitude.rawValue) * 5
        }

        orlan.configureSpawn(at: spawnPoint)

        activeDrones.append(orlan)
        addEntity(orlan)
    }

    /// Returns true if any Orlan-10 recon drone is alive (used by WaveManager for salvo timing)
    var isOrlanActive: Bool {
        activeDrones.contains { $0 is OrlanDroneEntity && !$0.isHit }
    }

    // MARK: - Kamikaze Spawn

    func spawnKamikaze() {
        let spawnX = CGFloat.random(in: 20...(frame.width - 20))
        let spawnY = frame.height + CGFloat.random(in: 20...50)
        let spawnPoint = CGPoint(x: spawnX, y: spawnY)

        // 50% chance to target a settlement, 50% HQ
        var targetSettlementRef: SettlementEntity?
        let target: CGPoint

        if Bool.random(), let settlement = settlementManager?.aliveSettlements().randomElement() {
            targetSettlementRef = settlement
            let scatterAngle = CGFloat.random(in: 0...(2 * .pi))
            let scatterDist = CGFloat.random(in: 0...15)
            target = CGPoint(
                x: settlement.worldPosition.x + cos(scatterAngle) * scatterDist,
                y: settlement.worldPosition.y + sin(scatterAngle) * scatterDist
            )
        } else {
            // Target HQ center with scatter
            let hqCenter: CGPoint
            if let gridMap {
                let hqRow = Constants.TowerDefense.gridRows - 1
                let hqCol = Constants.TowerDefense.gridCols / 2
                hqCenter = gridMap.worldPosition(forRow: hqRow, col: hqCol)
            } else {
                hqCenter = CGPoint(x: frame.midX, y: 60)
            }
            let scatterAngle = CGFloat.random(in: 0...(2 * .pi))
            let scatterDist = CGFloat.random(in: 0...40)
            target = CGPoint(
                x: hqCenter.x + cos(scatterAngle) * scatterDist,
                y: hqCenter.y + sin(scatterAngle) * scatterDist
            )
        }

        let kamikaze = KamikazeDroneEntity(sceneFrame: frame)
        kamikaze.targetSettlement = targetSettlementRef

        let altitude: DroneAltitude = .micro
        kamikaze.addComponent(AltitudeComponent(altitude: altitude))
        let shadow = ShadowComponent()
        kamikaze.addComponent(shadow)
        shadowLayer?.addChild(shadow.shadowNode)

        if let spriteNode = kamikaze.component(ofType: SpriteComponent.self)?.spriteNode {
            let scale = Constants.Kamikaze.spriteScale * altitude.droneVisualScale
            spriteNode.size = CGSize(width: 12 * scale, height: 14 * scale)
            spriteNode.zPosition = 61 + CGFloat(altitude.rawValue) * 5
        }

        kamikaze.configureFlight(from: spawnPoint, to: target, speed: Constants.Kamikaze.speed)

        activeDrones.append(kamikaze)
        addEntity(kamikaze)
    }

    // MARK: - EW Drone Spawn

    func spawnEWDrone() {
        let spawnX = CGFloat.random(in: 20...(frame.width - 20))
        let spawnY = frame.height + CGFloat.random(in: 30...50)
        let spawnPoint = CGPoint(x: spawnX, y: spawnY)

        let hqCenter: CGPoint
        if let gridMap {
            let hqRow = Constants.TowerDefense.gridRows - 1
            let hqCol = Constants.TowerDefense.gridCols / 2
            hqCenter = gridMap.worldPosition(forRow: hqRow, col: hqCol)
        } else {
            hqCenter = CGPoint(x: frame.midX, y: 60)
        }

        let ewDrone = EWDroneEntity(sceneFrame: frame)
        let altitude: DroneAltitude = .high
        ewDrone.addComponent(AltitudeComponent(altitude: altitude))
        let shadow = ShadowComponent()
        ewDrone.addComponent(shadow)
        shadowLayer?.addChild(shadow.shadowNode)

        if let spriteNode = ewDrone.component(ofType: SpriteComponent.self)?.spriteNode {
            let scale = altitude.droneVisualScale
            spriteNode.size = CGSize(width: 24 * scale, height: 24 * scale)
            spriteNode.zPosition = 61 + CGFloat(altitude.rawValue) * 5
        }

        ewDrone.configureFlight(from: spawnPoint, to: hqCenter, speed: Constants.EW.ewDroneSpeed)

        activeDrones.append(ewDrone)
        addEntity(ewDrone)
    }

    // MARK: - Heavy Drone Spawn

    func spawnHeavyDrone() {
        guard let gridMap else { return }
        let pathDefs = selectedLevel.dronePaths
        guard !pathDefs.isEmpty else { return }

        let pathDef = pathDefs.randomElement()!
        let waypoints = pathDef.gridWaypoints.map { wp in
            gridMap.worldPosition(forRow: wp.row, col: wp.col)
        }
        guard !waypoints.isEmpty else { return }

        let spawnWaypoints = waypoints.enumerated().map { index, wp -> CGPoint in
            if index == 0 {
                return CGPoint(x: wp.x + CGFloat.random(in: -15...15), y: wp.y + 40)
            }
            if index == waypoints.count - 1 {
                return CGPoint(x: wp.x + CGFloat.random(in: -5...5), y: wp.y)
            }
            return CGPoint(x: wp.x + CGFloat.random(in: -10...10), y: wp.y + CGFloat.random(in: -6...6))
        }

        let flightPath = DroneFlightPath(waypoints: spawnWaypoints, altitude: .medium, spawnEdge: pathDef.spawnEdge)
        let heavyDrone = HeavyDroneEntity(sceneFrame: frame, flightPath: flightPath)

        let altitude: DroneAltitude = .medium
        heavyDrone.addComponent(AltitudeComponent(altitude: altitude))
        let shadow = ShadowComponent()
        heavyDrone.addComponent(shadow)
        shadowLayer?.addChild(shadow.shadowNode)

        if let spriteNode = heavyDrone.component(ofType: SpriteComponent.self)?.spriteNode {
            let scale = Constants.AdvancedEnemies.heavyDroneSpriteScale * altitude.droneVisualScale
            spriteNode.size = CGSize(width: 30 * scale, height: 30 * scale)
            spriteNode.zPosition = 61 + CGFloat(altitude.rawValue) * 5
        }

        activeDrones.append(heavyDrone)
        addEntity(heavyDrone)
    }

    // MARK: - Cruise Missile Spawn

    func spawnCruiseMissile() {
        let spawnX = CGFloat.random(in: 40...(frame.width - 40))
        let spawnY = frame.height + 30
        let spawnPoint = CGPoint(x: spawnX, y: spawnY)

        let hqCenter: CGPoint
        if let gridMap {
            let hqRow = Constants.TowerDefense.gridRows - 1
            let hqCol = Constants.TowerDefense.gridCols / 2
            hqCenter = gridMap.worldPosition(forRow: hqRow, col: hqCol)
        } else {
            hqCenter = CGPoint(x: frame.midX, y: 60)
        }

        let cruise = CruiseMissileEntity(sceneFrame: frame)
        let altitude: DroneAltitude = .cruise
        cruise.addComponent(AltitudeComponent(altitude: altitude))
        let shadow = ShadowComponent()
        cruise.addComponent(shadow)
        shadowLayer?.addChild(shadow.shadowNode)

        if let spriteNode = cruise.component(ofType: SpriteComponent.self)?.spriteNode {
            let scale = altitude.droneVisualScale
            spriteNode.size = CGSize(width: 8 * scale, height: 22 * scale)
            spriteNode.zPosition = 61 + CGFloat(altitude.rawValue) * 5
        }

        let speed = CGFloat.random(in: Constants.AdvancedEnemies.cruiseMissileMinSpeed...Constants.AdvancedEnemies.cruiseMissileMaxSpeed)
        cruise.configureFlight(from: spawnPoint, to: hqCenter, speed: speed)

        activeDrones.append(cruise)
        addEntity(cruise)
    }

    // MARK: - Swarm Cloud Spawn

    func spawnSwarmCloud() {
        let spawnX = CGFloat.random(in: 40...(frame.width - 40))
        let spawnY = frame.height + 30

        let hqCenter: CGPoint
        if let gridMap {
            let hqRow = Constants.TowerDefense.gridRows - 1
            let hqCol = Constants.TowerDefense.gridCols / 2
            hqCenter = gridMap.worldPosition(forRow: hqRow, col: hqCol)
        } else {
            hqCenter = CGPoint(x: frame.midX, y: 60)
        }

        let swarm = SwarmCloudEntity(
            sceneFrame: frame,
            spawnCenter: CGPoint(x: spawnX, y: spawnY),
            target: hqCenter
        )

        for drone in swarm.swarmDrones {
            drone.addComponent(AltitudeComponent(altitude: .micro))
            let shadow = ShadowComponent(baseSize: CGSize(width: 8, height: 4))
            drone.addComponent(shadow)
            shadowLayer?.addChild(shadow.shadowNode)

            activeDrones.append(drone)
            addEntity(drone)
        }
        activeSwarmClouds.append(swarm)
    }
}
