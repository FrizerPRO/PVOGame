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
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let scene = InPlaySKScene(size: view.frame.size)

        view.presentScene(scene)
        RunLoop.current.run(until: Date().addingTimeInterval(0.01))

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
}
