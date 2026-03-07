//
//  SettingsButton.swift
//  PVOGame
//
//  Created by Frizer on 09.01.2023.
//

import UIKit

class SettingsButton: UIButton {
    let callInGameSettingsMenu: () -> Void

    init(frame: CGRect, callSettingsMenu: @escaping () -> Void) {
        self.callInGameSettingsMenu = callSettingsMenu
        super.init(frame: frame)
        setupUI()
    }

    private func setupUI() {
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .black
        layer.borderWidth = 2
        layer.borderColor = UIColor.green.cgColor
        layer.cornerRadius = 8

        let image = UIImage(systemName: "gearshape.fill")
        setImage(image, for: .normal)
        tintColor = .green
        addTarget(self, action: #selector(didTouchButton), for: .touchUpInside)
    }

    @objc
    private func didTouchButton() {
        callInGameSettingsMenu()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
