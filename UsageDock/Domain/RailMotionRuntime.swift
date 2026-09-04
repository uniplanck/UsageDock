import CoreGraphics
import Foundation

enum RailDragPhase: Equatable {
    case attached
    case floating
    case returning
    case docking
    case wetting
}

struct RailMotionFrame: Equatable {
    let rawProgress: CGFloat
    let canvasExtraWidth: CGFloat
    let stretch: CGFloat
    let detach: CGFloat
    let contentTravel: CGFloat
    let verticalPosition: Double
    let kinetic: CGFloat
    let impact: CGFloat
    let breakPulse: CGFloat
    let floatingCenterX: CGFloat
    let floatingCenterY: CGFloat
    let residue: CGFloat
    let wetting: CGFloat
}

struct RailMotionRuntime {
    static let detachStart: CGFloat = 0.12
    static let surfaceBreakThreshold: CGFloat = 0.30
    static let dockThreshold: CGFloat = 0.50

    // Compatibility name for older call sites/tests while F17.11 migrates the meaning
    // from "transfer" to "surface break".
    static let detachThreshold: CGFloat = surfaceBreakThreshold

    private enum FloatingMotionMode {
        case free
        case returning
        case docking
    }

    private struct SpringChannel {
        var position: CGFloat = 0
        var velocity: CGFloat = 0

        mutating func reset(_ position: CGFloat, velocity: CGFloat = 0) {
            self.position = position
            self.velocity = velocity
        }

        mutating func step(
            toward target: CGFloat,
            dt: CGFloat,
            response: CGFloat,
            dampingRatio: CGFloat
        ) {
            guard dt > 0 else { return }
            let maxSubstep: CGFloat = 1.0 / 240.0
            let count = max(1, min(24, Int(ceil(dt / maxSubstep))))
            let h = dt / CGFloat(count)
            let omega = (2 * CGFloat.pi) / max(response, 0.055)
            let stiffness = omega * omega
            let damping = 2 * dampingRatio * omega

            for _ in 0..<count {
                let acceleration = stiffness * (target - position) - damping * velocity
                velocity += acceleration * h
                position += velocity * h
            }
        }
    }

    private var widthSpring = SpringChannel()
    private var stretchSpring = SpringChannel()
    private var detachSpring = SpringChannel()
    private var contentSpring = SpringChannel()
    private var verticalSpring = SpringChannel()
    private var kineticSpring = SpringChannel()
    private var impactSpring = SpringChannel()
    private var breakPulseSpring = SpringChannel()
    private var floatingXSpring = SpringChannel()
    private var floatingYSpring = SpringChannel()
    private var residueSpring = SpringChannel()
    private var wettingSpring = SpringChannel()

    private var lastTimestamp: TimeInterval = 0
    private var previousOutwardDistance: CGFloat = 0
    private var filteredPointerVelocity: CGFloat = 0
    private var filteredPointerAcceleration: CGFloat = 0
    private var hasPointerSample = false
    private var rawProgress: CGFloat = 0

    private var floatingTargetX: CGFloat = 0
    private var floatingTargetY: CGFloat = 0
    private var previousFloatingTargetX: CGFloat = 0
    private var previousFloatingTargetY: CGFloat = 0
    private var filteredFloatingSpeed: CGFloat = 0
    private var hasFloatingSample = false

    private(set) var targetVerticalPosition: Double = 0
    private(set) var outwardVelocity: CGFloat = 0

    mutating func begin(
        verticalPosition: Double,
        originCenter: CGPoint = .zero,
        timestamp: TimeInterval
    ) {
        lastTimestamp = timestamp
        previousOutwardDistance = 0
        filteredPointerVelocity = 0
        filteredPointerAcceleration = 0
        hasPointerSample = false
        rawProgress = 0
        targetVerticalPosition = min(max(verticalPosition, 0), 1)
        outwardVelocity = 0

        floatingTargetX = originCenter.x
        floatingTargetY = originCenter.y
        previousFloatingTargetX = originCenter.x
        previousFloatingTargetY = originCenter.y
        filteredFloatingSpeed = 0
        hasFloatingSample = false

        widthSpring.reset(0)
        stretchSpring.reset(0)
        detachSpring.reset(0)
        contentSpring.reset(0)
        verticalSpring.reset(CGFloat(targetVerticalPosition))
        kineticSpring.reset(0)
        impactSpring.reset(0)
        breakPulseSpring.reset(0)
        floatingXSpring.reset(originCenter.x)
        floatingYSpring.reset(originCenter.y)
        residueSpring.reset(0)
        wettingSpring.reset(0)
    }

    mutating func updateDrag(
        outwardDistance: CGFloat,
        screenProgress: CGFloat,
        screenWidth: CGFloat,
        verticalTarget: Double,
        timestamp: TimeInterval
    ) -> RailMotionFrame {
        let time = advanceTime(timestamp)
        let distance = max(outwardDistance, 0)
        let width = max(screenWidth, 1)
        targetVerticalPosition = min(max(verticalTarget, 0), 1)

        updatePointerDynamics(distance: distance, measurementDt: time.measurement)

        let elasticDistance = min(max(width * 0.18, 280), 520)
        rawProgress = min(distance / elasticDistance, 1.45)

        let speedNormalized = min(abs(filteredPointerVelocity) / 2_200, 1)
        let outwardSpeedNormalized = min(max(filteredPointerVelocity, 0) / 2_200, 1)
        let accelerationNormalized = min(max(filteredPointerAcceleration, 0) / 28_000, 1)
        let kineticTarget = min(
            speedNormalized * 0.78 + min(abs(filteredPointerAcceleration) / 36_000, 1) * 0.22,
            1
        )

        let baseStretch = Self.stretchTarget(for: rawProgress)
        let targetStretch = min(
            baseStretch + 0.18 * outwardSpeedNormalized + 0.035 * accelerationNormalized,
            1.30
        )
        let velocityLead = min(max(filteredPointerVelocity, 0) * 0.018, 72)
        let maxExtraWidth = min(width * 0.46, 1_080)
        let targetExtraWidth = min(
            maxExtraWidth,
            distance * 0.84 + 112 * targetStretch + velocityLead
        )
        let targetContentTravel = min(
            maxExtraWidth,
            distance * 0.80 + 88 * targetStretch + velocityLead * 0.45
        )
        let targetDetach = Self.smoothStep(
            min(max(screenProgress, 0), 1),
            from: Self.detachStart,
            to: Self.surfaceBreakThreshold
        )

        stepChannels(
            widthTarget: targetExtraWidth,
            stretchTarget: targetStretch,
            detachTarget: targetDetach,
            contentTarget: targetContentTravel,
            verticalTarget: CGFloat(targetVerticalPosition),
            kineticTarget: kineticTarget,
            impactTarget: 0,
            dt: time.integration,
            kinetic: kineticTarget
        )

        residueSpring.step(toward: 0, dt: time.integration, response: 0.22, dampingRatio: 0.56)
        outwardVelocity = filteredPointerVelocity
        return frame
    }

