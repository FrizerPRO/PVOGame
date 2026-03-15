//
//  PVOGameTests.swift
//  PVOGameTests
//
//  Created by Frizer on 01.12.2022.
//

import XCTest
import UIKit
import SpriteKit
@testable import PVOGame

final class PVOGameTests: XCTestCase {

    // MARK: - Helpers

    private func makeScene() -> (scene: InPlaySKScene, view: SKView) {
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let scene = InPlaySKScene(size: view.frame.size)
        view.presentScene(scene)
        var attempts = 0
        while scene.view == nil && attempts < 12 {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
            attempts += 1
        }
        return (scene, view)
    }

    private func makeDetachedDrone() -> AttackDroneEntity {
        let path = FlyingPath(
            topLevel: 844,
            bottomLevel: 0,
            leadingLevel: 0,
            trailingLevel: 390,
            startLevel: 844,
            endLevel: 0,
            pathGenerator: { _ in
                [vector_float2(x: 195, y: 844), vector_float2(x: 195, y: 0)]
            }
        )
        return AttackDroneEntity(damage: 1, speed: 500, imageName: "Drone", flyingPath: path)
    }

    private func advanceScene(
        _ scene: InPlaySKScene,
        seconds: TimeInterval,
        currentTime: inout TimeInterval,
        step: TimeInterval = 0.016
    ) {
        let targetTime = currentTime + seconds
        while currentTime < targetTime {
            currentTime += step
            scene.update(currentTime)
        }
    }

    // MARK: - Grid Tests

    func testGridMapCreation() {
        let grid = GridMap(
            rows: 16, cols: 10,
            cellSize: CGSize(width: 30, height: 30),
            origin: CGPoint(x: 10, y: 50)
        )
        XCTAssertEqual(grid.rows, 16)
        XCTAssertEqual(grid.cols, 10)
        XCTAssertNotNil(grid.cell(atRow: 0, col: 0))
        XCTAssertNil(grid.cell(atRow: -1, col: 0))
        XCTAssertNil(grid.cell(atRow: 16, col: 0))
    }

    func testGridMapCanPlaceTower() {
        let grid = GridMap(
            rows: 4, cols: 4,
            cellSize: CGSize(width: 30, height: 30),
            origin: .zero
        )
        // All cells default to .ground — should be placeable
        XCTAssertTrue(grid.canPlaceTower(atRow: 0, col: 0))
        XCTAssertTrue(grid.canPlaceTower(atRow: 3, col: 3))

        // Place tower
        grid.placeTower(ObjectIdentifier(NSObject()), atRow: 1, col: 1)
        XCTAssertFalse(grid.canPlaceTower(atRow: 1, col: 1))

        // Out of bounds
        XCTAssertFalse(grid.canPlaceTower(atRow: -1, col: 0))
        XCTAssertFalse(grid.canPlaceTower(atRow: 0, col: 10))
    }

    func testGridMapPlaceAndRemoveTower() {
        let grid = GridMap(
            rows: 4, cols: 4,
            cellSize: CGSize(width: 30, height: 30),
            origin: .zero
        )
        let id = ObjectIdentifier(NSObject())
        XCTAssertTrue(grid.placeTower(id, atRow: 2, col: 2))
        XCTAssertFalse(grid.canPlaceTower(atRow: 2, col: 2))
        grid.removeTower(atRow: 2, col: 2)
        XCTAssertTrue(grid.canPlaceTower(atRow: 2, col: 2))
    }

    func testGridMapWorldPositionAndBack() {
        let grid = GridMap(
            rows: 4, cols: 4,
            cellSize: CGSize(width: 30, height: 30),
            origin: CGPoint(x: 10, y: 50)
        )
        let worldPos = grid.worldPosition(forRow: 0, col: 0)
        // Row 0 is the top row -> mapped to highest Y
        XCTAssertGreaterThan(worldPos.y, 100)

        let gridPos = grid.gridPosition(for: worldPos)
        XCTAssertNotNil(gridPos)
        XCTAssertEqual(gridPos?.row, 0)
        XCTAssertEqual(gridPos?.col, 0)
    }

