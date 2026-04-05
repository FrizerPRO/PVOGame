//
//  AnimationTextureCache.swift
//  PVOGame
//

import SpriteKit

/// Singleton that preloads and caches all game textures.
/// Falls back gracefully when sprites are not yet generated — returns nil textures
/// so callers use their existing colored-square fallback.
final class AnimationTextureCache {
    static let shared = AnimationTextureCache()

    // MARK: - Tower textures (base + turret/launcher + muzzle)

    struct TowerTextures {
        let base: SKTexture?
        let turret: SKTexture?      // turret / launcher / antenna / soldier
        let muzzle: SKTexture?      // muzzle flash (gun towers only)

        let turretSize: CGSize      // pt size of the turret sprite
        let muzzleSize: CGSize      // pt size of muzzle flash sprite
        let turretAnchor: CGPoint   // anchor point for rotation
        let muzzleOffsetLeft: CGPoint   // muzzle position relative to turret center (left barrel)
        let muzzleOffsetRight: CGPoint  // muzzle position relative to turret center (right barrel, for alternating)
    }

    private(set) var towerTextures: [TowerType: TowerTextures] = [:]

    // MARK: - Explosion sprite sheet sequences

    private(set) var smallExplosion: [SKTexture] = []
    private(set) var mediumExplosion: [SKTexture] = []
    private(set) var largeExplosion: [SKTexture] = []

    // MARK: - VFX textures

    private(set) var smokePuff: SKTexture?          // fx_smoke_puff
    private(set) var smokePuffGray: SKTexture?       // fx_smoke_puff_gray
    private(set) var flameGlow: SKTexture?           // fx_flame_glow
    private(set) var damageSmokeTexture: SKTexture?  // fx_damage_smoke
    private(set) var armorSparkTexture: SKTexture?   // fx_armor_spark

    // MARK: - Drone textures

    private(set) var droneTextures: [String: SKTexture] = [:]

    // MARK: - Projectile textures

    private(set) var projectileTextures: [String: SKTexture] = [:]

    // MARK: - Preload

    private var isPreloaded = false

    private init() {}

    /// Call once at app launch. Safe to call multiple times — subsequent calls are no-ops.
    func preload(completion: (() -> Void)? = nil) {
        guard !isPreloaded else { completion?(); return }
        isPreloaded = true

        // Load tower textures per type
        loadTowerTextures()

        // Load explosion atlas if available
        loadExplosionAtlas()

        // Load VFX textures
        smokePuff = loadOptionalTexture("fx_smoke_puff")
        smokePuffGray = loadOptionalTexture("fx_smoke_puff_gray")
        flameGlow = loadOptionalTexture("fx_flame_glow")
        damageSmokeTexture = loadOptionalTexture("fx_damage_smoke")
        armorSparkTexture = loadOptionalTexture("fx_armor_spark")

        // Load drone textures
        let droneNames = [
            "drone_regular", "drone_shahed", "drone_orlan", "drone_kamikaze",
            "drone_ew", "drone_heavy", "drone_lancet", "drone_bomber", "drone_swarm"
        ]
        for name in droneNames {
            if let tex = loadOptionalTexture(name) {
                droneTextures[name] = tex
            }
        }

        // Load projectile textures
        let projNames = [
            "projectile_autocannon", "projectile_ciws", "projectile_gepard",
            "projectile_sam", "projectile_interceptor", "projectile_pzrk",
            "missile_enemy", "missile_harm", "missile_cruise"
        ]
        for name in projNames {
            if let tex = loadOptionalTexture(name) {
                projectileTextures[name] = tex
            }
        }

        completion?()
    }

    // MARK: - Tower texture definitions

