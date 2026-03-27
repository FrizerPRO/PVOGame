//
//  FireControlState.swift
//  PVOGame
//
//  Extracted from InPlaySKScene — tower AI for rocket/missile targeting.
//

import Foundation
import CoreGraphics
import GameplayKit

struct FireControlState {
    struct PlanningProfile {
        let blastRadius: CGFloat
        let maxRange: CGFloat?
        let nominalSpeed: CGFloat
        let acceleration: CGFloat
        let maxSpeed: CGFloat
    }

    struct LaunchPlan {
        let targetPoint: CGPoint
        let claimedTrackIDs: Set<ObjectIdentifier>
        let eta: TimeInterval
        let score: CGFloat
    }

    private struct TrackState {
        let id: ObjectIdentifier
        var position: CGPoint
        var velocity: CGVector
        var lastUpdateTime: TimeInterval
        var threatWeight: CGFloat
        var health: Int
    }

    private struct Assignment {
        enum Phase {
            case inFlight
            case impactLock(expiresAt: TimeInterval)
        }

        let assignmentID: UUID
        let rocketID: ObjectIdentifier
        let spec: Constants.GameBalance.RocketSpec
        var targetPoint: CGPoint
        var claimedTrackIDs: Set<ObjectIdentifier>
        var eta: TimeInterval
        var createdAt: TimeInterval
        var updatedAt: TimeInterval
        var phase: Phase
    }

    private var tracks = [ObjectIdentifier: TrackState]()
    private var assignments = [ObjectIdentifier: Assignment]()
    private(set) var decisionLog = [String]()
    var trackCount: Int { tracks.count }

    mutating func reset() {
        tracks.removeAll()
        assignments.removeAll()
        decisionLog.removeAll()
    }

    mutating func syncTracks(
        with drones: [AttackDroneEntity],
        currentTime: TimeInterval,
        sceneHeight: CGFloat
    ) {
        let safeHeight = max(sceneHeight, 1)
        var observedIDs = Set<ObjectIdentifier>()
        for drone in drones {
            guard let point = drone.component(ofType: SpriteComponent.self)?.spriteNode.position else {
                continue
            }
            let id = ObjectIdentifier(drone)
            observedIDs.insert(id)
            let previous = tracks[id]
            let velocity: CGVector
            if let previous {
                let dt = currentTime - previous.lastUpdateTime
                if dt > 0.0001 {
                    velocity = CGVector(
                        dx: (point.x - previous.position.x) / dt,
                        dy: (point.y - previous.position.y) / dt
                    )
                } else {
                    velocity = previous.velocity
                }
            } else {
                velocity = CGVector(dx: 0, dy: 0)
            }
            let yNormalized = min(1, max(0, point.y / safeHeight))
            let threatWeight = 1 + (1 - yNormalized) * 1.75
            tracks[id] = TrackState(
                id: id,
                position: point,
                velocity: velocity,
                lastUpdateTime: currentTime,
                threatWeight: threatWeight,
                health: drone.health
            )
        }
        tracks = tracks.filter { observedIDs.contains($0.key) }
    }

    mutating func syncAssignments(
        withActiveRocketIDs activeRocketIDs: Set<ObjectIdentifier>,
        currentTime: TimeInterval
    ) {
        pruneExpiredImpactLocks(currentTime: currentTime)
        assignments = assignments.filter { _, assignment in
            switch assignment.phase {
            case .inFlight:
                return activeRocketIDs.contains(assignment.rocketID)
            case .impactLock:
                return true
            }
        }
    }

    func isDroneReservedByRocket(_ droneID: ObjectIdentifier) -> Bool {
        for assignment in assignments.values {
            if assignment.claimedTrackIDs.contains(droneID) { return true }
        }
        return false
    }

    func totalIncomingDamage(for droneID: ObjectIdentifier) -> Int {
        var total = 0
        for assignment in assignments.values {
            if assignment.claimedTrackIDs.contains(droneID) {
                total += assignment.spec.damage
            }
        }
        return total
    }

