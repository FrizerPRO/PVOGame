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

    private func makePath(start: CGPoint, end: CGPoint) -> FlyingPath {
        FlyingPath(
            topLevel: 844,
            bottomLevel: 0,
            leadingLevel: 0,
            trailingLevel: 390,
            startLevel: start.y,
            endLevel: end.y,
            pathGenerator: { _ in
                [vector_float2(x: Float(start.x), y: Float(start.y)),
                 vector_float2(x: Float(end.x), y: Float(end.y))]
            }
        )
    }

    @discardableResult
    private func moveOneDroneBelowHalfScreen(scene: InPlaySKScene, view: SKView) -> AttackDroneEntity? {
        for _ in 0..<5 {
            if let drone = scene.entities.compactMap({ $0 as? AttackDroneEntity }).first {
                let point = CGPoint(x: view.frame.midX, y: view.frame.height * 0.45)
                setDronePosition(drone, to: point)
                return drone
            }
            scene.startGame()
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        return nil
    }

    private func moveAllDronesAboveHalfScreen(scene: InPlaySKScene, view: SKView) {
        let drones = scene.entities.compactMap { $0 as? AttackDroneEntity }
        for (index, drone) in drones.enumerated() {
            let x = CGFloat(40 + (index % 6) * 45)
            let point = CGPoint(x: x, y: view.frame.height * 0.8)
            setDronePosition(drone, to: point)
        }
    }

    private func setDronePosition(_ drone: AttackDroneEntity, to point: CGPoint) {
        if let flight = drone.component(ofType: FlyingProjectileComponent.self) {
            flight.behavior?.removeAllGoals()
            flight.position = vector_float2(x: Float(point.x), y: Float(point.y))
        }
        drone.component(ofType: SpriteComponent.self)?.spriteNode.position = point
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

    private func firstMineLayer(in scene: InPlaySKScene) -> MineLayerDroneEntity? {
        scene.entities.compactMap { $0 as? MineLayerDroneEntity }.first
    }

    private func removeRegularDrones(scene: InPlaySKScene) {
        let regularDrones = scene.entities.compactMap { $0 as? AttackDroneEntity }.filter { !($0 is MineLayerDroneEntity) }
        for drone in regularDrones {
            scene.removeEntity(drone)
        }
    }

    private func advanceToMineLayerWave(scene: InPlaySKScene) {
        guard scene.currentWave < Constants.GameBalance.mineLayerFirstWave else { return }
        var currentTime: TimeInterval = 1.0
        scene.update(currentTime)
        var safetyCounter = 0
        while scene.currentWave < Constants.GameBalance.mineLayerFirstWave && safetyCounter < 240 {
            removeRegularDrones(scene: scene)
            currentTime += 0.05
            scene.update(currentTime)
            safetyCounter += 1
        }
    }

    private func ensureGameIsPlaying(scene: InPlaySKScene) {
        if !scene.isStarted {
            scene.startGame()
        }
        if !scene.isStarted {
            scene.playAgain()
        }
    }

    private func pointGun(at target: CGPoint, in scene: InPlaySKScene) {
        guard let gunSprite = scene.mainGun?.component(ofType: SpriteComponent.self)?.spriteNode else { return }
        let dx = target.x - gunSprite.position.x
        let dy = target.y - gunSprite.position.y
        gunSprite.zRotation = atan2(dy, dx) - .pi / 2
        scene.setGunAimForTests(point: target, isTouching: true)
    }

    private func signedDistanceToGunFireLine(point: CGPoint, in scene: InPlaySKScene) -> CGFloat? {
        guard let gunSprite = scene.mainGun?.component(ofType: SpriteComponent.self)?.spriteNode else { return nil }
        let aim = CGVector(
            dx: cos(gunSprite.zRotation + .pi / 2),
            dy: sin(gunSprite.zRotation + .pi / 2)
        )
        let aimLength = sqrt(aim.dx * aim.dx + aim.dy * aim.dy)
        guard aimLength > 0.001 else { return nil }
        let normalizedAim = CGVector(dx: aim.dx / aimLength, dy: aim.dy / aimLength)
        let toPoint = CGVector(dx: point.x - gunSprite.position.x, dy: point.y - gunSprite.position.y)
        return normalizedAim.dx * toPoint.dy - normalizedAim.dy * toPoint.dx
    }

    func testGunCopyFromCopiesWeaponStats() {
        let view = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let source = PistolGun(view, shell: BulletEntity(damage: 3, startImpact: 1200, imageName: "Bullet"))
        let target = MiniGun(view, shell: BulletEntity(damage: 1, startImpact: 1450, imageName: "Bullet"))

        target.copyFrom(gun: source)

        XCTAssertEqual(target.shootingSpeed, source.shootingSpeed)
        XCTAssertEqual(target.rotateSpeed, source.rotateSpeed)
        XCTAssertEqual(target.label, source.label)
        XCTAssertEqual(target.imageName, source.imageName)
        XCTAssertEqual(target.shell.damage, source.shell.damage)
    }

    func testWeaponCellShowsRotateSpeed() {
        let view = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let gun = MiniGun(view, shell: BulletEntity(damage: 1, startImpact: 1450, imageName: "Bullet"))
        let cell = WeaponCell(frame: CGRect(x: 0, y: 0, width: 300, height: 170), imageName: gun.imageName, gunEntity: gun)

        XCTAssertEqual(cell.rotateSpeedLabel?.text, "Rotate speed : \(gun.rotateSpeed)")
    }

    func testSceneStartStopMaintainsDronePool() {
        let (scene, view) = makeScene()
        _ = view

        XCTAssertEqual(scene.availableDroneCount, Constants.GameBalance.dronesPerWave)
        XCTAssertEqual(scene.activeDroneCount, 0)

        scene.startGame()

        XCTAssertTrue(scene.isStarted)
        XCTAssertGreaterThanOrEqual(scene.activeDroneCount, Constants.GameBalance.dronesPerWave)

        scene.stopGame()

        XCTAssertFalse(scene.isStarted)
        XCTAssertEqual(scene.activeDroneCount, 0)
        XCTAssertEqual(scene.availableDroneCount, Constants.GameBalance.dronesPerWave)
    }

    func testInGameSettingsMenuHasThreeRows() {
        let menu = InGameSettingsMenu(frame: CGRect(x: 0, y: 0, width: 280, height: 220), onResume: {}, onExit: {})
        XCTAssertEqual(menu.arrangedSubviews.count, 3)
    }

    func testStartGameInitializesWaveAndStats() {
        let (scene, view) = makeScene()
        _ = view

        scene.startGame()

        XCTAssertTrue(scene.isStarted)
        XCTAssertEqual(scene.currentWave, 1)
        XCTAssertEqual(scene.score, 0)
        XCTAssertEqual(scene.lives, Constants.GameBalance.defaultLives)
        XCTAssertGreaterThanOrEqual(scene.activeDroneCount, Constants.GameBalance.dronesPerWave)
        XCTAssertTrue(scene.isWaveInProgress)
    }

    func testStartGameInitializesRocketAmmo() {
        let (scene, view) = makeScene()
        _ = view

        scene.startGame()

        XCTAssertEqual(scene.rocketAmmoCount, Constants.GameBalance.defaultRocketAmmo)
        XCTAssertEqual(scene.rocketCooldownRemainingForTests, 0, accuracy: 0.0001)
    }

    func testStartGameInitializesInterceptorLauncherAndRange() {
        let (scene, view) = makeScene()
        _ = view

        scene.startGame()

        XCTAssertEqual(
            scene.interceptorAmmoCountForTests,
            Constants.GameBalance.interceptorRocketBaseSpec.defaultAmmo
        )
        XCTAssertEqual(scene.interceptorCooldownRemainingForTests, 0, accuracy: 0.0001)
        XCTAssertEqual(
            scene.activeInterceptorSpecForTests.maxFlightDistance,
            scene.frame.height * Constants.GameBalance.interceptorRangeScreenHeightRatio,
            accuracy: 0.0001
        )
        guard let launcherPosition = scene.interceptorLauncherPositionForTests else {
            XCTFail("Expected interceptor launcher node")
            return
        }
        XCTAssertLessThan(launcherPosition.x, scene.frame.midX)
        XCTAssertLessThan(launcherPosition.y, scene.frame.height * 0.2)
    }

    func testShortRangeRapidRocketProfileHasExpectedTradeoffs() {
        let standard = Constants.GameBalance.standardRocketSpec
        let rapid = Constants.GameBalance.shortRangeRapidRocketSpec

        XCTAssertLessThan(rapid.maxFlightDistance, standard.maxFlightDistance)
        XCTAssertGreaterThan(rapid.defaultAmmo, standard.defaultAmmo)
        XCTAssertLessThan(rapid.cooldown, standard.cooldown)
    }

    func testAoERocketDoesNotDetonateOnDirectImpact() {
        let rocket = RocketEntity(spec: Constants.GameBalance.standardRocketSpec)
        XCTAssertFalse(rocket.detonatesOnDirectImpact)
    }

    func testInterceptorRocketDetonatesOnDirectImpact() {
        let rocket = RocketEntity(spec: Constants.GameBalance.interceptorRocketBaseSpec)
        XCTAssertTrue(rocket.detonatesOnDirectImpact)
    }

    func testStartGameUsesSelectedRocketTypeAmmo() {
        let (scene, view) = makeScene()
        _ = view
        scene.setRocketType(.shortRangeRapid)

        scene.startGame()

        XCTAssertEqual(scene.rocketAmmoCount, Constants.GameBalance.shortRangeRapidRocketSpec.defaultAmmo)
    }

    func testRightRocketTargetPrefersReachableClusterOverLargerUnreachableCluster() {
        let (scene, view) = makeScene()
        scene.setRocketType(.shortRangeRapid)
        scene.startGame()

        let drones = scene.entities.compactMap { $0 as? AttackDroneEntity }
        guard drones.count >= 7 else {
            XCTFail("Expected at least seven drones in scene")
            return
        }

        let keep = Array(drones.prefix(7))
        for drone in drones.dropFirst(7) {
            scene.removeEntity(drone)
        }

        let launchOrigin = CGPoint(x: view.frame.width * 0.9, y: view.frame.height * 0.08)
        let reachableCluster = [
            CGPoint(x: launchOrigin.x - 95, y: view.frame.height * 0.22),
            CGPoint(x: launchOrigin.x - 120, y: view.frame.height * 0.25),
            CGPoint(x: launchOrigin.x - 75, y: view.frame.height * 0.24)
        ]
        let unreachableCluster = [
            CGPoint(x: 32, y: view.frame.height * 0.30),
            CGPoint(x: 56, y: view.frame.height * 0.34),
            CGPoint(x: 74, y: view.frame.height * 0.28),
            CGPoint(x: 88, y: view.frame.height * 0.32)
        ]

        for (drone, point) in zip(keep, reachableCluster + unreachableCluster) {
            setDronePosition(drone, to: point)
        }

        let target = scene.bestRocketTargetPoint(
            origin: launchOrigin,
            radius: Constants.GameBalance.shortRangeRapidRocketSpec.maxFlightDistance,
            influenceRadius: Constants.GameBalance.shortRangeRapidRocketSpec.blastRadius,
            reservingActiveRocketImpacts: false
        )
        guard let target else {
            XCTFail("Expected a reachable target for right rocket")
            return
        }

        let reachableCenter = CGPoint(
            x: reachableCluster.map(\.x).reduce(0, +) / CGFloat(reachableCluster.count),
            y: reachableCluster.map(\.y).reduce(0, +) / CGFloat(reachableCluster.count)
        )
        let unreachableCenter = CGPoint(
            x: unreachableCluster.map(\.x).reduce(0, +) / CGFloat(unreachableCluster.count),
            y: unreachableCluster.map(\.y).reduce(0, +) / CGFloat(unreachableCluster.count)
        )
        let distanceToReachable = hypot(target.x - reachableCenter.x, target.y - reachableCenter.y)
        let distanceToUnreachable = hypot(target.x - unreachableCenter.x, target.y - unreachableCenter.y)

        XCTAssertLessThan(distanceToReachable, distanceToUnreachable)
    }

    func testRocketLauncherConsumesAmmoAndCreatesRocket() {
        let (scene, view) = makeScene()
        scene.startGame()
        guard moveOneDroneBelowHalfScreen(scene: scene, view: view) != nil else {
            XCTFail("Expected active drone in scene")
            return
        }
        XCTAssertGreaterThan(scene.activeDroneCount, 0)
        XCTAssertNotNil(scene.bestRocketTargetPoint())

        let launched = scene.triggerRocketLauncher()

        XCTAssertTrue(launched)
        XCTAssertEqual(scene.rocketAmmoCount, Constants.GameBalance.defaultRocketAmmo - 1)
        XCTAssertGreaterThan(scene.rocketCooldownRemainingForTests, 0)
        XCTAssertTrue(scene.entities.contains { $0 is RocketEntity })
    }

    func testRightRocketLaunchCreatesAimMarker() {
        let (scene, view) = makeScene()
        scene.startGame()
        let drones = scene.entities.compactMap { $0 as? AttackDroneEntity }
        guard drones.count >= 2 else {
            XCTFail("Expected at least two drones in scene")
            return
        }
        let firstDrone = drones[0]
        let secondDrone = drones[1]
        for drone in drones.dropFirst(2) {
            scene.removeEntity(drone)
        }

        let firstPoint = CGPoint(x: 110, y: view.frame.height * 0.33)
        let secondPoint = CGPoint(x: 150, y: view.frame.height * 0.33)
        setDronePosition(firstDrone, to: firstPoint)
        setDronePosition(secondDrone, to: secondPoint)

        XCTAssertEqual(scene.rocketAimMarkerCountForTests, 0)
        XCTAssertTrue(scene.triggerRocketLauncher())
        XCTAssertEqual(scene.rocketAimMarkerCountForTests, 1)

        guard let activeRocket = scene.entities
            .compactMap({ $0 as? RocketEntity })
            .first(where: { $0.spec.type == .standard })
        else {
            XCTFail("Expected active standard rocket")
            return
        }

        let target = activeRocket.guidanceTargetPointForDisplay
        let minX = min(firstPoint.x, secondPoint.x)
        let maxX = max(firstPoint.x, secondPoint.x)
        XCTAssertGreaterThan(target.x, minX + 0.5)
        XCTAssertLessThan(target.x, maxX - 0.5)
        XCTAssertEqual(target.y, firstPoint.y, accuracy: 0.75)
    }

    func testLeftRocketLaunchCreatesAimMarker() {
        let (scene, view) = makeScene()
        scene.startGame()

        let drones = scene.entities.compactMap { $0 as? AttackDroneEntity }
        guard let targetDrone = drones.first else {
            XCTFail("Expected active drone in scene")
            return
        }
        for drone in drones where drone !== targetDrone {
            scene.removeEntity(drone)
        }
        setDronePosition(targetDrone, to: CGPoint(x: 85, y: view.frame.height * 0.28))

        XCTAssertEqual(scene.rocketAimMarkerCountForTests, 0)
        XCTAssertTrue(scene.triggerInterceptorLauncher())
        XCTAssertEqual(scene.rocketAimMarkerCountForTests, 1)
    }

    func testAimMarkerRemovedAfterRocketDetonation() {
        let (scene, view) = makeScene()
        scene.startGame()
        guard moveOneDroneBelowHalfScreen(scene: scene, view: view) != nil else {
            XCTFail("Expected active drone in scene")
            return
        }
        XCTAssertTrue(scene.triggerRocketLauncher())
        XCTAssertEqual(scene.rocketAimMarkerCountForTests, 1)
        guard let rocket = scene.entities.compactMap({ $0 as? RocketEntity }).first else {
            XCTFail("Expected active rocket in scene")
            return
        }

        rocket.detonateWithAnimation()

        XCTAssertEqual(scene.rocketAimMarkerCountForTests, 0)
    }

    func testNextRocketTargetSkipsAreaReservedByActiveRocket() {
        let (scene, view) = makeScene()
        scene.startGame()

        let drones = scene.entities.compactMap { $0 as? AttackDroneEntity }
        guard drones.count >= 3 else {
            XCTFail("Expected at least three drones in scene")
            return
        }
        let clusterOneA = drones[0]
        let clusterOneB = drones[1]
        let distantDrone = drones[2]
        for drone in drones.dropFirst(3) {
            scene.removeEntity(drone)
        }

        setDronePosition(clusterOneA, to: CGPoint(x: 100, y: view.frame.height * 0.32))
        setDronePosition(clusterOneB, to: CGPoint(x: 130, y: view.frame.height * 0.32))
        setDronePosition(distantDrone, to: CGPoint(x: view.frame.width - 70, y: view.frame.height * 0.33))

        XCTAssertTrue(scene.triggerRocketLauncher())
        guard let activeRocket = scene.entities.compactMap({ $0 as? RocketEntity }).first(where: { $0.spec.type == .standard }) else {
            XCTFail("Expected active standard rocket")
            return
        }
        let firstTarget = activeRocket.guidanceTargetPointForDisplay

        let nextTarget = scene.bestRocketTargetPoint(
            origin: nil,
            radius: nil,
            influenceRadius: scene.activeRocketSpecForTests.blastRadius * 1.2,
            reservingActiveRocketImpacts: true
        )
        guard let nextTarget else {
            XCTFail("Expected next target after reserved area projection")
            return
        }

        let dx = nextTarget.x - firstTarget.x
        let dy = nextTarget.y - firstTarget.y
        XCTAssertGreaterThan(
            dx * dx + dy * dy,
            scene.activeRocketSpecForTests.blastRadius * scene.activeRocketSpecForTests.blastRadius
        )
    }

    func testSecondRightRocketDoesNotLaunchIntoFullyReservedArea() {
        let (scene, view) = makeScene()
        scene.setRocketType(.standard)
        scene.startGame()

        let drones = scene.entities.compactMap { $0 as? AttackDroneEntity }
        guard drones.count >= 2 else {
            XCTFail("Expected at least two active drones in scene")
            return
        }
        let firstDrone = drones[0]
        let secondDrone = drones[1]
        for drone in drones.dropFirst(2) {
            scene.removeEntity(drone)
        }
        setDronePosition(firstDrone, to: CGPoint(x: view.frame.width * 0.66, y: view.frame.height * 0.26))
        setDronePosition(secondDrone, to: CGPoint(x: view.frame.width * 0.70, y: view.frame.height * 0.27))

        XCTAssertTrue(scene.triggerRocketLauncher())

        let reservedTarget = scene.bestRocketTargetPoint(
            origin: nil,
            radius: nil,
            influenceRadius: scene.activeRocketSpecForTests.blastRadius,
            reservingActiveRocketImpacts: true
        )
        XCTAssertNil(reservedTarget)

        var currentTime: TimeInterval = 1.0
        scene.update(currentTime)
        advanceScene(
            scene,
            seconds: scene.rocketCooldownRemainingForTests + 0.05,
            currentTime: &currentTime,
            step: 0.05
        )
        let rocketsBeforeSecondLaunch = scene.entities.compactMap { $0 as? RocketEntity }.count
        XCTAssertFalse(scene.triggerRocketLauncher())
        XCTAssertEqual(scene.entities.compactMap { $0 as? RocketEntity }.count, rocketsBeforeSecondLaunch)
    }

    func testSequentialRightRocketPlanningPicksDifferentImpactArea() {
        let (scene, view) = makeScene()
        scene.setRocketType(.standard)
        scene.startGame()

        let drones = scene.entities.compactMap { $0 as? AttackDroneEntity }
        guard drones.count >= 4 else {
            XCTFail("Expected at least four active drones in scene")
            return
        }
        let firstClusterA = drones[0]
        let firstClusterB = drones[1]
        let secondClusterA = drones[2]
        let secondClusterB = drones[3]
        for drone in drones.dropFirst(4) {
            scene.removeEntity(drone)
        }

        setDronePosition(firstClusterA, to: CGPoint(x: 95, y: view.frame.height * 0.32))
        setDronePosition(firstClusterB, to: CGPoint(x: 130, y: view.frame.height * 0.34))
        setDronePosition(secondClusterA, to: CGPoint(x: view.frame.width - 95, y: view.frame.height * 0.31))
        setDronePosition(secondClusterB, to: CGPoint(x: view.frame.width - 130, y: view.frame.height * 0.33))

        XCTAssertTrue(scene.triggerRocketLauncher())

        let rockets = scene.entities.compactMap { $0 as? RocketEntity }.filter { $0.spec.type == .standard }
        guard let firstRocket = rockets.first else {
            XCTFail("Expected first standard rocket in flight")
            return
        }
        let firstTarget = firstRocket.guidanceTargetPointForDisplay

        let nextTarget = scene.bestRocketTargetPoint(
            origin: nil,
            radius: nil,
            influenceRadius: scene.activeRocketSpecForTests.blastRadius,
            reservingActiveRocketImpacts: true
        )
        guard let nextTarget else {
            XCTFail("Expected planned second target in another area")
            return
        }

        let targetDistance = hypot(nextTarget.x - firstTarget.x, nextTarget.y - firstTarget.y)
        XCTAssertGreaterThan(targetDistance, scene.activeRocketSpecForTests.blastRadius)
    }

    func testRightRocketReservationTracksDroneIdentityAfterTargetMoves() {
        let (scene, view) = makeScene()
        scene.setRocketType(.standard)
        scene.startGame()

        let drones = scene.entities.compactMap { $0 as? AttackDroneEntity }
        guard drones.count >= 2 else {
            XCTFail("Expected at least two active drones in scene")
            return
        }
        let firstDrone = drones[0]
        let secondDrone = drones[1]
        for drone in drones.dropFirst(2) {
            scene.removeEntity(drone)
        }

        let firstDronePoint = CGPoint(x: view.frame.width * 0.74, y: view.frame.height * 0.27)
        let secondDronePoint = CGPoint(x: view.frame.width * 0.46, y: view.frame.height * 0.31)
        setDronePosition(firstDrone, to: firstDronePoint)
        setDronePosition(secondDrone, to: secondDronePoint)

        XCTAssertTrue(scene.triggerRocketLauncher())
        guard let firstRocket = scene.entities
            .compactMap({ $0 as? RocketEntity })
            .first(where: { $0.spec.type == .standard })
        else {
            XCTFail("Expected first standard rocket in flight")
            return
        }
        let firstTarget = firstRocket.guidanceTargetPointForDisplay

        let firstDistance = hypot(firstTarget.x - firstDronePoint.x, firstTarget.y - firstDronePoint.y)
        let secondDistance = hypot(firstTarget.x - secondDronePoint.x, firstTarget.y - secondDronePoint.y)
        let reservedDrone = firstDistance <= secondDistance ? firstDrone : secondDrone
        let freeDrone = reservedDrone === firstDrone ? secondDrone : firstDrone

        let movedReservedPoint = CGPoint(x: view.frame.width * 0.62, y: view.frame.height * 0.29)
        let movedFreePoint = CGPoint(x: firstTarget.x, y: firstTarget.y)
        setDronePosition(reservedDrone, to: movedReservedPoint)
        setDronePosition(freeDrone, to: movedFreePoint)

        let nextTarget = scene.bestRocketTargetPoint(
            origin: nil,
            radius: nil,
            influenceRadius: scene.activeRocketSpecForTests.blastRadius,
            reservingActiveRocketImpacts: true
        )
        guard let nextTarget else {
            XCTFail("Expected next target while first rocket is in flight")
            return
        }

        let toReserved = hypot(nextTarget.x - movedReservedPoint.x, nextTarget.y - movedReservedPoint.y)
        let toFree = hypot(nextTarget.x - movedFreePoint.x, nextTarget.y - movedFreePoint.y)
        XCTAssertLessThan(toFree, toReserved)
    }

    func testNextInterceptorTargetSkipsDroneReservedByActiveInterceptor() {
        let (scene, view) = makeScene()
        scene.startGame()

        let drones = scene.entities.compactMap { $0 as? AttackDroneEntity }
        guard drones.count >= 2 else {
            XCTFail("Expected at least two drones in scene")
            return
        }
        let firstDrone = drones[0]
        let secondDrone = drones[1]
        for drone in drones.dropFirst(2) {
            scene.removeEntity(drone)
        }

        setDronePosition(firstDrone, to: CGPoint(x: 85, y: view.frame.height * 0.28))
        setDronePosition(secondDrone, to: CGPoint(x: 115, y: view.frame.height * 0.30))

        XCTAssertTrue(scene.triggerInterceptorLauncher())
        guard let activeInterceptor = scene.entities.compactMap({ $0 as? RocketEntity }).first(where: { $0.spec.type == .interceptor }) else {
            XCTFail("Expected active interceptor rocket")
            return
        }
        let firstTarget = activeInterceptor.guidanceTargetPointForDisplay

        guard let launchPosition = scene.interceptorLauncherPositionForTests else {
            XCTFail("Expected interceptor launcher position")
            return
        }
        let nextTarget = scene.bestRocketTargetPoint(
            origin: launchPosition,
            radius: scene.activeInterceptorSpecForTests.maxFlightDistance,
            influenceRadius: 0,
            reservingActiveRocketImpacts: true
        )
        guard let nextTarget else {
            XCTFail("Expected a non-reserved interceptor target")
            return
        }

        let dx = nextTarget.x - firstTarget.x
        let dy = nextTarget.y - firstTarget.y
        XCTAssertGreaterThan(dx * dx + dy * dy, 30 * 30)
    }

    func testInterceptorLauncherDoesNotFireWhenThreatOutsideQuarterScreenRange() {
        let (scene, view) = makeScene()
        scene.startGame()

        let drones = scene.entities.compactMap { $0 as? AttackDroneEntity }
        guard let farDrone = drones.first else {
            XCTFail("Expected active drone in scene")
            return
        }
        for drone in drones where drone !== farDrone {
            scene.removeEntity(drone)
        }
        setDronePosition(
            farDrone,
            to: CGPoint(x: view.frame.width - 20, y: view.frame.height * 0.35)
        )

        let initialAmmo = scene.interceptorAmmoCountForTests
        let launched = scene.triggerInterceptorLauncher()

        XCTAssertFalse(launched)
        XCTAssertEqual(scene.interceptorAmmoCountForTests, initialAmmo)
        XCTAssertFalse(scene.entities.contains { entity in
            guard let rocket = entity as? RocketEntity else { return false }
            return rocket.spec.type == .interceptor
        })
    }

    func testInterceptorRocketSpriteIsSmallerThanStandardRocket() {
        let (scene, view) = makeScene()
        scene.startGame()

        let drones = scene.entities.compactMap { $0 as? AttackDroneEntity }
        guard drones.count >= 2 else {
            XCTFail("Expected at least two active drones in scene")
            return
        }
        let firstDrone = drones[0]
        let secondDrone = drones[1]
        for drone in drones.dropFirst(2) {
            scene.removeEntity(drone)
        }
        // Keep two separated targets so reservation logic allows both launchers to fire.
        setDronePosition(firstDrone, to: CGPoint(x: 70, y: view.frame.height * 0.31))
        setDronePosition(secondDrone, to: CGPoint(x: 200, y: view.frame.height * 0.20))

        XCTAssertTrue(scene.triggerRocketLauncher())
        XCTAssertTrue(scene.triggerInterceptorLauncher())

        let rockets = scene.entities.compactMap { $0 as? RocketEntity }
        guard let standard = rockets.first(where: { $0.spec.type == .standard }),
              let interceptor = rockets.first(where: { $0.spec.type == .interceptor }),
              let standardSize = standard.component(ofType: SpriteComponent.self)?.spriteNode.size,
              let interceptorSize = interceptor.component(ofType: SpriteComponent.self)?.spriteNode.size
        else {
            XCTFail("Expected both standard and interceptor rockets in scene")
            return
        }

        XCTAssertLessThan(interceptorSize.width, standardSize.width)
        XCTAssertLessThan(interceptorSize.height, standardSize.height)
        XCTAssertEqual(interceptor.blastRadius, 0, accuracy: 0.0001)
    }

    func testInterceptorDetonationDoesNotCreateBlastNode() {
        let (scene, view) = makeScene()
        _ = view
        scene.startGame()
        let interceptorSpec = scene.activeInterceptorSpecForTests
        let interceptor = RocketEntity(spec: interceptorSpec)
        scene.addEntity(interceptor)
        interceptor.component(ofType: SpriteComponent.self)?.spriteNode.position = CGPoint(x: 120, y: 260)

        interceptor.detonateWithAnimation()

        XCTAssertNil(scene.childNode(withName: "//rocketBlastNode"))
        XCTAssertFalse(scene.entities.contains { entity in
            guard let rocket = entity as? RocketEntity else { return false }
            return rocket === interceptor
        })
    }

    func testInterceptorDetonationClearsReservationImmediately() {
        let (scene, view) = makeScene()
        scene.startGame()

        let drones = scene.entities.compactMap { $0 as? AttackDroneEntity }
        guard let targetDrone = drones.first else {
            XCTFail("Expected active drone in scene")
            return
        }
        for drone in drones where drone !== targetDrone {
            scene.removeEntity(drone)
        }
        setDronePosition(targetDrone, to: CGPoint(x: 95, y: view.frame.height * 0.28))

        XCTAssertTrue(scene.triggerInterceptorLauncher())
        guard let interceptor = scene.entities
            .compactMap({ $0 as? RocketEntity })
            .first(where: { $0.spec.type == .interceptor }),
              let launchPosition = scene.interceptorLauncherPositionForTests
        else {
            XCTFail("Expected active interceptor rocket")
            return
        }

        let reservedTarget = scene.bestRocketTargetPoint(
            origin: launchPosition,
            radius: scene.activeInterceptorSpecForTests.maxFlightDistance,
            influenceRadius: 0,
            reservingActiveRocketImpacts: true
        )
        XCTAssertNil(reservedTarget)

        interceptor.detonateWithAnimation()

        let availableAfterDetonation = scene.bestRocketTargetPoint(
            origin: launchPosition,
            radius: scene.activeInterceptorSpecForTests.maxFlightDistance,
            influenceRadius: 0,
            reservingActiveRocketImpacts: true
        )
        XCTAssertNotNil(availableAfterDetonation)
    }

    func testLaunchedRocketWithoutTargetsKeepsLastGuidancePoint() {
        let (scene, view) = makeScene()
        scene.startGame()
        guard moveOneDroneBelowHalfScreen(scene: scene, view: view) != nil else {
            XCTFail("Expected active drone in scene")
            return
        }
        XCTAssertNotNil(scene.bestRocketTargetPoint())
        XCTAssertTrue(scene.triggerRocketLauncher())

        let drones = scene.entities.compactMap { $0 as? AttackDroneEntity }
        for drone in drones {
            scene.removeEntity(drone)
        }
        guard let rocket = scene.entities.compactMap({ $0 as? RocketEntity }).first,
              let sprite = rocket.component(ofType: SpriteComponent.self)?.spriteNode,
              let body = sprite.physicsBody else {
            XCTFail("Expected active rocket in scene")
            return
        }

        rocket.update(deltaTime: 0.1)

        XCTAssertGreaterThan(body.velocity.dy, 0)
        XCTAssertGreaterThan(abs(body.velocity.dx), 20)
    }

    func testRocketDoesNotLaunchWhenThreatsAreOutsideRangeRadius() {
        let (scene, view) = makeScene()
        scene.setRocketType(.shortRangeRapid)
        scene.startGame()

        let drones = scene.entities.compactMap { $0 as? AttackDroneEntity }
        guard let farDrone = drones.first else {
            XCTFail("Expected active drone in scene")
            return
        }
        for drone in drones where drone !== farDrone {
            scene.removeEntity(drone)
        }
        // Below 1/2 screen so launcher can fire, but too far from launcher for short-range guidance.
        setDronePosition(farDrone, to: CGPoint(x: 8, y: view.frame.height * 0.42))

        let ammoBefore = scene.rocketAmmoCount
        XCTAssertFalse(scene.triggerRocketLauncher())
        XCTAssertEqual(scene.rocketAmmoCount, ammoBefore)
        XCTAssertFalse(scene.entities.contains { $0 is RocketEntity })
    }

    func testManualRocketClimbsWhenNoTargets() {
        let (scene, view) = makeScene()
        scene.startGame()
        moveAllDronesAboveHalfScreen(scene: scene, view: view)
        let rocket = RocketEntity(
            damage: 1,
            startImpact: Constants.GameBalance.rocketStartImpact,
            imageName: "BulletY",
            blastRadius: Constants.GameBalance.rocketBlastRadius
        )
        scene.addEntity(rocket)
        guard let sprite = rocket.component(ofType: SpriteComponent.self)?.spriteNode else {
            XCTFail("Expected active rocket in scene")
            return
        }
        sprite.position = CGPoint(x: view.frame.midX, y: scene.frame.height * 0.35)
        rocket.configureFlight(
            targetPoint: CGPoint(x: view.frame.midX + 120, y: scene.frame.height * 0.6),
            initialSpeed: 120,
            climbsWhenNoTargets: true
        )
        guard let body = sprite.physicsBody else {
            XCTFail("Expected rocket body")
            return
        }

        rocket.update(deltaTime: 0.1)

        XCTAssertGreaterThan(body.velocity.dy, 0)
        XCTAssertLessThan(abs(body.velocity.dx), 5)
    }

    func testRocketAutoFiresWhenDroneCrossesHalfScreen() {
        let (scene, view) = makeScene()
        scene.startGame()
        let initialAmmo = scene.rocketAmmoCount

        guard moveOneDroneBelowHalfScreen(scene: scene, view: view) != nil else {
            XCTFail("Expected active drone in scene")
            return
        }

        scene.evaluateAutoRocketForTests()

        XCTAssertEqual(scene.rocketAmmoCount, initialAmmo - 1)
        XCTAssertTrue(scene.entities.contains { $0 is RocketEntity })
    }

    func testAutoRocketSecondLaunchAvoidsSameClusterWhenOtherClusterExists() {
        let (scene, view) = makeScene()
        scene.setRocketType(.standard)
        scene.startGame()

        let drones = scene.entities.compactMap { $0 as? AttackDroneEntity }
        guard drones.count >= 5 else {
            XCTFail("Expected at least five active drones in scene")
            return
        }

        let clusterA = Array(drones.prefix(3))
        let clusterB = Array(drones.dropFirst(3).prefix(2))
        for drone in drones.dropFirst(5) {
            scene.removeEntity(drone)
        }

        setDronePosition(clusterA[0], to: CGPoint(x: 90, y: view.frame.height * 0.32))
        setDronePosition(clusterA[1], to: CGPoint(x: 115, y: view.frame.height * 0.30))
        setDronePosition(clusterA[2], to: CGPoint(x: 140, y: view.frame.height * 0.31))
        setDronePosition(clusterB[0], to: CGPoint(x: view.frame.width - 95, y: view.frame.height * 0.33))
        setDronePosition(clusterB[1], to: CGPoint(x: view.frame.width - 125, y: view.frame.height * 0.31))

        scene.evaluateAutoRocketForTests()
        guard let firstRocket = scene.entities
            .compactMap({ $0 as? RocketEntity })
            .first(where: { $0.spec.type == .standard })
        else {
            XCTFail("Expected first auto-launched rocket")
            return
        }
        let firstTarget = firstRocket.guidanceTargetPointForDisplay

        var currentTime: TimeInterval = 1
        scene.update(currentTime)
        advanceScene(
            scene,
            seconds: scene.rocketCooldownRemainingForTests + 0.05,
            currentTime: &currentTime,
            step: 0.05
        )
        scene.evaluateAutoRocketForTests()

        let standardRockets = scene.entities.compactMap { $0 as? RocketEntity }
            .filter { $0.spec.type == .standard }
        guard standardRockets.count >= 2 else {
            XCTFail("Expected second auto-launched rocket")
            return
        }

        let newestRocket = standardRockets.last!
        let secondTarget = newestRocket.guidanceTargetPointForDisplay
        let distance = hypot(secondTarget.x - firstTarget.x, secondTarget.y - firstTarget.y)
        XCTAssertGreaterThan(distance, scene.activeRocketSpecForTests.blastRadius * 0.75)
    }

    func testDetonatedRocketKeepsImpactLockBeforeBlastContactsResolve() {
        let (scene, view) = makeScene()
        scene.setRocketType(.standard)
        scene.startGame()

        let drones = scene.entities.compactMap { $0 as? AttackDroneEntity }
        guard drones.count >= 5 else {
            XCTFail("Expected at least five active drones in scene")
            return
        }

        let clusterA = Array(drones.prefix(3))
        let clusterB = Array(drones.dropFirst(3).prefix(2))
        for drone in drones.dropFirst(5) {
            scene.removeEntity(drone)
        }

        setDronePosition(clusterA[0], to: CGPoint(x: 92, y: view.frame.height * 0.32))
        setDronePosition(clusterA[1], to: CGPoint(x: 118, y: view.frame.height * 0.30))
        setDronePosition(clusterA[2], to: CGPoint(x: 144, y: view.frame.height * 0.31))
        setDronePosition(clusterB[0], to: CGPoint(x: view.frame.width - 96, y: view.frame.height * 0.33))
        setDronePosition(clusterB[1], to: CGPoint(x: view.frame.width - 126, y: view.frame.height * 0.31))

        XCTAssertTrue(scene.triggerRocketLauncher())
        guard let firstRocket = scene.entities
            .compactMap({ $0 as? RocketEntity })
            .first(where: { $0.spec.type == .standard })
        else {
            XCTFail("Expected first standard rocket in flight")
            return
        }
        let firstTarget = firstRocket.guidanceTargetPointForDisplay

        // Simulate immediate detonation in the same frame. Blast contacts have not yet updated drone hit state.
        firstRocket.component(ofType: SpriteComponent.self)?.spriteNode.position = firstTarget
        firstRocket.detonateWithAnimation()

        guard let immediateNextTarget = scene.bestRocketTargetPoint(
            origin: nil,
            radius: nil,
            influenceRadius: scene.activeRocketSpecForTests.blastRadius,
            reservingActiveRocketImpacts: true
        ) else {
            XCTFail("Expected second target while first impact lock is active")
            return
        }

        let distance = hypot(immediateNextTarget.x - firstTarget.x, immediateNextTarget.y - firstTarget.y)
        XCTAssertGreaterThan(distance, scene.activeRocketSpecForTests.blastRadius * 0.75)
    }

    func testRocketDoesNotAutoFireWhenDronesAreAboveHalfScreen() {
        let (scene, view) = makeScene()
        scene.startGame()
        let initialAmmo = scene.rocketAmmoCount

        moveAllDronesAboveHalfScreen(scene: scene, view: view)

        scene.evaluateAutoRocketForTests()

        XCTAssertEqual(scene.rocketAmmoCount, initialAmmo)
        XCTAssertFalse(scene.entities.contains { $0 is RocketEntity })
    }

    func testBestRocketTargetPointReturnsNilWhenNoDroneCrossedHalfScreen() {
        let (scene, view) = makeScene()
        scene.startGame()
        moveAllDronesAboveHalfScreen(scene: scene, view: view)

        XCTAssertNil(scene.bestRocketTargetPoint())
    }

    func testRocketLauncherDoesNotFireWhenNoDroneCrossedHalfScreen() {
        let (scene, view) = makeScene()
        scene.startGame()
        moveAllDronesAboveHalfScreen(scene: scene, view: view)
        let initialAmmo = scene.rocketAmmoCount

        let launched = scene.triggerRocketLauncher()

        XCTAssertFalse(launched)
        XCTAssertEqual(scene.rocketAmmoCount, initialAmmo)
        XCTAssertFalse(scene.entities.contains { $0 is RocketEntity })
    }

    func testRocketGuidanceAcceleratesAndPointsAtTarget() {
        let (scene, view) = makeScene()
        _ = view
        let rocket = RocketEntity(
            damage: 1,
            startImpact: Constants.GameBalance.rocketStartImpact,
            imageName: "BulletY",
            blastRadius: Constants.GameBalance.rocketBlastRadius
        )
        guard let sprite = rocket.component(ofType: SpriteComponent.self)?.spriteNode else {
            XCTFail("Expected rocket sprite")
            return
        }

        sprite.position = CGPoint(x: 20, y: 40)
        scene.addEntity(rocket)
        rocket.configureFlight(targetPoint: CGPoint(x: 220, y: 140), initialSpeed: 100)
        let speedBefore = rocket.currentSpeed
        rocket.update(deltaTime: 0.1)
        let speedAfter = rocket.currentSpeed

        XCTAssertGreaterThanOrEqual(speedAfter, speedBefore)
        XCTAssertTrue(sprite.zRotation.isFinite)
    }

    func testRocketCoastsAfterExceedingMaxFlightDistanceAndDetonatesAtApex() {
        let (scene, view) = makeScene()
        _ = view
        let rocket = RocketEntity(
            damage: 1,
            startImpact: Constants.GameBalance.rocketStartImpact,
            imageName: "BulletY",
            blastRadius: Constants.GameBalance.rocketBlastRadius
        )
        scene.addEntity(rocket)
        guard let sprite = rocket.component(ofType: SpriteComponent.self)?.spriteNode else {
            XCTFail("Expected rocket sprite")
            return
        }

        sprite.position = CGPoint(x: 0, y: 0)
        rocket.configureFlight(targetPoint: CGPoint(x: 500, y: 500), initialSpeed: 200)
        sprite.position = CGPoint(x: Constants.GameBalance.rocketMaxFlightDistance + 30, y: 0)
        sprite.physicsBody?.velocity = CGVector(dx: 0, dy: 80)

        rocket.update(deltaTime: 0.016)

        XCTAssertTrue(rocket.isCoastingAfterFuelExhaustion)
        XCTAssertTrue(sprite.physicsBody?.affectedByGravity ?? false)
        XCTAssertTrue(scene.entities.contains { entity in
            guard let current = entity as? RocketEntity else { return false }
            return current === rocket
        })

        sprite.physicsBody?.velocity = CGVector(dx: 0, dy: -1)
        rocket.update(deltaTime: 0.016)

        XCTAssertFalse(scene.entities.contains { entity in
            guard let current = entity as? RocketEntity else { return false }
            return current === rocket
        })
    }

    func testDroneDestroyedUpdatesScoreAndCounter() {
        let (scene, view) = makeScene()
        _ = view
        scene.startGame()

        scene.onDroneDestroyed()
        scene.onDroneDestroyed()

        XCTAssertEqual(scene.score, Constants.GameBalance.scorePerDrone * 2)
        XCTAssertEqual(scene.dronesDestroyed, 2)
    }

    func testDroneReachedGroundTriggersGameOver() {
        let (scene, view) = makeScene()
        _ = view
        scene.startGame()

        for _ in 0..<Constants.GameBalance.defaultLives {
            scene.onDroneReachedGround()
        }

        XCTAssertEqual(scene.lives, 0)
        XCTAssertTrue(scene.isGameOver)
    }

    func testDroneReachedGroundForActiveDroneDecreasesLives() {
        let (scene, view) = makeScene()
        _ = view
        scene.startGame()

        guard let activeDrone = scene.entities.compactMap({ $0 as? AttackDroneEntity }).first else {
            XCTFail("Expected active drone in scene")
            return
        }
        let initialLives = scene.lives

        scene.onDroneReachedGround(drone: activeDrone)

        XCTAssertEqual(scene.lives, initialLives - 1)
    }

    func testHitDroneReachingGroundDoesNotDecreaseLives() {
        let (scene, view) = makeScene()
        _ = view
        scene.startGame()

        guard let activeDrone = scene.entities.compactMap({ $0 as? AttackDroneEntity }).first else {
            XCTFail("Expected active drone in scene")
            return
        }
        let initialLives = scene.lives
        activeDrone.didHit()

        scene.onDroneReachedGround(drone: activeDrone)

        XCTAssertEqual(scene.lives, initialLives)
    }

    func testOutOfBoundsAliveDroneIsRemovedAndCostsLife() {
        let (scene, view) = makeScene()
        scene.startGame()

        guard let activeDrone = scene.entities.compactMap({ $0 as? AttackDroneEntity }).first,
              let sprite = activeDrone.component(ofType: SpriteComponent.self)?.spriteNode
        else {
            XCTFail("Expected active drone in scene")
            return
        }
        let initialLives = scene.lives
        let initialActive = scene.activeDroneCount
        if let flight = activeDrone.component(ofType: FlyingProjectileComponent.self) {
            flight.behavior?.removeAllGoals()
            flight.position = vector_float2(x: Float(view.frame.midX), y: -120)
        }
        sprite.position = CGPoint(x: view.frame.midX, y: -120)

        scene.update(1.0)
        scene.update(1.016)

        XCTAssertEqual(scene.lives, initialLives - 1)
        XCTAssertEqual(scene.activeDroneCount, initialActive - 1)
    }

    func testOutOfBoundsHitDroneIsRemovedWithoutLifeLoss() {
        let (scene, view) = makeScene()
        scene.startGame()

        guard let activeDrone = scene.entities.compactMap({ $0 as? AttackDroneEntity }).first,
              let sprite = activeDrone.component(ofType: SpriteComponent.self)?.spriteNode
        else {
            XCTFail("Expected active drone in scene")
            return
        }
        activeDrone.didHit()
        let initialLives = scene.lives
        let initialActive = scene.activeDroneCount
        if let flight = activeDrone.component(ofType: FlyingProjectileComponent.self) {
            flight.behavior?.removeAllGoals()
            flight.position = vector_float2(x: Float(view.frame.midX), y: -120)
        }
        sprite.position = CGPoint(x: view.frame.midX, y: -120)

        scene.update(1.0)
        scene.update(1.016)

        XCTAssertEqual(scene.lives, initialLives)
        XCTAssertEqual(scene.activeDroneCount, initialActive - 1)
    }

    func testSideOutOfBoundsAliveDroneReroutesAndLandsNaturally() {
        let (scene, view) = makeScene()
        scene.startGame()

        let allDrones = scene.entities.compactMap { $0 as? AttackDroneEntity }
        guard let testDrone = allDrones.first,
              let sprite = testDrone.component(ofType: SpriteComponent.self)?.spriteNode
        else {
            XCTFail("Expected active drone in scene")
            return
        }
        for drone in allDrones where drone !== testDrone {
            scene.removeEntity(drone)
        }
        XCTAssertEqual(scene.activeDroneCount, 1)

        let initialLives = scene.lives
        if let flight = testDrone.component(ofType: FlyingProjectileComponent.self) {
            flight.behavior?.removeAllGoals()
            flight.position = vector_float2(x: -180, y: Float(view.frame.midY))
        }
        sprite.position = CGPoint(x: -180, y: view.frame.midY)

        // Escaping via side should not instantly cost life or force hit-state.
        scene.update(1.0)
        scene.update(1.016)
        XCTAssertEqual(scene.lives, initialLives)
        XCTAssertFalse(testDrone.isHit)

        var time = 1.0
        for _ in 0..<500 {
            time += 0.016
            scene.update(time)
            if scene.lives < initialLives {
                break
            }
        }

        XCTAssertEqual(scene.lives, initialLives - 1)
    }

    func testResetFlightMovesReusedDroneToNewStartPosition() {
        let originalPath = makePath(start: CGPoint(x: 10, y: 800), end: CGPoint(x: 200, y: 10))
        let newPath = makePath(start: CGPoint(x: 350, y: 840), end: CGPoint(x: 100, y: 20))
        let drone = AttackDroneEntity(damage: 1, speed: 500, imageName: "Drone", flyingPath: originalPath)
        guard let spriteNode = drone.component(ofType: SpriteComponent.self)?.spriteNode else {
            XCTFail("Expected drone sprite node")
            return
        }

        spriteNode.position = CGPoint(x: 120, y: 12)
        drone.didHit()
        drone.resetFlight(flyingPath: newPath, speed: 650)

        XCTAssertEqual(spriteNode.position.x, 350, accuracy: 0.001)
        XCTAssertEqual(spriteNode.position.y, 840, accuracy: 0.001)
        XCTAssertFalse(drone.isHit)
        XCTAssertFalse(spriteNode.physicsBody?.affectedByGravity ?? true)
        XCTAssertEqual(
            spriteNode.physicsBody?.contactTestBitMask,
            Constants.bulletBitMask | Constants.groundBitMask
        )
    }

    func testPlayAgainRemovesGameOverOverlay() {
        let (scene, view) = makeScene()
        _ = view
        scene.startGame()

        for _ in 0..<Constants.GameBalance.defaultLives {
            scene.onDroneReachedGround()
        }
        XCTAssertTrue(scene.isGameOver)
        XCTAssertTrue(scene.hasGameOverOverlay)

        scene.playAgain()

        XCTAssertFalse(scene.isGameOver)
        XCTAssertFalse(scene.hasGameOverOverlay)
        XCTAssertEqual(scene.lives, Constants.GameBalance.defaultLives)
        XCTAssertEqual(scene.currentWave, 1)
    }

    func testWaveScalingFormula() {
        let (scene, view) = makeScene()
        _ = view

        XCTAssertEqual(scene.dronesForWave(1), 100)
        XCTAssertEqual(scene.dronesForWave(5), 140)
        XCTAssertEqual(scene.speedForWave(1), 500)
        XCTAssertEqual(scene.speedForWave(5), 600)
    }

    func testWaveAdvancesWhenAllDronesCleared() {
        let (scene, view) = makeScene()
        _ = view
        scene.startGame()

        XCTAssertEqual(scene.currentWave, 1)
        XCTAssertGreaterThanOrEqual(scene.activeDroneCount, Constants.GameBalance.dronesPerWave)

        let dronesToRemove = scene.entities.compactMap { $0 as? AttackDroneEntity }
        for drone in dronesToRemove {
            scene.removeEntity(drone)
        }
        XCTAssertEqual(scene.activeDroneCount, 0)

        scene.update(1.0)
        scene.update(1.016)

        XCTAssertEqual(scene.currentWave, 2)
        XCTAssertTrue(scene.isWaveInProgress)
        XCTAssertGreaterThanOrEqual(scene.activeDroneCount, scene.dronesForWave(2))
    }

    func testNextWaveReplenishesTenRockets() {
        let (scene, view) = makeScene()
        scene.startGame()
        guard moveOneDroneBelowHalfScreen(scene: scene, view: view) != nil else {
            XCTFail("Expected active drone in scene")
            return
        }

        XCTAssertTrue(scene.triggerRocketLauncher())
        XCTAssertEqual(scene.rocketAmmoCount, Constants.GameBalance.defaultRocketAmmo - 1)

        let dronesToRemove = scene.entities.compactMap { $0 as? AttackDroneEntity }
        for drone in dronesToRemove {
            scene.removeEntity(drone)
        }
        scene.update(1.0)
        scene.update(1.016)

        XCTAssertEqual(scene.currentWave, 2)
        XCTAssertEqual(
            scene.rocketAmmoCount,
            Constants.GameBalance.defaultRocketAmmo - 1 + Constants.GameBalance.rocketAmmoPerWave
        )
    }

    func testNextWaveReplenishesRocketsForSelectedType() {
        let (scene, view) = makeScene()
        scene.setRocketType(.shortRangeRapid)
        scene.startGame()
        guard let reachableDrone = moveOneDroneBelowHalfScreen(scene: scene, view: view) else {
            XCTFail("Expected active drone in scene")
            return
        }
        setDronePosition(
            reachableDrone,
            to: CGPoint(x: view.frame.width * 0.78, y: view.frame.height * 0.22)
        )

        let rocketSpec = Constants.GameBalance.shortRangeRapidRocketSpec
        XCTAssertTrue(scene.triggerRocketLauncher())
        XCTAssertEqual(scene.rocketAmmoCount, rocketSpec.defaultAmmo - 1)
        XCTAssertEqual(scene.rocketCooldownRemainingForTests, rocketSpec.cooldown, accuracy: 0.0001)

        let dronesToRemove = scene.entities.compactMap { $0 as? AttackDroneEntity }
        for drone in dronesToRemove {
            scene.removeEntity(drone)
        }
        scene.update(1.0)
        scene.update(1.016)

        XCTAssertEqual(scene.currentWave, 2)
        XCTAssertEqual(scene.rocketAmmoCount, rocketSpec.defaultAmmo - 1 + rocketSpec.ammoPerWave)
    }

    func testPlayAgainResetsGameAndRemovesOverlay() {
        let (scene, view) = makeScene()
        _ = view
        scene.startGame()

        for _ in 0..<Constants.GameBalance.defaultLives {
            scene.onDroneReachedGround()
        }
        XCTAssertTrue(scene.isGameOver)
        XCTAssertNotNil(scene.childNode(withName: "//playAgainButton"))

        scene.playAgain()

        XCTAssertFalse(scene.isGameOver)
        XCTAssertEqual(scene.score, 0)
        XCTAssertEqual(scene.lives, Constants.GameBalance.defaultLives)
        XCTAssertEqual(scene.currentWave, 1)
        XCTAssertNil(scene.childNode(withName: "//playAgainButton"))
        XCTAssertTrue(scene.isWaveInProgress)
        XCTAssertGreaterThanOrEqual(scene.activeDroneCount, Constants.GameBalance.dronesPerWave)
    }

    func testPlayAgainIgnoresGroundEventFromDetachedDrone() {
        let (scene, view) = makeScene()
        _ = view
        scene.startGame()

        for _ in 0..<Constants.GameBalance.defaultLives {
            scene.onDroneReachedGround()
        }
        XCTAssertTrue(scene.isGameOver)
        XCTAssertTrue(scene.hasGameOverOverlay)

        scene.playAgain()

        XCTAssertFalse(scene.isGameOver)
        XCTAssertFalse(scene.hasGameOverOverlay)
        XCTAssertEqual(scene.lives, Constants.GameBalance.defaultLives)

        let detachedDrone = makeDetachedDrone()
        scene.onDroneReachedGround(drone: detachedDrone)

        XCTAssertEqual(scene.lives, Constants.GameBalance.defaultLives)
        XCTAssertFalse(scene.isGameOver)
        XCTAssertFalse(scene.hasGameOverOverlay)
    }

    func testMineLayerSpawnsInWave() {
        let (scene, view) = makeScene()
        _ = view
        scene.setMineLayerEnabledForTests(true)
        scene.startGame()

        XCTAssertEqual(scene.currentWave, 1)
        XCTAssertEqual(scene.activeMineLayerCount, 0)

        advanceToMineLayerWave(scene: scene)

        XCTAssertEqual(scene.currentWave, Constants.GameBalance.mineLayerFirstWave)
        XCTAssertEqual(scene.activeMineLayerCount, Constants.GameBalance.mineLayerBasePerWave)
    }

    func testStartGameWithoutRegularDronesSpawnsNoRegularEnemies() {
        let (scene, view) = makeScene()
        _ = view
        scene.setRegularDronesEnabledForTests(false)
        scene.setMineLayerEnabledForTests(false)

        scene.startGame()

        XCTAssertTrue(scene.isWaveInProgress)
        XCTAssertEqual(scene.activeRegularDroneCountForTests, 0)
        XCTAssertEqual(scene.activeMineLayerCount, 0)
        XCTAssertEqual(scene.activeDroneCount, 0)
    }

    func testWaveWithDisabledRegularDronesCanSpawnMineLayerOnly() {
        let (scene, view) = makeScene()
        _ = view
        scene.setRegularDronesEnabledForTests(false)
        scene.setMineLayerEnabledForTests(true)
        scene.startGame()

        advanceToMineLayerWave(scene: scene)

        XCTAssertEqual(scene.currentWave, Constants.GameBalance.mineLayerFirstWave)
        XCTAssertEqual(scene.activeRegularDroneCountForTests, 0)
        XCTAssertEqual(scene.activeMineLayerCount, Constants.GameBalance.mineLayerBasePerWave)
        XCTAssertEqual(scene.activeDroneCount, scene.activeMineLayerCount)
    }

    func testMineLayerStartsDroppingOnlyAfterHoverStop() {
        let sceneFrame = CGRect(x: 0, y: 0, width: 390, height: 844)
        let mineLayer = MineLayerDroneEntity(sceneFrame: sceneFrame)
        mineLayer.beginCycle(in: sceneFrame)
        mineLayer.update(deltaTime: 0.45)
        XCTAssertEqual(mineLayer.bombsDroppedInCurrentCycle, 0)
    }

    func testMineLayerEvadesOnAimThreat() {
        let (scene, view) = makeScene()
        _ = view
        scene.setMineLayerEnabledForTests(true)
        scene.startGame()
        advanceToMineLayerWave(scene: scene)
        removeRegularDrones(scene: scene)
        guard let mineLayer = firstMineLayer(in: scene),
              let spriteNode = mineLayer.component(ofType: SpriteComponent.self)?.spriteNode
        else {
            XCTFail("Expected mine-layer drone in scene")
            return
        }

        let startPoint = CGPoint(x: scene.frame.midX, y: scene.frame.height * 0.87)
        mineLayer.forceHoverForTests(at: startPoint)
        pointGun(at: startPoint, in: scene)
        let initialLineDistance = abs(signedDistanceToGunFireLine(point: startPoint, in: scene) ?? 0)

        mineLayer.update(
            deltaTime: Constants.GameBalance.mineLayerAimThreatConfirmTime + 0.02
        )

        XCTAssertEqual(mineLayer.phase, .evading)
        XCTAssertEqual(scene.mineBombsDropped, 0)

        for _ in 0..<6 {
            mineLayer.update(deltaTime: 0.05)
        }

        let movedPoint = spriteNode.position
        let dx = movedPoint.x - startPoint.x
        let dy = movedPoint.y - startPoint.y
        XCTAssertGreaterThan(dx * dx + dy * dy, 30 * 30)
        let movedLineDistance = abs(signedDistanceToGunFireLine(point: movedPoint, in: scene) ?? 0)
        XCTAssertGreaterThan(movedLineDistance, initialLineDistance + 20)
    }

    func testMineLayerDoesNotEvadeWhenAimLineTooFar() {
        let (scene, view) = makeScene()
        _ = view
        scene.setMineLayerEnabledForTests(true)
        scene.startGame()
        advanceToMineLayerWave(scene: scene)
        removeRegularDrones(scene: scene)
        guard let mineLayer = firstMineLayer(in: scene) else {
            XCTFail("Expected mine-layer drone in scene")
            return
        }

        let startPoint = CGPoint(x: scene.frame.midX, y: scene.frame.height * 0.87)
        mineLayer.forceHoverForTests(at: startPoint)
        let offsetTarget = CGPoint(
            x: startPoint.x + Constants.GameBalance.mineLayerAimThreatLineDistance * 3.0,
            y: startPoint.y
        )
        pointGun(at: offsetTarget, in: scene)

        mineLayer.update(
            deltaTime: Constants.GameBalance.mineLayerAimThreatConfirmTime + 0.02
        )

        XCTAssertEqual(mineLayer.phase, .waitingForDrop)
    }

    func testMineLayerEvadesWhenAimLineIsNear() {
        let (scene, view) = makeScene()
        _ = view
        scene.setMineLayerEnabledForTests(true)
        scene.startGame()
        advanceToMineLayerWave(scene: scene)
        removeRegularDrones(scene: scene)
        guard let mineLayer = firstMineLayer(in: scene) else {
            XCTFail("Expected mine-layer drone in scene")
            return
        }

        let startPoint = CGPoint(x: scene.frame.midX, y: scene.frame.height * 0.87)
        mineLayer.forceHoverForTests(at: startPoint)
        let nearOffsetTarget = CGPoint(
            x: startPoint.x + Constants.GameBalance.mineLayerAimThreatLineDistance * 0.85,
            y: startPoint.y
        )
        pointGun(at: nearOffsetTarget, in: scene)

        mineLayer.update(
            deltaTime: Constants.GameBalance.mineLayerAimThreatConfirmTime + 0.02
        )

        XCTAssertEqual(mineLayer.phase, .evading)
    }

    func testMineLayerReroutesWhileApproachingWhenPathCrossesFireCorridor() {
        let (scene, view) = makeScene()
        _ = view
        scene.setMineLayerEnabledForTests(true)
        scene.startGame()
        advanceToMineLayerWave(scene: scene)
        removeRegularDrones(scene: scene)
        guard let mineLayer = firstMineLayer(in: scene) else {
            XCTFail("Expected mine-layer drone in scene")
            return
        }

        let startPoint = CGPoint(x: scene.frame.midX, y: scene.frame.height * 0.92)
        let hoverTarget = CGPoint(x: scene.frame.midX, y: scene.frame.height * 0.86)
        mineLayer.forceApproachForTests(from: startPoint, to: hoverTarget)
        pointGun(at: hoverTarget, in: scene)

        mineLayer.update(deltaTime: 0.02)

        XCTAssertEqual(mineLayer.phase, .evading)
        let targetDistance = abs(signedDistanceToGunFireLine(point: mineLayer.evadeTargetPointForTests, in: scene) ?? 0)
        XCTAssertGreaterThan(
            targetDistance,
            Constants.GameBalance.mineLayerFireCorridorHalfWidth
        )
    }

    func testMineLayerEvadeTargetLeavesFireCorridor() {
        let (scene, view) = makeScene()
        _ = view
        scene.setMineLayerEnabledForTests(true)
        scene.startGame()
        advanceToMineLayerWave(scene: scene)
        removeRegularDrones(scene: scene)
        guard let mineLayer = firstMineLayer(in: scene) else {
            XCTFail("Expected mine-layer drone in scene")
            return
        }

        let startPoint = CGPoint(x: scene.frame.midX, y: scene.frame.height * 0.87)
        mineLayer.forceHoverForTests(at: startPoint)
        pointGun(at: startPoint, in: scene)

        mineLayer.update(
            deltaTime: Constants.GameBalance.mineLayerAimThreatConfirmTime + 0.02
        )
        XCTAssertEqual(mineLayer.phase, .evading)

        let target = mineLayer.evadeTargetPointForTests
        let targetLineDistance = abs(signedDistanceToGunFireLine(point: target, in: scene) ?? 0)
        XCTAssertGreaterThan(
            targetLineDistance,
            Constants.GameBalance.mineLayerFireCorridorHalfWidth + Constants.GameBalance.mineLayerFireCorridorSafetyMargin
        )
    }

    func testMineLayerEvadesAgainWithoutCooldown() {
        let (scene, view) = makeScene()
        _ = view
        scene.setMineLayerEnabledForTests(true)
        scene.startGame()
        advanceToMineLayerWave(scene: scene)
        removeRegularDrones(scene: scene)
        guard let mineLayer = firstMineLayer(in: scene),
              let spriteNode = mineLayer.component(ofType: SpriteComponent.self)?.spriteNode
        else {
            XCTFail("Expected mine-layer drone in scene")
            return
        }

        let startPoint = CGPoint(x: scene.frame.midX, y: scene.frame.height * 0.87)
        mineLayer.forceHoverForTests(at: startPoint)

        pointGun(at: startPoint, in: scene)
        mineLayer.update(
            deltaTime: Constants.GameBalance.mineLayerAimThreatConfirmTime + 0.02
        )
        XCTAssertEqual(mineLayer.phase, .evading)
        scene.setGunAimForTests(point: startPoint, isTouching: false)

        for _ in 0..<40 where mineLayer.phase == .evading {
            mineLayer.update(deltaTime: 0.04)
        }
        XCTAssertEqual(mineLayer.phase, .waitingForDrop)

        let secondAimPoint = spriteNode.position
        pointGun(at: secondAimPoint, in: scene)
        mineLayer.update(
            deltaTime: Constants.GameBalance.mineLayerAimThreatConfirmTime + 0.02
        )

        XCTAssertEqual(mineLayer.phase, .evading)
        XCTAssertEqual(mineLayer.bombsDroppedInCurrentCycle, 0)
    }

    func testMineLayerDropsFiveBombsPerCycleWithoutForcedReposition() {
        let (scene, view) = makeScene()
        _ = view
        scene.setMineLayerEnabledForTests(true)
        scene.startGame()
        advanceToMineLayerWave(scene: scene)
        removeRegularDrones(scene: scene)
        guard let mineLayer = firstMineLayer(in: scene),
              let sprite = mineLayer.component(ofType: SpriteComponent.self)?.spriteNode else {
            XCTFail("Expected mine-layer drone in scene")
            return
        }
        XCTAssertNotNil(mineLayer.mineLayerDelegate)
        mineLayer.forceHoverForTests(at: sprite.position)
        for _ in 0..<(Constants.GameBalance.mineBombsPerCycle * 3) {
            mineLayer.update(deltaTime: Constants.GameBalance.mineBombDropInterval)
        }

        XCTAssertEqual(scene.mineBombsDropped, Constants.GameBalance.mineBombsPerCycle)
        let bombPositions = scene.entities
            .compactMap { $0 as? MineBombEntity }
            .compactMap { $0.component(ofType: SpriteComponent.self)?.spriteNode.position }
        let uniqueDropPoints = Set(
            bombPositions.map { point in
                "\(Int(point.x.rounded())):\(Int(point.y.rounded()))"
            }
        )
        XCTAssertEqual(uniqueDropPoints.count, 1)
    }

    func testMineLayerCrashRunMovesAwayAndDropsRemainingBombs() {
        let (scene, view) = makeScene()
        _ = view
        scene.setMineLayerEnabledForTests(true)
        scene.setRegularDronesEnabledForTests(true)
        scene.startGame()
        advanceToMineLayerWave(scene: scene)
        removeRegularDrones(scene: scene)
        guard let mineLayer = firstMineLayer(in: scene),
              let sprite = mineLayer.component(ofType: SpriteComponent.self)?.spriteNode else {
            XCTFail("Expected mine-layer drone in scene")
            return
        }

        let hoverPoint = CGPoint(x: scene.frame.width * 0.25, y: scene.frame.height * 0.88)
        mineLayer.forceHoverForTests(at: hoverPoint)
        mineLayer.update(deltaTime: Constants.GameBalance.mineBombDropInterval * 2.1)
        let droppedBeforeHit = mineLayer.bombsDroppedInCurrentCycle
        XCTAssertGreaterThan(droppedBeforeHit, 0)

        mineLayer.didHit()
        XCTAssertEqual(mineLayer.phase, .crashRun)
        let startPoint = sprite.position

        for _ in 0..<60 {
            mineLayer.update(deltaTime: 0.05)
        }

        let movedPoint = sprite.position
        XCTAssertGreaterThan(movedPoint.x, startPoint.x + 20)
        XCTAssertLessThan(movedPoint.y, startPoint.y - 8)

        let crashBombs = scene.entities
            .compactMap { $0 as? MineBombEntity }
            .filter { $0.isFromCrashedMineLayer }
        XCTAssertEqual(crashBombs.count, Constants.GameBalance.mineBombsPerCycle - droppedBeforeHit)
        if let firstCrashBomb = crashBombs.first {
            XCTAssertFalse(firstCrashBomb.canHitDrone(mineLayer))
        }
    }

    func testMineLayerDropsBombsFromHighAltitude() {
        let (scene, view) = makeScene()
        _ = view
        scene.setMineLayerEnabledForTests(true)
        scene.startGame()
        advanceToMineLayerWave(scene: scene)
        removeRegularDrones(scene: scene)

        var currentTime: TimeInterval = 2.0
        scene.update(currentTime)
        while scene.mineBombsDropped == 0 {
            advanceScene(scene, seconds: 0.1, currentTime: &currentTime, step: 0.1)
            if currentTime > 8 {
                break
            }
        }

        XCTAssertGreaterThan(scene.mineBombsDropped, 0)
        let firstMineY = scene.entities
            .compactMap { $0 as? MineBombEntity }
            .compactMap { $0.component(ofType: SpriteComponent.self)?.spriteNode.position.y }
            .max() ?? 0
        XCTAssertGreaterThan(firstMineY, scene.frame.height * 0.78)
    }

    func testMineBombGroundHitCostsLife() {
        let (scene, view) = makeScene()
        _ = view
        scene.setMineLayerEnabledForTests(true)
        scene.setRegularDronesEnabledForTests(true)
        ensureGameIsPlaying(scene: scene)
        XCTAssertEqual(scene.gameState, .playing)
        let initialLives = scene.lives

        scene.onMineReachedGround()

        XCTAssertEqual(scene.lives, initialLives - 1)
    }

    func testCrashOriginMineBombGroundHitDoesNotCostLife() {
        let (scene, view) = makeScene()
        _ = view
        scene.setMineLayerEnabledForTests(true)
        scene.setRegularDronesEnabledForTests(true)
        ensureGameIsPlaying(scene: scene)
        XCTAssertEqual(scene.gameState, .playing)
        let initialLives = scene.lives

        let mine = MineBombEntity()
        mine.configureOrigin(isFromCrashedDrone: true)
        mine.place(at: CGPoint(x: scene.frame.midX, y: scene.frame.midY))
        scene.addEntity(mine)

        scene.onMineReachedGround(mine)

        XCTAssertEqual(scene.lives, initialLives)
    }

    func testRegularMineBombContactMaskIncludesBullets() {
        let mine = MineBombEntity()
        mine.configureOrigin(isFromCrashedDrone: false)
        guard let contactMask = mine.component(ofType: GeometryComponent.self)?.geometryNode.physicsBody?.contactTestBitMask else {
            XCTFail("Expected mine physics body")
            return
        }

        XCTAssertNotEqual(contactMask & Constants.bulletBitMask, 0)
        XCTAssertNotEqual(contactMask & Constants.groundBitMask, 0)
        XCTAssertEqual(contactMask & Constants.droneBitMask, 0)
    }

    func testCrashOriginMineBombContactMaskIgnoresBullets() {
        let mine = MineBombEntity()
        mine.configureOrigin(isFromCrashedDrone: true)
        guard let contactMask = mine.component(ofType: GeometryComponent.self)?.geometryNode.physicsBody?.contactTestBitMask else {
            XCTFail("Expected mine physics body")
            return
        }

        XCTAssertEqual(contactMask & Constants.bulletBitMask, 0)
        XCTAssertNotEqual(contactMask & Constants.groundBitMask, 0)
        XCTAssertNotEqual(contactMask & Constants.droneBitMask, 0)
    }

    func testRocketBlastDoesNotDestroyMineBomb() {
        let (scene, view) = makeScene()
        _ = view
        scene.setMineLayerEnabledForTests(true)
        scene.playAgain()
        XCTAssertTrue(scene.isStarted)
        let mine = MineBombEntity()
        let position = CGPoint(x: scene.frame.midX, y: scene.frame.midY)
        mine.place(at: position)
        mine.component(ofType: GeometryComponent.self)?.geometryNode.physicsBody?.affectedByGravity = false
        scene.addEntity(mine)
        XCTAssertTrue(scene.entities.contains { current in
            guard let bomb = current as? MineBombEntity else { return false }
            return bomb === mine
        })
        scene.spawnRocketBlast(at: position, radius: 200)

        XCTAssertTrue(scene.entities.contains { current in
            guard let bomb = current as? MineBombEntity else { return false }
            return bomb === mine
        })
    }

    func testMineBombShotInAirDamagesOnlyNearbyDrone() {
        let (scene, view) = makeScene()
        _ = view
        scene.setMineLayerEnabledForTests(true)
        scene.setRegularDronesEnabledForTests(true)
        ensureGameIsPlaying(scene: scene)

        let drones = scene.entities
            .compactMap { $0 as? AttackDroneEntity }
            .filter { !($0 is MineLayerDroneEntity) }
        guard drones.count >= 2 else {
            XCTFail("Expected at least two active drones")
            return
        }

        let blastCenter = CGPoint(x: scene.frame.midX, y: scene.frame.midY)
        for drone in drones {
            setDronePosition(drone, to: CGPoint(x: 32, y: scene.frame.height - 70))
        }

        let nearDrone = drones[0]
        let farDrone = drones[1]
        setDronePosition(
            nearDrone,
            to: CGPoint(
                x: blastCenter.x + Constants.GameBalance.mineBombBlastRadius * 0.35,
                y: blastCenter.y
            )
        )
        setDronePosition(
            farDrone,
            to: CGPoint(
                x: blastCenter.x + Constants.GameBalance.mineBombBlastRadius + 70,
                y: blastCenter.y
            )
        )

        let mine = MineBombEntity()
        mine.place(at: blastCenter)
        scene.addEntity(mine)
        let initialScore = scene.score

        scene.onMineShotInAir(mine)

        var currentTime: TimeInterval = 1.0
        scene.update(currentTime)
        advanceScene(scene, seconds: 0.25, currentTime: &currentTime)

        XCTAssertTrue(nearDrone.isHit)
        XCTAssertFalse(farDrone.isHit)
        XCTAssertEqual(scene.score, initialScore + Constants.GameBalance.scorePerDrone)
        XCTAssertFalse(scene.entities.contains { current in
            guard let mineEntity = current as? MineBombEntity else { return false }
            return mineEntity === mine
        })
    }

    func testCrashMineBombHitDroneDamagesNearbyDrone() {
        let (scene, view) = makeScene()
        _ = view
        scene.setMineLayerEnabledForTests(true)
        scene.setRegularDronesEnabledForTests(true)
        ensureGameIsPlaying(scene: scene)

        let drones = scene.entities
            .compactMap { $0 as? AttackDroneEntity }
            .filter { !($0 is MineLayerDroneEntity) }
        guard drones.count >= 2 else {
            XCTFail("Expected at least two active drones")
            return
        }

        let blastCenter = CGPoint(x: scene.frame.midX, y: scene.frame.midY)
        for drone in drones {
            setDronePosition(drone, to: CGPoint(x: 32, y: scene.frame.height - 70))
        }

        let nearDrone = drones[0]
        let farDrone = drones[1]
        setDronePosition(
            nearDrone,
            to: CGPoint(
                x: blastCenter.x + Constants.GameBalance.mineBombBlastRadius * 0.33,
                y: blastCenter.y
            )
        )
        setDronePosition(
            farDrone,
            to: CGPoint(
                x: blastCenter.x + Constants.GameBalance.mineBombBlastRadius + 70,
                y: blastCenter.y
            )
        )

        let mine = MineBombEntity()
        mine.configureOrigin(isFromCrashedDrone: true)
        mine.place(at: blastCenter)
        scene.addEntity(mine)
        let initialScore = scene.score

        scene.onMineHitDrone(mine, drone: nearDrone)

        var currentTime: TimeInterval = 1.0
        scene.update(currentTime)
        advanceScene(scene, seconds: 0.25, currentTime: &currentTime)

        XCTAssertTrue(nearDrone.isHit)
        XCTAssertFalse(farDrone.isHit)
        XCTAssertEqual(scene.score, initialScore + Constants.GameBalance.scorePerDrone)
        XCTAssertFalse(scene.entities.contains { current in
            guard let mineEntity = current as? MineBombEntity else { return false }
            return mineEntity === mine
        })
    }

    func testMineBombBlastRadiusIsSmallerThanRocketBlast() {
        XCTAssertLessThan(
            Constants.GameBalance.mineBombBlastRadius,
            Constants.GameBalance.rocketBlastRadius
        )
    }

    func testWaveAdvancesWithRearmingMineLayerAndAddsBonusMineLayer() {
        let (scene, view) = makeScene()
        _ = view
        scene.setMineLayerEnabledForTests(true)
        scene.startGame()
        advanceToMineLayerWave(scene: scene)
        removeRegularDrones(scene: scene)
        guard let mineLayer = firstMineLayer(in: scene) else {
            XCTFail("Expected mine-layer drone in scene")
            return
        }

        scene.mineLayerDidExitForRearm(mineLayer)
        XCTAssertEqual(scene.activeDroneCount, 0)
        XCTAssertEqual(scene.rearmingMineLayerCountForTests, 1)

        scene.update(2.0)
        scene.update(2.016)

        XCTAssertEqual(scene.currentWave, 3)
        XCTAssertEqual(
            scene.activeMineLayerCount,
            Constants.GameBalance.mineLayerBasePerWave + 1
        )
    }

    func testReturnToMenuStopsGame() {
        let (scene, view) = makeScene()
        _ = view
        scene.startGame()

        for _ in 0..<Constants.GameBalance.defaultLives {
            scene.onDroneReachedGround()
        }
        XCTAssertTrue(scene.isGameOver)

        scene.returnToMenu()

        XCTAssertFalse(scene.isStarted)
        XCTAssertFalse(scene.isGameOver)
        XCTAssertEqual(scene.activeDroneCount, 0)
    }
}
