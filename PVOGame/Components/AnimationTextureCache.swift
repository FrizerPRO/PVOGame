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
        /// Where to place the turret/launcher sprite relative to the base's center.
        /// For multi-cell bases, offset toward the "rear" cell so the launcher sits
        /// on one cell instead of floating between them.
        var turretPosition: CGPoint = .zero
        /// Render size override for the base sprite. When set, the base is rendered
        /// at this size (usually narrower/shorter than the full footprint) so the
        /// native content aspect ratio is preserved. The physics body still covers
        /// the full footprint. Only meaningful when `base` is already cropped to
        /// its non-transparent content region.
        var baseRenderSize: CGSize? = nil
    }

    private(set) var towerTextures: [TowerType: TowerTextures] = [:]

    // MARK: - Explosion sprite sheet sequences

    private(set) var smallExplosion: [SKTexture] = []
    private(set) var mediumExplosion: [SKTexture] = []
    private(set) var largeExplosion: [SKTexture] = []

    // Per-frame hold durations, aligned 1:1 with the *Explosion arrays above.
    // Intermediate half-step frames (f1_5, f2_5, f3_5) get shorter holds so
    // inserting them doesn't stretch the total animation duration.
    private(set) var smallExplosionHolds: [TimeInterval] = []
    private(set) var mediumExplosionHolds: [TimeInterval] = []
    private(set) var largeExplosionHolds: [TimeInterval] = []

    // MARK: - VFX textures

    private(set) var smokePuff: SKTexture?          // fx_smoke_puff
    private(set) var smokePuffGray: SKTexture?       // fx_smoke_puff_gray
    private(set) var flameGlow: SKTexture?           // fx_flame_glow
    private(set) var damageSmokeTexture: SKTexture?  // fx_damage_smoke
    private(set) var ewRing: SKTexture?              // fx_ew_ring
    private(set) var radarPulse: SKTexture?          // fx_radar_pulse
    private(set) var rocketTrailPuff: SKTexture?     // fx_rocket_trail_puff

    /// Directional EW lightning bolt sprites (jagged / forked / branching / twin).
    /// Picked at random for each jamming discharge from the EW drone.
    private(set) var ewBoltTextures: [SKTexture] = []
    /// Radial corona burst sprite, designed to overlay the EW drone itself.
    private(set) var ewBoltBurst: SKTexture?

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
        ewRing = loadOptionalTexture("fx_ew_ring")
        radarPulse = loadOptionalTexture("fx_radar_pulse")
        rocketTrailPuff = loadOptionalTexture("fx_rocket_trail_puff")

        ewBoltTextures = ["fx_ew_bolt_jagged", "fx_ew_bolt_forked",
                          "fx_ew_bolt_branching", "fx_ew_bolt_twin"]
            .compactMap { loadOptionalTexture($0) }
        ewBoltBurst = loadOptionalTexture("fx_ew_bolt_burst")

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

        // SAM Launcher (S-300) — 2×1 vertical chassis, cab on top.
        // Native PNG is 1024² but the truck occupies rows 36..964, cols 316..714
        // (AR 0.429). Crop to that bbox and render at 33×76 to preserve proportions
        // while fitting the 38×76 footprint height.
        let samBaseRaw = loadOptionalTexture("tower_sam_base")
        let samBaseCropped = samBaseRaw.map {
            SKTexture(rect: CGRect(x: 316.0/1024, y: (1024 - 964.0)/1024,
                                   width: 399.0/1024, height: 929.0/1024),
                      in: $0)
        }
        // Visual is scaled to 80% (base + launcher + offset) while keeping the
        // 2×1 grid footprint so the tower occupies the same cells, just looks
        // smaller. Launcher position shrinks proportionally too.
        towerTextures[.samLauncher] = TowerTextures(
            base: samBaseCropped,
            turret: loadOptionalTexture("tower_sam_launcher"),
            muzzle: nil,
            turretSize: CGSize(width: 29, height: 29),
            muzzleSize: .zero,
            turretAnchor: CGPoint(x: 0.5, y: 0.5),
            muzzleOffsetLeft: .zero,
            muzzleOffsetRight: .zero,
            turretPosition: CGPoint(x: 0, y: -10),
            baseRenderSize: CGSize(width: 26, height: 61)
        )

        // Interceptor (Patriot) — 1×2 horizontal chassis, cab on right.
        // Native PNG is 1024² with content in rows 330..693, cols 28..995
        // (AR 2.659). Crop to that bbox and render at 76×29 to preserve
        // proportions while fitting the 76×38 footprint width.
        let intBaseRaw = loadOptionalTexture("tower_interceptor_base")
        let intBaseCropped = intBaseRaw.map {
            SKTexture(rect: CGRect(x: 28.0/1024, y: (1024 - 693.0)/1024,
                                   width: 968.0/1024, height: 364.0/1024),
                      in: $0)
        }
        towerTextures[.interceptor] = TowerTextures(
            base: intBaseCropped,
            turret: loadOptionalTexture("tower_interceptor_launcher"),
            muzzle: nil,
            turretSize: CGSize(width: 36, height: 36),
            muzzleSize: .zero,
            turretAnchor: CGPoint(x: 0.5, y: 0.5),
            muzzleOffsetLeft: .zero,
            muzzleOffsetRight: .zero,
            turretPosition: CGPoint(x: -15, y: 0),
            baseRenderSize: CGSize(width: 76, height: 29)
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

        // EW Tower — 8-wheel chassis with antenna array on the roof. Base content
        // is ~666×815 in a 1024² canvas (AR 0.817), so crop to that bbox and
        // render at 31×38 to keep chassis proportions. Array is shrunk to 26×26
        // so the truck's wheels and mounting hardware stay visible around it.
        let ewBaseRaw = loadOptionalTexture("tower_ew_base")
        let ewBaseCropped = ewBaseRaw.map {
            SKTexture(rect: CGRect(x: 179.0/1024, y: (1024 - 923.0)/1024,
                                   width: 666.0/1024, height: 815.0/1024),
                      in: $0)
        }
        towerTextures[.ewTower] = TowerTextures(
            base: ewBaseCropped,
            turret: loadOptionalTexture("tower_ew_array"),
            muzzle: nil,
            turretSize: CGSize(width: 26, height: 26),
            muzzleSize: .zero,
            turretAnchor: CGPoint(x: 0.5, y: 0.5),
            muzzleOffsetLeft: .zero,
            muzzleOffsetRight: .zero,
            baseRenderSize: CGSize(width: 31, height: 38)
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

        // Oil refinery (НПЗ) — economy building, doesn't fight, so only base
        // texture; turret/muzzle slots stay nil.
        towerTextures[.oilRefinery] = TowerTextures(
            base: loadOptionalTexture("tower_oilrefinery_base"),
            turret: nil,
            muzzle: nil,
            turretSize: .zero,
            muzzleSize: .zero,
            turretAnchor: CGPoint(x: 0.5, y: 0.5),
            muzzleOffsetLeft: .zero,
            muzzleOffsetRight: .zero
        )
    }

    // MARK: - Explosion atlas

    private func loadExplosionAtlas() {
        let atlas = SKTextureAtlas(named: "Explosions")
        let names = atlas.textureNames
        print("[TextureCache] Explosions atlas loaded: \(names.count) textureNames")
        if names.count <= 40 {
            print("[TextureCache]   names: \(names.sorted())")
        }

        // When the atlas is compiled from an asset-catalog .spriteatlas the
        // texture names come out without a namespace prefix (we set
        // provides-namespace=false in Contents.json). On some Xcode versions
        // names may include an "Explosions/" prefix anyway — probe both.
        func hasFrame(size: String, suffix: String) -> Bool {
            let bare = "fx_explosion_\(size)_\(suffix)"
            return names.contains(bare) || names.contains("Explosions/\(bare)")
        }
        func texture(size: String, suffix: String) -> SKTexture {
            let bare = "fx_explosion_\(size)_\(suffix)"
            if names.contains(bare) { return atlas.textureNamed(bare) }
            return atlas.textureNamed("Explosions/\(bare)")
        }

        // Uniform per-frame hold — every texture (main or intermediate f*_5)
        // gets the same duration. Total length scales linearly with the
        // number of rendered frames.
        let perFrameHold: TimeInterval = 0.032

        // Builds the texture sequence for one size by interleaving any
        // available intermediate frames between the main frames. Missing
        // frames are silently skipped.
        func buildSequence(size: String, totalMain: Int) -> ([SKTexture], [TimeInterval]) {
            guard hasFrame(size: size, suffix: "f1") else { return ([], []) }
            var textures: [SKTexture] = []
            var holds: [TimeInterval] = []
            for frame in 1...totalMain {
                textures.append(texture(size: size, suffix: "f\(frame)"))
                holds.append(perFrameHold)
                // Intermediate after this main frame — only defined for
                // early frames (f1_5, f2_5, f3_5).
                if frame <= 3, hasFrame(size: size, suffix: "f\(frame)_5") {
                    textures.append(texture(size: size, suffix: "f\(frame)_5"))
                    holds.append(perFrameHold)
                }
            }
            return (textures, holds)
        }

        // Each size is loaded independently so partial atlases work — e.g. if
        // only medium + large frames are generated, those still play while the
        // small sequence stays empty.
        (smallExplosion, smallExplosionHolds)   = buildSequence(size: "small",  totalMain: 5)
        (mediumExplosion, mediumExplosionHolds) = buildSequence(size: "medium", totalMain: 6)
        (largeExplosion, largeExplosionHolds)   = buildSequence(size: "large",  totalMain: 7)
        print("[TextureCache] explosions loaded: small=\(smallExplosion.count) medium=\(mediumExplosion.count) large=\(largeExplosion.count)")
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
