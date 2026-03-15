//
//  LevelDefinition.swift
//  PVOGame
//

import Foundation
import CoreGraphics

struct WaveDefinition {
    let droneCount: Int
    let mineLayerCount: Int
    let speed: CGFloat
    let spawnInterval: TimeInterval
    let spawnBatchSize: Int
    let altitude: DroneAltitude
    let droneHealth: Int

    static func defaultWave(number: Int) -> WaveDefinition {
        let baseCount = 50 + number * 4
        let speed: CGFloat = 40 + CGFloat(number) * 5
        let altitude: DroneAltitude
        if number <= 2 {
            altitude = .low
        } else if number <= 4 {
            altitude = [.low, .medium].randomElement()!
        } else {
            altitude = DroneAltitude.regularCases.randomElement()!
        }
        let health = 2 + (number - 1) / 2
        let batch = min(3 + number / 2, 6)
        return WaveDefinition(
            droneCount: baseCount,
            mineLayerCount: number >= 3 ? 1 : 0,
            speed: speed,
            spawnInterval: max(0.35, 1.2 - Double(number) * 0.07),
            spawnBatchSize: batch,
            altitude: altitude,
            droneHealth: health
        )
    }
}

struct LevelDefinition {
    let gridLayout: [[Int]]
    let dronePaths: [DronePathDefinition]
    let waves: [WaveDefinition]
    let startingResources: Int

    // 0 = ground (placeable), 1 = flight path, 2 = blocked, 3 = headquarters
    static let level1: LevelDefinition = {
        // 16 rows x 10 cols, portrait orientation
        // Drones fly top to bottom through the flight path
        let layout: [[Int]] = [
            [0, 0, 0, 0, 1, 1, 0, 0, 0, 0],  // row 0 (top)
            [0, 0, 0, 0, 1, 1, 0, 0, 0, 0],
            [0, 0, 0, 0, 1, 1, 0, 0, 0, 0],
            [0, 0, 1, 1, 1, 0, 0, 0, 0, 0],
            [0, 0, 1, 0, 0, 0, 0, 0, 0, 0],
            [0, 0, 1, 0, 0, 0, 0, 0, 0, 0],
            [0, 0, 1, 1, 1, 1, 1, 1, 0, 0],
            [0, 0, 0, 0, 0, 0, 0, 1, 0, 0],
            [0, 0, 0, 0, 0, 0, 0, 1, 0, 0],
            [0, 0, 0, 1, 1, 1, 1, 1, 0, 0],
            [0, 0, 0, 1, 0, 0, 0, 0, 0, 0],
            [0, 0, 0, 1, 0, 0, 0, 0, 0, 0],
            [0, 0, 0, 1, 1, 1, 0, 0, 0, 0],
            [0, 0, 0, 0, 0, 1, 0, 0, 0, 0],
            [0, 0, 0, 0, 0, 1, 0, 0, 0, 0],
            [0, 0, 0, 0, 3, 3, 0, 0, 0, 0],  // row 15 (bottom) — HQ
        ]

        let pathA = DronePathDefinition(
            gridWaypoints: [
                .init(row: 0, col: 4),
                .init(row: 2, col: 4),
                .init(row: 3, col: 2),
                .init(row: 5, col: 2),
                .init(row: 6, col: 4),
                .init(row: 6, col: 7),
                .init(row: 8, col: 7),
                .init(row: 9, col: 5),
                .init(row: 9, col: 3),
                .init(row: 11, col: 3),
                .init(row: 12, col: 4),
                .init(row: 13, col: 5),
                .init(row: 14, col: 5),
                .init(row: 15, col: 4),
            ],
            altitude: .low,
            spawnEdge: .top
        )

        let pathB = DronePathDefinition(
            gridWaypoints: [
                .init(row: 0, col: 5),
                .init(row: 2, col: 5),
                .init(row: 3, col: 3),
                .init(row: 5, col: 2),
                .init(row: 6, col: 5),
                .init(row: 6, col: 7),
                .init(row: 8, col: 7),
                .init(row: 9, col: 6),
                .init(row: 9, col: 3),
                .init(row: 11, col: 3),
                .init(row: 12, col: 3),
                .init(row: 13, col: 5),
                .init(row: 14, col: 5),
                .init(row: 15, col: 5),
            ],
            altitude: .low,
            spawnEdge: .top
        )

        let pathC = DronePathDefinition(
            gridWaypoints: [
                .init(row: 0, col: 4),
                .init(row: 1, col: 5),
                .init(row: 3, col: 2),
                .init(row: 4, col: 2),
                .init(row: 6, col: 3),
                .init(row: 6, col: 7),
                .init(row: 7, col: 7),
                .init(row: 9, col: 4),
                .init(row: 10, col: 3),
                .init(row: 12, col: 4),
                .init(row: 12, col: 5),
                .init(row: 14, col: 5),
                .init(row: 15, col: 4),
            ],
            altitude: .low,
            spawnEdge: .top
        )

        let waves = (1...20).map { WaveDefinition.defaultWave(number: $0) }

        return LevelDefinition(
            gridLayout: layout,
            dronePaths: [pathA, pathB, pathC],
            waves: waves,
            startingResources: Constants.TowerDefense.startingResources
        )
    }()
}
