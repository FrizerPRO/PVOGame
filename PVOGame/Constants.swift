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
        static let settingsMenuHeight: CGFloat = 270
        static let defaultLives = 10
        static let scorePerDrone = 100
        static let scorePerMineLayerDrone = 250
        static let waveSpeedIncrease: CGFloat = 25
        static let waveDroneIncrease = 10
        // Asymptotic drone speed curve: baseSpeed + maxBonus * (1 - exp(-wave * rate))
        static let droneBaseSpeed: CGFloat = 40
        static let droneMaxSpeedBonus: CGFloat = 55
        static let droneSpeedGrowthRate: CGFloat = 0.12
        static let isRegularDroneEnabled = true
        static let isMineLayerEnabled = true
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
        static let mineLayerArcMargin: CGFloat = 40
        static let mineLayerArcStepAngle: CGFloat = .pi / 6  // 30°
        static let mineLayerRetargetInterval: TimeInterval = 1.5
        static let interceptorRangeScreenHeightRatio: CGFloat = 0.25

        // Enemy missile (РСЗО/Град) constants
        static let isEnemyMissileEnabled = true
        static let enemyMissileFirstWave = 4
        static let enemyMissileBaseSpeed: CGFloat = 130
        static let enemyMissileSpeedVariance: CGFloat = 25
        static let enemyMissileBaseSalvoSize = 3
        static let enemyMissileSalvoGrowthInterval = 2
        static let enemyMissileMaxSalvoSize = 8
        static let enemyMissileSalvoSpawnDelay: TimeInterval = 6.0
        static let enemyMissileSalvoInterval: TimeInterval = 12.0
        static let enemyMissileInSalvoInterval: TimeInterval = 0.4
        static let enemyMissileScatterRadius: CGFloat = 60
        static let enemyMissileWarningTime: TimeInterval = 1.5
        static let scorePerMissile = 150
        static let resourcesPerMissileKill = 30
        static let enemyMissileHQDamage = 2

        // HARM (anti-radiation) missile constants
        static let isHarmMissileEnabled = true
        static let harmMissileFirstWave = 7
        static let harmMissileBaseSpeed: CGFloat = 220
        static let harmMissileSpeedVariance: CGFloat = 30
        static let harmMissileBaseSalvoSize = 3
        static let harmMissileSalvoGrowthInterval = 2
        static let harmMissileMaxSalvoSize = 8
        static let harmMissileSalvoSpawnDelay: TimeInterval = 8.0
        static let harmMissileSalvoInterval: TimeInterval = 12.0
        static let harmMissileInSalvoInterval: TimeInterval = 0.35
        static let harmMissileWarningTime: TimeInterval = 2.0
        static let harmMissileTowerDamage = 2
        static let scorePerHarmMissile = 200
        static let resourcesPerHarmMissileKill = 40

        static let hudFontName = "Menlo-Bold"
        static let hudFontSize: CGFloat = 18

        static let defaultRocketType: RocketType = .standard

        static let standardRocketSpec = RocketSpec(
            type: .standard,
            damage: 3,
            startImpact: 900,
            blastRadius: 0,
            imageName: "BulletY",
            initialSpeed: 40,
            acceleration: 1400,
            maxSpeed: 1700,
            maxFlightDistance: 400,
            turnSpeed: .pi * 1.4,
            retargetInterval: 0.18,
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
            retargetInterval: 0.14,
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
            retargetInterval: 0.12,
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
        static let bombFallSpeed: CGFloat = 150
        static let mineLayerSpawnDelay: TimeInterval = 5.0
        static let mineLayerSpawnInterval: TimeInterval = 8.0
        static let mineLayerThreatAwarenessTime: TimeInterval = 3.0
        static let rocketInitialSpeed: CGFloat = standardRocketSpec.initialSpeed
        static let rocketAcceleration: CGFloat = standardRocketSpec.acceleration
        static let rocketMaxSpeed: CGFloat = standardRocketSpec.maxSpeed
        static let rocketMaxFlightDistance: CGFloat = standardRocketSpec.maxFlightDistance
        static let rocketTurnSpeed: CGFloat = standardRocketSpec.turnSpeed
        static let rocketRetargetInterval: TimeInterval = standardRocketSpec.retargetInterval
    }

    // MARK: - Tower Defense Constants
    struct TowerDefense {
        static let gridRows = 16
        static let gridCols = 10

        static let startingResources = 500
        static let resourcesPerDroneKill = 20
        static let resourcesPerMineLayerKill = 50
        static let waveCompletionBonus = 100
        static let sellRefundPercent: CGFloat = 0.6

        static let autocannonCost = 100
        static let ciwsCost = 200
        static let samCost = 350
        static let interceptorCost = 250
        static let radarCost = 150
        static let pzrkCost = 50
        static let gepardCost = 175
        static let upgradeCostMultiplier: CGFloat = 1.5

        static let hqLives = 20
    }

    // MARK: - Kamikaze Drone Constants
    struct Kamikaze {
        static let isEnabled = true
        static let firstWave = 5
        static let speed: CGFloat = 40
        static let health = 1
        static let hqDamage = 3
        static let towerDamage = 2
        static let reward = 10
        static let scorePerKill = 50
        static let spawnBatchMin = 5
        static let spawnBatchMax = 8
        static let spawnInterval: TimeInterval = 0.3
        static let spriteScale: CGFloat = 0.5
        static let spawnDelay: TimeInterval = 4.0
    }

    // MARK: - Night Wave Constants
    struct NightWave {
        static let overlayAlpha: CGFloat = 1.0
        static let transitionDuration: TimeInterval = 2.0
        static let nightWaveInterval = 4
        static let firstNightWave = 3
        static let nightEffectZPosition: CGFloat = 91
    }

    // MARK: - EW (Electronic Warfare) Constants
    struct EW {
        // Enemy EW drone
        static let isEWDroneEnabled = true
        static let ewDroneFirstWave = 6
        static let ewDroneSpeed: CGFloat = 60
        static let ewDroneHealth = 4
        static let ewDroneJamRadius: CGFloat = 150
        static let ewDroneAccuracyMultiplier: CGFloat = 0.4
        static let ewDroneTurnRateMultiplier: CGFloat = 0.5
        static let ewDroneReward = 60
        static let ewDroneScore = 300
        // Player EW tower
        static let ewTowerCost = 175
        static let ewTowerRange: CGFloat = 120
        static let ewTowerSlowMultiplier: CGFloat = 0.6
        static let ewTowerFPVKillChance: CGFloat = 0.25
        static let ewTowerFPVKillInterval: TimeInterval = 0.5
    }

    // MARK: - Ability Constants
    struct Abilities {
        // Fighter
        static let fighterCooldown: TimeInterval = 90
        static let fighterMaxKills = 5
        static let fighterFlyDuration: TimeInterval = 0.8
        static let fighterZPosition: CGFloat = 85
        // Barrage
        static let barrageCooldown: TimeInterval = 60
        static let barrageDelay: TimeInterval = 2.0
        static let barrageExplosionCount = 5
        static let barrageRadius: CGFloat = 80
        static let barrageDamage = 3
        // Emergency Reload
        static let reloadCooldown: TimeInterval = 15
        // UI
        static let abilityButtonSize: CGFloat = 50
        static let abilityButtonZPosition: CGFloat = 98
    }

    // MARK: - Advanced Enemy Constants
    struct AdvancedEnemies {
        // Heavy Drone (Bayraktar)
        static let heavyDroneFirstWave = 7
        static let heavyDroneSpeed: CGFloat = 25
        static let heavyDroneHealth = 12
        static let heavyDroneArmor = 2
        static let heavyDroneBombCount = 2
        static let heavyDroneExitSpeed: CGFloat = 80
        static let heavyDroneSpriteScale: CGFloat = 1.4
        static let heavyDroneReward = 80
        static let heavyDroneScore = 300
        // Cruise Missile
        static let cruiseMissileFirstWave = 8
        static let cruiseMissileMinSpeed: CGFloat = 150
        static let cruiseMissileMaxSpeed: CGFloat = 200
        static let cruiseMissileHealth = 3
        static let cruiseMissileHQDamage = 4
        static let cruiseMissileEvasionRadius: CGFloat = 60
        static let cruiseMissileMaxEvasions = 3
        static let cruiseMissileEvasionAngle: CGFloat = .pi / 3  // 60°
        static let cruiseMissileDiveChance: CGFloat = 0.3
        static let cruiseMissileDiveDuration: TimeInterval = 1.5
        static let cruiseMissileScore = 250
        static let cruiseMissileReward = 45
        // Swarm
        static let swarmFirstWave = 10
        static let swarmDroneCount = 15
        static let swarmDroneHealth = 1
        static let swarmSeparation: CGFloat = 12
        static let swarmCohesion: CGFloat = 15
        static let swarmSpeed: CGFloat = 50
        static let swarmScore = 30  // per drone
        static let swarmReward = 8  // per drone
        static let swarmMaxBlastKills = 6
        static let swarmDisorganizedSpeed: CGFloat = 65
        static let swarmFanAngle: CGFloat = .pi / 4
    }

    // MARK: - Shahed-136 Constants
    struct Shahed {
        static let firstWave = 6
        static let speed: CGFloat = 50
        static let health = 2
        static let reward = 8
        static let scorePerKill = 30
        static let batchSize = 10      // drones per spawn batch
        static let spawnInterval: TimeInterval = 0.5  // between drones in a batch
        static let batchDelay: TimeInterval = 8.0     // between batches
    }

    // MARK: - Lancet Constants
    struct Lancet {
        static let firstWave = 8
        static let speed: CGFloat = 60
        static let health = 2
        static let reward = 25
        static let scorePerKill = 100
        static let loiterDuration: TimeInterval = 10.0  // circle before diving
        static let diveSpeed: CGFloat = 200
        static let towerDestroyDamage = 100  // enough to destroy any tower
        static let spawnDelay: TimeInterval = 12.0
    }

    // MARK: - Orlan-10 Constants
    struct Orlan {
        static let firstWave = 9
        static let speed: CGFloat = 40
        static let health = 4
        static let reward = 35
        static let scorePerKill = 150
        static let buffRadius: CGFloat = 999  // global effect while alive
        static let salvoIntervalMultiplier: CGFloat = 0.65  // missiles come 35% faster
        static let spawnDelay: TimeInterval = 15.0
    }

    // MARK: - Settlement Constants
    struct Settlement {
        static let count = 5
        static let minDistanceFromEdge = 2
        static let minDistanceBetween = 3
        static let minDistanceFromHQ = 3

        // HP per level
        static let baseHP = 3
        static let level2HP = 5
        static let level3HP = 8

        // Income per wave per level
        static let level1Income = 30
        static let level2Income = 60
        static let level3Income = 100

        // Upgrade costs
        static let upgradeCostLevel2 = 150
        static let upgradeCostLevel3 = 300

        // Damage to global lives
        static let droneDamageToLives = 1
        static let kamikazeDamageToLives = 2
        static let cruiseMissileDamageToLives = 3

        // Drone targeting
        static let strategicTargetingChance: CGFloat = 0.6
        static let level2TargetPriorityMultiplier: CGFloat = 1.5
        static let level3TargetPriorityMultiplier: CGFloat = 2.0

        // Visual
        static let spriteZPosition: CGFloat = 15
    }

    static let hqName = "headquarters"
    static let towerBitMask: UInt32 = 0x1 << 7
    static let kamikazeBitMask: UInt32 = 0x1 << 8
    static let settlementBitMask: UInt32 = 0x1 << 9
}