    mutating func release(timestamp: TimeInterval) -> RailMotionFrame {
        let time = advanceTime(timestamp)
        rawProgress = 0
        let releaseEnergy = min(
            abs(filteredPointerVelocity) / 2_400 + abs(filteredPointerAcceleration) / 42_000,
            1
        )
        impactSpring.position = max(impactSpring.position, 0.18 + 0.42 * releaseEnergy)
        impactSpring.velocity += 0.7 * releaseEnergy

        stepTowardRest(dt: time.integration)
        residueSpring.step(toward: 0, dt: time.integration, response: 0.22, dampingRatio: 0.56)
        return frame
    }

    mutating func breakSurface(
        floatingCenter: CGPoint,
        verticalPosition: Double,
        timestamp: TimeInterval
    ) -> RailMotionFrame {
        let time = advanceTime(timestamp)
        targetVerticalPosition = min(max(verticalPosition, 0), 1)
        rawProgress = 0

        let motionEnergy = min(
            abs(filteredPointerVelocity) / 2_400 + abs(filteredPointerAcceleration) / 42_000,
            1
        )

        floatingTargetX = floatingCenter.x
        floatingTargetY = floatingCenter.y
        previousFloatingTargetX = floatingCenter.x
        previousFloatingTargetY = floatingCenter.y
        filteredFloatingSpeed = abs(filteredPointerVelocity) * 0.28
        hasFloatingSample = true

        // Rupture is an event, not a distance effect. Every break gets the same strong
        // surface-tension collapse/rebound; pointer energy only flavors the later free motion.
        widthSpring.reset(26, velocity: -190)
        stretchSpring.reset(0.28, velocity: -1.15)
        detachSpring.reset(0)
        contentSpring.reset(0)
        verticalSpring.reset(CGFloat(targetVerticalPosition))
        kineticSpring.reset(max(0.20, motionEnergy * 0.42))

        impactSpring.reset(1.0, velocity: 2.8)
        breakPulseSpring.reset(0, velocity: 9.6)
        // F17.20: the anchor-side remnant gets an event-driven bulge with enough
        // momentum to cross through zero once, producing a visible snap-back before
        // the residue disappears. Distance never changes this initial impulse.
        residueSpring.reset(1.25, velocity: 10.8)
        floatingXSpring.reset(floatingCenter.x)
        floatingYSpring.reset(floatingCenter.y)
        wettingSpring.reset(0)

        stepFloating(mode: .free, dt: time.integration, kinetic: max(0.20, motionEnergy * 0.42))
        return frame
    }

    mutating func updateFloating(
        floatingCenter: CGPoint,
        verticalPosition: Double,
        timestamp: TimeInterval
    ) -> RailMotionFrame {
        let time = advanceTime(timestamp)
        targetVerticalPosition = min(max(verticalPosition, 0), 1)
        updateFloatingDynamics(target: floatingCenter, measurementDt: time.measurement)
        floatingTargetX = floatingCenter.x
        floatingTargetY = floatingCenter.y
        rawProgress = 0

        let energy = min(filteredFloatingSpeed / 2_500, 1)
        stepFloating(mode: .free, dt: time.integration, kinetic: energy)
        return frame
    }

    mutating func tickFloating(timestamp: TimeInterval) -> RailMotionFrame {
        let time = advanceTime(timestamp)
        let decay = CGFloat(exp(-Double(time.measurement) / 0.085))
        filteredFloatingSpeed *= decay
        let energy = min(filteredFloatingSpeed / 2_500, 1)
        stepFloating(mode: .free, dt: time.integration, kinetic: energy)
        return frame
    }

    mutating func beginReturn(
        to center: CGPoint,
        verticalPosition: Double,
        timestamp: TimeInterval
    ) -> RailMotionFrame {
        let time = advanceTime(timestamp)
        floatingTargetX = center.x
        floatingTargetY = center.y
        targetVerticalPosition = min(max(verticalPosition, 0), 1)
        rawProgress = 0
        residueSpring.position = 0
        residueSpring.velocity = 0
        wettingSpring.reset(0)
        impactSpring.position = max(impactSpring.position, 0.38)
        impactSpring.velocity += 0.70
        stepFloating(mode: .returning, dt: time.integration, kinetic: min(filteredFloatingSpeed / 2_500, 1))
        return frame
    }

    mutating func stepReturn(timestamp: TimeInterval) -> RailMotionFrame {
        let time = advanceTime(timestamp)
        let decay = CGFloat(exp(-Double(time.measurement) / 0.10))
        filteredFloatingSpeed *= decay
        stepFloating(mode: .returning, dt: time.integration, kinetic: min(filteredFloatingSpeed / 2_500, 1))
        return frame
    }

    mutating func beginDock(
        to center: CGPoint,
        verticalPosition: Double,
        incomingVelocity: CGFloat,
        timestamp: TimeInterval
    ) -> RailMotionFrame {
        let time = advanceTime(timestamp)
        floatingTargetX = center.x
        floatingTargetY = center.y
        targetVerticalPosition = min(max(verticalPosition, 0), 1)
        rawProgress = 0
        residueSpring.position = 0
        residueSpring.velocity = 0
        wettingSpring.reset(0)

        let energy = min(max(abs(incomingVelocity), filteredFloatingSpeed) / 2_600, 1)
        impactSpring.position = max(impactSpring.position, 0.62 + 0.28 * energy)
        impactSpring.velocity += 1.05 + 0.85 * energy
        kineticSpring.position = max(kineticSpring.position, energy)
        stepFloating(mode: .docking, dt: time.integration, kinetic: energy)
        return frame
    }