    func testGridMapLoadLevel() {
        let grid = GridMap(
            rows: 4, cols: 4,
            cellSize: CGSize(width: 30, height: 30),
            origin: .zero
        )
        let level = LevelDefinition(
            gridLayout: [
                [0, 1, 0, 0],
                [0, 1, 0, 0],
                [0, 1, 0, 0],
                [0, 3, 0, 0],
            ],
            dronePaths: [],
            waves: [],
            startingResources: 500
        )
        grid.loadLevel(level)
        XCTAssertEqual(grid.cell(atRow: 0, col: 0)?.terrain, .ground)
        XCTAssertEqual(grid.cell(atRow: 0, col: 1)?.terrain, .flightPath)
        XCTAssertEqual(grid.cell(atRow: 3, col: 1)?.terrain, .headquarters)

        // Can't place on flight path
        XCTAssertFalse(grid.canPlaceTower(atRow: 0, col: 1))
        // Can't place on HQ
        XCTAssertFalse(grid.canPlaceTower(atRow: 3, col: 1))
    }

    // MARK: - Economy Tests

    func testEconomyManager() {
        let economy = EconomyManager(startingResources: 500)
        XCTAssertEqual(economy.resources, 500)
        XCTAssertTrue(economy.canAfford(100))
        XCTAssertTrue(economy.spend(100))
        XCTAssertEqual(economy.resources, 400)
        XCTAssertFalse(economy.canAfford(500))
        XCTAssertFalse(economy.spend(500))
        XCTAssertEqual(economy.resources, 400)
        economy.earn(200)
        XCTAssertEqual(economy.resources, 600)
    }

    func testEconomyReset() {
        let economy = EconomyManager(startingResources: 500)
        economy.spend(300)
        economy.reset(to: 1000)
        XCTAssertEqual(economy.resources, 1000)
    }

    // MARK: - Tower Stats Tests

    func testTowerStatsUpgrade() {
        let stats = TowerStatsComponent(
            towerType: .autocannon,
            range: 100,
            fireRate: 8,
            damage: 1,
            reachableAltitudes: [.low, .medium],
            cost: 100
        )
        XCTAssertEqual(stats.level, 1)

        let cost = stats.upgrade()
        XCTAssertEqual(stats.level, 2)
        XCTAssertGreaterThan(cost, 0)
        XCTAssertGreaterThan(stats.range, 100)
        XCTAssertGreaterThan(stats.fireRate, 8)

        let cost2 = stats.upgrade()
        XCTAssertEqual(stats.level, 3)
        XCTAssertGreaterThan(cost2, 0)
        XCTAssertTrue(stats.reachableAltitudes.contains(.high)) // autocannon gets .high at level 3

        // Can't upgrade past level 3
        let cost3 = stats.upgrade()
        XCTAssertEqual(cost3, 0)
        XCTAssertEqual(stats.level, 3)
    }

    func testTowerTypeCosts() {
        XCTAssertEqual(TowerType.autocannon.cost, Constants.TowerDefense.autocannonCost)
        XCTAssertEqual(TowerType.ciws.cost, Constants.TowerDefense.ciwsCost)
        XCTAssertEqual(TowerType.samLauncher.cost, Constants.TowerDefense.samCost)
        XCTAssertEqual(TowerType.interceptor.cost, Constants.TowerDefense.interceptorCost)
        XCTAssertEqual(TowerType.radar.cost, Constants.TowerDefense.radarCost)
    }

    func testTowerTypeAltitudes() {
        XCTAssertTrue(TowerType.autocannon.reachableAltitudes.contains(.micro))
        XCTAssertTrue(TowerType.autocannon.reachableAltitudes.contains(.low))
        XCTAssertTrue(TowerType.autocannon.reachableAltitudes.contains(.medium))
        XCTAssertTrue(TowerType.ciws.reachableAltitudes.contains(.micro))
        XCTAssertTrue(TowerType.ciws.reachableAltitudes.contains(.low))
        XCTAssertFalse(TowerType.samLauncher.reachableAltitudes.contains(.micro))
        XCTAssertFalse(TowerType.interceptor.reachableAltitudes.contains(.micro))
        XCTAssertTrue(TowerType.radar.reachableAltitudes.isEmpty)
    }

    // MARK: - Tower Entity Tests

