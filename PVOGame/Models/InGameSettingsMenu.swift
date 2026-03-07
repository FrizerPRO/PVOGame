//
//  InGameSettingsMenu.swift
//  PVOGame
//
//  Created by Frizer on 09.01.2023.
//

import UIKit

class InGameSettingsMenu: UIStackView {
    private let onResume: () -> Void
    private let onExit: () -> Void
    private let titleLabel = UILabel()
    private let resumeButton = UIButton(type: .system)
    private let exitButton = UIButton(type: .system)

    init(frame: CGRect, onResume: @escaping () -> Void, onExit: @escaping () -> Void) {
        self.onResume = onResume
        self.onExit = onExit
        super.init(frame: frame)
        setupUI()
    }

    private func setupUI() {
        translatesAutoresizingMaskIntoConstraints = false
        axis = .vertical
        spacing = 12
        alignment = .fill
        distribution = .fillEqually
        isLayoutMarginsRelativeArrangement = true
        directionalLayoutMargins = NSDirectionalEdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)
        backgroundColor = .black
        layer.borderColor = UIColor.green.cgColor
        layer.borderWidth = 4
        layer.cornerRadius = 12

        titleLabel.text = "Game Paused"
        titleLabel.textColor = .green
        titleLabel.textAlignment = .center
        titleLabel.font = .boldSystemFont(ofSize: 26)

        resumeButton.setTitle("Resume", for: .normal)
        resumeButton.backgroundColor = .darkGray
        resumeButton.setTitleColor(.green, for: .normal)
        resumeButton.layer.cornerRadius = 8
        resumeButton.addTarget(self, action: #selector(resumeDidTap), for: .touchUpInside)

        exitButton.setTitle("Exit to Menu", for: .normal)
        exitButton.backgroundColor = .red
        exitButton.setTitleColor(.white, for: .normal)
        exitButton.layer.cornerRadius = 8
        exitButton.addTarget(self, action: #selector(exitDidTap), for: .touchUpInside)

        addArrangedSubview(titleLabel)
        addArrangedSubview(resumeButton)
        addArrangedSubview(exitButton)
    }

    @objc
    private func resumeDidTap() {
        onResume()
    }

    @objc
    private func exitDidTap() {
        onExit()
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