    mutating func stepDock(timestamp: TimeInterval) -> RailMotionFrame {
        let time = advanceTime(timestamp)
        let decay = CGFloat(exp(-Double(time.measurement) / 0.085))
        filteredFloatingSpeed *= decay
        stepFloating(mode: .docking, dt: time.integration, kinetic: min(filteredFloatingSpeed / 2_500, 1))
        return frame
    }

    mutating func beginWetting(
        verticalPosition: Double,
        incomingVelocity: CGFloat,
        timestamp: TimeInterval
    ) -> RailMotionFrame {
        let time = advanceTime(timestamp)
        targetVerticalPosition = min(max(verticalPosition, 0), 1)
        rawProgress = 0
        let energy = min(max(abs(incomingVelocity), filteredFloatingSpeed) / 2_600, 1)

        // Contact first compresses the drop, then the wetting front spreads across the
        // screen edge. A slightly under-damped progress spring gives the requested
        // "juwaa" expansion without snapping directly to the final Rail silhouette.
        wettingSpring.reset(0.04, velocity: 0.72 + 0.46 * energy)
        impactSpring.position = max(impactSpring.position, 0.58 + 0.22 * energy)
        impactSpring.velocity += 0.52 + 0.42 * energy
        stretchSpring.position = max(stretchSpring.position, 0.12 + 0.06 * energy)
        stretchSpring.velocity -= 0.26 + 0.20 * energy
        kineticSpring.position = max(kineticSpring.position, 0.22 + 0.28 * energy)

        stepWetting(dt: time.integration, kinetic: energy)
        return frame
    }

    mutating func stepWetting(timestamp: TimeInterval) -> RailMotionFrame {
        let time = advanceTime(timestamp)
        let decay = CGFloat(exp(-Double(time.measurement) / 0.095))
        filteredFloatingSpeed *= decay
        stepWetting(dt: time.integration, kinetic: min(filteredFloatingSpeed / 2_500, 1))
        return frame
    }

    mutating func stepTowardRest(timestamp: TimeInterval) -> RailMotionFrame {
        let time = advanceTime(timestamp)
        let decay = CGFloat(exp(-Double(time.measurement) / 0.060))
        filteredPointerVelocity *= decay
        filteredPointerAcceleration *= decay
        outwardVelocity = filteredPointerVelocity
        rawProgress = 0
        stepTowardRest(dt: time.integration)
        residueSpring.step(toward: 0, dt: time.integration, response: 0.22, dampingRatio: 0.56)
        return frame
    }

    var isSettled: Bool {
        abs(widthSpring.position) < 0.35 && abs(widthSpring.velocity) < 8 &&
        abs(contentSpring.position) < 0.35 && abs(contentSpring.velocity) < 8 &&
        abs(stretchSpring.position) < 0.004 && abs(stretchSpring.velocity) < 0.05 &&
        abs(detachSpring.position) < 0.004 && abs(detachSpring.velocity) < 0.05 &&
        abs(kineticSpring.position) < 0.006 && abs(kineticSpring.velocity) < 0.08 &&
        abs(impactSpring.position) < 0.006 && abs(impactSpring.velocity) < 0.08 &&
        abs(breakPulseSpring.position) < 0.006 && abs(breakPulseSpring.velocity) < 0.08 &&
        abs(residueSpring.position) < 0.006 && abs(residueSpring.velocity) < 0.08 &&
        abs(verticalSpring.position - CGFloat(targetVerticalPosition)) < 0.0005 &&
        abs(verticalSpring.velocity) < 0.01
    }

    var isFloatingSettled: Bool {
        abs(floatingXSpring.position - floatingTargetX) < 0.75 && abs(floatingXSpring.velocity) < 12 &&
        abs(floatingYSpring.position - floatingTargetY) < 0.75 && abs(floatingYSpring.velocity) < 12 &&
        abs(widthSpring.position) < 0.75 && abs(widthSpring.velocity) < 14 &&
        abs(stretchSpring.position) < 0.012 && abs(stretchSpring.velocity) < 0.10 &&
        abs(kineticSpring.position) < 0.012 && abs(kineticSpring.velocity) < 0.12 &&
        abs(impactSpring.position) < 0.012 && abs(impactSpring.velocity) < 0.12 &&
        abs(breakPulseSpring.position) < 0.012 && abs(breakPulseSpring.velocity) < 0.12
    }

    var isWettingSettled: Bool {
        abs(wettingSpring.position - 1) < 0.006 && abs(wettingSpring.velocity) < 0.045 &&
        abs(impactSpring.position) < 0.014 && abs(impactSpring.velocity) < 0.11 &&
        abs(stretchSpring.position) < 0.014 && abs(stretchSpring.velocity) < 0.11 &&
        abs(floatingXSpring.position - floatingTargetX) < 0.55 && abs(floatingXSpring.velocity) < 9 &&
        abs(floatingYSpring.position - floatingTargetY) < 0.55 && abs(floatingYSpring.velocity) < 9
    }

    var frame: RailMotionFrame {
        RailMotionFrame(
            rawProgress: min(max(rawProgress, 0), 1.45),
            canvasExtraWidth: min(max(widthSpring.position, 0), 1_120),
            stretch: min(max(stretchSpring.position, 0), 1.34),
            detach: min(max(detachSpring.position, 0), 1),
            contentTravel: min(max(contentSpring.position, 0), 1_080),
            verticalPosition: Double(min(max(verticalSpring.position, 0), 1)),
            kinetic: min(max(kineticSpring.position, 0), 1),
            impact: min(abs(impactSpring.position), 1),
            breakPulse: min(max(breakPulseSpring.position, -1), 1),
            floatingCenterX: floatingXSpring.position,
            floatingCenterY: floatingYSpring.position,
            residue: min(max(residueSpring.position, -0.65), 1.25),
            wetting: min(max(wettingSpring.position, 0), 1.08)
        )
    }

