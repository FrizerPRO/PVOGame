//
//  TowerAnimationComponent.swift
//  PVOGame
//

import GameplayKit
import SpriteKit

/// Manages tower-specific visual animations: recoil, muzzle flash, radar spin, EW pulse.
/// Attached to TowerEntity alongside other components. Requires multi-layer sprite setup.
class TowerAnimationComponent: GKComponent {
    /// The turret/launcher/antenna/soldier child node (rotates or animates)
    weak var turretNode: SKSpriteNode?
    /// The muzzle flash child node (shown during firing)
    weak var muzzleNode: SKSpriteNode?

    private let towerType: TowerType
    private var alternatingBarrel = false  // toggles left/right for Pantsir/Gepard
    private var isFiringContinuously = false
    private var textures: AnimationTextureCache.TowerTextures?

    init(towerType: TowerType) {
        self.towerType = towerType
        super.init()
        self.textures = AnimationTextureCache.shared.towerTextures[towerType]
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Public API called by TowerTargetingComponent

    /// Called each time the tower fires a bullet (gun towers).
    func onBulletFired() {
        switch towerType {
        case .autocannon:
            animateAutocannonRecoil()
            showMuzzleFlash(duration: 0.05)
        case .ciws:
            startContinuousFiring()
            showAlternatingMuzzleFlash()
        case .gepard:
            animateGepardAlternating()
            showAlternatingMuzzleFlash()
        default:
            break
        }
    }

    /// Called each time the tower fires a rocket (missile towers).
    func onRocketFired() {
        switch towerType {
        case .samLauncher:
            animateLauncherRecoil()
        case .interceptor:
            animateLauncherRecoil()
        case .pzrk:
            animateSoldierRecoil()
        default:
            break
        }
    }

    /// Called when the tower loses its target (stop continuous effects).
    func onTargetLost() {
        stopContinuousFiring()
    }

    /// Called when the tower is placed on the grid.
    func onTowerPlaced() {
        // Scale bounce
        guard let spriteNode = entity?.component(ofType: SpriteComponent.self)?.spriteNode else { return }
        spriteNode.setScale(1.2)
        spriteNode.run(SKAction.scale(to: 1.0, duration: 0.2))

        // Radar: start spinning
        if towerType == .radar {
            startRadarSpin()
        }
        // EW: start pulse
        if towerType == .ewTower {
            startEWPulse()
        }
    }

    /// Called when the tower is disabled (stop all animations).
    func onDisabled() {
        stopContinuousFiring()
        turretNode?.removeAction(forKey: "radarSpin")
        turretNode?.removeAction(forKey: "ewPulse")
    }

    /// Called when the tower is repaired.
    func onRepaired() {
        if towerType == .radar {
            startRadarSpin()
        }
        if towerType == .ewTower {
            startEWPulse()
        }
    }

    // MARK: - Autocannon (ZU-23-2) — simultaneous barrel recoil

    private func animateAutocannonRecoil() {
        guard let turret = turretNode else { return }
        // Reset position first to prevent drift from interrupted animations
        turret.removeAction(forKey: "recoil")
        turret.position = .zero
        let recoil = SKAction.sequence([
            SKAction.moveBy(x: 0, y: -2.0, duration: 0.02),
            SKAction.moveBy(x: 0, y: 2.0, duration: 0.06)
        ])
        turret.run(recoil, withKey: "recoil")
    }

    // MARK: - CIWS (Pantsir) — alternating barrels, continuous vibration

    private func startContinuousFiring() {
        guard let turret = turretNode, !isFiringContinuously else { return }
        isFiringContinuously = true

        // Rapid vibration simulating alternating barrel recoil
        let vibrate = SKAction.sequence([
            SKAction.moveBy(x: CGFloat.random(in: -0.4...0.4), y: -0.5, duration: 0.015),
            SKAction.moveBy(x: CGFloat.random(in: -0.4...0.4), y: 0.5, duration: 0.015)
        ])
        turret.run(SKAction.repeatForever(vibrate), withKey: "ciwsVibrate")

        // Muzzle flash continuous flicker
        if let muzzle = muzzleNode {
            muzzle.isHidden = false
            let flicker = SKAction.sequence([
                SKAction.fadeAlpha(to: 0.9, duration: 0.02),
                SKAction.fadeAlpha(to: 0.3, duration: 0.02)
            ])
            muzzle.run(SKAction.repeatForever(flicker), withKey: "ciwsFlash")
        }
    }

    private func stopContinuousFiring() {
        guard isFiringContinuously else { return }
        isFiringContinuously = false

        turretNode?.removeAction(forKey: "ciwsVibrate")
        turretNode?.position = .zero  // Reset to center of base

        muzzleNode?.removeAction(forKey: "ciwsFlash")
        muzzleNode?.isHidden = true
    }

    // MARK: - Gepard — alternating barrels

    private func animateGepardAlternating() {
        guard let turret = turretNode else { return }
        turret.removeAction(forKey: "recoil")
        turret.position = .zero
        let recoil = SKAction.sequence([
            SKAction.moveBy(x: alternatingBarrel ? -0.3 : 0.3, y: -1.5, duration: 0.02),
            SKAction.moveBy(x: alternatingBarrel ? 0.3 : -0.3, y: 1.5, duration: 0.04)
        ])
        turret.run(recoil, withKey: "recoil")
    }

    // MARK: - Muzzle flash

    private func showMuzzleFlash(duration: TimeInterval) {
        guard let muzzle = muzzleNode else { return }
        muzzle.isHidden = false
        muzzle.alpha = 1.0
        muzzle.removeAction(forKey: "muzzleHide")
        muzzle.run(SKAction.sequence([
            SKAction.wait(forDuration: duration),
            SKAction.run { muzzle.isHidden = true }
        ]), withKey: "muzzleHide")
    }

    private func showAlternatingMuzzleFlash() {
        guard let muzzle = muzzleNode, let textures else { return }
        // Alternate position between left and right barrel offsets
        let offset = alternatingBarrel ? textures.muzzleOffsetLeft : textures.muzzleOffsetRight
        muzzle.position = offset
        alternatingBarrel.toggle()

        // For Gepard (non-continuous), show brief flash
        if towerType == .gepard {
            showMuzzleFlash(duration: 0.04)
        }
        // For CIWS, flash is managed by continuous flicker — just update position
    }

    // MARK: - S-300 / Interceptor — launcher recoil (scaleY)

    private func animateLauncherRecoil() {
        guard let turret = turretNode else { return }
        turret.removeAction(forKey: "launchRecoil")
        let recoil = SKAction.sequence([
            SKAction.scaleY(to: 0.93, duration: 0.08),
            SKAction.scaleY(to: 1.0, duration: 0.15)
        ])
        turret.run(recoil, withKey: "launchRecoil")
    }

    // MARK: - PZRK — soldier recoil

    private func animateSoldierRecoil() {
        guard let turret = turretNode else { return }
        turret.removeAction(forKey: "soldierRecoil")
        turret.position = .zero
        let recoil = SKAction.sequence([
            SKAction.moveBy(x: 0, y: -2.0, duration: 0.06),
            SKAction.moveBy(x: 0, y: 2.0, duration: 0.10)
        ])
        turret.run(recoil, withKey: "soldierRecoil")
    }

    // MARK: - Radar — continuous antenna rotation

    private func startRadarSpin() {
        guard let turret = turretNode else { return }
        turret.removeAction(forKey: "radarSpin")
        let fullRotation = SKAction.rotate(byAngle: .pi * 2, duration: 3.0)
        turret.run(SKAction.repeatForever(fullRotation), withKey: "radarSpin")
    }

    // MARK: - EW Tower — scale pulse

    private func startEWPulse() {
        guard let turret = turretNode else { return }
        turret.removeAction(forKey: "ewPulse")
        let pulse = SKAction.sequence([
            SKAction.scale(to: 1.05, duration: 1.0),
            SKAction.scale(to: 1.0, duration: 1.0)
        ])
        turret.run(SKAction.repeatForever(pulse), withKey: "ewPulse")
    }
}
