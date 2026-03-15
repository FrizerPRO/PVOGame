//
//  DroneFlightPath.swift
//  PVOGame
//

import Foundation
import CoreGraphics
import GameplayKit

enum DroneAltitude: Int, CaseIterable {
    case low = 0
    case medium = 1
    case high = 2
    case micro = 3

    /// Altitudes available for regular (non-micro) drones.
    static let regularCases: [DroneAltitude] = [.low, .medium, .high]

    var shadowScale: CGFloat {
        switch self {
        case .low: return 1.0
        case .medium: return 0.7
        case .high: return 0.45
        case .micro: return 1.0
        }
    }

    var shadowOffset: CGPoint {
        switch self {
        case .low: return CGPoint(x: 3, y: -3)
        case .medium: return CGPoint(x: 6, y: -6)
        case .high: return CGPoint(x: 10, y: -10)
        case .micro: return CGPoint(x: 2, y: -2)
        }
    }

    var droneVisualScale: CGFloat {
        switch self {
        case .low: return 1.0
        case .medium: return 0.85
        case .high: return 0.7
        case .micro: return 0.6
        }
    }

    var displayName: String {
        switch self {
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        case .micro: return "Micro"
        }
    }
}

enum SpawnEdge {
    case top
    case left
    case right
}

struct DroneFlightPath {
    let waypoints: [CGPoint]
    let altitude: DroneAltitude
    let spawnEdge: SpawnEdge

    func toFlyingPath() -> FlyingPath {
        guard let first = waypoints.first, let last = waypoints.last else {
            return FlyingPath(
                topLevel: 844, bottomLevel: 0,
                leadingLevel: 0, trailingLevel: 390,
                startLevel: 844, endLevel: 0,
                pathGenerator: { _ in [vector_float2(x: 195, y: 844), vector_float2(x: 195, y: 0)] }
            )
        }
        let allPoints = waypoints
        return FlyingPath(
            topLevel: max(first.y, last.y),
            bottomLevel: min(first.y, last.y),
            leadingLevel: 0,
            trailingLevel: waypoints.map(\.x).max() ?? 390,
            startLevel: first.y,
            endLevel: last.y,
            pathGenerator: { _ in
                allPoints.map { vector_float2(x: Float($0.x), y: Float($0.y)) }
            }
        )
    }
}

struct DronePathDefinition {
    struct GridWaypoint {
        let row: Int
        let col: Int
    }

    let gridWaypoints: [GridWaypoint]
    let altitude: DroneAltitude
    let spawnEdge: SpawnEdge
}