    private mutating func updatePointerDynamics(distance: CGFloat, measurementDt: CGFloat) {
        defer {
            previousOutwardDistance = distance
            hasPointerSample = true
        }
        guard hasPointerSample else { return }

        let measuredVelocity = min(
            max((distance - previousOutwardDistance) / max(measurementDt, 1.0 / 240.0), -6_000),
            6_000
        )
        let velocityBlend = Self.exponentialBlend(dt: measurementDt, response: 0.035)
        let previousVelocity = filteredPointerVelocity
        filteredPointerVelocity += (measuredVelocity - filteredPointerVelocity) * velocityBlend

        let measuredAcceleration = min(
            max((filteredPointerVelocity - previousVelocity) / max(measurementDt, 1.0 / 240.0), -60_000),
            60_000
        )
        let accelerationBlend = Self.exponentialBlend(dt: measurementDt, response: 0.050)
        filteredPointerAcceleration += (measuredAcceleration - filteredPointerAcceleration) * accelerationBlend
    }

    private mutating func updateFloatingDynamics(target: CGPoint, measurementDt: CGFloat) {
        defer {
            previousFloatingTargetX = target.x
            previousFloatingTargetY = target.y
            hasFloatingSample = true
        }
        guard hasFloatingSample else { return }

        let dt = max(measurementDt, 1.0 / 240.0)
        let dx = target.x - previousFloatingTargetX
        let dy = target.y - previousFloatingTargetY
        let measuredSpeed = min(hypot(dx, dy) / dt, 7_000)
        let blend = Self.exponentialBlend(dt: measurementDt, response: 0.038)
        filteredFloatingSpeed += (measuredSpeed - filteredFloatingSpeed) * blend
    }

    private mutating func stepTowardRest(dt: CGFloat) {
        stepChannels(
            widthTarget: 0,
            stretchTarget: 0,
            detachTarget: 0,
            contentTarget: 0,
            verticalTarget: CGFloat(targetVerticalPosition),
            kineticTarget: 0,
            impactTarget: 0,
            dt: dt,
            kinetic: min(abs(filteredPointerVelocity) / 2_200, 1)
        )
    }

    private mutating func stepFloating(
        mode: FloatingMotionMode,
        dt: CGFloat,
        kinetic: CGFloat
    ) {
        let energy = min(max(kinetic, 0), 1)
        let positionResponse: CGFloat
        let positionDamping: CGFloat
        let widthTarget: CGFloat
        let stretchTarget: CGFloat

        switch mode {
        case .free:
            positionResponse = 0.088 - 0.018 * energy
            positionDamping = 0.82 - 0.08 * energy
            widthTarget = 8 + 10 * energy
            stretchTarget = 0.045 + 0.075 * energy
        case .returning:
            positionResponse = 0.235
            positionDamping = 0.66
            widthTarget = 0
            stretchTarget = 0
        case .docking:
            positionResponse = 0.190
            positionDamping = 0.61
            widthTarget = 4 + 7 * energy
            stretchTarget = 0.035 + 0.055 * energy
        }

        floatingXSpring.step(
            toward: floatingTargetX,
            dt: dt,
            response: positionResponse,
            dampingRatio: positionDamping
        )
        floatingYSpring.step(
            toward: floatingTargetY,
            dt: dt,
            response: positionResponse * 1.04,
            dampingRatio: min(positionDamping + 0.03, 0.92)
        )

        stepChannels(
            widthTarget: widthTarget,
            stretchTarget: stretchTarget,
            detachTarget: 0,
            contentTarget: 0,
            verticalTarget: CGFloat(targetVerticalPosition),
            kineticTarget: mode == .free ? energy : 0,
            impactTarget: 0,
            dt: dt,
            kinetic: energy
        )

        // A dedicated signed rupture spring keeps oscillating even if the pointer pauses
        // at the threshold, so the "pochan" is driven by the break event, never distance.
        breakPulseSpring.step(
            toward: 0,
            dt: dt,
            response: 0.31,
            dampingRatio: 0.38
        )

        // The screen-side remnant behaves like the second droplet in a pinched liquid bridge:
        // it rebounds, overshoots slightly, and then disappears independently of the body.
        residueSpring.step(
            toward: 0,
            dt: dt,
            response: mode == .free ? 0.245 : 0.20,
            dampingRatio: mode == .free ? 0.27 : 0.64
        )
    }

    private mutating func stepWetting(dt: CGFloat, kinetic: CGFloat) {
        let energy = min(max(kinetic, 0), 1)
        floatingXSpring.step(
            toward: floatingTargetX,
            dt: dt,
            response: 0.145,
            dampingRatio: 0.84
        )
        floatingYSpring.step(
            toward: floatingTargetY,
            dt: dt,
            response: 0.150,
            dampingRatio: 0.86
        )
        wettingSpring.step(
            toward: 1,
            dt: dt,
            response: 0.42,
            dampingRatio: 0.70
        )
        stepChannels(
            widthTarget: 0,
            stretchTarget: 0,
            detachTarget: 0,
            contentTarget: 0,
            verticalTarget: CGFloat(targetVerticalPosition),
            kineticTarget: 0,
            impactTarget: 0,
            dt: dt,
            kinetic: energy
        )
        residueSpring.step(toward: 0, dt: dt, response: 0.20, dampingRatio: 0.68)
    }

