//
//  AltitudeComponent.swift
//  PVOGame
//

import GameplayKit

class AltitudeComponent: GKComponent {
    var altitude: DroneAltitude

    init(altitude: DroneAltitude) {
        self.altitude = altitude
        super.init()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