    func isDroneOverkilled(_ droneID: ObjectIdentifier) -> Bool {
        guard let track = tracks[droneID] else { return false }
        return totalIncomingDamage(for: droneID) >= track.health
    }

    mutating func handleRocketRemoved(_ rocketID: ObjectIdentifier) {
        guard let assignment = assignments[rocketID] else { return }
        guard case .inFlight = assignment.phase else { return }
        assignments.removeValue(forKey: rocketID)
    }

    mutating func lockAssignmentForImpact(
        rocketID: ObjectIdentifier,
        impactPoint: CGPoint,
        impactRadius: CGFloat,
        currentTime: TimeInterval,
        lockDuration: TimeInterval
    ) {
        guard var assignment = assignments[rocketID] else { return }
        guard impactRadius > 0.01 else {
            assignments.removeValue(forKey: rocketID)
            return
        }
        assignment.targetPoint = impactPoint
        assignment.claimedTrackIDs.removeAll()
        assignment.eta = 0
        assignment.updatedAt = currentTime
        assignment.phase = .impactLock(expiresAt: currentTime + max(lockDuration, 0.01))
        assignments[rocketID] = assignment
    }

    mutating func upsertAssignment(
        rocketID: ObjectIdentifier,
        spec: Constants.GameBalance.RocketSpec,
        targetPoint: CGPoint,
        launchOrigin: CGPoint?,
        currentTime: TimeInterval,
        forcedClaimedTrackIDs: Set<ObjectIdentifier>? = nil
    ) {
        let speed = max(120, spec.initialSpeed)
        let eta = estimatedETA(origin: launchOrigin, target: targetPoint, speed: speed, acceleration: spec.acceleration, maxSpeed: spec.maxSpeed)
        let claimedIDs = forcedClaimedTrackIDs ?? claimedTrackIDs(
            around: targetPoint,
            blastRadius: spec.blastRadius,
            eta: eta
        )
        if var existing = assignments[rocketID] {
            existing.targetPoint = targetPoint
            existing.claimedTrackIDs = claimedIDs
            existing.eta = eta
            existing.updatedAt = currentTime
            existing.phase = .inFlight
            assignments[rocketID] = existing
            return
        }
        assignments[rocketID] = Assignment(
            assignmentID: UUID(),
            rocketID: rocketID,
            spec: spec,
            targetPoint: targetPoint,
            claimedTrackIDs: claimedIDs,
            eta: eta,
            createdAt: currentTime,
            updatedAt: currentTime,
            phase: .inFlight
        )
    }

