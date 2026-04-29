//
//  GridMap.swift
//  PVOGame
//

import Foundation
import CoreGraphics

enum CellTerrain: Int {
    case ground = 0
    case highGround = 1     // towers get +20% range
    case blocked = 2
    case headquarters = 3
    case settlement = 4
    case concealed = 5      // tower immune to HARM missiles
    case valley = 6         // drones speed up here

    var isTowerPlaceable: Bool {
        switch self {
        case .ground, .highGround, .concealed: return true
        default: return false
        }
    }
}

struct GridCell {
    let row: Int
    let col: Int
    var terrain: CellTerrain
    var towerID: ObjectIdentifier?
    var settlementID: ObjectIdentifier?
    var isOccupied: Bool { towerID != nil }
    var hasSettlement: Bool { settlementID != nil }
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
        worldPosition(forRow: row, col: col, footprint: (rows: 1, cols: 1))
    }

    /// World-space center of a multi-cell footprint anchored at (row, col) as its top-left cell.
    func worldPosition(forRow row: Int, col: Int, footprint: (rows: Int, cols: Int)) -> CGPoint {
        let centerCol = CGFloat(col) + CGFloat(footprint.cols) / 2.0
        let centerRowFromTop = CGFloat(row) + CGFloat(footprint.rows) / 2.0
        // Grid y-axis grows downward (row 0 at top); screen y grows upward, hence the flip.
        let centerRowFromBottom = CGFloat(rows) - centerRowFromTop
        return CGPoint(
            x: origin.x + centerCol * cellSize.width,
            y: origin.y + centerRowFromBottom * cellSize.height
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
        canPlaceTower(atRow: row, col: col, footprint: (rows: 1, cols: 1))
    }

    /// Every cell in the footprint must be placeable, unoccupied, and settlement-free.
    func canPlaceTower(atRow row: Int, col: Int, footprint: (rows: Int, cols: Int)) -> Bool {
        guard row >= 0, col >= 0,
              row + footprint.rows <= rows,
              col + footprint.cols <= cols else { return false }
        for r in row..<(row + footprint.rows) {
            for c in col..<(col + footprint.cols) {
                let cell = cells[r][c]
                if !cell.terrain.isTowerPlaceable || cell.isOccupied || cell.hasSettlement {
                    return false
                }
            }
        }
        return true
    }

    @discardableResult
    func placeTower(_ towerID: ObjectIdentifier, atRow row: Int, col: Int) -> Bool {
        placeTower(towerID, atRow: row, col: col, footprint: (rows: 1, cols: 1))
    }

    @discardableResult
    func placeTower(_ towerID: ObjectIdentifier, atRow row: Int, col: Int,
                    footprint: (rows: Int, cols: Int)) -> Bool {
        guard canPlaceTower(atRow: row, col: col, footprint: footprint) else { return false }
        for r in row..<(row + footprint.rows) {
            for c in col..<(col + footprint.cols) {
                cells[r][c].towerID = towerID
            }
        }
        return true
    }

    func removeTower(atRow row: Int, col: Int) {
        removeTower(atRow: row, col: col, footprint: (rows: 1, cols: 1))
    }

    func removeTower(atRow row: Int, col: Int, footprint: (rows: Int, cols: Int)) {
        for r in row..<(row + footprint.rows) {
            for c in col..<(col + footprint.cols) {
                guard r >= 0, r < rows, c >= 0, c < cols else { continue }
                cells[r][c].towerID = nil
            }
        }
    }

    func cell(atRow row: Int, col: Int) -> GridCell? {
        guard row >= 0, row < rows, col >= 0, col < cols else { return nil }
        return cells[row][col]
    }

    // MARK: - Settlement Placement

    @discardableResult
    func placeSettlement(_ id: ObjectIdentifier, atRow row: Int, col: Int) -> Bool {
        placeSettlement(id, atRow: row, col: col, footprint: (rows: 1, cols: 1))
    }

    @discardableResult
    func placeSettlement(_ id: ObjectIdentifier, atRow row: Int, col: Int,
                         footprint: (rows: Int, cols: Int)) -> Bool {
        guard row >= 0, col >= 0,
              row + footprint.rows <= rows,
              col + footprint.cols <= cols else { return false }
        // Every cell in the footprint must be placeable, free of towers, and
        // free of other settlements.
        for r in row..<(row + footprint.rows) {
            for c in col..<(col + footprint.cols) {
                let cell = cells[r][c]
                if !cell.terrain.isTowerPlaceable || cell.isOccupied || cell.hasSettlement {
                    return false
                }
            }
        }
        for r in row..<(row + footprint.rows) {
            for c in col..<(col + footprint.cols) {
                cells[r][c].settlementID = id
                cells[r][c].terrain = .settlement
            }
        }
        return true
    }

    func removeSettlement(atRow row: Int, col: Int) {
        removeSettlement(atRow: row, col: col, footprint: (rows: 1, cols: 1))
    }

    func removeSettlement(atRow row: Int, col: Int, footprint: (rows: Int, cols: Int)) {
        for r in row..<(row + footprint.rows) {
            for c in col..<(col + footprint.cols) {
                guard r >= 0, r < rows, c >= 0, c < cols else { continue }
                cells[r][c].settlementID = nil
                cells[r][c].terrain = .ground
            }
        }
    }

    // MARK: - Line of Sight

    /// Returns true if a highGround cell blocks the line from tower to drone.
    /// Towers ON highGround have elevated view and are never blocked.
    func isLineOfSightBlocked(from towerPos: CGPoint, to dronePos: CGPoint, towerOnHighGround: Bool) -> Bool {
        if towerOnHighGround { return false }

        let dx = dronePos.x - towerPos.x
        let dy = dronePos.y - towerPos.y
        let dist = sqrt(dx * dx + dy * dy)
        guard dist > 0 else { return false }

        let stepSize = min(cellSize.width, cellSize.height) * 0.5
        let steps = Int(ceil(dist / stepSize))

        for i in 1..<steps {
            let t = CGFloat(i) / CGFloat(steps)
            let point = CGPoint(x: towerPos.x + dx * t, y: towerPos.y + dy * t)
            if let pos = gridPosition(for: point),
               let cell = cell(atRow: pos.row, col: pos.col),
               cell.terrain == .highGround {
                return true
            }
        }
        return false
    }

    /// Data for one highGround occlusion: angular range and distance to the blocking cell.
    struct OcclusionSector {
        let startAngle: CGFloat
        let endAngle: CGFloat
        let distance: CGFloat  // distance from tower to the highGround cell center
    }

    /// Returns occlusion sectors caused by highGround cells within the given radius.
    func occlusionSectors(from center: CGPoint, radius: CGFloat, towerOnHighGround: Bool) -> [OcclusionSector] {
        if towerOnHighGround { return [] }

        var sectors: [OcclusionSector] = []
        let radiusSq = radius * radius

        for row in 0..<rows {
            for col in 0..<cols {
                guard cells[row][col].terrain == .highGround else { continue }
                let cellCenter = worldPosition(forRow: row, col: col)
                let dx = cellCenter.x - center.x
                let dy = cellCenter.y - center.y
                let distSq = dx * dx + dy * dy
                guard distSq < radiusSq && distSq > 1 else { continue }

                let dist = sqrt(distSq)
                let centerAngle = atan2(dy, dx)
                let halfCell = max(cellSize.width, cellSize.height) * 0.5
                let halfAngle = atan2(halfCell, dist)

                sectors.append(OcclusionSector(
                    startAngle: centerAngle - halfAngle,
                    endAngle: centerAngle + halfAngle,
                    distance: dist
                ))
            }
        }
        return sectors
    }

    /// Builds a CGPath representing the range circle with blocked sectors cut out.
    /// Blocked area starts at the highGround cell, not from the tower center.
    /// Path is relative to (0,0).
    func rangePathWithOcclusion(radius: CGFloat, towerWorldPos: CGPoint, towerOnHighGround: Bool) -> CGPath {
        let sectors = occlusionSectors(from: towerWorldPos, radius: radius, towerOnHighGround: towerOnHighGround)

        if sectors.isEmpty {
            return CGPath(ellipseIn: CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2), transform: nil)
        }

        // Normalize and merge overlapping angular ranges, keeping min distance for inner arc
        struct MergedSector {
            var start: CGFloat
            var end: CGFloat
            var distance: CGFloat
        }
        let normalized = sectors.map { s -> MergedSector in
            MergedSector(start: normalizeAngle(s.startAngle), end: normalizeAngle(s.endAngle), distance: s.distance)
        }.filter { $0.start < $0.end }
        let sorted = normalized.sorted { $0.start < $1.start }

        var merged: [MergedSector] = []
        for s in sorted {
            if let last = merged.last, s.start <= last.end {
                merged[merged.count - 1].end = max(last.end, s.end)
                merged[merged.count - 1].distance = min(last.distance, s.distance)
            } else {
                merged.append(s)
            }
        }

        let path = CGMutablePath()

        // Build: for each blocked sector, draw visible arc, then inner arc at highGround distance,
        // then outer arc edge → creates a "shadow" starting at the highGround cell.
        var visibleArcs: [(start: CGFloat, end: CGFloat)] = []
        var blockedArcs: [(start: CGFloat, end: CGFloat, innerR: CGFloat)] = []
        var angle: CGFloat = -.pi

        for s in merged {
            if angle < s.start {
                visibleArcs.append((start: angle, end: s.start))
            }
            let halfCell = max(cellSize.width, cellSize.height) * 0.5
            let innerR = max(0, s.distance - halfCell)
            blockedArcs.append((start: s.start, end: s.end, innerR: innerR))
            angle = s.end
        }
        if angle < .pi {
            visibleArcs.append((start: angle, end: .pi))
        }

        // Draw the full shape: alternating visible arcs (at radius) and blocked notches
        // Combine into one subpath going around the circle
        var allSegments: [(start: CGFloat, end: CGFloat, isBlocked: Bool, innerR: CGFloat)] = []
        for v in visibleArcs {
            allSegments.append((start: v.start, end: v.end, isBlocked: false, innerR: 0))
        }
        for b in blockedArcs {
            allSegments.append((start: b.start, end: b.end, isBlocked: true, innerR: b.innerR))
        }
        allSegments.sort { $0.start < $1.start }

        guard !allSegments.isEmpty else {
            return CGPath(ellipseIn: CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2), transform: nil)
        }

        let first = allSegments[0]
        let startR = first.isBlocked ? first.innerR : radius
        path.move(to: CGPoint(x: cos(first.start) * startR, y: sin(first.start) * startR))

        for seg in allSegments {
            if seg.isBlocked {
                // Inner arc at highGround distance (visible part between tower and hill)
                path.addArc(center: .zero, radius: seg.innerR, startAngle: seg.start, endAngle: seg.end, clockwise: false)
            } else {
                // Full-radius arc (visible zone)
                path.addArc(center: .zero, radius: radius, startAngle: seg.start, endAngle: seg.end, clockwise: false)
            }
            // Connect to next segment with radial line if radii differ
            if let nextIdx = allSegments.firstIndex(where: { $0.start == seg.end }) {
                let nextSeg = allSegments[nextIdx]
                let nextR = nextSeg.isBlocked ? nextSeg.innerR : radius
                let currentR = seg.isBlocked ? seg.innerR : radius
                if abs(nextR - currentR) > 0.5 {
                    path.addLine(to: CGPoint(x: cos(seg.end) * nextR, y: sin(seg.end) * nextR))
                }
            }
        }

        path.closeSubpath()
        return path
    }

    /// Sample the occlusion range shape as an array of radii at N evenly-spaced angles.
    /// Returns N radii from angle -π to just before +π. Each radius is either the full range
    /// or the inner (occluded) radius at that angle.
    func occlusionRadii(from center: CGPoint, radius: CGFloat, towerOnHighGround: Bool, sampleCount: Int = 72) -> [CGFloat] {
        let sectors = occlusionSectors(from: center, radius: radius, towerOnHighGround: towerOnHighGround)

        // Default: full radius everywhere
        var radii = [CGFloat](repeating: radius, count: sampleCount)
        guard !sectors.isEmpty else { return radii }

        // Normalize and merge (same logic as rangePathWithOcclusion)
        struct MergedSector {
            var start: CGFloat
            var end: CGFloat
            var distance: CGFloat
        }
        let normalized = sectors.map { s -> MergedSector in
            MergedSector(start: normalizeAngle(s.startAngle), end: normalizeAngle(s.endAngle), distance: s.distance)
        }.filter { $0.start < $0.end }
        let sorted = normalized.sorted { $0.start < $1.start }

        var merged: [MergedSector] = []
        for s in sorted {
            if let last = merged.last, s.start <= last.end {
                merged[merged.count - 1].end = max(last.end, s.end)
                merged[merged.count - 1].distance = min(last.distance, s.distance)
            } else {
                merged.append(s)
            }
        }

        let halfCell = max(cellSize.width, cellSize.height) * 0.5
        let step = (2.0 * .pi) / CGFloat(sampleCount)

        for i in 0..<sampleCount {
            let angle = -.pi + CGFloat(i) * step
            for s in merged {
                if angle >= s.start && angle <= s.end {
                    radii[i] = max(0, s.distance - halfCell)
                    break
                }
            }
        }

        return radii
    }

    /// Build a CGPath from an array of polar radii (one per evenly-spaced angle from -π).
    static func pathFromRadii(_ radii: [CGFloat]) -> CGPath {
        let count = radii.count
        guard count > 2 else {
            return CGPath(ellipseIn: CGRect(x: -1, y: -1, width: 2, height: 2), transform: nil)
        }
        let step = (2.0 * .pi) / CGFloat(count)
        let path = CGMutablePath()
        for i in 0..<count {
            let angle = -.pi + CGFloat(i) * step
            let r = radii[i]
            let pt = CGPoint(x: cos(angle) * r, y: sin(angle) * r)
            if i == 0 { path.move(to: pt) }
            else { path.addLine(to: pt) }
        }
        path.closeSubpath()
        return path
    }

    private func normalizeAngle(_ a: CGFloat) -> CGFloat {
        var r = a
        while r > .pi { r -= 2 * .pi }
        while r < -.pi { r += 2 * .pi }
        return r
    }

    func generateSettlementPositions(count: Int) -> [(row: Int, col: Int)] {
        generateSettlementPositions(count: count, footprint: (rows: 1, cols: 1))
    }

    /// Returns valid top-left anchor positions for settlements of the given
    /// footprint, respecting min edge / HQ / inter-settlement distance
    /// constraints. All cells inside the footprint must be placeable.
    func generateSettlementPositions(count: Int,
                                      footprint: (rows: Int, cols: Int)) -> [(row: Int, col: Int)] {
        let minEdge = Constants.Settlement.minDistanceFromEdge
        let minBetween = Constants.Settlement.minDistanceBetween
        let minFromHQ = Constants.Settlement.minDistanceFromHQ

        // Find HQ row (bottom rows typically)
        let hqRow = rows - 1

        // Collect valid candidate anchor positions
        var candidates: [(row: Int, col: Int)] = []
        for row in 0..<rows {
            for col in 0..<cols {
                // Anchor + footprint must fit within edge-restricted bounds
                guard row >= minEdge, row + footprint.rows <= rows - minEdge else { continue }
                guard col >= minEdge, col + footprint.cols <= cols - minEdge else { continue }
                // Every cell in the footprint must be placeable
                var allPlaceable = true
                for r in row..<(row + footprint.rows) {
                    for c in col..<(col + footprint.cols) {
                        if !cells[r][c].terrain.isTowerPlaceable {
                            allPlaceable = false
                            break
                        }
                    }
                    if !allPlaceable { break }
                }
                guard allPlaceable else { continue }
                // Must be far enough from HQ — measured from the near side
                // of the footprint (bottom-most row) to the HQ row.
                let nearSideRow = row + footprint.rows - 1
                guard (hqRow - nearSideRow) >= minFromHQ else { continue }
                candidates.append((row, col))
            }
        }

        candidates.shuffle()

        var selected: [(row: Int, col: Int)] = []
        for candidate in candidates {
            guard selected.count < count else { break }
            // Distance between footprint bounding-box centers, Manhattan-ish.
            // A 2×2 at (r,c) has center (r+0.5, c+0.5); using anchor+fp/2
            // approximates center distance and still excludes overlap.
            let tooClose = selected.contains { existing in
                let dr = abs((existing.row + footprint.rows / 2)
                             - (candidate.row + footprint.rows / 2))
                let dc = abs((existing.col + footprint.cols / 2)
                             - (candidate.col + footprint.cols / 2))
                return dr + dc < minBetween + max(footprint.rows, footprint.cols) - 1
            }
            if !tooClose {
                selected.append(candidate)
            }
        }

        return selected
    }
}
