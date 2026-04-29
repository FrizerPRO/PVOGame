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
        static let droneHealth = 3
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
        /// Horizontal padding kept inside the scene frame for mine-layer waypoints.
        static let mineLayerFrameMargin: CGFloat = 40
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
        static let harmMissileBaseSpeed: CGFloat = 280
        static let harmMissileSpeedVariance: CGFloat = 40
        /// Remaining distance fraction at which HARM enters terminal dive (×diveBoost speed).
        static let harmTerminalDiveFraction: CGFloat = 0.25
        static let harmTerminalDiveBoost: CGFloat = 1.4
        static let harmMissileBaseSalvoSize = 3
        static let harmMissileSalvoGrowthInterval = 2
        static let harmMissileMaxSalvoSize = 8
        static let harmMissileSalvoSpawnDelay: TimeInterval = 8.0
        static let harmMissileSalvoInterval: TimeInterval = 12.0
        static let harmMissileInSalvoInterval: TimeInterval = 0.35
        static let harmMissileWarningTime: TimeInterval = 2.0
        static let harmMissileTowerDamage = 100  // one-shot: HARM destroys radars/SAMs in reality
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
            imageName: "projectile_sam",
            initialSpeed: 40,
            acceleration: 1400,
            maxSpeed: 1700,
            maxFlightDistance: 400,
            turnSpeed: .pi * 1.4,
            retargetInterval: 0.18,
            cooldown: 0.625,
            defaultAmmo: 20,
            ammoPerWave: 10,
            visualScale: 1.5
        )

        static let shortRangeRapidRocketSpec = RocketSpec(
            type: .shortRangeRapid,
            damage: 1,
            startImpact: 820,
            blastRadius: 85,
            imageName: "projectile_sam",
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
            imageName: "projectile_interceptor",
            initialSpeed: 65,
            acceleration: 1600,
            maxSpeed: 1750,
            maxFlightDistance: 300,
            turnSpeed: .pi * 2.2,
            retargetInterval: 0.12,
            cooldown: 0.32,
            defaultAmmo: 100,
            ammoPerWave: 14,
            visualScale: 1
        )

        static let pzrkRocketBaseSpec = RocketSpec(
            type: interceptorRocketBaseSpec.type,
            damage: interceptorRocketBaseSpec.damage,
            startImpact: interceptorRocketBaseSpec.startImpact,
            blastRadius: interceptorRocketBaseSpec.blastRadius,
            imageName: "projectile_pzrk",
            initialSpeed: interceptorRocketBaseSpec.initialSpeed,
            acceleration: interceptorRocketBaseSpec.acceleration,
            maxSpeed: interceptorRocketBaseSpec.maxSpeed,
            maxFlightDistance: interceptorRocketBaseSpec.maxFlightDistance,
            turnSpeed: interceptorRocketBaseSpec.turnSpeed,
            retargetInterval: interceptorRocketBaseSpec.retargetInterval,
            cooldown: interceptorRocketBaseSpec.cooldown,
            defaultAmmo: interceptorRocketBaseSpec.defaultAmmo,
            ammoPerWave: interceptorRocketBaseSpec.ammoPerWave,
            // ПЗРК stays small regardless of interceptor bumps — real MANPADS
            // are shoulder-launched 9M39 Igla / FIM-92 Stinger, not bus-sized.
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
        static let oilRefineryCost = 200
        static let upgradeCostMultiplier: CGFloat = 1.5

        static let hqLives = 20
    }

    // MARK: - Kamikaze Drone Constants
    struct Kamikaze {
        static let isEnabled = true
        static let firstWave = 5
        static let speed: CGFloat = 110
        static let health = 2
        static let hqDamage = 3
        static let towerDamage = 2
        static let reward = 10
        static let scorePerKill = 50
        static let spawnBatchMin = 5
        static let spawnBatchMax = 8
        static let spawnInterval: TimeInterval = 0.3
        static let spriteScale: CGFloat = 0.5
        static let spawnDelay: TimeInterval = 4.0
        /// Distance to target at which terminal dive kicks in (×diveBoost speed).
        static let diveTriggerDistance: CGFloat = 80
        static let diveBoost: CGFloat = 1.8
        /// ±yaw amplitude (radians) applied to sprite heading during cruise.
        static let yawAmplitude: CGFloat = .pi / 18  // ~10°
        static let yawFrequency: CGFloat = 3.0       // Hz
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
        /// Durability damage applied to a tower per bolt strike during a discharge.
        static let ewLightningTowerDamage = 1
        /// Half-width of the bolt's hit corridor in points; tower within this perpendicular
        /// distance of a bolt's segment counts as struck.
        static let ewLightningHitHalfWidth: CGFloat = 24
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
        // Heavy Drone (Bayraktar TB2 / Reaper-style strike UAV)
        //
        // Flight model: kinematic fixed-wing controller with bank inertia.
        // Forward speed follows the altitude/dive tween, but turn-rate
        // authority uses a cruise-speed reference and angular acceleration
        // limit so entering/exiting turns does not snap.
        //
        // It steers toward an ordered list of waypoints. Strikes are
        // a flyby waypoint sequence (approach → release → exit); the
        // dive shape EMERGES from the drone banking toward the
        // release point, rather than being scripted as a curve.
        static let heavyDroneFirstWave = 7
        static let heavyDroneSpeed: CGFloat = 120               // cruise speed (px/s). Modulated by altitudeProportionalSpeedFactor when the dive shrinks the silhouette.
        static let heavyDroneHealth = 12
        static let heavyDroneBombCount = 2                      // guided bombs released during overflight
        static let heavyDroneBombDamage: Int = 3                // MAM-L-class munition — single hit downs ANY tower (max baseDurability is 3)
        static let heavyDroneSpriteScale: CGFloat = 1.8         // imposing cruise silhouette
        static let heavyDroneAttackSpriteScale: CGFloat = 0.75  // sprite shrinks during dive — smaller + faster reads as acceleration
        static let heavyDroneAttackSpeedFactor: CGFloat = 1.6   // dive speed multiplier at attack scale — combined with sprite shrink reads as acceleration
        static let heavyDroneReward = 80
        static let heavyDroneScore = 300

        // Fixed-wing flight tuning.
        //
        // CRUCIAL INVARIANT: every consecutive pair of waypoints must
        // be far enough for the cruise-envelope turn radius, OR the drone
        // must arrive at the first waypoint
        // already heading roughly toward the second. Otherwise the
        // second waypoint falls INSIDE one of the drone's two
        // "no-go circles" (radius R, perpendicular to current heading)
        // and pursuit steering can orbit instead of
        // arriving. The constants below are tuned so this invariant
        // holds for all typical strike geometries.
        static let heavyDroneMinTurnRadius: CGFloat = 60        // px at cruise speed. Maneuvering uses the cruise envelope so dive speed does not make the drone snap into a tighter turn.
        static let heavyDroneTurnRateReferenceSpeed: CGFloat = heavyDroneSpeed // px/s. Fixed reference for max turn rate; altitude changes affect forward speed, not control authority.
        static let heavyDroneAngularAcceleration: CGFloat = 7.0 // rad/s². Limits how quickly the drone banks into/out of a turn; removes 0→max-turn snaps.
        static let heavyDroneSpeedChangeRate: CGFloat = 220     // px/s². Smooths flight-speed response to the altitude/scale tween.
        static let heavyDronePathLookAheadDistance: CGFloat = 90 // px. Steering chases a point ahead on the route, not the waypoint itself, so corners read as fly-through arcs.
        static let heavyDroneBoundarySoftMargin: CGFloat = 75   // px inside each screen edge where containment starts nudging the route target inward.
        static let heavyDroneBoundaryHardOutset: CGFloat = 180  // px outside each screen edge where containment reaches full authority.
        static let heavyDroneBoundaryPredictionTime: CGFloat = 1.1 // seconds ahead used to anticipate fixed-wing turn radius before crossing the edge.
        static let heavyDroneBoundaryRecoveryLead: CGFloat = 140 // px inside the soft boundary used as recovery target during offscreen/near-edge turns.
        static let heavyDroneSideCleanupOutset: CGFloat = 280    // px outside screen; Heavy is cleaned up here only if still flying farther out.
        static let heavyDroneStrikeApproachOffset: CGFloat = 150 // lateral px from target where the approach waypoint sits. Approach→release distance = √(150²+100²) = 180 px, and the transit leg lines up the heading before the dive.
        static let heavyDroneStrikeApproachAltitude: CGFloat = 130 // px above target at the approach waypoint. Combined with release altitude 30 gives a 33.7° dive (atan(100/150)) — matches the spec dive angle. Drone is at cruise scale here.
        static let heavyDroneStrikeReleaseAltitude: CGFloat = 30 // px above target at the release waypoint. Drone is at attack scale; bomb separates when drone passes overhead.
        static let heavyDroneStrikeExitOffset: CGFloat = 150    // lateral px past target where the exit waypoint sits. Release→exit mirrors the approach geometry so climb-out stays smooth.
        static let heavyDroneStrikeExitAltitude: CGFloat = 130  // px above target at the exit waypoint. Same as approach altitude — drone climbs back out with a 33.7° climb angle (mirror of the dive).
        static let heavyDroneTransitCruiseAltitudeFromTop: CGFloat = 60 // between strikes the drone routes through `frame.maxY - this` — the climb-out before the next strike. High enough to clear strike altitudes; below the HUD so the silhouette stays visible.
        static let heavyDroneTransitSideOffset: CGFloat = 180   // lateral px from the next target where the pre-strike transit waypoint sits. Long descent leg from transit aligns drone heading with the strike axis by the time it arrives at approach.
        static let heavyDroneEgressTopMargin: CGFloat = 80      // y above frame.maxY where egress completes. Drone is removed once it crosses this line.
        static let heavyDroneEgressSteeringTopMargin: CGFloat = 260 // y above frame.maxY for the steering target, kept far past the removal line so egress is a fly-through instead of a small point to orbit.
        static let heavyDroneEgressArrivalRadius: CGFloat = 120 // fallback radius for egress waypoint arrival if cleanup/removal line did not trigger first.
        static let heavyDroneStrikeBombReleaseLateralTolerance: CGFloat = 14 // px. Bomb releases when |drone.x - target.x| < this. Sized so the release fires on the frame the drone visually crosses over the tower.
        static let heavyDroneWaypointArrivalRadius: CGFloat = 30
        static let heavyDroneStrikeWaypointArrivalRadius: CGFloat = 45
        static let heavyDroneDescendDuration: TimeInterval = 0.5 // sprite-scale tween when diving from cruise (1.0) to attack (0.75). Fires on arrival at the strike approach waypoint.
        static let heavyDroneClimbDuration: TimeInterval = 0.4   // sprite-scale tween from 0.75 → 1.0. Fires on arrival at the strike exit waypoint.
        static let heavyDroneVortexBirthRate: CGFloat = 120      // wingtip-vortex particles per second per wing during the strike segment (between approach and exit waypoints).
        // Cruise Missile
        static let cruiseMissileFirstWave = 8
        static let cruiseMissileMinSpeed: CGFloat = 150
        static let cruiseMissileMaxSpeed: CGFloat = 200
        static let cruiseMissileHealth = 3
        static let cruiseMissileHQDamage = 4
        static let cruiseMissileEvasionRadius: CGFloat = 60
        static let cruiseMissileTurnRate: CGFloat = .pi / 6  // 30° per second
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
        /// One swarm drone is enough to disable any tower — the rest of the
        /// swarm immediately retargets to the next combat tower.
        static let swarmTowerDamage: Int = 100
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
        // Formation constants
        static let formationSpacing: CGFloat = 42     // px between drone centers
        static let formationDelay: TimeInterval = 3.0 // delay before formation spawns
        static let formationStagger: TimeInterval = 0.01 // near-instant spawn for tight formation
    }

    // MARK: - Lancet Constants
    struct Lancet {
        static let firstWave = 8
        static let speed: CGFloat = 90
        static let health = 4
        static let reward = 25
        static let scorePerKill = 100
        static let loiterDuration: TimeInterval = 10.0  // circle before diving
        static let diveSpeed: CGFloat = 260
        static let towerDestroyDamage = 100  // enough to destroy any tower
        static let spawnDelay: TimeInterval = 12.0
        /// Sinusoidal evasion during the approach phase.
        static let approachEvasionAmplitude: CGFloat = 15
        static let approachEvasionFrequency: CGFloat = 2.0  // Hz
    }

    // MARK: - Orlan-10 Constants
    struct Orlan {
        static let firstWave = 9
        static let speed: CGFloat = 40
        static let health = 4
        static let reward = 35
        static let scorePerKill = 150
        static let salvoIntervalMultiplier: CGFloat = 0.65  // missiles come 35% faster
        static let spawnDelay: TimeInterval = 15.0

        // Camera
        static let cameraFOV: CGFloat = .pi / 2              // 90° field of view
        static let cameraRange: CGFloat = 120                 // detection radius (points)
        static let cameraSearchRotationSpeed: CGFloat = 1.5   // rad/s while searching

        // Orbit
        static let orbitRadius: CGFloat = 80                  // orbit circle radius around tower
        static let orbitAngularSpeed: CGFloat = 1.0           // rad/s around tower

        // Speed boost for drones near spotted tower
        static let boostRadius: CGFloat = 150                 // radius around spotted tower
        static let speedBoostMultiplier: CGFloat = 3.0        // 3x speed for nearby drones

        // Lancet spawning while orbiting
        static let lancetSpawnInterval: TimeInterval = 8.0    // seconds between lancet spawns
        static let lancetAmmo: Int = 3                        // max lancets per Orlan

        // Retreat
        static let retreatSpeed: CGFloat = 60                 // faster than patrol when fleeing
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

    struct OilRefinery {
        static let baseHP = 3
        static let incomeAmount = 15
        static let incomeInterval: TimeInterval = 8.0
        static let targetPriority: CGFloat = 3.0
        static let refineryTargetChance: CGFloat = 0.7
        static let droneDamageToLives = 1
    }

    // MARK: - Sprite Sizes
    struct SpriteSize {
        static let towerBase: CGFloat = 38
        static let towerPreview: CGFloat = 32
        static let settlement: CGFloat = 34
        static let shahed: CGFloat = 28
        static let kamikaze = CGSize(width: 16, height: 18)
        static let ewDrone: CGFloat = 30
        static let lancet = CGSize(width: 18, height: 22)
        static let orlan: CGFloat = 40
        static let heavyDroneBase: CGFloat = 36
        static let cruiseMissile = CGSize(width: 10, height: 28)
        static let harmMissile = CGSize(width: 9, height: 26)
        static let enemyMissile = CGSize(width: 22, height: 38)
        static let swarmUnit: CGFloat = 5
        static let attackDrone: CGFloat = 30
    }

    // MARK: - Terrain Zone Constants
    struct TerrainZone {
        static let highGroundRangeMultiplier: CGFloat = 1.2
        static let valleySpeedMultiplier: CGFloat = 1.3
    }

    // MARK: - Explosion Visual FX
    struct Explosion {
        // Peak radii for the expanding core/ring. Deliberately small — we
        // lean on the sprite-based fireball that will replace this later.
        static let smallRadius: CGFloat = 10
        static let mediumRadius: CGFloat = 16
        static let largeRadius: CGFloat = 24
        static let coreGrowDuration: TimeInterval = 0.06
        static let coreFadeDuration: TimeInterval = 0.14
        static let ringDuration: TimeInterval = 0.28
        static let zPosition: CGFloat = 65
        // Night "reveal" glow — how long the warm illumination holds at
        // the blast position and how fast it fades out.
        static let nightHoleRadiusMultiplier: CGFloat = 3.5
        static let nightHoleHold: TimeInterval = 0.04
        static let nightHoleFadeOut: TimeInterval = 0.18
    }

    static let hqName = "headquarters"
    static let towerBitMask: UInt32 = 0x1 << 7
    static let kamikazeBitMask: UInt32 = 0x1 << 8
    static let settlementBitMask: UInt32 = 0x1 << 9
}