    mutating func planLaunch(
        preferredPoint: CGPoint?,
        origin: CGPoint?,
        reservingAssignments: Bool,
        excludingRocketID: ObjectIdentifier?,
        profile: PlanningProfile,
        singleTargetReservationSnapDistance: CGFloat = 72,
        singleTargetReservationCoverageRadius: CGFloat = 18
    ) -> LaunchPlan? {
        guard !tracks.isEmpty else {
            appendLog("No tracks: planner has nothing to target.")
            return nil
        }

        let speed = max(120, profile.nominalSpeed)
        let accel = profile.acceleration
        let vMax = profile.maxSpeed
        let blastRadius = max(0, profile.blastRadius)
        let candidateTracks = tracks.values.filter { track in
            guard let origin, let maxRange = profile.maxRange else { return true }
            return Self.squaredDistance(track.position, origin) <= maxRange * maxRange
        }
        guard !candidateTracks.isEmpty else {
            appendLog("No reachable tracks in launch range.")
            return nil
        }

        var candidatePointsByKey = [String: CGPoint]()
        for track in candidateTracks {
            // Damped iterative intercept prediction (4 steps, averaged)
            var predictedTarget = track.position
            for _ in 0..<4 {
                let eta = estimatedETA(origin: origin, target: predictedTarget, speed: speed, acceleration: accel, maxSpeed: vMax)
                let predicted = predictedPosition(for: track, after: eta)
                predictedTarget = CGPoint(
                    x: (predictedTarget.x + predicted.x) * 0.5,
                    y: (predictedTarget.y + predicted.y) * 0.5
                )
            }
            let projectedSeed = predictedTarget
            if let origin, let maxRange = profile.maxRange,
               Self.squaredDistance(projectedSeed, origin) > maxRange * maxRange {
                continue
            }
            let seedETA = estimatedETA(origin: origin, target: projectedSeed, speed: speed, acceleration: accel, maxSpeed: vMax)
            let candidatePoint: CGPoint
            if blastRadius > 0.01 {
                var centroidX: CGFloat = 0
                var centroidY: CGFloat = 0
                var centroidCount = 0
                for otherTrack in candidateTracks {
                    let otherProjected = predictedPosition(for: otherTrack, after: seedETA)
                    guard Self.squaredDistance(otherProjected, projectedSeed) <= blastRadius * blastRadius else { continue }
                    if reservingAssignments {
                        if isTrackReservedByLive(
                            hitID: otherTrack.id,
                            predictedPosition: otherProjected,
                            excludingRocketID: excludingRocketID,
                            singleTargetCoverage: singleTargetReservationCoverageRadius
                        ) { continue }
                    }
                    centroidX += otherProjected.x
                    centroidY += otherProjected.y
                    centroidCount += 1
                }
                if centroidCount == 0 {
                    if reservingAssignments {
                        continue
                    }
                    candidatePoint = projectedSeed
                } else {
                    candidatePoint = CGPoint(
                        x: centroidX / CGFloat(centroidCount),
                        y: centroidY / CGFloat(centroidCount)
                    )
                }
            } else {
                candidatePoint = projectedSeed
            }
            let key = "\(Int((candidatePoint.x * 2).rounded())):\(Int((candidatePoint.y * 2).rounded()))"
            candidatePointsByKey[key] = candidatePoint
        }

        if let preferredPoint {
            let key = "\(Int((preferredPoint.x * 2).rounded())):\(Int((preferredPoint.y * 2).rounded()))"
            candidatePointsByKey[key] = preferredPoint
        }

        let candidatePoints = candidatePointsByKey.values.sorted { lhs, rhs in
            if lhs.x == rhs.x { return lhs.y < rhs.y }
            return lhs.x < rhs.x
        }
        guard !candidatePoints.isEmpty else {
            appendLog("Planner produced no candidate points.")
            return nil
        }

        var bestPlan: LaunchPlan?
        var bestNewCoverage = -1
        var bestPreferredDistance = CGFloat.greatestFiniteMagnitude
        var bestSeparatedPlan: LaunchPlan?
        var bestSeparatedNewCoverage = -1
        var bestSeparatedPreferredDistance = CGFloat.greatestFiniteMagnitude

        func shouldReplacePlan(
            _ currentPlan: LaunchPlan?,
            currentCoverage: Int,
            currentPreferredDistance: CGFloat,
            candidatePoint: CGPoint,
            candidateScore: CGFloat,
            candidateCoverage: Int,
            candidatePreferredDistance: CGFloat
        ) -> Bool {
            guard let currentPlan else { return true }
            let scoreDelta = candidateScore - currentPlan.score
            if scoreDelta > 0.0001 { return true }
            if abs(scoreDelta) <= 0.0001, candidateCoverage > currentCoverage { return true }
            if abs(scoreDelta) <= 0.0001,
               candidateCoverage == currentCoverage,
               candidatePreferredDistance < currentPreferredDistance { return true }
            if abs(scoreDelta) <= 0.0001,
               candidateCoverage == currentCoverage,
               abs(candidatePreferredDistance - currentPreferredDistance) <= 0.0001 {
                if candidatePoint.x == currentPlan.targetPoint.x {
                    return candidatePoint.y < currentPlan.targetPoint.y
                }
                return candidatePoint.x < currentPlan.targetPoint.x
            }
            return false
        }

        for point in candidatePoints {
            if let origin, let maxRange = profile.maxRange,
               Self.squaredDistance(point, origin) > maxRange * maxRange {
                continue
            }

            let eta = estimatedETA(origin: origin, target: point, speed: speed, acceleration: accel, maxSpeed: vMax)
            let hits = impactedTrackIDs(
                around: point,
                blastRadius: blastRadius,
                eta: eta,
                snapDistance: singleTargetReservationSnapDistance
            )
            guard !hits.isEmpty else { continue }

            var newHits = Set<ObjectIdentifier>()
            var overlapCount = 0
            var weightedThreat: CGFloat = 0
            for hitID in hits {
                guard let track = tracks[hitID] else { continue }
                let predicted = predictedPosition(for: track, after: eta)
                if isTrackReservedByLive(
                    hitID: hitID,
                    predictedPosition: predicted,
                    excludingRocketID: excludingRocketID,
                    singleTargetCoverage: singleTargetReservationCoverageRadius
                ) {
                    overlapCount += 1
                } else {
                    newHits.insert(hitID)
                    weightedThreat += track.threatWeight
                }
            }

            if reservingAssignments && newHits.isEmpty { continue }

            var geometricProximityPenalty: CGFloat = 0
            for (rocketID, assignment) in assignments {
                if let excludingRocketID, rocketID == excludingRocketID { continue }
                let avoidanceRadius = softAvoidanceRadius(
                    for: assignment,
                    candidateBlastRadius: blastRadius,
                    singleTargetCoverage: singleTargetReservationCoverageRadius
                )
                guard avoidanceRadius > 0.01 else { continue }
                let distanceSquared = Self.squaredDistance(point, assignment.targetPoint)
                guard distanceSquared < avoidanceRadius * avoidanceRadius else { continue }
                let distance = sqrt(distanceSquared)
                let normalized = 1 - min(1, distance / avoidanceRadius)
                geometricProximityPenalty += normalized
            }
            let preferredDistance: CGFloat
            if let preferredPoint {
                preferredDistance = sqrt(Self.squaredDistance(point, preferredPoint))
            } else {
                preferredDistance = 0
            }
            let etaPenalty = CGFloat(eta) * 0.9
            let overlapPenalty = CGFloat(overlapCount) * 8
            let geometricPenalty = geometricProximityPenalty * (reservingAssignments ? 42 : 18)
            let preferredPenalty = preferredDistance * 0.015
            let score =
                weightedThreat * 12 +
                CGFloat(newHits.count) * 5 -
                overlapPenalty -
                geometricPenalty -
                etaPenalty -
                preferredPenalty

            let claimed = newHits.isEmpty ? hits : newHits
            if shouldReplacePlan(
                bestPlan,
                currentCoverage: bestNewCoverage,
                currentPreferredDistance: bestPreferredDistance,
                candidatePoint: point,
                candidateScore: score,
                candidateCoverage: newHits.count,
                candidatePreferredDistance: preferredDistance
            ) {
                bestPlan = LaunchPlan(
                    targetPoint: point,
                    claimedTrackIDs: claimed,
                    eta: eta,
                    score: score
                )
                bestNewCoverage = newHits.count
                bestPreferredDistance = preferredDistance
            }

            var isSeparatedFromAssignments = true
            for (rocketID, assignment) in assignments {
                if let excludingRocketID, rocketID == excludingRocketID { continue }
                if !isBlastSeparated(
                    candidatePoint: point,
                    candidateBlastRadius: blastRadius,
                    from: assignment,
                    singleTargetCoverage: singleTargetReservationCoverageRadius
                ) {
                    isSeparatedFromAssignments = false
                    break
                }
            }
            if isSeparatedFromAssignments,
               shouldReplacePlan(
                bestSeparatedPlan,
                currentCoverage: bestSeparatedNewCoverage,
                currentPreferredDistance: bestSeparatedPreferredDistance,
                candidatePoint: point,
                candidateScore: score,
                candidateCoverage: newHits.count,
                candidatePreferredDistance: preferredDistance
               ) {
                bestSeparatedPlan = LaunchPlan(
                    targetPoint: point,
                    claimedTrackIDs: claimed,
                    eta: eta,
                    score: score
                )
                bestSeparatedNewCoverage = newHits.count
                bestSeparatedPreferredDistance = preferredDistance
            }
        }

        let selectedPlan: LaunchPlan?
        if reservingAssignments, let bestSeparatedPlan {
            selectedPlan = bestSeparatedPlan
            appendLog("Using non-overlapping impact plan.")
        } else {
            selectedPlan = bestPlan
        }

        if let selectedPlan {
            appendLog(
                "Selected point (\(Int(selectedPlan.targetPoint.x)), \(Int(selectedPlan.targetPoint.y))) " +
                "score=\(String(format: "%.2f", selectedPlan.score)) " +
                "claimed=\(selectedPlan.claimedTrackIDs.count)"
            )
        } else {
            appendLog("No launch plan survived overlap/range constraints.")
        }
        return selectedPlan
    }

