//
//  RadarComponent.swift
//  PVOGame
//
//  Player radar tower behavior:
//   - Day:    only the spinning antenna is visible — no rings, no overlays.
//   - Night:  a classic phosphor-green PPI activates around the tower.
//             A static overlay (faint disc backdrop + range rings + lubber
//             line + center crosshair) frames the display, and a rotating
//             sweep (two stacked pie sectors approximating phosphor afterglow,
//             plus a brighter leading-edge line) rakes around it. Whenever
//             the leading edge crosses an enemy drone's angular position, a
//             round blip with a halo is dropped at WHERE THE DRONE WAS at
//             that exact moment (frozen position, not live). Blips fade over
//             one sweep period so the next pass refreshes them.
//
//  Visuals are added directly to the scene at zPosition above the night
//  overlay (which is a fully-opaque black SKSpriteNode at z=90). Anything
//  parented to the tower or drone sprite would sit at z<90 and be hidden.
//

import GameplayKit
import SpriteKit

class RadarComponent: GKComponent {
    /// Static, non-rotating elements: backdrop disc, range rings, lubber line,
    /// center crosshair. Repositioned each frame to follow the tower.
    private var staticOverlay: SKNode?
    /// Rotating container at the radar position; holds the sweep sectors and
    /// leading-edge line.
    private var sweepContainer: SKNode?
    /// Per-drone "last seen" blips at the position the drone occupied when
    /// the sweep last crossed its angular bearing.
    private var blips: [ObjectIdentifier: SKNode] = [:]

    /// Sweep state — radians, [0, 2π). Advanced manually each frame so the
    /// detection logic (which checks "did angle X get crossed since last
    /// frame?") stays in sync with the visual rotation.
    private var sweepAngle: CGFloat = 0
    private var previousSweepAngle: CGFloat = 0

    /// One full revolution per `sweepPeriod` seconds. Blips fade out over the
    /// same duration so each sweep refreshes them.
    private let sweepPeriod: TimeInterval = 3.0

    // Phosphor-green palette — muted, classic CRT PPI look.
    private static let structureColor = UIColor(red: 0.10, green: 0.75, blue: 0.30, alpha: 1.0)
    private static let backdropColor  = UIColor(red: 0.00, green: 0.18, blue: 0.05, alpha: 1.0)
    private static let sweepColor     = UIColor(red: 0.20, green: 1.00, blue: 0.35, alpha: 1.0)
    private static let blipColor      = UIColor(red: 0.30, green: 1.00, blue: 0.45, alpha: 1.0)

    override init() { super.init() }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func update(deltaTime seconds: TimeInterval) {
        guard let tower = entity as? TowerEntity,
              let stats = tower.component(ofType: TowerStatsComponent.self),
              let towerSprite = tower.component(ofType: SpriteComponent.self)?.spriteNode,
              let scene = towerSprite.scene as? InPlaySKScene
        else { return }

        // Day, disabled, or no scene → tear everything down.
        guard !stats.isDisabled, scene.isNightWave else {
            removeVisuals()
            removeAllBlips()
            return
        }

        let towerPos = towerSprite.position
        let range = stats.range
        let rangeSq = range * range

        ensureVisuals(at: towerPos, range: range, in: scene)

        // Advance sweep — store previous so we can check what got crossed.
        previousSweepAngle = sweepAngle
        let sweepSpeed = 2 * CGFloat.pi / CGFloat(sweepPeriod)
        var nextAngle = sweepAngle + sweepSpeed * CGFloat(seconds)
        // Normalize to [0, 2π).
        nextAngle = nextAngle.truncatingRemainder(dividingBy: 2 * .pi)
        if nextAngle < 0 { nextAngle += 2 * .pi }
        sweepAngle = nextAngle

        staticOverlay?.position = towerPos
        sweepContainer?.position = towerPos
        sweepContainer?.zRotation = sweepAngle

        // For each drone in range, check if the sweep just crossed its bearing
        // this frame. If yes, snapshot its current position as a blip.
        // We blip ONLY drones that gun towers can engage (low/medium/micro
        // altitudes). Cruise missiles and ballistic rockets aren't shot at by
        // guns, so they shouldn't show up as targets on the gun-aiming PPI.
        for drone in scene.activeDronesForTowers {
            guard !drone.isHit,
                  let droneSprite = drone.component(ofType: SpriteComponent.self)?.spriteNode
            else { continue }
            let altitude = drone.component(ofType: AltitudeComponent.self)?.altitude ?? .low
            guard Self.gunEngageableAltitudes.contains(altitude) else { continue }

            let dronePos = droneSprite.position
            let dx = dronePos.x - towerPos.x
            let dy = dronePos.y - towerPos.y
            guard dx * dx + dy * dy <= rangeSq else { continue }

            var droneAngle = atan2(dy, dx)
            if droneAngle < 0 { droneAngle += 2 * .pi }

            if sweepCrossed(prev: previousSweepAngle, curr: sweepAngle, target: droneAngle) {
                placeBlip(for: ObjectIdentifier(drone), at: dronePos, in: scene)
            }
        }
    }

