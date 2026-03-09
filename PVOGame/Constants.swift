//
//  Constants.swift
//  PVOGame
//
//  Created by Frizer on 12.03.2023.
//

import Foundation
import CoreGraphics

class Constants{
    static let boundsBitMask : UInt32 = 0x1 << 1
    static let droneBitMask : UInt32 = 0x1 << 2
    static let bulletBitMask : UInt32 = 0x1 << 3
    static let groundBitMask : UInt32 = 0x1 << 4
    static let rocketBlastBitMask: UInt32 = 0x1 << 5
    static let mineBombBitMask: UInt32 = 0x1 << 6
    static let backgroundName = "background"
    static let groundName = "ground"
    static let menuButtonName = "menuButton"
    static let exitFromGameButtonName = "exitFromGameButtonName"
    static let cancelExitFromGameButtonName = "cancelExitFromGameButtonName"
    static let exitMenuName = "exitMenuName"
    static let noTapPoint = CGPoint(x: 0.5, y: -1)

    struct GameBalance {
        enum RocketType: String, CaseIterable {
            case standard
            case shortRangeRapid
            case interceptor
        }

        struct RocketSpec {
            let type: RocketType
            let damage: Int
            let startImpact: Int
            let blastRadius: CGFloat
            let imageName: String
            let initialSpeed: CGFloat
            let acceleration: CGFloat
            let maxSpeed: CGFloat
            let maxFlightDistance: CGFloat
            let turnSpeed: CGFloat
            let retargetInterval: TimeInterval
            let cooldown: TimeInterval
            let defaultAmmo: Int
            let ammoPerWave: Int
            let visualScale: CGFloat
        }

        static let defaultBulletDamage = 1
        static let defaultBulletStartImpact = 1450
        static let dronesPerWave = 100
        static let droneSpeed: CGFloat = 500
        static let dronePathMinNodes = 15
        static let dronePathMaxNodes = 200
        static let groundHeightRatio: CGFloat = 30
        static let gunPanelTopInset: CGFloat = 100
        static let gunPanelHeight: CGFloat = 195
        static let gunCellSize = CGSize(width: 300, height: 170)
        static let settingsButtonSize = CGSize(width: 40, height: 40)
        static let settingsButtonInsets = CGPoint(x: 20, y: 40)
        static let settingsMenuWidthRatio: CGFloat = 0.75
        static let settingsMenuHeight: CGFloat = 220
        static let defaultLives = 10
        static let scorePerDrone = 100
        static let scorePerMineLayerDrone = 250
        static let waveSpeedIncrease: CGFloat = 25
        static let waveDroneIncrease = 10
        static let isRegularDroneEnabled = true
        static let isMineLayerEnabled = false
        static let isRocketLauncherEnabled = false
        static let isInterceptorLauncherEnabled = true
        static let mineLayerBasePerWave = 1
        static let mineLayerFirstWave = 2
        static let mineBombsPerCycle = 5
        static let mineBombDropInterval: TimeInterval = 1.05
        static let mineLayerRearmCooldown: TimeInterval = 10
        static let mineLayerApproachSpeed: CGFloat = 73.3333333333
        static let mineLayerExitSpeed: CGFloat = 100
        static let mineLayerHoverMinHeightRatio: CGFloat = 0.84
        static let mineLayerHoverMaxHeightRatio: CGFloat = 0.93
        static let mineLayerDropMinTravelDistance: CGFloat = 70
        static let mineLayerEvadeSpeed: CGFloat = 106.6666666667
        static let mineLayerEvadeMinTravelDistance: CGFloat = 95
        static let mineLayerEvadeLateralStep: CGFloat = 128
        static let mineLayerEvadeForwardBias: CGFloat = 28
        static let mineLayerEvadeRepathInterval: TimeInterval = 0.06
        static let mineLayerFireCorridorHalfWidth: CGFloat = 24
        static let mineLayerFireCorridorSafetyMargin: CGFloat = 14
        static let mineLayerAimThreatLineDistance: CGFloat = 42
        static let mineLayerAimThreatEnterAngle: CGFloat = (.pi / 180) * 11
        static let mineLayerAimThreatExitAngle: CGFloat = (.pi / 180) * 14
        static let mineLayerAimThreatConfirmTime: TimeInterval = 0.11
        static let mineLayerCrashHorizontalSpeed: CGFloat = 72
        static let mineLayerCrashVerticalSpeed: CGFloat = 36
        static let mineLayerCrashDropInterval: TimeInterval = mineBombDropInterval * 0.5
        static let mineLayerCrashOutOfBoundsMargin: CGFloat = 90
        static let interceptorRangeScreenHeightRatio: CGFloat = 0.25
        static let hudFontName = "Menlo-Bold"
        static let hudFontSize: CGFloat = 18