    func testTowerEntityCreation() {
        let tower = TowerEntity(
            towerType: .autocannon,
            at: (row: 5, col: 3),
            worldPosition: CGPoint(x: 100, y: 200)
        )
        XCTAssertEqual(tower.towerType, .autocannon)
        XCTAssertNotNil(tower.stats)
        XCTAssertNotNil(tower.component(ofType: SpriteComponent.self))
        XCTAssertNotNil(tower.component(ofType: GridPositionComponent.self))
        XCTAssertNotNil(tower.component(ofType: TowerTargetingComponent.self))
        XCTAssertNotNil(tower.component(ofType: TowerRotationComponent.self))

        let gridPos = tower.component(ofType: GridPositionComponent.self)!
        XCTAssertEqual(gridPos.row, 5)
        XCTAssertEqual(gridPos.col, 3)
    }

    func testTowerRangeIndicator() {
        let tower = TowerEntity(
            towerType: .samLauncher,
            at: (row: 5, col: 3),
            worldPosition: CGPoint(x: 100, y: 200)
        )
        let spriteNode = tower.component(ofType: SpriteComponent.self)!.spriteNode

        tower.showRangeIndicator()
        XCTAssertEqual(spriteNode.children.count, 1) // range circle

        tower.hideRangeIndicator()
        XCTAssertEqual(spriteNode.children.count, 0)
    }

    // MARK: - Altitude Tests

    func testDroneAltitudeProperties() {
        XCTAssertEqual(DroneAltitude.low.shadowScale, 1.0)
        XCTAssertGreaterThan(DroneAltitude.low.shadowScale, DroneAltitude.medium.shadowScale)
        XCTAssertGreaterThan(DroneAltitude.medium.shadowScale, DroneAltitude.high.shadowScale)

        XCTAssertEqual(DroneAltitude.low.droneVisualScale, 1.0)
        XCTAssertLessThan(DroneAltitude.high.droneVisualScale, 1.0)
    }

    func testAltitudeComponent() {
        let comp = AltitudeComponent(altitude: .medium)
        XCTAssertEqual(comp.altitude, .medium)
        comp.altitude = .high
        XCTAssertEqual(comp.altitude, .high)
    }

    // MARK: - Shadow Tests

    func testShadowComponent() {
        let shadow = ShadowComponent()
        XCTAssertNotNil(shadow.shadowNode)

        let pos = CGPoint(x: 100, y: 200)
        shadow.updateShadow(dronePosition: pos, altitude: .low)
        XCTAssertEqual(
            shadow.shadowNode.position.x,
            pos.x + DroneAltitude.low.shadowOffset.x
        )

        shadow.updateShadow(dronePosition: pos, altitude: .high)
        XCTAssertEqual(
            shadow.shadowNode.position.x,
            pos.x + DroneAltitude.high.shadowOffset.x
        )
    }

    // MARK: - Flight Path Tests

    func testDroneFlightPathToFlyingPath() {
        let waypoints = [
            CGPoint(x: 100, y: 800),
            CGPoint(x: 200, y: 600),
            CGPoint(x: 100, y: 400),
            CGPoint(x: 200, y: 200),
        ]
        let flightPath = DroneFlightPath(
            waypoints: waypoints,
            altitude: .low,
            spawnEdge: .top
        )
        let flyingPath = flightPath.toFlyingPath()
        XCTAssertEqual(flyingPath.startLevel, 800)
        XCTAssertEqual(flyingPath.endLevel, 200)
    }

    func testEmptyFlightPathFallback() {
        let flightPath = DroneFlightPath(
            waypoints: [],
            altitude: .low,
            spawnEdge: .top
        )
        let flyingPath = flightPath.toFlyingPath()
        // Should produce a valid fallback path
        XCTAssertGreaterThan(flyingPath.topLevel, 0)
    }

    // MARK: - Wave Definition Tests

    func testDefaultWaveDefinition() {
        let wave1 = WaveDefinition.defaultWave(number: 1)
        XCTAssertGreaterThan(wave1.droneCount, 0)
        XCTAssertGreaterThan(wave1.speed, 0)
        XCTAssertGreaterThan(wave1.spawnInterval, 0)

        let wave10 = WaveDefinition.defaultWave(number: 10)
        XCTAssertGreaterThan(wave10.droneCount, wave1.droneCount)
        XCTAssertGreaterThan(wave10.speed, wave1.speed)
    }

    func testLevelDefinitionLevel1Exists() {
        let level = LevelDefinition.level1
        XCTAssertEqual(level.gridLayout.count, Constants.TowerDefense.gridRows)
        XCTAssertEqual(level.gridLayout.first?.count, Constants.TowerDefense.gridCols)
        XCTAssertFalse(level.dronePaths.isEmpty)
        XCTAssertFalse(level.waves.isEmpty)
        XCTAssertEqual(level.startingResources, Constants.TowerDefense.startingResources)
    }