    /// Altitudes that any gun-based AA tower (autocannon/ciws/gepard/pzrk)
    /// can hit. Drones above this — cruise missiles, ballistic rockets — are
    /// invisible to gun targeting and so are never blipped on the gun PPI.
    private static let gunEngageableAltitudes: Set<DroneAltitude> = [.low, .medium, .micro]

    /// True if the sweep, advancing from `prev` to `curr` (CCW, normalized
    /// to [0, 2π)), crossed `target` this frame. Handles the wraparound case
    /// where the sweep crossed the 0/2π boundary.
    private func sweepCrossed(prev: CGFloat, curr: CGFloat, target: CGFloat) -> Bool {
        if prev <= curr {
            return target > prev && target <= curr
        }
        // Wrapped around: prev was just before 2π, curr is just after 0.
        return target > prev || target <= curr
    }

    // MARK: - Visuals

    private func ensureVisuals(at pos: CGPoint, range: CGFloat, in scene: SKScene) {
        ensureStaticOverlay(at: pos, range: range, in: scene)
        ensureSweepContainer(at: pos, range: range, in: scene)
    }

    private func ensureStaticOverlay(at pos: CGPoint, range: CGFloat, in scene: SKScene) {
        if staticOverlay != nil { return }
        let overlay = SKNode()
        overlay.position = pos
        overlay.zPosition = Constants.NightWave.nightEffectZPosition + 1
        scene.addChild(overlay)

        // Backdrop disc — very faint dark-green fill so the operator's
        // "screen" reads as a panel rather than the sweep floating in space.
        let backdrop = SKShapeNode(circleOfRadius: range)
        backdrop.fillColor = Self.backdropColor.withAlphaComponent(0.18)
        backdrop.strokeColor = Self.structureColor.withAlphaComponent(0.45)
        backdrop.lineWidth = 1.0
        overlay.addChild(backdrop)

        // Range rings at 33% and 66% (the 100% ring is the disc edge above).
        for fraction in [CGFloat(0.33), CGFloat(0.66)] {
            let ring = SKShapeNode(circleOfRadius: range * fraction)
            ring.fillColor = .clear
            ring.strokeColor = Self.structureColor.withAlphaComponent(0.30)
            ring.lineWidth = 1.0
            overlay.addChild(ring)
        }

        // Lubber line — points "up" on the PPI as a heading reference.
        let lubberPath = CGMutablePath()
        lubberPath.move(to: .zero)
        lubberPath.addLine(to: CGPoint(x: 0, y: range))
        let lubber = SKShapeNode(path: lubberPath)
        lubber.strokeColor = Self.structureColor.withAlphaComponent(0.40)
        lubber.lineWidth = 1.0
        overlay.addChild(lubber)

        // Center crosshair — small "+" so the radar position itself reads
        // as a fixed point on the display.
        let crossPath = CGMutablePath()
        let armLen: CGFloat = 6
        crossPath.move(to: CGPoint(x: -armLen, y: 0))
        crossPath.addLine(to: CGPoint(x:  armLen, y: 0))
        crossPath.move(to: CGPoint(x: 0, y: -armLen))
        crossPath.addLine(to: CGPoint(x: 0, y:  armLen))
        let cross = SKShapeNode(path: crossPath)
        cross.strokeColor = Self.structureColor.withAlphaComponent(0.55)
        cross.lineWidth = 1.0
        overlay.addChild(cross)

        staticOverlay = overlay
    }

    private func ensureSweepContainer(at pos: CGPoint, range: CGFloat, in scene: SKScene) {
        if sweepContainer != nil { return }
        let container = SKNode()
        container.position = pos
        container.zPosition = Constants.NightWave.nightEffectZPosition + 1
        scene.addChild(container)

        // Phosphor-afterglow wedge: a single sprite carrying a pre-rendered
        // conic gradient that fades from the bright leading edge (angle 0
        // in container frame) back through ~80° of trail. Using a real
        // gradient avoids the visible step you get from stacking SKShapeNode
        // sectors at different alphas.
        let sweepWedgeAngle: CGFloat = .pi * 80 / 180  // 80°
        let texture = Self.makeSweepTexture(
            range: range,
            sweepAngleRad: sweepWedgeAngle,
            color: Self.sweepColor
        )
        let wedge = SKSpriteNode(texture: texture)
        wedge.size = CGSize(width: range * 2, height: range * 2)
        wedge.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        wedge.position = .zero
        wedge.blendMode = .alpha
        container.addChild(wedge)

        // Bright thin line on the leading edge (angle 0 in container space).
        let leadingPath = CGMutablePath()
        leadingPath.move(to: .zero)
        leadingPath.addLine(to: CGPoint(x: range, y: 0))
        let leading = SKShapeNode(path: leadingPath)
        leading.strokeColor = Self.sweepColor.withAlphaComponent(0.70)
        leading.lineWidth = 1.5
        leading.glowWidth = 1.0
        container.addChild(leading)

        sweepContainer = container
    }