    // MARK: - Private Helpers

    private func impactedTrackIDs(
        around point: CGPoint,
        blastRadius: CGFloat,
        eta: TimeInterval,
        snapDistance: CGFloat = 72
    ) -> Set<ObjectIdentifier> {
        if blastRadius > 0.01 {
            let radiusSquared = blastRadius * blastRadius
            var result = Set<ObjectIdentifier>()
            for track in tracks.values {
                let predicted = predictedPosition(for: track, after: eta)
                if Self.squaredDistance(predicted, point) <= radiusSquared {
                    result.insert(track.id)
                }
            }
            return result
        }

        var nearestID: ObjectIdentifier?
        var nearestDistanceSquared = CGFloat.greatestFiniteMagnitude
        for track in tracks.values {
            let predicted = predictedPosition(for: track, after: eta)
            let distanceSquared = Self.squaredDistance(predicted, point)
            if distanceSquared < nearestDistanceSquared {
                nearestDistanceSquared = distanceSquared
                nearestID = track.id
            }
        }
        guard let nearestID else { return [] }
        let maxSnapDistanceSquared = snapDistance * snapDistance
        guard nearestDistanceSquared <= maxSnapDistanceSquared else { return [] }
        return [nearestID]
    }

    private func claimedTrackIDs(
        around point: CGPoint,
        blastRadius: CGFloat,
        eta: TimeInterval
    ) -> Set<ObjectIdentifier> {
        impactedTrackIDs(around: point, blastRadius: blastRadius, eta: eta)
    }

