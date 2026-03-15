//
//  GridPositionComponent.swift
//  PVOGame
//

import GameplayKit

class GridPositionComponent: GKComponent {
    var row: Int
    var col: Int

    init(row: Int, col: Int) {
        self.row = row
        self.col = col
        super.init()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