    /// Builds a square RGBA texture containing a conic-gradient wedge:
    /// fully opaque (at `peakAlpha`) along sprite-frame angle 0, fading to
    /// zero alpha at angle `-sweepAngleRad` (i.e. the trail goes CW from
    /// the leading edge in SK's math frame). Outside that arc, alpha = 0.
    /// The image is computed in CPU once per radar — cost is negligible
    /// for a ~260px disc and avoids the visible banding of stacked sectors.
    private static func makeSweepTexture(range: CGFloat,
                                          sweepAngleRad: CGFloat,
                                          color: UIColor) -> SKTexture {
        let side = max(8, Int(ceil(range * 2)))
        let pixelCount = side * side
        var pixels = [UInt8](repeating: 0, count: pixelCount * 4)

        var rC: CGFloat = 0, gC: CGFloat = 0, bC: CGFloat = 0, aC: CGFloat = 0
        color.getRed(&rC, green: &gC, blue: &bC, alpha: &aC)
        let cr = Float(rC), cg = Float(gC), cb = Float(bC)

        let halfSide = CGFloat(side) / 2
        let rangeSq = range * range
        let invSweep = 1 / sweepAngleRad
        // Peak alpha at the leading edge — kept moderate so the wedge feels
        // like an afterglow rather than a solid pie slice.
        let peakAlpha: Float = 0.40
        // Falloff exponent: >1 concentrates brightness near the leading edge.
        let falloff: Float = 1.6

        pixels.withUnsafeMutableBufferPointer { buf in
            for py in 0..<side {
                let dyImage = CGFloat(py) + 0.5 - halfSide
                let dy = -dyImage  // flip CG y-down to SK sprite-frame y-up
                for px in 0..<side {
                    let dx = CGFloat(px) + 0.5 - halfSide
                    let r2 = dx * dx + dy * dy
                    if r2 > rangeSq { continue }

                    let angle = atan2(dy, dx)  // (-π, π]
                    // Sweep occupies angles in [-sweepAngleRad, 0].
                    if angle > 0 || angle < -sweepAngleRad { continue }

                    let t = Float((angle + sweepAngleRad) * invSweep)  // 0 at trail → 1 at leading
                    let alphaF = pow(t, falloff) * peakAlpha
                    // Premultiplied alpha (premultipliedLast).
                    let idx = (py * side + px) * 4
                    buf[idx]     = UInt8(min(255, max(0, cr * alphaF * 255)))
                    buf[idx + 1] = UInt8(min(255, max(0, cg * alphaF * 255)))
                    buf[idx + 2] = UInt8(min(255, max(0, cb * alphaF * 255)))
                    buf[idx + 3] = UInt8(min(255, max(0, alphaF * 255)))
                }
            }
        }

        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        let provider = CGDataProvider(data: NSData(bytes: pixels, length: pixels.count))!
        let cgImage = CGImage(
            width: side, height: side,
            bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: side * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo,
            provider: provider, decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )!
        return SKTexture(cgImage: cgImage)
    }

    private func removeVisuals() {
        staticOverlay?.removeFromParent()
        staticOverlay = nil
        sweepContainer?.removeFromParent()
        sweepContainer = nil
    }

    // MARK: - Blips (frozen "last seen" positions)

    private func placeBlip(for id: ObjectIdentifier, at pos: CGPoint, in scene: InPlaySKScene) {
        // Replace any existing blip for this drone with a fresh one at the
        // newly-detected position. Existing blip is yanked out instantly so
        // we don't end up stacking multiple stale blips per drone.
        blips[id]?.removeFromParent()

        let blip = SKNode()
        blip.position = pos
        blip.zPosition = Constants.NightWave.nightEffectZPosition + 1
        blip.alpha = 1.0

        // Soft halo — larger, low-alpha, mimics phosphor bleed around the dot.
        let halo = SKShapeNode(circleOfRadius: 7)
        halo.fillColor = Self.blipColor.withAlphaComponent(0.30)
        halo.strokeColor = .clear
        blip.addChild(halo)

        // Bright core dot.
        let core = SKShapeNode(circleOfRadius: 3)
        core.fillColor = Self.blipColor
        core.strokeColor = .clear
        core.glowWidth = 1.0
        blip.addChild(core)

        scene.addChild(blip)

        // Fade out over one sweep period so blips have a natural "radar
        // persistence" — by the time the sweep returns, the previous blip
        // is almost gone and gets refreshed at the drone's new position.
        blip.run(SKAction.sequence([
            SKAction.fadeAlpha(to: 0, duration: sweepPeriod),
            SKAction.removeFromParent()
        ]))
        blips[id] = blip

        // Register this blip in the scene's gun-targeting registry so gun
        // towers can fire at the frozen position instead of the drone's live
        // position. Expiry matches the visual fade duration.
        let now = CACurrentMediaTime()
        scene.nightBlips[id] = InPlaySKScene.NightBlip(
            position: pos, expiry: now + sweepPeriod
        )
    }

    private func removeAllBlips() {
        for (_, blip) in blips { blip.removeFromParent() }
        blips.removeAll()
    }
}
