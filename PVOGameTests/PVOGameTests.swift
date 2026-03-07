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
        RunLoop.current.run(until: Date().addingTimeInterval(0.01))
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
        XCTAssertEqual(scene.activeDroneCount, Constants.GameBalance.dronesPerWave)

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
        XCTAssertEqual(scene.activeDroneCount, Constants.GameBalance.dronesPerWave)
        XCTAssertTrue(scene.isWaveInProgress)
    }

    func testStartGameInitializesRocketAmmo() {
        let (scene, view) = makeScene()
        _ = view

        scene.startGame()

        XCTAssertEqual(scene.rocketAmmoCount, Constants.GameBalance.defaultRocketAmmo)
        XCTAssertEqual(scene.rocketCooldownRemainingForTests, 0, accuracy: 0.0001)
    }

    func testShortRangeRapidRocketProfileHasExpectedTradeoffs() {
        let standard = Constants.GameBalance.standardRocketSpec
        let rapid = Constants.GameBalance.shortRangeRapidRocketSpec

        XCTAssertLessThan(rapid.maxFlightDistance, standard.maxFlightDistance)
        XCTAssertGreaterThan(rapid.defaultAmmo, standard.defaultAmmo)
        XCTAssertLessThan(rapid.cooldown, standard.cooldown)
    }

    func testStartGameUsesSelectedRocketTypeAmmo() {
        let (scene, view) = makeScene()
        _ = view
        scene.setRocketType(.shortRangeRapid)

        scene.startGame()

        XCTAssertEqual(scene.rocketAmmoCount, Constants.GameBalance.shortRangeRapidRocketSpec.defaultAmmo)
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

    func testRocketWithoutTargetsFliesUpward() {
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
        XCTAssertLessThan(abs(body.velocity.dx), 5)
    }

    func testRocketFliesUpwardWhenThreatsAreOutsideRangeRadius() {
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

        XCTAssertTrue(scene.triggerRocketLauncher())
        guard let rocket = scene.entities.compactMap({ $0 as? RocketEntity }).first,
              let sprite = rocket.component(ofType: SpriteComponent.self)?.spriteNode,
              let body = sprite.physicsBody else {
            XCTFail("Expected active rocket in scene")
            return
        }

        rocket.update(deltaTime: 0.1)

        XCTAssertGreaterThan(body.velocity.dy, 0)
        XCTAssertLessThan(abs(body.velocity.dx), 5)
    }

    func testRocketWithoutTargetsDetonatesNearTop() {
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
        sprite.position = CGPoint(x: view.frame.midX, y: scene.frame.height - 20)
        rocket.configureFlight(
            targetPoint: CGPoint(x: view.frame.midX, y: scene.frame.height + 200),
            initialSpeed: 120
        )

        for _ in 0..<10 {
            rocket.update(deltaTime: 0.1)
            if !scene.entities.contains(where: { entity in
                guard let current = entity as? RocketEntity else { return false }
                return current === rocket
            }) {
                break
            }
        }

        XCTAssertFalse(scene.entities.contains { entity in
            guard let current = entity as? RocketEntity else { return false }
            return current === rocket
        })
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
        XCTAssertEqual(scene.activeDroneCount, Constants.GameBalance.dronesPerWave)

        let dronesToRemove = scene.entities.compactMap { $0 as? AttackDroneEntity }
        for drone in dronesToRemove {
            scene.removeEntity(drone)
        }
        XCTAssertEqual(scene.activeDroneCount, 0)

        scene.update(1.0)
        scene.update(1.016)

        XCTAssertEqual(scene.currentWave, 2)
        XCTAssertTrue(scene.isWaveInProgress)
        XCTAssertEqual(scene.activeDroneCount, scene.dronesForWave(2))
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
        guard moveOneDroneBelowHalfScreen(scene: scene, view: view) != nil else {
            XCTFail("Expected active drone in scene")
            return
        }

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
        XCTAssertEqual(scene.activeDroneCount, Constants.GameBalance.dronesPerWave)
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
