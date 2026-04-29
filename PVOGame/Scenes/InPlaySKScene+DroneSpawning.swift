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
    func spawnDrone(flightPath: DroneFlightPath, altitude: DroneAltitude, targetSettlement: SettlementEntity? = nil, targetRefinery: TowerEntity? = nil) {
        let flyingPath = flightPath.toFlyingPath()
        let drone = ShahedDroneEntity.create(flyingPath: flyingPath)
        drone.targetSettlement = targetSettlement
        drone.targetRefinery = targetRefinery

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
        guard gridMap != nil else { return }

        // Assign target (refinery or settlement)
        let targetResult = settlementManager?.assignTarget(
            towers: towerPlacement?.towers ?? []
        ) ?? .none

        // Random point along the entire HQ row — drones spread across the
        // full bottom width instead of all converging on the centre.
        let hqPoint = comboHQPoint()

        // Random spawn from top
        let spawnPoint = CGPoint(
            x: CGFloat.random(in: 20...(frame.width - 20)),
            y: frame.height + CGFloat.random(in: 20...50)
        )

        // Path: spawn → through target → HQ
        let waypoints: [CGPoint]
        let targetSettlement: SettlementEntity?
        let targetRefinery: TowerEntity?
        switch targetResult {
        case .settlement(let s):
            waypoints = generateSettlementPath(from: spawnPoint, through: s.worldPosition, to: hqPoint)
            targetSettlement = s
            targetRefinery = nil
        case .refinery(let r):
            waypoints = generateSettlementPath(from: spawnPoint, through: r.worldPosition, to: hqPoint)
            targetSettlement = nil
            targetRefinery = r
        case .none:
            waypoints = generateSettlementPath(from: spawnPoint, to: hqPoint)
            targetSettlement = nil
            targetRefinery = nil
        }

        let altitude: DroneAltitude = .low
        let flightPath = DroneFlightPath(waypoints: waypoints, altitude: altitude, spawnEdge: .top)
        let flyingPath = flightPath.toFlyingPath()
        let drone = ShahedDroneEntity.create(flyingPath: flyingPath)
        drone.targetSettlement = targetSettlement
        drone.targetRefinery = targetRefinery

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

    /// Max drones per single chevron / triangle sub-group.
    /// Groups larger than this are split into sequential waves.
    private static let maxChevronGroupSize = 7
    private static let maxTriangleGroupSize = 10

    /// Top-edge formation anchored at a specific fraction of the screen width.
    /// Used by combos like Pincer that want multiple formations entering the top
    /// at different X positions instead of one random anchor.
    func spawnShahedFormation(count: Int, formation: ShahedFormation, xFraction: CGFloat) {
        let centerX = frame.width * max(0.05, min(0.95, xFraction))
        spawnShahedFormation(count: count, formation: formation, centerXOverride: centerX)
    }

    func spawnShahedFormation(count: Int, formation: ShahedFormation) {
        spawnShahedFormation(count: count, formation: formation, centerXOverride: nil)
    }

    private func spawnShahedFormation(count: Int, formation: ShahedFormation, centerXOverride: CGFloat?) {
        guard let gridMap else { return }
        _ = gridMap  // silence unused-warning when not referenced below

        // Split large formations into sequential groups
        let groups = splitIntoGroups(count: count, formation: formation)

        // Reserve ALL drones upfront so WaveManager doesn't think wave is over
        // between groups. Each spawnSingleFormationGroup will decrement as drones spawn.
        pendingShahedSpawns += count

        let spacing = Constants.Shahed.formationSpacing
        let speed = Constants.Shahed.speed

        // Delay between groups: time for previous group to clear its Y-depth
        var groupDelay: TimeInterval = 0

        for group in groups {
            let capturedDelay = groupDelay
            let capturedCount = group

            let capturedCenterX = centerXOverride
            run(SKAction.sequence([
                SKAction.wait(forDuration: capturedDelay),
                SKAction.run { [weak self] in
                    self?.spawnSingleFormationGroup(
                        count: capturedCount,
                        formation: formation,
                        centerXOverride: capturedCenterX
                    )
                }
            ]))

            // Calculate Y-depth of this group to determine gap before next
            let groupDepth = formationYDepth(count: group, formation: formation, spacing: spacing)
            let gapBetweenGroups = spacing * 1.5  // breathing room between groups
            groupDelay += TimeInterval((groupDepth + gapBetweenGroups) / speed)
        }
    }

    /// Split total count into groups of manageable size
    private func splitIntoGroups(count: Int, formation: ShahedFormation) -> [Int] {
        let maxSize: Int
        switch formation {
        case .scattered:
            return [count]  // scattered doesn't need splitting
        case .chevron:
            maxSize = Self.maxChevronGroupSize
        case .triangle:
            maxSize = Self.maxTriangleGroupSize
        case .tripleTriangle:
            // tripleTriangle is already 3 sub-triangles; limit total per wave
            maxSize = Self.maxTriangleGroupSize * 3
        }

        guard count > maxSize else { return [count] }

        var groups = [Int]()
        var remaining = count
        while remaining > 0 {
            let groupSize = min(maxSize, remaining)
            groups.append(groupSize)
            remaining -= groupSize
        }
        return groups
    }

    /// Calculate Y-depth (in pixels) of a formation group
    private func formationYDepth(count: Int, formation: ShahedFormation, spacing: CGFloat) -> CGFloat {
        switch formation {
        case .scattered:
            return 60
        case .chevron:
            let maxDepth = CGFloat((count - 1 + 1) / 2)
            let adaptiveSpacing = maxDepth > 0 ? min(spacing, 160 / maxDepth) : spacing
            return maxDepth * adaptiveSpacing * 0.35
        case .triangle:
            // Triangle with N drones has ceil((-1+sqrt(1+8N))/2) rows
            let rows = ceil((-1 + sqrt(1 + 8 * Double(count))) / 2)
            return CGFloat(rows - 1) * spacing * 0.4
        case .tripleTriangle:
            let perTriangle = count / 3 + count % 3
            let rows = ceil((-1 + sqrt(1 + 8 * Double(perTriangle))) / 2)
            return CGFloat(rows - 1) * spacing * 0.4 + spacing * 0.4  // +backOffset
        }
    }

    /// Spawn one formation group (original logic, unchanged)
    private func spawnSingleFormationGroup(count: Int, formation: ShahedFormation, centerXOverride: CGFloat? = nil) {
        guard gridMap != nil else { return }

        // One shared random HQ point per formation — every drone in the same
        // formation aims for the same X so the V/triangle stays cohesive.
        let hqPoint = comboHQPoint()

        let centerX = centerXOverride.map { min(max($0, 60), frame.width - 60) }
            ?? CGFloat.random(in: 60...(frame.width - 60))
        let centerY = frame.height + 20
        let leaderSpawn = CGPoint(x: centerX, y: centerY)

        let offsets = shahedFormationOffsets(for: formation, count: count)

        let targetResult = settlementManager?.assignTarget(
            towers: towerPlacement?.towers ?? []
        ) ?? .none

        let referencePath: [CGPoint]
        let formationTargetSettlement: SettlementEntity?
        let formationTargetRefinery: TowerEntity?
        switch targetResult {
        case .settlement(let s):
            referencePath = generateSettlementPath(from: leaderSpawn, through: s.worldPosition, to: hqPoint)
            formationTargetSettlement = s
            formationTargetRefinery = nil
        case .refinery(let r):
            referencePath = generateSettlementPath(from: leaderSpawn, through: r.worldPosition, to: hqPoint)
            formationTargetSettlement = nil
            formationTargetRefinery = r
        case .none:
            referencePath = generateSettlementPath(from: leaderSpawn, to: hqPoint)
            formationTargetSettlement = nil
            formationTargetRefinery = nil
        }

        let wpCount = referencePath.count

        // pendingShahedSpawns already reserved by spawnShahedFormation

        for (i, offset) in offsets.enumerated() {
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
            waypoints[wpCount - 1] = hqPoint

            let altitude: DroneAltitude = .low
            let flightPath = DroneFlightPath(waypoints: waypoints, altitude: altitude, spawnEdge: .top)
            let flyingPath = flightPath.toFlyingPath()

            let cgPath = CGMutablePath()
            cgPath.move(to: waypoints[0])
            for wpIdx in 1..<waypoints.count {
                cgPath.addLine(to: waypoints[wpIdx])
            }

            let capturedPath = flyingPath
            let capturedCGPath = cgPath
            let capturedTargetSettlement = formationTargetSettlement
            let capturedTargetRefinery = formationTargetRefinery
            let capturedWaypoints = waypoints
            let capturedSpeed = Constants.Shahed.speed

            run(SKAction.sequence([
                SKAction.wait(forDuration: TimeInterval(i) * Constants.Shahed.formationStagger),
                SKAction.run { [weak self] in
                    guard let self else { return }
                    let drone = ShahedDroneEntity.create(flyingPath: capturedPath)
                    drone.targetSettlement = capturedTargetSettlement
                    drone.targetRefinery = capturedTargetRefinery
                    drone.isFormationFlight = true

                    if let flight = drone.component(ofType: FlyingProjectileComponent.self) {
                        flight.behavior = GKBehavior()
                        flight.maxSpeed = 0
                        // Also zero out the agent's current speed and acceleration —
                        // otherwise its initial cruise vector (50, 0) keeps trying to
                        // drag the agent (and its rotation) rightward each frame.
                        flight.speed = 0
                        flight.maxAcceleration = 0
                    }

                    drone.addComponent(AltitudeComponent(altitude: altitude))
                    let shadow = ShadowComponent()
                    drone.addComponent(shadow)
                    self.shadowLayer?.addChild(shadow.shadowNode)

                    if let spriteNode = drone.component(ofType: SpriteComponent.self)?.spriteNode {
                        spriteNode.zPosition = 61 + CGFloat(altitude.rawValue) * 5
                        spriteNode.position = capturedWaypoints[0]

                        if capturedWaypoints.count >= 2 {
                            let dx = capturedWaypoints[1].x - capturedWaypoints[0].x
                            let dy = capturedWaypoints[1].y - capturedWaypoints[0].y
                            spriteNode.zRotation = atan2(dy, dx) - .pi / 2
                        }

                        let followAction = SKAction.follow(
                            capturedCGPath,
                            asOffset: false,
                            orientToPath: false,
                            speed: capturedSpeed
                        )

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
            let base = Constants.SpriteSize.orlan
            spriteNode.size = CGSize(width: base * scale, height: base * scale)
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

        // 50% chance to target a settlement/refinery, 50% HQ
        var targetSettlementRef: SettlementEntity?
        var targetRefineryRef: TowerEntity?
        let target: CGPoint

        if Bool.random() {
            // Try refinery first (high priority), then settlement
            let targetResult = settlementManager?.assignTarget(
                towers: towerPlacement?.towers ?? []
            ) ?? .none
            switch targetResult {
            case .refinery(let r):
                targetRefineryRef = r
                let scatterAngle = CGFloat.random(in: 0...(2 * .pi))
                let scatterDist = CGFloat.random(in: 0...15)
                target = CGPoint(
                    x: r.worldPosition.x + cos(scatterAngle) * scatterDist,
                    y: r.worldPosition.y + sin(scatterAngle) * scatterDist
                )
            case .settlement(let s):
                targetSettlementRef = s
                let scatterAngle = CGFloat.random(in: 0...(2 * .pi))
                let scatterDist = CGFloat.random(in: 0...15)
                target = CGPoint(
                    x: s.worldPosition.x + cos(scatterAngle) * scatterDist,
                    y: s.worldPosition.y + sin(scatterAngle) * scatterDist
                )
            case .none:
                let hqCenter = comboHQPoint()
                let scatterAngle = CGFloat.random(in: 0...(2 * .pi))
                let scatterDist = CGFloat.random(in: 0...40)
                target = CGPoint(
                    x: hqCenter.x + cos(scatterAngle) * scatterDist,
                    y: hqCenter.y + sin(scatterAngle) * scatterDist
                )
            }
        } else {
            // Target a random HQ-row point with scatter
            let hqCenter = comboHQPoint()
            let scatterAngle = CGFloat.random(in: 0...(2 * .pi))
            let scatterDist = CGFloat.random(in: 0...40)
            target = CGPoint(
                x: hqCenter.x + cos(scatterAngle) * scatterDist,
                y: hqCenter.y + sin(scatterAngle) * scatterDist
            )
        }

        let kamikaze = KamikazeDroneEntity(sceneFrame: frame)
        kamikaze.targetSettlement = targetSettlementRef
        kamikaze.targetRefinery = targetRefineryRef

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

        let hqCenter = comboHQPoint()

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

        // Spawn the heavy drone fully off-screen above the frame so the
        // entry isn't visible — drone flies in from above the HUD. Entry
        // x gets a wide jitter (±55) because Heavies removed the path-
        // following component (FlyingProjectileComponent) at init: only
        // the first waypoint actually places the drone, so two Heavies
        // picking the same level path would otherwise drop on identical
        // columns. Combined with the per-drone scoutHeadingOffset, this
        // gives co-spawned Heavies visibly different entry corridors.
        // Final x is clamped to leave a 70 px margin from each frame
        // edge: a Heavy that started right at the wall would have to
        // immediately fight the lateral containment force, which makes
        // the entry read as "drone is bouncing off the wall" instead
        // of a confident strike approach.
        let entrySideMargin: CGFloat = 70
        let entryMinX = frame.minX + entrySideMargin
        let entryMaxX = frame.maxX - entrySideMargin
        let spawnWaypoints = waypoints.enumerated().map { index, wp -> CGPoint in
            if index == 0 {
                let jitteredX = wp.x + CGFloat.random(in: -55...55)
                return CGPoint(
                    x: max(entryMinX, min(entryMaxX, jitteredX)),
                    y: frame.height + CGFloat.random(in: 40...80)
                )
            }
            if index == waypoints.count - 1 {
                return CGPoint(x: wp.x + CGFloat.random(in: -5...5), y: wp.y)
            }
            return CGPoint(x: wp.x + CGFloat.random(in: -10...10), y: wp.y + CGFloat.random(in: -6...6))
        }

        let flightPath = DroneFlightPath(waypoints: spawnWaypoints, altitude: .high, spawnEdge: pathDef.spawnEdge)
        let heavyDrone = HeavyDroneEntity(sceneFrame: frame, flightPath: flightPath)

        let altitude: DroneAltitude = .high
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

        let hqCenter = comboHQPoint()

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

    // MARK: - Combo Spawn Helpers (used by WaveScript)

    /// Compute a randomized off-screen anchor for the requested edge.
    /// .top → above frame, .left/.right → mid-height off the left/right edge.
    func comboSpawnPoint(forSide side: SpawnEdge) -> CGPoint {
        switch side {
        case .top:
            return CGPoint(
                x: CGFloat.random(in: 40...(frame.width - 40)),
                y: frame.height + CGFloat.random(in: 20...50)
            )
        case .left:
            return CGPoint(
                x: -30,
                y: frame.height * CGFloat.random(in: 0.50...0.80)
            )
        case .right:
            return CGPoint(
                x: frame.width + 30,
                y: frame.height * CGFloat.random(in: 0.50...0.80)
            )
        }
    }

    /// Random point along the entire HQ row (the whole bottom row is the
    /// damage zone). Each call returns a fresh X — drones spread out across
    /// the full width instead of all converging on the centre column.
    func comboHQPoint() -> CGPoint {
        guard let gridMap else { return CGPoint(x: frame.midX, y: 60) }
        let hqRow = Constants.TowerDefense.gridRows - 1
        let leftPos = gridMap.worldPosition(forRow: hqRow, col: 0)
        let rightPos = gridMap.worldPosition(forRow: hqRow, col: Constants.TowerDefense.gridCols - 1)
        let x = CGFloat.random(in: leftPos.x...rightPos.x)
        return CGPoint(x: x, y: leftPos.y)
    }

    // MARK: M2 — Micro-staggered Grad/HARM salvos

    /// Spawns `count` Grad rockets with a micro-stagger between launches.
    /// All rockets in a single salvo launch from one fixed "launcher" point
    /// (real БМ-21 doesn't scatter its tubes across the sky); individual rockets
    /// land within `scatter` px of HQ.
    func spawnGradSalvoMicro(count: Int, micro: TimeInterval, scatter: CGFloat, side: SpawnEdge) {
        guard count > 0 else { return }
        // Fix ONE launcher anchor for the whole salvo.
        let launcherAnchor = comboSpawnPoint(forSide: side)
        pendingMissileSpawns += count
        for i in 0..<count {
            let delay = TimeInterval(i) * micro
            run(SKAction.sequence([
                SKAction.wait(forDuration: delay),
                SKAction.run { [weak self] in
                    self?.spawnSingleGradMissile(scatter: scatter, launcherAnchor: launcherAnchor)
                }
            ]))
        }
    }

    /// Single Grad rocket. Internal helper for the micro-staggered salvo.
    private func spawnSingleGradMissile(scatter: CGFloat, launcherAnchor: CGPoint) {
        pendingMissileSpawns = max(0, pendingMissileSpawns - 1)
        let gb = Constants.GameBalance.self
        // Tight per-rocket jitter around the launcher anchor: ±18 X, ±6 Y.
        let spawnPoint = CGPoint(
            x: launcherAnchor.x + CGFloat.random(in: -18...18),
            y: launcherAnchor.y + CGFloat.random(in: -6...6)
        )
        let hqCenter = comboHQPoint()

        let scatterAngle = CGFloat.random(in: 0...(2 * .pi))
        let scatterDist = CGFloat.random(in: 0...scatter)
        let target = CGPoint(
            x: hqCenter.x + cos(scatterAngle) * scatterDist,
            y: hqCenter.y + sin(scatterAngle) * scatterDist
        )

        let missileSpeed = gb.enemyMissileBaseSpeed
            + CGFloat.random(in: -gb.enemyMissileSpeedVariance...gb.enemyMissileSpeedVariance)

        let missile = EnemyMissileEntity(sceneFrame: frame)
        missile.addComponent(AltitudeComponent(altitude: .ballistic))
        let shadow = ShadowComponent()
        missile.addComponent(shadow)
        shadowLayer?.addChild(shadow.shadowNode)

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

    /// Spawns `count` HARMs targeting current radar emitters, micro-staggered.
    func spawnHarmSalvoMicro(count: Int, micro: TimeInterval) {
        guard count > 0 else { return }
        let targets = selectHarmTargets(salvoSize: count)
        guard !targets.isEmpty else { return }

        pendingHarmSpawns += targets.count
        for (i, tower) in targets.enumerated() {
            let delay = TimeInterval(i) * micro
            run(SKAction.sequence([
                SKAction.wait(forDuration: delay),
                SKAction.run { [weak self, weak tower] in
                    guard let self else { return }
                    guard let tower else {
                        self.pendingHarmSpawns = max(0, self.pendingHarmSpawns - 1)
                        return
                    }
                    self.spawnSingleHarm(targetTower: tower)
                }
            ]))
        }
    }

    // MARK: Side-aware single-unit spawns

    /// Spawn a Cruise Missile from a given edge.
    func spawnCruiseMissile(fromSide side: SpawnEdge) {
        let spawnPoint = comboSpawnPoint(forSide: side)
        let hqCenter = comboHQPoint()

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

        let speed = CGFloat.random(
            in: Constants.AdvancedEnemies.cruiseMissileMinSpeed...Constants.AdvancedEnemies.cruiseMissileMaxSpeed
        )
        cruise.configureFlight(from: spawnPoint, to: hqCenter, speed: speed)
        activeDrones.append(cruise)
        addEntity(cruise)
    }

    /// Spawn a single Kamikaze drone from the requested edge, targeting HQ.
    func spawnKamikaze(fromSide side: SpawnEdge) {
        let spawnPoint = comboSpawnPoint(forSide: side)
        let hqCenter = comboHQPoint()

        let scatterAngle = CGFloat.random(in: 0...(2 * .pi))
        let scatterDist = CGFloat.random(in: 0...40)
        let target = CGPoint(
            x: hqCenter.x + cos(scatterAngle) * scatterDist,
            y: hqCenter.y + sin(scatterAngle) * scatterDist
        )

        let kamikaze = KamikazeDroneEntity(sceneFrame: frame)
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

    /// Spawn an EW drone whose entry point is the given anchor (instead of random top).
    func spawnEWDrone(at anchor: CGPoint) {
        _ = spawnEWDroneEntity(at: anchor)
    }

    /// Same as `spawnEWDrone(at:)` but returns the created entity so callers
    /// can attach follower drones to it (escort formations).
    @discardableResult
    func spawnEWDroneEntity(at anchor: CGPoint) -> EWDroneEntity {
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
        ewDrone.configureFlight(from: anchor, to: comboHQPoint(), speed: Constants.EW.ewDroneSpeed)

        activeDrones.append(ewDrone)
        addEntity(ewDrone)
        return ewDrone
    }

    /// Spawn a Heavy drone with a custom direct flight path from `anchor`.
    /// Skips the level grid waypoints; used by composite formations only.
    func spawnHeavyDroneDirect(from anchor: CGPoint) {
        let hq = comboHQPoint()
        // Three-point sloppy path so the drone doesn't fly arrow-straight.
        let mid = CGPoint(
            x: lerp(anchor.x, hq.x, 0.5) + CGFloat.random(in: -20...20),
            y: lerp(anchor.y, hq.y, 0.5) + CGFloat.random(in: -10...10)
        )
        let path = DroneFlightPath(
            waypoints: [anchor, mid, hq],
            altitude: .high,
            spawnEdge: .top
        )
        let heavy = HeavyDroneEntity(sceneFrame: frame, flightPath: path)
        let altitude: DroneAltitude = .high
        heavy.addComponent(AltitudeComponent(altitude: altitude))
        let shadow = ShadowComponent()
        heavy.addComponent(shadow)
        shadowLayer?.addChild(shadow.shadowNode)

        if let spriteNode = heavy.component(ofType: SpriteComponent.self)?.spriteNode {
            let scale = Constants.AdvancedEnemies.heavyDroneSpriteScale * altitude.droneVisualScale
            spriteNode.size = CGSize(width: 30 * scale, height: 30 * scale)
            spriteNode.zPosition = 61 + CGFloat(altitude.rawValue) * 5
        }

        activeDrones.append(heavy)
        addEntity(heavy)
    }

    private func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat {
        a + (b - a) * t
    }

    // MARK: M1 — Composite formations

    /// Spawn a fixed-geometry composite formation (M1) anchored to the given edge.
    /// Each kind hand-places its constituent enemies relative to a single anchor
    /// so they read on screen as one coherent attack.
    func spawnCompositeFormation(_ kind: CompositeFormationKind, side: SpawnEdge) {
        let anchor = comboSpawnPoint(forSide: side)
        switch kind {
        case .ewConvoy:
            spawnEWConvoy(anchor: anchor)
        case .bomberRun:
            spawnBomberRunComposite(anchor: anchor)
        case .mineLayerEscort:
            spawnMineLayerEscort(anchor: anchor)
        case .deathFromAbove:
            spawnDeathFromAboveComposite(anchor: anchor)
        case .ghostBomberEscort:
            spawnGhostBomberEscort(anchor: anchor)
        case .armoredBomberEscort:
            spawnArmoredBomberEscort(anchor: anchor)
        }
    }

    /// 2 Heavy drones up front as living shields for a Mine-Layer trailing
    /// behind, with 4 Shaheds flanking. The Heavies (12 HP each) soak the
    /// player's gun fire while the Mine-Layer closes in to drop ordnance.
    private func spawnArmoredBomberEscort(anchor: CGPoint) {
        // Two Heavies side-by-side in front, each on its own sloppy path.
        spawnHeavyDroneDirect(from: CGPoint(x: anchor.x - 30, y: anchor.y))
        spawnHeavyDroneDirect(from: CGPoint(x: anchor.x + 30, y: anchor.y))

        // Mine-Layer with extra HP (its own AI picks a target tower).
        spawnMineLayer(health: Constants.GameBalance.droneHealth * 2)

        // 4 Shahed flankers around/behind the formation.
        let shieldOffsets: [CGPoint] = [
            CGPoint(x: -55, y: 25),
            CGPoint(x:  55, y: 25),
            CGPoint(x: -30, y: 55),
            CGPoint(x:  30, y: 55),
        ]
        spawnShahedShield(anchor: anchor, offsets: shieldOffsets)
    }

    /// Night raid: 1 EW leader + ~24-Shahed double escort.
    /// Inner ring of 8 shaheds hugs the jammer, outer arrow of 16 shaheds
    /// forms a layered vanguard ahead and around it — visually distinct from
    /// the concentric-hex ewConvoy composite.
    private func spawnGhostBomberEscort(anchor: CGPoint) {
        let ewDrone = spawnEWDroneEntity(at: anchor)

        // Inner ring — 8 tight around the jammer.
        let innerRadius: CGFloat = 40
        let innerOffsets: [CGPoint] = (0..<8).map { i in
            let angle = CGFloat(i) * (.pi * 2 / 8) + .pi / 8
            return CGPoint(x: cos(angle) * innerRadius, y: sin(angle) * innerRadius)
        }
        // Outer layer — 16 shaheds: 10-drone forward arrow + 6 wings covering rear flanks.
        let outerOffsets: [CGPoint] = [
            // Arrow tip (5 drones at increasing depth)
            CGPoint(x:  0,   y: -110),
            CGPoint(x: -25,  y:  -95),
            CGPoint(x:  25,  y:  -95),
            CGPoint(x: -55,  y:  -75),
            CGPoint(x:  55,  y:  -75),
            // Arrow shoulders (5 drones spread wider ahead)
            CGPoint(x: -85,  y:  -55),
            CGPoint(x:  85,  y:  -55),
            CGPoint(x: -40,  y:  -55),
            CGPoint(x:  40,  y:  -55),
            CGPoint(x:  0,   y:  -60),
            // Rear wings (6 drones protecting the trailing flanks)
            CGPoint(x: -95,  y:   15),
            CGPoint(x:  95,  y:   15),
            CGPoint(x: -75,  y:   45),
            CGPoint(x:  75,  y:   45),
            CGPoint(x: -40,  y:   65),
            CGPoint(x:  40,  y:   65),
        ]
        spawnEscortedShaheds(leader: ewDrone, offsets: innerOffsets + outerOffsets)
    }

    /// 1 EW Drone leading, ~20 Shahed escorts locked in a two-layer ring around
    /// it: inner hex of 6 at close range + outer ring of 14 at long range.
    /// When the EW drone dies, the shaheds detach and resume as normal Shaheds
    /// heading for the nearest settlement.
    private func spawnEWConvoy(anchor: CGPoint) {
        let ewDrone = spawnEWDroneEntity(at: anchor)

        // Inner protective hex — tight around the jammer.
        let innerRadius: CGFloat = 45
        let innerOffsets: [CGPoint] = (0..<6).map { i in
            let angle = CGFloat(i) * (.pi * 2 / 6)
            return CGPoint(x: cos(angle) * innerRadius, y: sin(angle) * innerRadius)
        }
        // Outer defensive ring — 14 shaheds spread wide to screen for the leader.
        let outerRadius: CGFloat = 95
        let outerOffsets: [CGPoint] = (0..<14).map { i in
            let angle = CGFloat(i) * (.pi * 2 / 14) + .pi / 14
            return CGPoint(x: cos(angle) * outerRadius, y: sin(angle) * outerRadius)
        }
        spawnEscortedShaheds(leader: ewDrone, offsets: innerOffsets + outerOffsets)
    }

    /// 2 Heavy drones, V of 6 Shahed in front, 2 Kamikaze flanking.
    private func spawnBomberRunComposite(anchor: CGPoint) {
        // 2 heavies side by side at the anchor.
        spawnHeavyDroneDirect(from: CGPoint(x: anchor.x - 25, y: anchor.y))
        spawnHeavyDroneDirect(from: CGPoint(x: anchor.x + 25, y: anchor.y))

        // 6-Shahed V-shield in front (lower y = ahead, since drones fly downward).
        let spacing: CGFloat = 30
        let shieldOffsets: [CGPoint] = [
            CGPoint(x:  0,            y: -spacing * 2),  // tip
            CGPoint(x: -spacing,      y: -spacing * 1.4),
            CGPoint(x:  spacing,      y: -spacing * 1.4),
            CGPoint(x: -spacing * 2,  y: -spacing * 0.8),
            CGPoint(x:  spacing * 2,  y: -spacing * 0.8),
            CGPoint(x:  0,            y: -spacing * 0.6),
        ]
        spawnShahedShield(anchor: anchor, offsets: shieldOffsets)

        // Two kamikaze flankers from the sides of the anchor.
        let leftFlank = CGPoint(x: max(20, anchor.x - 80), y: anchor.y + 20)
        let rightFlank = CGPoint(x: min(frame.width - 20, anchor.x + 80), y: anchor.y + 20)
        spawnKamikaze(at: leftFlank)
        spawnKamikaze(at: rightFlank)
    }

    /// 1 Mine-Layer + 1 EW drone escort flying close together.
    private func spawnMineLayerEscort(anchor: CGPoint) {
        // Mine layer ignores anchor (uses its own AI to pick a target tower),
        // but the EW shows up next to where it would notionally enter with its
        // own shahed escort so the player has to commit firepower to kill it.
        spawnMineLayer(health: Constants.GameBalance.droneHealth * 2)
        let ewAnchor = CGPoint(x: anchor.x + 30, y: anchor.y)
        let ewDrone = spawnEWDroneEntity(at: ewAnchor)

        // 10-shahed ring escort — single layer, tighter than ewConvoy since
        // Bomber Run already stacks a mine layer threat alongside the jammer.
        let radius: CGFloat = 55
        let offsets: [CGPoint] = (0..<10).map { i in
            let angle = CGFloat(i) * (.pi * 2 / 10) + .pi / 10
            return CGPoint(x: cos(angle) * radius, y: sin(angle) * radius)
        }
        spawnEscortedShaheds(leader: ewDrone, offsets: offsets)
    }

    /// Boss-grade composite for combo #14: Heavy (boss) + EW leader with a
    /// two-layer shahed shield locked to it. When the EW is killed the shield
    /// detaches and the shaheds resume their own flight to the nearest HQ.
    private func spawnDeathFromAboveComposite(anchor: CGPoint) {
        // Heavy (the boss threat) — flies independently on its own path.
        spawnHeavyDroneDirect(from: anchor)

        // EW drone becomes the leader of the shahed shield.
        let ewDrone = spawnEWDroneEntity(at: CGPoint(x: anchor.x, y: anchor.y - 20))

        // Inner tight hex — 6 shaheds at close range.
        let innerRadius: CGFloat = 42
        let innerOffsets: [CGPoint] = (0..<6).map { i in
            let angle = CGFloat(i) * (.pi * 2 / 6)
            return CGPoint(x: cos(angle) * innerRadius, y: sin(angle) * innerRadius)
        }
        // Outer forward V — 12 shaheds screening the front of the pair.
        let spacing: CGFloat = 32
        let outerOffsets: [CGPoint] = [
            CGPoint(x:  0,            y: -spacing * 3.2),
            CGPoint(x: -spacing,      y: -spacing * 2.6),
            CGPoint(x:  spacing,      y: -spacing * 2.6),
            CGPoint(x: -spacing * 2,  y: -spacing * 2.0),
            CGPoint(x:  spacing * 2,  y: -spacing * 2.0),
            CGPoint(x: -spacing * 3,  y: -spacing * 1.4),
            CGPoint(x:  spacing * 3,  y: -spacing * 1.4),
            CGPoint(x: -spacing * 3.8, y: -spacing * 0.6),
            CGPoint(x:  spacing * 3.8, y: -spacing * 0.6),
            CGPoint(x: -spacing * 2,  y:  spacing * 0.6),
            CGPoint(x:  spacing * 2,  y:  spacing * 0.6),
            CGPoint(x:  0,            y:  spacing * 1.2),
        ]
        spawnEscortedShaheds(leader: ewDrone, offsets: innerOffsets + outerOffsets)
    }

    /// Spawn Shaheds locked to a leader drone at fixed offsets (hex shield etc.).
    /// While the leader is alive the shaheds track its position directly. When
    /// the leader dies, each shahed rebuilds its own path to the nearest HQ
    /// point and flies the rest of the combo on its own.
    func spawnEscortedShaheds(leader: AttackDroneEntity, offsets: [CGPoint]) {
        guard let leaderSprite = leader.component(ofType: SpriteComponent.self)?.spriteNode else {
            return
        }
        let leaderPos = leaderSprite.position

        for offset in offsets {
            let spawnPoint = CGPoint(
                x: min(max(leaderPos.x + offset.x, 10), frame.width - 10),
                y: leaderPos.y + offset.y
            )
            // Dummy path — leader-follow tick drives the sprite; we just need a
            // path object for ShahedDroneEntity's base init.
            let dummyPath = DroneFlightPath(
                waypoints: [spawnPoint, CGPoint(x: spawnPoint.x, y: 0)],
                altitude: .low,
                spawnEdge: .top
            ).toFlyingPath()

            let drone = ShahedDroneEntity.create(flyingPath: dummyPath)
            drone.addComponent(AltitudeComponent(altitude: .low))
            let shadow = ShadowComponent()
            drone.addComponent(shadow)
            shadowLayer?.addChild(shadow.shadowNode)

            if let spriteNode = drone.component(ofType: SpriteComponent.self)?.spriteNode {
                spriteNode.zPosition = 61 + CGFloat(DroneAltitude.low.rawValue) * 5
                spriteNode.position = spawnPoint
            }

            if let flight = drone.component(ofType: FlyingProjectileComponent.self) {
                flight.behavior = GKBehavior()
                flight.maxSpeed = 0
                flight.speed = 0
                flight.maxAcceleration = 0
            }

            drone.attachToLeader(leader, offset: offset)
            drone.onLeaderLostHandler = { [weak self] follower in
                self?.resumeShahedFlightAfterEscort(follower)
            }

            activeDrones.append(drone)
            addEntity(drone)
        }
    }

    /// Called when an escort leader dies: rebuild a fresh path from the shahed's
    /// current position to the nearest HQ point and drive it with an SKAction.
    private func resumeShahedFlightAfterEscort(_ drone: AttackDroneEntity) {
        guard let spriteNode = drone.component(ofType: SpriteComponent.self)?.spriteNode else {
            return
        }
        let start = spriteNode.position
        let waypoints = generateSettlementPath(from: start, to: comboHQPoint())
        guard waypoints.count >= 2 else { return }

        let cgPath = CGMutablePath()
        cgPath.move(to: waypoints[0])
        for idx in 1..<waypoints.count {
            cgPath.addLine(to: waypoints[idx])
        }

        let followAction = SKAction.follow(
            cgPath,
            asOffset: false,
            orientToPath: false,
            speed: Constants.Shahed.speed
        )
        var lastPos = waypoints[0]
        let rotateAction = SKAction.customAction(withDuration: followAction.duration) { node, _ in
            let dx = node.position.x - lastPos.x
            let dy = node.position.y - lastPos.y
            if dx * dx + dy * dy > 0.5 {
                node.zRotation = atan2(dy, dx) - .pi / 2
                lastPos = node.position
            }
        }
        drone.isFormationFlight = true  // keep agent synced from sprite
        spriteNode.removeAllActions()
        spriteNode.run(SKAction.group([followAction, rotateAction]))
    }

    /// Internal helper: spawn a small set of Shaheds at fixed offsets from
    /// `anchor`, each flying its own jittered path to HQ. Used by composite
    /// formations only — bypasses `spawnSingleFormationGroup`'s random anchor.
    private func spawnShahedShield(anchor: CGPoint, offsets: [CGPoint]) {
        let hq = comboHQPoint()
        pendingShahedSpawns += offsets.count
        let speed = Constants.Shahed.speed

        for (i, offset) in offsets.enumerated() {
            let spawnPoint = CGPoint(
                x: min(max(anchor.x + offset.x, 10), frame.width - 10),
                y: anchor.y + offset.y
            )
            let waypoints = generateSettlementPath(from: spawnPoint, to: hq)

            let cgPath = CGMutablePath()
            cgPath.move(to: waypoints[0])
            for wpIdx in 1..<waypoints.count {
                cgPath.addLine(to: waypoints[wpIdx])
            }

            let flightPath = DroneFlightPath(waypoints: waypoints, altitude: .low, spawnEdge: .top)
            let flyingPath = flightPath.toFlyingPath()

            let capturedWaypoints = waypoints
            let capturedCGPath = cgPath
            let capturedSpeed = speed

            run(SKAction.sequence([
                SKAction.wait(forDuration: TimeInterval(i) * 0.04),
                SKAction.run { [weak self] in
                    guard let self else { return }
                    let drone = ShahedDroneEntity.create(flyingPath: flyingPath)
                    drone.isFormationFlight = true

                    if let flight = drone.component(ofType: FlyingProjectileComponent.self) {
                        flight.behavior = GKBehavior()
                        flight.maxSpeed = 0
                    }

                    drone.addComponent(AltitudeComponent(altitude: .low))
                    let shadow = ShadowComponent()
                    drone.addComponent(shadow)
                    self.shadowLayer?.addChild(shadow.shadowNode)

                    if let spriteNode = drone.component(ofType: SpriteComponent.self)?.spriteNode {
                        spriteNode.zPosition = 61 + CGFloat(DroneAltitude.low.rawValue) * 5
                        spriteNode.position = capturedWaypoints[0]

                        if capturedWaypoints.count >= 2 {
                            let dx = capturedWaypoints[1].x - capturedWaypoints[0].x
                            let dy = capturedWaypoints[1].y - capturedWaypoints[0].y
                            spriteNode.zRotation = atan2(dy, dx) - .pi / 2
                        }

                        let followAction = SKAction.follow(
                            capturedCGPath,
                            asOffset: false,
                            orientToPath: false,
                            speed: capturedSpeed
                        )

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

    /// Spawn a kamikaze whose entry point is the given anchor (no edge logic).
    private func spawnKamikaze(at anchor: CGPoint) {
        let hqCenter = comboHQPoint()
        let scatterAngle = CGFloat.random(in: 0...(2 * .pi))
        let scatterDist = CGFloat.random(in: 0...40)
        let target = CGPoint(
            x: hqCenter.x + cos(scatterAngle) * scatterDist,
            y: hqCenter.y + sin(scatterAngle) * scatterDist
        )

        let kamikaze = KamikazeDroneEntity(sceneFrame: frame)
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

        kamikaze.configureFlight(from: anchor, to: target, speed: Constants.Kamikaze.speed)
        activeDrones.append(kamikaze)
        addEntity(kamikaze)
    }

    // MARK: Side-aware Shahed formation spawn

    /// Side-aware variant of `spawnShahedFormation`: when `side != .top`, the
    /// formation enters from the left or right edge instead of the top.
    func spawnShahedFormation(count: Int, formation: ShahedFormation, fromSide side: SpawnEdge) {
        guard side != .top else {
            spawnShahedFormation(count: count, formation: formation)
            return
        }
        // For side entries we keep things simple: render the offsets through
        // the same `shahedFormationOffsets` table but anchor on the left/right
        // edge and let the path generator route the formation toward HQ.
        let offsets = shahedFormationOffsets(for: formation, count: count)
        let anchor = comboSpawnPoint(forSide: side)
        spawnShahedShield(anchor: anchor, offsets: offsets)
    }

    // MARK: - Swarm Cloud Spawn

    func spawnSwarmCloud() {
        let spawnX = CGFloat.random(in: 40...(frame.width - 40))
        let spawnY = frame.height + 30
        let spawnPoint = CGPoint(x: spawnX, y: spawnY)

        let hqCenter = comboHQPoint()

        // Swarms attack AA/radar/gun towers — never the oil refinery.
        // If no combat towers exist, fall back to HQ.
        let initialTarget = nearestCombatTower(from: spawnPoint)
        let target = initialTarget?.worldPosition ?? hqCenter

        let swarm = SwarmCloudEntity(
            sceneFrame: frame,
            spawnCenter: spawnPoint,
            target: target
        )
        swarm.fallbackPoint = hqCenter
        if let initialTarget {
            swarm.setTargetTower(initialTarget)
        }
        swarm.retargetProvider = { [weak self] from in
            self?.nearestCombatTower(from: from)
        }

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