    // MARK: - Scene Tests

    func testSceneStartsInMainMenu() {
        let (scene, _) = makeScene()
        XCTAssertEqual(scene.currentPhase, .mainMenu)
    }

    func testSceneStartGame() {
        let (scene, _) = makeScene()
        scene.startGame()
        XCTAssertEqual(scene.currentPhase, .build)
        XCTAssertEqual(scene.score, 0)
        XCTAssertEqual(scene.lives, Constants.TowerDefense.hqLives)
    }

    func testSceneStopGame() {
        let (scene, _) = makeScene()
        scene.startGame()
        XCTAssertEqual(scene.currentPhase, .build)
        scene.stopGame()
        XCTAssertEqual(scene.currentPhase, .mainMenu)
    }

    func testDroneReachingHQDoesNotReduceLivesOutsideCombat() {
        let (scene, _) = makeScene()
        scene.startGame()
        XCTAssertEqual(scene.currentPhase, .build)

        let initialLives = scene.lives
        // onDroneReachedHQ should be no-op outside combat
        scene.onDroneReachedHQ(drone: nil)
        XCTAssertEqual(scene.lives, initialLives)
    }

    func testDroneDestroyedRequiresCombat() {
        let (scene, _) = makeScene()
        scene.startGame()
        XCTAssertEqual(scene.score, 0)
        // onDroneDestroyed should be no-op outside combat
        scene.onDroneDestroyed(drone: nil)
        XCTAssertEqual(scene.score, 0)
    }

    func testStartGameResetsState() {
        let (scene, _) = makeScene()
        scene.startGame()
        XCTAssertEqual(scene.currentPhase, .build)
        XCTAssertEqual(scene.lives, Constants.TowerDefense.hqLives)
        XCTAssertEqual(scene.score, 0)
        XCTAssertEqual(scene.dronesDestroyed, 0)
    }

    // MARK: - Fire Control Tests

    func testFireControlStateReset() {
        var fc = FireControlState()
        fc.reset()
        XCTAssertTrue(fc.decisionLog.isEmpty)
    }

    func testFireControlPlanLaunchNoTracks() {
        var fc = FireControlState()
        let profile = FireControlState.PlanningProfile(
            blastRadius: 100,
            maxRange: nil,
            nominalSpeed: 200,
            acceleration: 1400,
            maxSpeed: 1700
        )
        let plan = fc.planLaunch(
            preferredPoint: nil,
            origin: CGPoint(x: 195, y: 100),
            reservingAssignments: false,
            excludingRocketID: nil,
            profile: profile
        )
        XCTAssertNil(plan)
    }

    func testFireControlSquaredDistance() {
        let a = CGPoint(x: 0, y: 0)
        let b = CGPoint(x: 3, y: 4)
        XCTAssertEqual(FireControlState.squaredDistance(a, b), 25)
    }

    // MARK: - Bullet / Rocket Tests

    func testBulletEntityCreation() {
        let bullet = BulletEntity(damage: 1, startImpact: 1450, imageName: "Bullet")
        XCTAssertNotNil(bullet.component(ofType: SpriteComponent.self))
        XCTAssertNotNil(bullet.component(ofType: ShootComponent.self))
        XCTAssertNotNil(bullet.component(ofType: GeometryComponent.self))
    }

    func testRocketEntityCreation() {
        let spec = Constants.GameBalance.standardRocketSpec
        let rocket = RocketEntity(spec: spec)
        XCTAssertEqual(rocket.blastRadius, spec.blastRadius)
        XCTAssertFalse(rocket.detonatesOnDirectImpact) // standard has AoE
    }

    func testInterceptorRocketDirectImpact() {
        let spec = Constants.GameBalance.interceptorRocketBaseSpec
        let rocket = RocketEntity(spec: spec)
        XCTAssertTrue(rocket.detonatesOnDirectImpact) // interceptor has 0 blast radius
    }

    // MARK: - Constants Tests

    func testTowerDefenseConstants() {
        XCTAssertEqual(Constants.TowerDefense.gridRows, 16)
        XCTAssertEqual(Constants.TowerDefense.gridCols, 10)
        XCTAssertGreaterThan(Constants.TowerDefense.startingResources, 0)
        XCTAssertGreaterThan(Constants.TowerDefense.hqLives, 0)
        XCTAssertGreaterThan(Constants.TowerDefense.sellRefundPercent, 0)
        XCTAssertLessThanOrEqual(Constants.TowerDefense.sellRefundPercent, 1.0)
    }