    private mutating func stepChannels(
        widthTarget: CGFloat,
        stretchTarget: CGFloat,
        detachTarget: CGFloat,
        contentTarget: CGFloat,
        verticalTarget: CGFloat,
        kineticTarget: CGFloat,
        impactTarget: CGFloat,
        dt: CGFloat,
        kinetic: CGFloat
    ) {
        let energy = min(max(kinetic, 0), 1)
        widthSpring.step(
            toward: widthTarget,
            dt: dt,
            response: 0.165 - 0.050 * energy,
            dampingRatio: 0.88 - 0.13 * energy
        )
        stretchSpring.step(
            toward: stretchTarget,
            dt: dt,
            response: 0.145 - 0.045 * energy,
            dampingRatio: 0.78 - 0.10 * energy
        )
        detachSpring.step(
            toward: detachTarget,
            dt: dt,
            response: 0.095,
            dampingRatio: 0.94
        )
        contentSpring.step(
            toward: contentTarget,
            dt: dt,
            response: 0.205 - 0.050 * energy,
            dampingRatio: 0.84 - 0.10 * energy
        )
        verticalSpring.step(
            toward: verticalTarget,
            dt: dt,
            response: 0.180 - 0.025 * energy,
            dampingRatio: 0.86
        )
        kineticSpring.step(
            toward: kineticTarget,
            dt: dt,
            response: 0.105,
            dampingRatio: 0.90
        )
        impactSpring.step(
            toward: impactTarget,
            dt: dt,
            response: 0.245,
            dampingRatio: 0.52
        )
    }

    private mutating func advanceTime(_ timestamp: TimeInterval) -> (measurement: CGFloat, integration: CGFloat) {
        let rawElapsed = lastTimestamp > 0 ? timestamp - lastTimestamp : (1.0 / 60.0)
        lastTimestamp = timestamp
        let measurement = CGFloat(min(max(rawElapsed, 1.0 / 240.0), 0.25))
        return (measurement, min(measurement, 0.05))
    }

    private static func stretchTarget(for rawProgress: CGFloat) -> CGFloat {
        let progress = min(max(rawProgress, 0), 1.45)
        let normalized = CGFloat(tanh(Double(progress * 1.55)) / tanh(1.55))
        let overpull = max(progress - 1, 0)
        return min(normalized + overpull * 0.12, 1.18)
    }

    private static func smoothStep(_ value: CGFloat, from start: CGFloat, to end: CGFloat) -> CGFloat {
        guard end > start else { return value >= end ? 1 : 0 }
        let t = min(max((value - start) / (end - start), 0), 1)
        return t * t * (3 - 2 * t)
    }

    private static func exponentialBlend(dt: CGFloat, response: CGFloat) -> CGFloat {
        1 - CGFloat(exp(-Double(dt / max(response, 0.001))))
    }
}

struct RailDragVelocityTracker: Equatable {
    private(set) var velocity: CGVector = .zero
    private var previousTranslation: CGSize = .zero
    private var previousTimestamp: TimeInterval = 0
    private var hasSample = false

    mutating func begin(translation: CGSize = .zero, timestamp: TimeInterval) {
        velocity = .zero
        previousTranslation = translation
        previousTimestamp = timestamp
        hasSample = true
    }

    @discardableResult
    mutating func update(translation: CGSize, timestamp: TimeInterval) -> CGVector {
        guard hasSample else {
            begin(translation: translation, timestamp: timestamp)
            return velocity
        }

        let rawDt = timestamp - previousTimestamp
        let dt = CGFloat(min(max(rawDt, 1.0 / 240.0), 0.12))
        let measuredX = min(max((translation.width - previousTranslation.width) / dt, -7_000), 7_000)
        let measuredY = min(max((translation.height - previousTranslation.height) / dt, -7_000), 7_000)
        let blend = 1 - CGFloat(exp(-Double(dt / 0.040)))
        velocity.dx += (measuredX - velocity.dx) * blend
        velocity.dy += (measuredY - velocity.dy) * blend
        previousTranslation = translation
        previousTimestamp = timestamp
        return velocity
    }

    func decayedVelocity(at timestamp: TimeInterval) -> CGVector {
        guard hasSample else { return .zero }
        let idle = max(timestamp - previousTimestamp, 0)
        let decay = CGFloat(exp(-idle / 0.105))
        return CGVector(dx: velocity.dx * decay, dy: velocity.dy * decay)
    }
}

enum RailDropletShape: UInt8, Equatable {
    case round
    case teardrop
    case stretchedTeardrop
    case hangingDrop
}

enum RailDropletSizeClass: UInt8, Equatable {
    case small
    case medium
    case large
}

enum RailDropletMotionPhase: UInt8, Equatable {
    case hanging
    case falling
}

struct RailDragDropletSample: Equatable {
    let xOffset: CGFloat
    let yOffset: CGFloat
    let width: CGFloat
    let height: CGFloat
    let opacity: CGFloat
    let highlightOpacity: CGFloat
    let rotation: CGFloat
    let secondaryLobe: CGFloat
    let shape: RailDropletShape
    let sizeClass: RailDropletSizeClass
    let phase: RailDropletMotionPhase
}

enum RailDragDropletEmitter {
    static let slotDuration: TimeInterval = 0.240

