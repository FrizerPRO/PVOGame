//
//  InPlaySKScene+Settings.swift
//  PVOGame
//

import SpriteKit
import UIKit

extension InPlaySKScene {
    // MARK: - Auto-Pause

    func registerAutoPauseObservers() {
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(autoPauseOnResignActive),
                       name: UIApplication.willResignActiveNotification, object: nil)
        nc.addObserver(self, selector: #selector(autoPauseOnInterruption),
                       name: UIApplication.didEnterBackgroundNotification, object: nil)
    }

    func removeAutoPauseObservers() {
        NotificationCenter.default.removeObserver(self,
            name: UIApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.removeObserver(self,
            name: UIApplication.didEnterBackgroundNotification, object: nil)
    }

    @objc private func autoPauseOnResignActive() {
        presentPauseMenu()
    }

    @objc private func autoPauseOnInterruption() {
        presentPauseMenu()
    }

    // MARK: - Settings

    func setupSettingsButton(_ view: SKView) {
        let buttonSize = Constants.GameBalance.settingsButtonSize
        let button = SettingsButton(frame: CGRect(origin: .zero, size: buttonSize)) { [weak self] in
            self?.presentPauseMenu()
        }
        view.addSubview(button)
        button.pinLeft(to: view, Int(Constants.GameBalance.settingsButtonInsets.x))
        button.pinTop(to: view, Int(Constants.GameBalance.settingsButtonInsets.y))
        button.setWidth(buttonSize.width).isActive = true
        button.setHeight(buttonSize.height).isActive = true
        button.isHidden = true
        settingsButton = button
    }

    func setupSettingsMenu(_ view: SKView) {
        let width = view.frame.width * Constants.GameBalance.settingsMenuWidthRatio
        let menu = InGameSettingsMenu(
            frame: CGRect(x: 0, y: 0, width: width, height: Constants.GameBalance.settingsMenuHeight),
            onResume: { [weak self] in self?.resumeGame() },
            onRestart: { [weak self] in self?.restartGame() },
            onExit: { [weak self] in self?.exitToMainMenu() }
        )
        view.addSubview(menu)
        menu.pinCenterX(to: view.centerXAnchor)
        menu.pinCenterY(to: view.centerYAnchor)
        menu.setWidth(width).isActive = true
        menu.setHeight(Constants.GameBalance.settingsMenuHeight).isActive = true
        menu.isHidden = true
        settingsMenu = menu
    }

    func presentPauseMenu() {
        guard currentPhase == .build || currentPhase == .combat else { return }
        settingsMenu?.isHidden = false
        isPaused = true
    }

    func resumeGame() {
        settingsMenu?.isHidden = true
        // Reset lastUpdateTime so the next frame doesn't see a huge dt
        lastUpdateTime = 0
        isPaused = false
    }

    func restartGame() {
        resumeGame()
        stopGame()
        startGame()
    }

    func exitToMainMenu() {
        resumeGame()
        stopGame()
        showMainMenu()
    }
}
