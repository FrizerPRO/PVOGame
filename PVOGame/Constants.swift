//
//  Constants.swift
//  PVOGame
//
//  Created by Frizer on 12.03.2023.
//

import CoreGraphics

class Constants{
    static let boundsBitMask : UInt32 = 0x1 << 1
    static let droneBitMask : UInt32 = 0x1 << 2
    static let bulletBitMask : UInt32 = 0x1 << 3
    static let groundBitMask : UInt32 = 0x1 << 4
    static let backgroundName = "background"
    static let groundName = "ground"
    static let menuButtonName = "menuButton"
    static let exitFromGameButtonName = "exitFromGameButtonName"
    static let cancelExitFromGameButtonName = "cancelExitFromGameButtonName"
    static let exitMenuName = "exitMenuName"
    static let noTapPoint = CGPoint(x: 0.5, y: -1)

    struct GameBalance {
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
    }
}