        static let defaultRocketType: RocketType = .standard

        static let standardRocketSpec = RocketSpec(
            type: .standard,
            damage: 1,
            startImpact: 900,
            blastRadius: 100,
            imageName: "BulletY",
            initialSpeed: 40,
            acceleration: 1400,
            maxSpeed: 1700,
            maxFlightDistance: 345,
            turnSpeed: .pi * 1.4,
            retargetInterval: 0.08,
            cooldown: 0.625,
            defaultAmmo: 20,
            ammoPerWave: 10,
            visualScale: 1
        )

        static let shortRangeRapidRocketSpec = RocketSpec(
            type: .shortRangeRapid,
            damage: 1,
            startImpact: 820,
            blastRadius: 85,
            imageName: "BulletY",
            initialSpeed: 55,
            acceleration: 1500,
            maxSpeed: 1800,
            maxFlightDistance: 220,
            turnSpeed: .pi * 1.6,
            retargetInterval: 0.06,
            cooldown: 0.22,
            defaultAmmo: 36,
            ammoPerWave: 16,
            visualScale: 1
        )

        static let interceptorRocketBaseSpec = RocketSpec(
            type: .interceptor,
            damage: 1,
            startImpact: 760,
            blastRadius: 0,
            imageName: "BulletY",
            initialSpeed: 65,
            acceleration: 1600,
            maxSpeed: 1750,
            maxFlightDistance: 200,
            turnSpeed: .pi * 2.2,
            retargetInterval: 0.045,
            cooldown: 0.32,
            defaultAmmo: 100,
            ammoPerWave: 14,
            visualScale: 0.62
        )

        static func interceptorRocketSpec(forScreenHeight screenHeight: CGFloat) -> RocketSpec {
            let dynamicDistance = max(40, screenHeight * interceptorRangeScreenHeightRatio)
            return RocketSpec(
                type: interceptorRocketBaseSpec.type,
                damage: interceptorRocketBaseSpec.damage,
                startImpact: interceptorRocketBaseSpec.startImpact,
                blastRadius: interceptorRocketBaseSpec.blastRadius,
                imageName: interceptorRocketBaseSpec.imageName,
                initialSpeed: interceptorRocketBaseSpec.initialSpeed,
                acceleration: interceptorRocketBaseSpec.acceleration,
                maxSpeed: interceptorRocketBaseSpec.maxSpeed,
                maxFlightDistance: dynamicDistance,
                turnSpeed: interceptorRocketBaseSpec.turnSpeed,
                retargetInterval: interceptorRocketBaseSpec.retargetInterval,
                cooldown: interceptorRocketBaseSpec.cooldown,
                defaultAmmo: interceptorRocketBaseSpec.defaultAmmo,
                ammoPerWave: interceptorRocketBaseSpec.ammoPerWave,
                visualScale: interceptorRocketBaseSpec.visualScale
            )
        }

        static func rocketSpec(for type: RocketType) -> RocketSpec {
            switch type {
            case .standard:
                return standardRocketSpec
            case .shortRangeRapid:
                return shortRangeRapidRocketSpec
            case .interceptor:
                return interceptorRocketBaseSpec
            }
        }

        // Backward-compatible aliases for existing tests and gameplay code paths.
        static let defaultRocketAmmo = standardRocketSpec.defaultAmmo
        static let rocketAmmoPerWave = standardRocketSpec.ammoPerWave
        static let rocketCooldown: TimeInterval = standardRocketSpec.cooldown
        static let rocketStartImpact = standardRocketSpec.startImpact
        static let rocketBlastRadius: CGFloat = standardRocketSpec.blastRadius
        static let mineBombBlastRadius: CGFloat = 55
        static let rocketInitialSpeed: CGFloat = standardRocketSpec.initialSpeed
        static let rocketAcceleration: CGFloat = standardRocketSpec.acceleration
        static let rocketMaxSpeed: CGFloat = standardRocketSpec.maxSpeed
        static let rocketMaxFlightDistance: CGFloat = standardRocketSpec.maxFlightDistance
        static let rocketTurnSpeed: CGFloat = standardRocketSpec.turnSpeed
        static let rocketRetargetInterval: TimeInterval = standardRocketSpec.retargetInterval
    }
}