    private func isTrackReserved(
        hitID: ObjectIdentifier,
        predictedPosition: CGPoint,
        by assignments: [Assignment],
        singleTargetCoverage: CGFloat
    ) -> Bool {
        for assignment in assignments {
            if !assignment.claimedTrackIDs.isEmpty {
                if assignment.claimedTrackIDs.contains(hitID) { return true }
                continue
            }
            if isPointCovered(predictedPosition, by: assignment, singleTargetCoverage: singleTargetCoverage) { return true }
        }
        return false
    }

    private func isTrackReservedByLive(
        hitID: ObjectIdentifier,
        predictedPosition: CGPoint,
        excludingRocketID: ObjectIdentifier?,
        singleTargetCoverage: CGFloat
    ) -> Bool {
        for (rocketID, assignment) in assignments {
            if let excludingRocketID, rocketID == excludingRocketID { continue }
            if !assignment.claimedTrackIDs.isEmpty {
                if assignment.claimedTrackIDs.contains(hitID) { return true }
                continue
            }
            if isPointCovered(predictedPosition, by: assignment, singleTargetCoverage: singleTargetCoverage) { return true }
        }
        return false
    }

    private func isPointCovered(
        _ point: CGPoint,
        by assignment: Assignment,
        singleTargetCoverage: CGFloat
    ) -> Bool {
        let coverageRadius: CGFloat = assignment.spec.blastRadius > 0.01
            ? assignment.spec.blastRadius
            : singleTargetCoverage
        return Self.squaredDistance(point, assignment.targetPoint) <= coverageRadius * coverageRadius
    }