    func testRocketSpecs() {
        let standard = Constants.GameBalance.standardRocketSpec
        let shortRange = Constants.GameBalance.shortRangeRapidRocketSpec
        let interceptor = Constants.GameBalance.interceptorRocketBaseSpec

        XCTAssertGreaterThan(standard.maxFlightDistance, shortRange.maxFlightDistance)
        XCTAssertGreaterThan(standard.blastRadius, 0)
        XCTAssertEqual(interceptor.blastRadius, 0) // interceptor = direct hit
        XCTAssertGreaterThan(shortRange.defaultAmmo, standard.defaultAmmo) // rapid has more ammo
    }

    // MARK: - Drone Entity Tests

    func testDroneEntityCanBeCreated() {
        let drone = makeDetachedDrone()
        XCTAssertNotNil(drone.component(ofType: SpriteComponent.self))
        XCTAssertNotNil(drone.component(ofType: FlyingProjectileComponent.self))
    }

    func testDroneIsHitMarking() {
        let drone = makeDetachedDrone()
        XCTAssertFalse(drone.isHit)
        drone.didHit()
        XCTAssertTrue(drone.isHit)
    }

    // MARK: - Drone HP Tests

    func testTakeDamageReducesHealth() {
        let drone = makeDetachedDrone()
        drone.configureHealth(5)
        XCTAssertEqual(drone.health, 5)
        drone.takeDamage(2)
        XCTAssertEqual(drone.health, 3)
        XCTAssertFalse(drone.isHit)
    }

    func testDroneDiesWhenHPReachesZero() {
        let drone = makeDetachedDrone()
        drone.configureHealth(3)
        drone.takeDamage(3)
        XCTAssertEqual(drone.health, 0)
        XCTAssertTrue(drone.isHit)
    }

    func testDroneDiesWhenOverkilled() {
        let drone = makeDetachedDrone()
        drone.configureHealth(2)
        drone.takeDamage(5)
        XCTAssertEqual(drone.health, 0)
        XCTAssertTrue(drone.isHit)
    }

    func testTakeDamageIgnoredWhenAlreadyHit() {
        let drone = makeDetachedDrone()
        drone.configureHealth(3)
        drone.takeDamage(3)
        XCTAssertTrue(drone.isHit)
        // Further damage should be ignored
        drone.takeDamage(1)
        XCTAssertEqual(drone.health, 0)
    }

    func testWaveDefinitionDroneHealth() {
        let wave1 = WaveDefinition.defaultWave(number: 1)
        XCTAssertEqual(wave1.droneHealth, 2) // 2 + (1-1)/2 = 2

        let wave3 = WaveDefinition.defaultWave(number: 3)
        XCTAssertEqual(wave3.droneHealth, 3) // 2 + (3-1)/2 = 3

        let wave5 = WaveDefinition.defaultWave(number: 5)
        XCTAssertEqual(wave5.droneHealth, 4) // 2 + (5-1)/2 = 4

        let wave7 = WaveDefinition.defaultWave(number: 7)
        XCTAssertEqual(wave7.droneHealth, 5) // 2 + (7-1)/2 = 5
    }

    func testWaveDefinitionSpawnBatch() {
        let wave1 = WaveDefinition.defaultWave(number: 1)
        XCTAssertEqual(wave1.spawnBatchSize, 3) // 3 + 1/2 = 3

        let wave2 = WaveDefinition.defaultWave(number: 2)
        XCTAssertEqual(wave2.spawnBatchSize, 4) // 3 + 2/2 = 4

        let wave6 = WaveDefinition.defaultWave(number: 6)
        XCTAssertEqual(wave6.spawnBatchSize, 6) // 3 + 6/2 = 6, capped at 6

        let wave10 = WaveDefinition.defaultWave(number: 10)
        XCTAssertEqual(wave10.spawnBatchSize, 6) // capped at 6

        XCTAssertGreaterThan(wave10.droneCount, wave1.droneCount)
    }

    // MARK: - Tower Durability Tests