    static func samples(
        seed: UInt64,
        elapsed: TimeInterval,
        intensity: CGFloat,
        velocity: CGVector = .zero
    ) -> [RailDragDropletSample] {
        guard elapsed >= 0 else { return [] }
        let clampedIntensity = min(max(intensity, 0), 1)
        let speed = hypot(velocity.dx, velocity.dy)
        let energy = min(speed / 1_900, 1)
        let currentSlot = max(Int(floor(elapsed / slotDuration)), 0)
        let firstSlot = max(currentSlot - 6, 0)
        var result: [RailDragDropletSample] = []
        result.reserveCapacity(7)

        for slot in firstSlot...currentSlot {
            let slotSeed = seed ^ (UInt64(slot) &* 0x9E37_79B9_7F4A_7C15)
            let emissionChance = 0.48 + 0.24 * Double(clampedIntensity)
            guard unit(slotSeed, salt: 1) < emissionChance else { continue }

            let birth = Double(slot) * slotDuration + unit(slotSeed, salt: 2) * 0.055
            let age = elapsed - birth
            let hangingDuration = 0.23 + unit(slotSeed, salt: 3) * 0.17
            let fallingLifetime = 0.66 + unit(slotSeed, salt: 4) * 0.34
            let totalLifetime = hangingDuration + fallingLifetime
            guard age >= 0, age <= totalLifetime else { continue }

            let phase: RailDropletMotionPhase = age < hangingDuration ? .hanging : .falling
            let hangingProgress = min(max(age / hangingDuration, 0), 1)
            let hangingEase = hangingProgress * hangingProgress * (3 - 2 * hangingProgress)
            let fallingAge = max(age - hangingDuration, 0)
            let fallingProgress = min(max(fallingAge / fallingLifetime, 0), 1)

            let sizeRoll = unit(slotSeed, salt: 5)
            let sizeClass: RailDropletSizeClass
            let baseSize: CGFloat
            if sizeRoll < 0.10 {
                sizeClass = .small
                baseSize = 2.40 + CGFloat(unit(slotSeed, salt: 6)) * 1.10
            } else if sizeRoll < 0.72 {
                sizeClass = .medium
                baseSize = 4.45 + CGFloat(unit(slotSeed, salt: 6)) * 2.05
            } else {
                sizeClass = .large
                baseSize = 6.55 + CGFloat(unit(slotSeed, salt: 6)) * 2.85
            }

            let fallingShapeRoll = unit(slotSeed, salt: 7)
            let fallingShape: RailDropletShape
            if fallingShapeRoll < 0.42 {
                fallingShape = .round
            } else if fallingShapeRoll < 0.88 {
                fallingShape = .teardrop
            } else if fallingShapeRoll < 0.95 {
                fallingShape = .stretchedTeardrop
            } else {
                fallingShape = .hangingDrop
            }
            let shape: RailDropletShape = phase == .hanging ? .hangingDrop : fallingShape

            let xJitter = CGFloat(unit(slotSeed, salt: 8) - 0.5) * (phase == .hanging ? 1.6 : 3.2)
            let backwardX: CGFloat
            if speed < 220 {
                backwardX = CGFloat(unit(slotSeed, salt: 9) - 0.5) * 2.4
            } else {
                let directional = -velocity.dx * (0.013 + 0.017 * energy)
                backwardX = min(max(directional, -62), 62)
                    + CGFloat(unit(slotSeed, salt: 9) - 0.5) * 3.4
            }
            let initialFall = 8 + CGFloat(unit(slotSeed, salt: 10)) * 7
            let gravity = 410 + CGFloat(unit(slotSeed, salt: 11)) * 105

            let width: CGFloat
            let height: CGFloat
            let xOffset: CGFloat
            let yOffset: CGFloat
            let opacity: CGFloat
            let rotation: CGFloat
            if phase == .hanging {
                width = baseSize * CGFloat(0.62 + 0.38 * hangingEase)
                height = width * CGFloat(1.20 + 0.52 * hangingEase)
                xOffset = xJitter * CGFloat(0.4 + 0.6 * hangingEase)
                yOffset = 0
                opacity = CGFloat(0.52 + 0.22 * hangingEase) * (0.82 + 0.12 * clampedIntensity)
                rotation = 0
            } else {
                let fadeOut = CGFloat(pow(max(1 - fallingProgress, 0), 0.72))
                width = baseSize * (1 - 0.07 * CGFloat(fallingProgress))
                let aspect: CGFloat
                switch shape {
                case .round: aspect = 1.04
                case .teardrop: aspect = 1.24 + 0.08 * CGFloat(fallingProgress)
                case .stretchedTeardrop: aspect = 1.38 + 0.08 * energy
                case .hangingDrop: aspect = 1.34
                }
                height = width * aspect
                xOffset = xJitter + backwardX * CGFloat(fallingAge)
                yOffset = 1.2 + initialFall * CGFloat(fallingAge) + 0.5 * gravity * CGFloat(fallingAge * fallingAge)
                opacity = fadeOut * (0.58 + 0.16 * clampedIntensity)
                rotation = min(max(backwardX / 1_300, -0.045), 0.045)
            }

            result.append(
                RailDragDropletSample(
                    xOffset: xOffset,
                    yOffset: yOffset,
                    width: width,
                    height: height,
                    opacity: opacity,
                    highlightOpacity: opacity * (0.30 + 0.12 * CGFloat(unit(slotSeed, salt: 12))),
                    rotation: rotation,
                    secondaryLobe: 0,
                    shape: shape,
                    sizeClass: sizeClass,
                    phase: phase
                )
            )
        }
        return result
    }

    static func unit(_ seed: UInt64, salt: UInt64) -> Double {
        var z = seed &+ salt &* 0xD1B5_4A32_D192_ED03 &+ 0x9E37_79B9_7F4A_7C15
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return Double(z >> 11) / 9_007_199_254_740_992.0
    }
}

enum RailFloatingDropletEmitter {
    static let slotDuration: TimeInterval = 0.270