    private func loadTowerTextures() {
        // Autocannon (ZU-23-2)
        towerTextures[.autocannon] = TowerTextures(
            base: loadOptionalTexture("tower_autocannon_base"),
            turret: loadOptionalTexture("tower_autocannon_turret"),
            muzzle: loadOptionalTexture("tower_autocannon_muzzle"),
            turretSize: CGSize(width: 42, height: 42),
            muzzleSize: CGSize(width: 14, height: 14),
            turretAnchor: CGPoint(x: 0.5, y: 0.4),
            muzzleOffsetLeft: CGPoint(x: 0, y: 20),        // center (both barrels fire simultaneously)
            muzzleOffsetRight: CGPoint(x: 0, y: 20)        // same position — simultaneous fire
        )

        // CIWS (Pantsir)
        towerTextures[.ciws] = TowerTextures(
            base: loadOptionalTexture("tower_ciws_base"),
            turret: loadOptionalTexture("tower_ciws_turret"),
            muzzle: loadOptionalTexture("tower_ciws_muzzle"),
            turretSize: CGSize(width: 36, height: 36),
            muzzleSize: CGSize(width: 11, height: 11),
            turretAnchor: CGPoint(x: 0.5, y: 0.5),
            muzzleOffsetLeft: CGPoint(x: -5, y: 16),
            muzzleOffsetRight: CGPoint(x: 5, y: 16)
        )

        // SAM Launcher (S-300)
        towerTextures[.samLauncher] = TowerTextures(
            base: loadOptionalTexture("tower_sam_base"),
            turret: loadOptionalTexture("tower_sam_launcher"),
            muzzle: nil,
            turretSize: CGSize(width: 39, height: 39),
            muzzleSize: .zero,
            turretAnchor: CGPoint(x: 0.5, y: 0.5),
            muzzleOffsetLeft: .zero,
            muzzleOffsetRight: .zero
        )

        // Interceptor (Patriot)
        towerTextures[.interceptor] = TowerTextures(
            base: loadOptionalTexture("tower_interceptor_base"),
            turret: loadOptionalTexture("tower_interceptor_launcher"),
            muzzle: nil,
            turretSize: CGSize(width: 36, height: 36),
            muzzleSize: .zero,
            turretAnchor: CGPoint(x: 0.5, y: 0.5),
            muzzleOffsetLeft: .zero,
            muzzleOffsetRight: .zero
        )

        // Radar
        towerTextures[.radar] = TowerTextures(
            base: loadOptionalTexture("tower_radar_base"),
            turret: loadOptionalTexture("tower_radar_antenna"),
            muzzle: nil,
            turretSize: CGSize(width: 42, height: 28),
            muzzleSize: .zero,
            turretAnchor: CGPoint(x: 0.5, y: 0.5),
            muzzleOffsetLeft: .zero,
            muzzleOffsetRight: .zero
        )

        // EW Tower
        towerTextures[.ewTower] = TowerTextures(
            base: loadOptionalTexture("tower_ew_base"),
            turret: loadOptionalTexture("tower_ew_array"),
            muzzle: nil,
            turretSize: CGSize(width: 36, height: 36),
            muzzleSize: .zero,
            turretAnchor: CGPoint(x: 0.5, y: 0.5),
            muzzleOffsetLeft: .zero,
            muzzleOffsetRight: .zero
        )

        // PZRK
        towerTextures[.pzrk] = TowerTextures(
            base: loadOptionalTexture("tower_pzrk_base"),
            turret: loadOptionalTexture("tower_pzrk_soldier"),
            muzzle: nil,
            turretSize: CGSize(width: 28, height: 28),
            muzzleSize: .zero,
            turretAnchor: CGPoint(x: 0.5, y: 0.5),
            muzzleOffsetLeft: .zero,
            muzzleOffsetRight: .zero
        )

        // Gepard
        towerTextures[.gepard] = TowerTextures(
            base: loadOptionalTexture("tower_gepard_base"),
            turret: loadOptionalTexture("tower_gepard_turret"),
            muzzle: loadOptionalTexture("tower_gepard_muzzle"),
            turretSize: CGSize(width: 32, height: 32),
            muzzleSize: CGSize(width: 12, height: 12),
            turretAnchor: CGPoint(x: 0.5, y: 0.45),
            muzzleOffsetLeft: CGPoint(x: -4, y: 16),
            muzzleOffsetRight: CGPoint(x: 4, y: 16)
        )
    }

    // MARK: - Explosion atlas

    private func loadExplosionAtlas() {
        let atlas = SKTextureAtlas(named: "Explosions")
        // Check if atlas actually has textures (not just a missing placeholder)
        guard atlas.textureNames.contains("fx_explosion_small_f1") else { return }

        smallExplosion = (1...5).map { atlas.textureNamed("fx_explosion_small_f\($0)") }
        mediumExplosion = (1...6).map { atlas.textureNamed("fx_explosion_medium_f\($0)") }
        largeExplosion = (1...7).map { atlas.textureNamed("fx_explosion_large_f\($0)") }
    }

    // MARK: - Helpers

    /// Loads a texture from the asset catalog. Returns nil if the image doesn't exist.
    private func loadOptionalTexture(_ named: String) -> SKTexture? {
        guard UIImage(named: named) != nil else {
            print("[TextureCache] MISS: \(named)")
            return nil
        }
        print("[TextureCache] LOADED: \(named)")
        return SKTexture(imageNamed: named)
    }
}