    func testTowerDurabilityInitialization() {
        let stats = TowerStatsComponent(
            towerType: .autocannon,
            range: 100, fireRate: 8, damage: 1,
            reachableAltitudes: [.low, .medium, .micro],
            cost: 100
        )
        XCTAssertEqual(stats.durability, 3)
        XCTAssertEqual(stats.maxDurability, 3)
        XCTAssertFalse(stats.isDisabled)
    }

    func testTowerDurabilityByType() {
        XCTAssertEqual(TowerType.autocannon.baseDurability, 3)
        XCTAssertEqual(TowerType.ciws.baseDurability, 2)
        XCTAssertEqual(TowerType.samLauncher.baseDurability, 1)
        XCTAssertEqual(TowerType.interceptor.baseDurability, 1)
        XCTAssertEqual(TowerType.radar.baseDurability, 1)
    }

    func testTowerRepairTimeByType() {
        XCTAssertEqual(TowerType.autocannon.baseRepairTime, 8)
        XCTAssertEqual(TowerType.ciws.baseRepairTime, 10)
        XCTAssertEqual(TowerType.samLauncher.baseRepairTime, 15)
        XCTAssertEqual(TowerType.interceptor.baseRepairTime, 12)
        XCTAssertEqual(TowerType.radar.baseRepairTime, 12)
    }

    func testTowerTakesBombDamage() {
        let stats = TowerStatsComponent(
            towerType: .autocannon,
            range: 100, fireRate: 8, damage: 1,
            reachableAltitudes: [.low, .medium, .micro],
            cost: 100
        )
        stats.takeBombDamage(1)
        XCTAssertEqual(stats.durability, 2)
        XCTAssertFalse(stats.isDisabled)

        stats.takeBombDamage(2)
        XCTAssertEqual(stats.durability, 0)
        XCTAssertTrue(stats.isDisabled)
    }

    func testTowerDisabledAutoRepair() {
        let stats = TowerStatsComponent(
            towerType: .samLauncher,
            range: 200, fireRate: 0.5, damage: 3,
            reachableAltitudes: [.low, .medium, .high],
            cost: 350
        )
        XCTAssertEqual(stats.durability, 1) // S-300 has 1 durability

        stats.takeBombDamage(1)
        XCTAssertTrue(stats.isDisabled)

        // Tick repair timer — should not repair yet
        stats.updateRepair(deltaTime: 10.0)
        XCTAssertTrue(stats.isDisabled) // 10s < 15s repairTime

        // After full repair time
        stats.updateRepair(deltaTime: 5.0)
        XCTAssertFalse(stats.isDisabled) // 10+5 = 15s >= 15s
        XCTAssertEqual(stats.durability, stats.maxDurability)
    }

    func testTowerNotRepairedWhenNotDisabled() {
        let stats = TowerStatsComponent(
            towerType: .autocannon,
            range: 100, fireRate: 8, damage: 1,
            reachableAltitudes: [.low, .medium, .micro],
            cost: 100
        )
        stats.takeBombDamage(1) // 3 -> 2
        XCTAssertFalse(stats.isDisabled)
        stats.updateRepair(deltaTime: 100) // should not repair non-disabled tower
        XCTAssertEqual(stats.durability, 2) // unchanged
    }

    // MARK: - Micro Altitude Tests

    func testMicroAltitudeProperties() {
        XCTAssertEqual(DroneAltitude.micro.droneVisualScale, 0.6)
        XCTAssertEqual(DroneAltitude.micro.displayName, "Micro")
        XCTAssertEqual(DroneAltitude.micro.shadowScale, 1.0)
    }

    func testRegularCasesExcludesMicro() {
        XCTAssertFalse(DroneAltitude.regularCases.contains(.micro))
        XCTAssertTrue(DroneAltitude.regularCases.contains(.low))
        XCTAssertTrue(DroneAltitude.regularCases.contains(.medium))
        XCTAssertTrue(DroneAltitude.regularCases.contains(.high))
    }

    func testMicroAltitudeTargeting() {
        // ZU (autocannon) can target .micro
        XCTAssertTrue(TowerType.autocannon.reachableAltitudes.contains(.micro))
        // ZRPK (ciws) can target .micro
        XCTAssertTrue(TowerType.ciws.reachableAltitudes.contains(.micro))
        // S-300 cannot target .micro
        XCTAssertFalse(TowerType.samLauncher.reachableAltitudes.contains(.micro))
        // Interceptor cannot target .micro
        XCTAssertFalse(TowerType.interceptor.reachableAltitudes.contains(.micro))
        // Radar cannot target anything
        XCTAssertFalse(TowerType.radar.reachableAltitudes.contains(.micro))
    }