    static func samples(
        seed: UInt64,
        elapsed: TimeInterval,
        intensity: CGFloat,
        velocity: CGVector,
        emitterHalfWidth: CGFloat = 0,
        surfaceYOffset: (CGFloat) -> CGFloat = { _ in 0 },
        fallingSurfaceYOffset: ((CGFloat) -> CGFloat)? = nil
    ) -> [RailDragDropletSample] {
        guard elapsed >= 0 else { return [] }
        let clampedIntensity = min(max(intensity, 0), 1)
        let speed = hypot(velocity.dx, velocity.dy)
        let energy = min(speed / 1_850, 1)
        let currentSlot = max(Int(floor(elapsed / slotDuration)), 0)
        let firstSlot = max(currentSlot - 6, 0)
        var result: [RailDragDropletSample] = []
        result.reserveCapacity(7)

        for slot in firstSlot...currentSlot {
            let slotSeed = seed ^ (UInt64(slot) &* 0xA24B_AED4_963E_E407)
            let chance = 0.50 + 0.20 * Double(clampedIntensity) + 0.05 * Double(energy)
            guard RailDragDropletEmitter.unit(slotSeed, salt: 1) < chance else { continue }

            let birth = Double(slot) * slotDuration + RailDragDropletEmitter.unit(slotSeed, salt: 2) * 0.060
            let ageDouble = elapsed - birth
            let hangingDuration = 0.20 + RailDragDropletEmitter.unit(slotSeed, salt: 3) * 0.16
            let fallingLifetime = 0.70 + RailDragDropletEmitter.unit(slotSeed, salt: 4) * 0.36
            guard ageDouble >= 0, ageDouble <= hangingDuration + fallingLifetime else { continue }

            let phase: RailDropletMotionPhase = ageDouble < hangingDuration ? .hanging : .falling
            let hangingProgress = min(max(ageDouble / hangingDuration, 0), 1)
            let hangingEase = hangingProgress * hangingProgress * (3 - 2 * hangingProgress)
            let fallingAge = max(ageDouble - hangingDuration, 0)
            let fallingProgress = min(max(CGFloat(fallingAge / fallingLifetime), 0), 1)

            let sizeRoll = RailDragDropletEmitter.unit(slotSeed, salt: 5)
            let sizeClass: RailDropletSizeClass
            let baseSize: CGFloat
            if sizeRoll < 0.09 {
                sizeClass = .small
                baseSize = 2.50 + CGFloat(RailDragDropletEmitter.unit(slotSeed, salt: 6)) * 1.10
            } else if sizeRoll < 0.70 {
                sizeClass = .medium
                baseSize = 4.60 + CGFloat(RailDragDropletEmitter.unit(slotSeed, salt: 6)) * 2.10
            } else {
                sizeClass = .large
                baseSize = 6.75 + CGFloat(RailDragDropletEmitter.unit(slotSeed, salt: 6)) * 2.80
            }

            let shapeRoll = RailDragDropletEmitter.unit(slotSeed, salt: 7)
            let fallingShape: RailDropletShape = shapeRoll < 0.45
                ? .round
                : shapeRoll < 0.89 ? .teardrop : shapeRoll < 0.96 ? .stretchedTeardrop : .hangingDrop
            let shape: RailDropletShape = phase == .hanging ? .hangingDrop : fallingShape

            let bandHalfWidth = max(emitterHalfWidth, 0)
            let bandRoll = CGFloat(RailDragDropletEmitter.unit(slotSeed, salt: 14) * 2 - 1)
            let bandSpread = 0.52 + CGFloat(RailDragDropletEmitter.unit(slotSeed, salt: 15)) * 0.48
            let bandOffset = bandRoll * bandHalfWidth * bandSpread
            let hangingSurfaceYOffset = surfaceYOffset(bandOffset)
            let detachmentSurfaceYOffset = fallingSurfaceYOffset?(bandOffset) ?? hangingSurfaceYOffset
            let backwardMagnitude = min(
                speed * (0.014 + 0.028 * energy)
                    * (0.86 + CGFloat(RailDragDropletEmitter.unit(slotSeed, salt: 8)) * 0.28),
                88
            )
            let backwardUnit: CGVector
            if speed > 180 {
                backwardUnit = CGVector(dx: -velocity.dx / speed, dy: -velocity.dy / speed)
            } else {
                backwardUnit = .zero
            }
            let vx = speed > 180
                ? backwardUnit.dx * backwardMagnitude + CGFloat(RailDragDropletEmitter.unit(slotSeed, salt: 9) - 0.5) * 2.8
                : CGFloat(RailDragDropletEmitter.unit(slotSeed, salt: 9) - 0.5) * 2.8
            let inertialY = speed > 180 ? backwardUnit.dy * backwardMagnitude * 0.34 : 0
            let initialFall = 8 + CGFloat(RailDragDropletEmitter.unit(slotSeed, salt: 10)) * 7
            let vy = max(inertialY + initialFall, -24)
            let mass = 1.00 + baseSize * 0.18 + CGFloat(RailDragDropletEmitter.unit(slotSeed, salt: 11)) * 0.18
            let drag = 1.15 + CGFloat(RailDragDropletEmitter.unit(slotSeed, salt: 12)) * 0.80
            let fallAge = CGFloat(fallingAge)
            let k = drag / max(mass, 0.25)
            let travelFactor = k > 0.001
                ? CGFloat((1 - exp(-Double(k * fallAge))) / Double(k))
                : fallAge
            let gravity = 420 + 85 / max(mass, 0.7)

            let width: CGFloat
            let height: CGFloat
            let xOffset: CGFloat
            let yOffset: CGFloat
            let opacity: CGFloat
            let rotation: CGFloat
            if phase == .hanging {
                width = baseSize * CGFloat(0.60 + 0.40 * hangingEase)
                height = width * CGFloat(1.22 + 0.50 * hangingEase)
                xOffset = bandOffset + backwardUnit.dx * CGFloat(2.2 * hangingEase)
                yOffset = hangingSurfaceYOffset
                opacity = CGFloat(0.54 + 0.20 * hangingEase) * (0.84 + 0.10 * clampedIntensity)
                rotation = 0
            } else {
                let fadeOut = pow(max(1 - fallingProgress, 0), 0.74)
                width = baseSize * (1 - 0.065 * fallingProgress)
                let aspect: CGFloat
                switch shape {
                case .round: aspect = 1.04
                case .teardrop: aspect = 1.24
                case .stretchedTeardrop: aspect = 1.36 + 0.06 * energy
                case .hangingDrop: aspect = 1.34
                }
                height = width * aspect
                xOffset = bandOffset + vx * travelFactor
                yOffset = detachmentSurfaceYOffset + 1.1 + vy * travelFactor + 0.5 * gravity * fallAge * fallAge
                opacity = fadeOut * (0.58 + 0.14 * clampedIntensity)
                rotation = min(max(vx / 1_450, -0.040), 0.040)
            }

            result.append(
                RailDragDropletSample(
                    xOffset: xOffset,
                    yOffset: yOffset,
                    width: width,
                    height: height,
                    opacity: opacity,
                    highlightOpacity: opacity * (0.28 + 0.12 * CGFloat(RailDragDropletEmitter.unit(slotSeed, salt: 13))),
                    rotation: rotation,
                    secondaryLobe: 0,
                    shape: shape,
                    sizeClass: sizeClass,
                    phase: phase
                )
            )
        }
        return result
    }
}

enum RailBreakDropletGroup: UInt8, Equatable {
    case freeSideSpray
    case anchorSideSplash
}

