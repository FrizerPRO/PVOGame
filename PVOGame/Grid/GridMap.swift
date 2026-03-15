//
//  GridMap.swift
//  PVOGame
//

import Foundation
import CoreGraphics

enum CellTerrain: Int {
    case ground = 0
    case flightPath = 1
    case blocked = 2
    case headquarters = 3
}

struct GridCell {
    let row: Int
    let col: Int
    var terrain: CellTerrain
    var towerID: ObjectIdentifier?
    var isOccupied: Bool { towerID != nil }
}

class GridMap {
    let rows: Int
    let cols: Int
    let cellSize: CGSize
    let origin: CGPoint
    private(set) var cells: [[GridCell]]
    private(set) var dronePaths: [DroneFlightPath]

    init(rows: Int, cols: Int, cellSize: CGSize, origin: CGPoint) {
        self.rows = rows
        self.cols = cols
        self.cellSize = cellSize
        self.origin = origin
        self.dronePaths = []
        self.cells = (0..<rows).map { row in
            (0..<cols).map { col in
                GridCell(row: row, col: col, terrain: .ground)
            }
        }
    }

    func loadLevel(_ level: LevelDefinition) {
        for row in 0..<min(rows, level.gridLayout.count) {
            for col in 0..<min(cols, level.gridLayout[row].count) {
                let value = level.gridLayout[row][col]
                cells[row][col].terrain = CellTerrain(rawValue: value) ?? .ground
            }
        }
        dronePaths = level.dronePaths.map { def in
            DroneFlightPath(
                waypoints: def.gridWaypoints.map { worldPosition(forRow: $0.row, col: $0.col) },
                altitude: def.altitude,
                spawnEdge: def.spawnEdge
            )
        }
    }

    func worldPosition(forRow row: Int, col: Int) -> CGPoint {
        CGPoint(
            x: origin.x + CGFloat(col) * cellSize.width + cellSize.width / 2,
            y: origin.y + CGFloat(rows - 1 - row) * cellSize.height + cellSize.height / 2
        )
    }

    func gridPosition(for worldPoint: CGPoint) -> (row: Int, col: Int)? {
        let col = Int((worldPoint.x - origin.x) / cellSize.width)
        let rowFromBottom = Int((worldPoint.y - origin.y) / cellSize.height)
        let row = rows - 1 - rowFromBottom
        guard row >= 0, row < rows, col >= 0, col < cols else { return nil }
        return (row, col)
    }

    func canPlaceTower(atRow row: Int, col: Int) -> Bool {
        guard row >= 0, row < rows, col >= 0, col < cols else { return false }
        let cell = cells[row][col]
        return cell.terrain == .ground && !cell.isOccupied
    }

    @discardableResult
    func placeTower(_ towerID: ObjectIdentifier, atRow row: Int, col: Int) -> Bool {
        guard canPlaceTower(atRow: row, col: col) else { return false }
        cells[row][col].towerID = towerID
        return true
    }

    func removeTower(atRow row: Int, col: Int) {
        guard row >= 0, row < rows, col >= 0, col < cols else { return }
        cells[row][col].towerID = nil
    }

    func cell(atRow row: Int, col: Int) -> GridCell? {
        guard row >= 0, row < rows, col >= 0, col < cols else { return nil }
        return cells[row][col]
    }
}