    // MARK: - Tower Accuracy Tests

    func testAutocannonAccuracyVsRegular() {
        XCTAssertEqual(TowerType.autocannon.accuracy(against: .low), 0.70)
        XCTAssertEqual(TowerType.autocannon.accuracy(against: .medium), 0.70)
        XCTAssertEqual(TowerType.autocannon.accuracy(against: .high), 0.70)
    }

    func testAutocannonAccuracyVsMicro() {
        XCTAssertEqual(TowerType.autocannon.accuracy(against: .micro), 0.05)
    }

    func testCiwsAccuracyVsRegular() {
        XCTAssertEqual(TowerType.ciws.accuracy(against: .low), 0.90)
    }

    func testCiwsAccuracyVsMicro() {
        XCTAssertEqual(TowerType.ciws.accuracy(against: .micro), 0.15)
    }

    func testRocketTowersAlwaysHit() {
        for altitude in DroneAltitude.allCases {
            XCTAssertEqual(TowerType.samLauncher.accuracy(against: altitude), 1.0)
            XCTAssertEqual(TowerType.interceptor.accuracy(against: altitude), 1.0)
            XCTAssertEqual(TowerType.radar.accuracy(against: altitude), 1.0)
        }
    }

    // MARK: - Best Bombing Target Tests

    /// Helper: place a tower in the scene via TowerPlacementManager.
    private func placeTower(_ type: TowerType, row: Int, col: Int, scene: InPlaySKScene) -> TowerEntity? {
        scene.towerPlacement.selectTowerType(type)
        return scene.towerPlacement.placeTower(at: (row: row, col: col), economy: scene.economyManager)
    }

    func testBombingTargetIsolatedSAM() {
        let (scene, _) = makeScene()
        scene.startGame()

        // Place an isolated S-300 — no anti-micro tower nearby
        let sam = placeTower(.samLauncher, row: 0, col: 0, scene: scene)
        XCTAssertNotNil(sam)

        let target = scene.bestBombingTarget()
        XCTAssertTrue(target === sam, "Isolated S-300 should be a valid bombing target")
    }

    func testBombingTargetCoveredBySAMNearZU() {
        let (scene, _) = makeScene()
        scene.startGame()

        // Place S-300 and ZU adjacent (within ZU range of 120)
        let sam = placeTower(.samLauncher, row: 0, col: 0, scene: scene)
        let zu = placeTower(.autocannon, row: 0, col: 1, scene: scene)
        XCTAssertNotNil(sam)
        XCTAssertNotNil(zu)

        let target = scene.bestBombingTarget()
        XCTAssertNil(target, "S-300 covered by ZU should not be a valid bombing target")
    }

    func testBombingTargetDisabledZUDoesNotCover() {
        let (scene, _) = makeScene()
        scene.startGame()

        // Place S-300 and ZU adjacent
        let sam = placeTower(.samLauncher, row: 0, col: 0, scene: scene)
        let zu = placeTower(.autocannon, row: 0, col: 1, scene: scene)
        XCTAssertNotNil(sam)
        XCTAssertNotNil(zu)

        // Disable the ZU by depleting its durability
        zu!.stats!.takeBombDamage(zu!.stats!.maxDurability)
        XCTAssertTrue(zu!.stats!.isDisabled)

        let target = scene.bestBombingTarget()
        XCTAssertTrue(target === sam, "S-300 should be targetable when covering ZU is disabled")
    }

    func testBombingTargetOnlyAntiMicroTowersReturnsNil() {
        let (scene, _) = makeScene()
        scene.startGame()

        // Place only anti-micro towers
        let zu = placeTower(.autocannon, row: 0, col: 0, scene: scene)
        XCTAssertNotNil(zu)

        let target = scene.bestBombingTarget()
        XCTAssertNil(target, "Only anti-micro towers on field — no valid bombing target")
    }

    // MARK: - Wave Mine Layer Tests

    func testWaveDefinitionMineLayerCount() {
        let wave1 = WaveDefinition.defaultWave(number: 1)
        XCTAssertEqual(wave1.mineLayerCount, 0) // No mine layers before wave 3

        let wave3 = WaveDefinition.defaultWave(number: 3)
        XCTAssertEqual(wave3.mineLayerCount, 1) // Mine layers from wave 3+
    }
}
