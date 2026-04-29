//
//  GridPositionComponent.swift
//  PVOGame
//

import GameplayKit

class GridPositionComponent: GKComponent {
    /// Top-left anchor cell of the footprint.
    var row: Int
    var col: Int
    /// Footprint extent in cells. Defaults to 1×1 (single-cell tower).
    var rowSpan: Int
    var colSpan: Int

    init(row: Int, col: Int, rowSpan: Int = 1, colSpan: Int = 1) {
        self.row = row
        self.col = col
        self.rowSpan = rowSpan
        self.colSpan = colSpan
        super.init()
    }

    /// True if (r, c) is any cell inside this component's footprint.
    func contains(row r: Int, col c: Int) -> Bool {
        r >= row && r < row + rowSpan && c >= col && c < col + colSpan
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
