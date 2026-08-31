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

        let breakEnergy = min(
            abs(filteredPointerVelocity) / 2_400 + abs(filteredPointerAcceleration) / 42_000,
            1
        )

        floatingTargetX = floatingCenter.x
        floatingTargetY = floatingCenter.y
        previousFloatingTargetX = floatingCenter.x
        previousFloatingTargetY = floatingCenter.y
        filteredFloatingSpeed = abs(filteredPointerVelocity) * 0.38
        hasFloatingSample = true

        // Surface tension collapses the stretched tether quickly into one independent drop.
        widthSpring.reset(14 + 18 * breakEnergy, velocity: -(95 + 155 * breakEnergy))
        stretchSpring.reset(0.19 + 0.11 * breakEnergy, velocity: -(0.55 + 0.65 * breakEnergy))
        detachSpring.reset(0)
        contentSpring.reset(0)
        verticalSpring.reset(CGFloat(targetVerticalPosition))
        kineticSpring.reset(max(0.24, breakEnergy))

        // Main drop and screen-side residue receive opposite-looking rebound energy.
        impactSpring.reset(0.82 + 0.18 * breakEnergy, velocity: 1.55 + 1.20 * breakEnergy)
        residueSpring.reset(1.0, velocity: 2.35 + 1.55 * breakEnergy)
        floatingXSpring.reset(floatingCenter.x)
        floatingYSpring.reset(floatingCenter.y)
        wettingSpring.reset(0)

        stepFloating(mode: .free, dt: time.integration, kinetic: max(0.24, breakEnergy))
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
        abs(impactSpring.position) < 0.012 && abs(impactSpring.velocity) < 0.12
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

        // The screen-side remnant behaves like the second droplet in a pinched liquid bridge:
        // it rebounds, overshoots slightly, and then disappears independently of the body.
        residueSpring.step(
            toward: 0,
            dt: dt,
            response: mode == .free ? 0.265 : 0.20,
            dampingRatio: mode == .free ? 0.46 : 0.64
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