    private func softAvoidanceRadius(
        for assignment: Assignment,
        candidateBlastRadius: CGFloat,
        singleTargetCoverage: CGFloat
    ) -> CGFloat {
        let assignmentCoverage: CGFloat = assignment.spec.blastRadius > 0.01
            ? assignment.spec.blastRadius
            : singleTargetCoverage * 2.2
        let candidateCoverage: CGFloat = candidateBlastRadius > 0.01
            ? candidateBlastRadius
            : singleTargetCoverage * 1.6
        return max(assignmentCoverage, candidateCoverage)
    }

    private func isBlastSeparated(
        candidatePoint: CGPoint,
        candidateBlastRadius: CGFloat,
        from assignment: Assignment,
        singleTargetCoverage: CGFloat
    ) -> Bool {
        let minimumDistance = blastConflictDistance(
            candidateBlastRadius: candidateBlastRadius,
            assignment: assignment,
            singleTargetCoverage: singleTargetCoverage
        )
        return Self.squaredDistance(candidatePoint, assignment.targetPoint) >= minimumDistance * minimumDistance
    }

    private func blastConflictDistance(
        candidateBlastRadius: CGFloat,
        assignment: Assignment,
        singleTargetCoverage: CGFloat
    ) -> CGFloat {
        let assignmentCoverage: CGFloat = assignment.spec.blastRadius > 0.01
            ? assignment.spec.blastRadius
            : singleTargetCoverage
        let candidateCoverage: CGFloat = candidateBlastRadius > 0.01
            ? candidateBlastRadius
            : singleTargetCoverage
        return assignmentCoverage + candidateCoverage
    }

    private mutating func pruneExpiredImpactLocks(currentTime: TimeInterval) {
        assignments = assignments.filter { _, assignment in
            switch assignment.phase {
            case .inFlight:
                return true
            case let .impactLock(expiresAt):
                return expiresAt > currentTime
            }
        }
    }

    private func predictedPosition(for track: TrackState, after delta: TimeInterval) -> CGPoint {
        CGPoint(
            x: track.position.x + track.velocity.dx * delta,
            y: track.position.y + track.velocity.dy * delta
        )
    }

    private func estimatedETA(
        origin: CGPoint?,
        target: CGPoint,
        speed: CGFloat,
        acceleration: CGFloat = 0,
        maxSpeed: CGFloat = .greatestFiniteMagnitude
    ) -> TimeInterval {
        guard let origin else { return 0 }
        let distance = sqrt(Self.squaredDistance(origin, target))
        let v0 = max(speed, 1)
        guard distance > 0.0001 else { return 0 }
        guard acceleration > 0.0001, v0 < maxSpeed else {
            return TimeInterval(distance / v0)
        }
        let vMax = maxSpeed
        let a = acceleration
        let tAccel = (vMax - v0) / a
        let dAccel = v0 * tAccel + 0.5 * a * tAccel * tAccel
        if dAccel >= distance {
            let t = (-v0 + sqrt(v0 * v0 + 2 * a * distance)) / a
            return TimeInterval(t)
        }
        return TimeInterval(tAccel + (distance - dAccel) / vMax)
    }

    static func squaredDistance(_ lhs: CGPoint, _ rhs: CGPoint) -> CGFloat {
        let dx = lhs.x - rhs.x
        let dy = lhs.y - rhs.y
        return dx * dx + dy * dy
    }

    private mutating func appendLog(_ line: String) {
        decisionLog.append(line)
        let maxEntries = 60
        if decisionLog.count > maxEntries {
            decisionLog.removeFirst(decisionLog.count - maxEntries)
        }
    }
}