struct RailBreakDropletSample: Equatable {
    let group: RailBreakDropletGroup
    let xOffset: CGFloat
    let yOffset: CGFloat
    let width: CGFloat
    let height: CGFloat
    let opacity: CGFloat
    let highlightOpacity: CGFloat
    let rotation: CGFloat
    let secondaryLobe: CGFloat
    let shape: RailDropletShape
    let mass: CGFloat
    let drag: CGFloat
    let lifespan: CGFloat
}

enum RailBreakDropletEmitter {
    static let maxLifetime: TimeInterval = 1.05

    static func samples(
        seed: UInt64,
        elapsed: TimeInterval,
        velocity: CGVector,
        freeDirection: CGFloat
    ) -> [RailBreakDropletSample] {
        guard elapsed >= 0, elapsed <= maxLifetime else { return [] }
        let speed = hypot(velocity.dx, velocity.dy)
        let energy = min(speed / 2_200, 1)
        let direction = freeDirection >= 0 ? CGFloat(1) : CGFloat(-1)
        var result: [RailBreakDropletSample] = []
        result.reserveCapacity(9)

        for index in 0..<9 {
            let group: RailBreakDropletGroup = index < 6 ? .freeSideSpray : .anchorSideSplash
            let particleSeed = seed
                ^ (UInt64(index + 1) &* 0xA24B_AED4_963E_E407)
                ^ (group == .freeSideSpray ? 0x9FB2_1C65_1E98_DF25 : 0xD6E8_FEB8_6659_FD93)
            let birthWindow = group == .freeSideSpray ? 0.095 : 0.070
            let birth = RailDragDropletEmitter.unit(particleSeed, salt: 1) * birthWindow
            let ageDouble = elapsed - birth
            guard ageDouble >= 0 else { continue }

            let sizeRoll = RailDragDropletEmitter.unit(particleSeed, salt: 2)
            let baseSize: CGFloat
            if sizeRoll < 0.10 {
                baseSize = 2.50 + CGFloat(RailDragDropletEmitter.unit(particleSeed, salt: 3)) * 1.10
            } else if sizeRoll < 0.70 {
                baseSize = 4.35 + CGFloat(RailDragDropletEmitter.unit(particleSeed, salt: 3)) * 2.00
            } else {
                baseSize = 6.45 + CGFloat(RailDragDropletEmitter.unit(particleSeed, salt: 3)) * 2.70
            }
            let mass = 0.98 + baseSize * 0.18 + CGFloat(RailDragDropletEmitter.unit(particleSeed, salt: 4)) * 0.22
            let drag = 1.15 + CGFloat(RailDragDropletEmitter.unit(particleSeed, salt: 5)) * 0.95
            let lifespan = CGFloat(0.62 + RailDragDropletEmitter.unit(particleSeed, salt: 6) * 0.30)
            let age = CGFloat(ageDouble)
            guard age <= lifespan else { continue }

            let vx: CGFloat
            let vy: CGFloat
            if group == .freeSideSpray {
                if energy < 0.12 {
                    vx = direction * (3 + CGFloat(RailDragDropletEmitter.unit(particleSeed, salt: 7)) * 9)
                    vy = 10 + CGFloat(RailDragDropletEmitter.unit(particleSeed, salt: 8)) * 13
                } else {
                    let baseAngle = atan2(velocity.dy, velocity.dx)
                    let scatter = (CGFloat(RailDragDropletEmitter.unit(particleSeed, salt: 7)) - 0.5) * 0.18
                    let angle = baseAngle + scatter
                    let impulse = min(
                        speed
                            * (0.026 + 0.026 * energy)
                            * (0.86 + CGFloat(RailDragDropletEmitter.unit(particleSeed, salt: 8)) * 0.28),
                        104
                    )
                    vx = cos(angle) * impulse
                    vy = sin(angle) * impulse * 0.52 + 8
                }
            } else {
                vx = direction * (14 + 36 * energy)
                    * (0.84 + CGFloat(RailDragDropletEmitter.unit(particleSeed, salt: 7)) * 0.28)
                vy = (CGFloat(RailDragDropletEmitter.unit(particleSeed, salt: 8)) - 0.40) * (42 + 24 * energy) + 8
            }

            let k = drag / max(mass, 0.2)
            let travelFactor = k > 0.001
                ? CGFloat((1 - exp(-Double(k * age))) / Double(k))
                : age
            let gravity = 430 + 90 / max(mass, 0.7)
            let x = vx * travelFactor
            let y = vy * travelFactor + 0.5 * gravity * age * age
            let progress = min(max(age / max(lifespan, 0.01), 0), 1)
            let fadeIn = min(age / 0.055, 1)
            let fadeOut = pow(max(1 - progress, 0), 0.70)
            let opacity = fadeIn * fadeOut * (group == .freeSideSpray ? 0.64 : 0.54)
            let shapeRoll = RailDragDropletEmitter.unit(particleSeed, salt: 9)
            let shape: RailDropletShape = shapeRoll < 0.46
                ? .round
                : shapeRoll < 0.91 ? .teardrop : shapeRoll < 0.96 ? .stretchedTeardrop : .hangingDrop
            let width = baseSize * (1 - 0.07 * progress)
            let aspect: CGFloat
            switch shape {
            case .round: aspect = 1.04
            case .teardrop: aspect = 1.22
            case .stretchedTeardrop: aspect = 1.36
            case .hangingDrop: aspect = 1.34
            }
            let height = width * aspect

            result.append(
                RailBreakDropletSample(
                    group: group,
                    xOffset: x,
                    yOffset: y,
                    width: width,
                    height: height,
                    opacity: opacity,
                    highlightOpacity: opacity * (0.28 + 0.12 * CGFloat(RailDragDropletEmitter.unit(particleSeed, salt: 10))),
                    rotation: CGFloat((RailDragDropletEmitter.unit(particleSeed, salt: 11) - 0.5) * 0.08),
                    secondaryLobe: 0,
                    shape: shape,
                    mass: mass,
                    drag: drag,
                    lifespan: lifespan
                )
            )
        }
        return result
    }
}
