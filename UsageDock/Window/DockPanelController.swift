import AppKit
import Combine
import SwiftUI

final class NonActivatingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
final class RailDragOverlayModel: ObservableObject {
    @Published var snapshot: RailDragVisualSnapshot? = nil
}

private struct SurfaceResidueShape: Shape {
    let edge: DockEdge
    var amount: CGFloat

    var animatableData: CGFloat {
        get { amount }
        set { amount = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let signed = min(max(amount, -0.65), 1.25)
        let bulgeStrength = min(max(signed, 0), 1.25)
        let snapBack = min(max(-signed, 0), 0.65)
        let midY = rect.midY
        let topY = rect.minY + rect.height * (0.16 - 0.035 * min(bulgeStrength, 1) + 0.08 * snapBack)
        let bottomY = rect.maxY - rect.height * (0.16 - 0.035 * min(bulgeStrength, 1) + 0.08 * snapBack)
        let bulge = rect.width * (0.50 + 0.31 * min(bulgeStrength, 1) - 0.18 * snapBack)
        var path = Path()

        switch edge {
        case .left:
            path.move(to: CGPoint(x: rect.minX, y: topY))
            path.addCurve(
                to: CGPoint(x: rect.minX + bulge, y: midY),
                control1: CGPoint(x: rect.minX + rect.width * 0.14, y: topY),
                control2: CGPoint(x: rect.minX + bulge, y: midY - rect.height * 0.22)
            )
            path.addCurve(
                to: CGPoint(x: rect.minX, y: bottomY),
                control1: CGPoint(x: rect.minX + bulge, y: midY + rect.height * 0.22),
                control2: CGPoint(x: rect.minX + rect.width * 0.14, y: bottomY)
            )
            path.closeSubpath()
        case .right:
            path.move(to: CGPoint(x: rect.maxX, y: topY))
            path.addCurve(
                to: CGPoint(x: rect.maxX - bulge, y: midY),
                control1: CGPoint(x: rect.maxX - rect.width * 0.14, y: topY),
                control2: CGPoint(x: rect.maxX - bulge, y: midY - rect.height * 0.22)
            )
            path.addCurve(
                to: CGPoint(x: rect.maxX, y: bottomY),
                control1: CGPoint(x: rect.maxX - bulge, y: midY + rect.height * 0.22),
                control2: CGPoint(x: rect.maxX - rect.width * 0.14, y: bottomY)
            )
            path.closeSubpath()
        }
        return path
    }
}

private struct LiquidDropletPalette {
    let tint: Color
    let rim: Color
    let belly: Color
    let innerGlow: Color
    let specular: Color
    let bodyOpacityScale: CGFloat
    let rimOpacityScale: CGFloat
    let bellyOpacityScale: CGFloat
    let specularOpacityScale: CGFloat
}

enum LiquidDropletDrawing {
    static func path(in rect: CGRect, shape: RailDropletShape, secondaryLobe _: CGFloat) -> Path {
        switch shape {
        case .round:
            return Path(ellipseIn: rect.insetBy(dx: rect.width * 0.03, dy: rect.height * 0.03))
        case .teardrop, .stretchedTeardrop, .hangingDrop:
            let hanging = shape == .hangingDrop
            let stretched = shape == .stretchedTeardrop
            let neckWidth = rect.width * (hanging ? 0.20 : stretched ? 0.30 : 0.38)
            let shoulderY = rect.minY + rect.height * (hanging ? 0.30 : stretched ? 0.25 : 0.22)
            let bellyY = rect.minY + rect.height * (hanging ? 0.70 : 0.64)
            let topY = hanging ? rect.minY : rect.minY + rect.height * 0.05
            var path = Path()
            path.move(to: CGPoint(x: rect.midX - neckWidth * 0.5, y: topY))
            path.addCurve(
                to: CGPoint(x: rect.minX + rect.width * 0.09, y: shoulderY),
                control1: CGPoint(x: rect.midX - neckWidth * 0.64, y: topY + rect.height * 0.08),
                control2: CGPoint(x: rect.minX + rect.width * 0.16, y: shoulderY - rect.height * 0.06)
            )
            path.addCurve(
                to: CGPoint(x: rect.midX, y: rect.maxY),
                control1: CGPoint(x: rect.minX - rect.width * 0.01, y: bellyY),
                control2: CGPoint(x: rect.midX - rect.width * 0.34, y: rect.maxY)
            )
            path.addCurve(
                to: CGPoint(x: rect.maxX - rect.width * 0.09, y: shoulderY),
                control1: CGPoint(x: rect.midX + rect.width * 0.34, y: rect.maxY),
                control2: CGPoint(x: rect.maxX + rect.width * 0.01, y: bellyY)
            )
            path.addCurve(
                to: CGPoint(x: rect.midX + neckWidth * 0.5, y: topY),
                control1: CGPoint(x: rect.maxX - rect.width * 0.16, y: shoulderY - rect.height * 0.06),
                control2: CGPoint(x: rect.midX + neckWidth * 0.64, y: topY + rect.height * 0.08)
            )
            path.addQuadCurve(
                to: CGPoint(x: rect.midX - neckWidth * 0.5, y: topY),
                control: CGPoint(x: rect.midX, y: rect.minY)
            )
            path.closeSubpath()
            return path
        }
    }

    fileprivate static func draw(
        context: inout GraphicsContext,
        rect: CGRect,
        shape: RailDropletShape,
        secondaryLobe: CGFloat,
        palette: LiquidDropletPalette,
        opacity: CGFloat,
        highlightOpacity: CGFloat
    ) {
        let drop = path(in: rect, shape: shape, secondaryLobe: secondaryLobe)
        let bodyOpacity = min(max(opacity * palette.bodyOpacityScale, 0), 0.74)
        let rimOpacity = min(max(highlightOpacity * palette.rimOpacityScale, 0), 0.42)
        context.fill(drop, with: .color(palette.tint.opacity(Double(bodyOpacity))))
        context.stroke(
            drop,
            with: .color(palette.rim.opacity(Double(rimOpacity))),
            lineWidth: max(0.24, min(rect.width * 0.042, 0.58))
        )

        let lowerBelly = CGRect(
            x: rect.minX + rect.width * 0.20,
            y: rect.minY + rect.height * 0.54,
            width: rect.width * 0.60,
            height: rect.height * 0.34
        )
        context.fill(
            Path(ellipseIn: lowerBelly),
            with: .color(palette.belly.opacity(Double(bodyOpacity * palette.bellyOpacityScale)))
        )

        let innerGlow = CGRect(
            x: rect.minX + rect.width * 0.27,
            y: rect.minY + rect.height * 0.22,
            width: rect.width * 0.42,
            height: rect.height * 0.34
        )
        context.fill(
            Path(ellipseIn: innerGlow),
            with: .color(palette.innerGlow.opacity(Double(min(highlightOpacity * 0.18, 0.12))))
        )

        let specular = CGRect(
            x: rect.minX + rect.width * 0.24,
            y: rect.minY + rect.height * 0.15,
            width: max(rect.width * 0.18, 0.55),
            height: max(rect.height * 0.10, 0.55)
        )
        context.fill(
            Path(ellipseIn: specular),
            with: .color(palette.specular.opacity(Double(min(highlightOpacity * palette.specularOpacityScale, 0.40))))
        )
    }
}

private struct DragDropletField: View {
    let snapshot: RailDragVisualSnapshot
    let origin: CGPoint
    let emitterHalfWidth: CGFloat
    let floatingSurfaceYOffset: ((CGFloat) -> CGFloat)?
    let floatingDetachmentYOffset: ((CGFloat) -> CGFloat)?
    let materialMode: RailMaterialMode
    let theme: UsageDockTheme

    private var palette: LiquidDropletPalette { liquidPalette(materialMode: materialMode, theme: theme) }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            Canvas { context, _ in
                let intensity = min(max(snapshot.stretch * 0.58 + snapshot.kinetic * 0.42, 0.16), 1)
                let motionAge = max(ProcessInfo.processInfo.systemUptime - snapshot.dragVelocitySampledAt, 0)
                let motionDecay = CGFloat(exp(-motionAge / 0.105))
                let decayedVelocity = CGVector(
                    dx: snapshot.dragVelocityX * motionDecay,
                    dy: snapshot.dragVelocityY * motionDecay
                )
                let samples: [RailDragDropletSample]
                if snapshot.phase == .floating, snapshot.breakStartedAt > 0 {
                    let elapsed = timeline.date.timeIntervalSinceReferenceDate - snapshot.breakStartedAt
                    samples = RailFloatingDropletEmitter.samples(
                        seed: snapshot.particleSeed ^ 0xF17_21D1_1F10_A771,
                        elapsed: elapsed,
                        intensity: max(intensity, 0.26),
                        velocity: decayedVelocity,
                        emitterHalfWidth: emitterHalfWidth,
                        surfaceYOffset: floatingSurfaceYOffset ?? { _ in 0 },
                        fallingSurfaceYOffset: floatingDetachmentYOffset
                    )
                } else {
                    let elapsed = timeline.date.timeIntervalSinceReferenceDate - snapshot.dragStartedAt
                    samples = RailDragDropletEmitter.samples(
                        seed: snapshot.particleSeed,
                        elapsed: elapsed,
                        intensity: intensity,
                        velocity: decayedVelocity
                    )
                }

                for sample in samples {
                    let rect = CGRect(
                        x: origin.x + sample.xOffset - sample.width * 0.5,
                        y: origin.y + sample.yOffset,
                        width: sample.width,
                        height: sample.height
                    )
                    LiquidDropletDrawing.draw(
                        context: &context,
                        rect: rect,
                        shape: sample.shape,
                        secondaryLobe: sample.secondaryLobe,
                        palette: palette,
                        opacity: sample.opacity,
                        highlightOpacity: sample.highlightOpacity
                    )
                }
            }
        }
        .allowsHitTesting(false)
    }
}

private struct FloatingSurfaceTensionFilm: View {
    let centerX: CGFloat
    let centerY: CGFloat
    let halfWidth: CGFloat
    let intensity: CGFloat
    let seed: UInt64
    let surfaceYOffset: (CGFloat) -> CGFloat
    let materialMode: RailMaterialMode
    let theme: UsageDockTheme
    let backgroundOpacity: Double

    private var palette: LiquidDropletPalette { liquidPalette(materialMode: materialMode, theme: theme) }

    var body: some View {
        Canvas { context, _ in
            let steps = 64
            var film = Path()
            var lowerContour = Path()

            for index in 0...steps {
                let progress = CGFloat(index) / CGFloat(steps)
                let xOffset = -halfWidth + halfWidth * 2 * progress
                let x = centerX + xOffset
                let y = centerY + surfaceYOffset(xOffset) - FloatingSurfaceTensionGeometry.bodyOverlap
                if index == 0 {
                    film.move(to: CGPoint(x: x, y: y))
                } else {
                    film.addLine(to: CGPoint(x: x, y: y))
                }
            }

            for index in stride(from: steps, through: 0, by: -1) {
                let progress = CGFloat(index) / CGFloat(steps)
                let xOffset = -halfWidth + halfWidth * 2 * progress
                let x = centerX + xOffset
                let sag = FloatingSurfaceTensionGeometry.sagOffset(
                    xOffset: xOffset,
                    halfWidth: halfWidth,
                    intensity: intensity,
                    seed: seed
                )
                let y = centerY + surfaceYOffset(xOffset) + sag
                film.addLine(to: CGPoint(x: x, y: y))
                if index == steps {
                    lowerContour.move(to: CGPoint(x: x, y: y))
                } else {
                    lowerContour.addLine(to: CGPoint(x: x, y: y))
                }
            }
            film.closeSubpath()

            context.fill(film, with: .color(ProviderBrand.railFill(theme: theme, opacity: backgroundOpacity)))
            context.fill(film, with: .color(palette.tint.opacity(Double(0.08 + 0.08 * intensity))))
            context.stroke(
                lowerContour,
                with: .color(palette.rim.opacity(Double(0.08 + 0.08 * intensity))),
                lineWidth: 0.45
            )
        }
        .allowsHitTesting(false)
    }
}

private struct BreakDropletField: View {
    let snapshot: RailDragVisualSnapshot
    let freeOrigin: CGPoint
    let anchorOrigin: CGPoint
    let materialMode: RailMaterialMode
    let theme: UsageDockTheme

    private var palette: LiquidDropletPalette { liquidPalette(materialMode: materialMode, theme: theme) }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 45.0)) { timeline in
            Canvas { context, _ in
                let elapsed = timeline.date.timeIntervalSinceReferenceDate - snapshot.breakStartedAt
                let freeDirection: CGFloat = snapshot.edge == .left ? 1 : -1
                let samples = RailBreakDropletEmitter.samples(
                    seed: snapshot.particleSeed ^ 0xF17_20B0_BA11_1571,
                    elapsed: elapsed,
                    velocity: CGVector(dx: snapshot.breakVelocityX, dy: snapshot.breakVelocityY),
                    freeDirection: freeDirection
                )

                for sample in samples {
                    let source = sample.group == .freeSideSpray ? freeOrigin : anchorOrigin
                    let rect = CGRect(
                        x: source.x + sample.xOffset - sample.width * 0.5,
                        y: source.y + sample.yOffset - sample.height * 0.25,
                        width: sample.width,
                        height: sample.height
                    )
                    LiquidDropletDrawing.draw(
                        context: &context,
                        rect: rect,
                        shape: sample.shape,
                        secondaryLobe: sample.secondaryLobe,
                        palette: palette,
                        opacity: sample.opacity,
                        highlightOpacity: sample.highlightOpacity
                    )
                }
            }
        }
        .allowsHitTesting(false)
    }
}

private func liquidPalette(materialMode: RailMaterialMode, theme: UsageDockTheme) -> LiquidDropletPalette {
    switch materialMode {
    case .standard:
        let tint = theme == .pop
            ? Color(red: 0.72, green: 0.61, blue: 1.0)
            : theme == .light ? Color.white : Color(red: 0.80, green: 0.86, blue: 0.94)
        return LiquidDropletPalette(
            tint: tint,
            rim: theme == .light ? Color.black.opacity(0.30) : Color.white,
            belly: Color.black,
            innerGlow: Color.white,
            specular: Color.white,
            bodyOpacityScale: 0.54,
            rimOpacityScale: 0.54,
            bellyOpacityScale: 0.10,
            specularOpacityScale: 0.66
        )
    case .waterdrop:
        return LiquidDropletPalette(
            tint: Color(red: 0.60, green: 0.86, blue: 1.0),
            rim: Color(red: 0.86, green: 0.96, blue: 1.0),
            belly: Color(red: 0.10, green: 0.28, blue: 0.42),
            innerGlow: Color(red: 0.90, green: 0.98, blue: 1.0),
            specular: Color.white,
            bodyOpacityScale: 0.46,
            rimOpacityScale: 0.78,
            bellyOpacityScale: 0.12,
            specularOpacityScale: 0.92
        )
    case .space:
        return LiquidDropletPalette(
            tint: Color(red: 0.26, green: 0.20, blue: 0.52),
            rim: Color(red: 0.62, green: 0.72, blue: 1.0),
            belly: Color(red: 0.03, green: 0.04, blue: 0.12),
            innerGlow: Color(red: 0.48, green: 0.54, blue: 1.0),
            specular: Color(red: 0.82, green: 0.78, blue: 1.0),
            bodyOpacityScale: 0.70,
            rimOpacityScale: 0.84,
            bellyOpacityScale: 0.24,
            specularOpacityScale: 0.76
        )
    case .bar3D:
        return LiquidDropletPalette(
            tint: theme == .light ? Color(red: 0.74, green: 0.78, blue: 0.82) : Color(red: 0.38, green: 0.43, blue: 0.50),
            rim: theme == .light ? Color.white.opacity(0.70) : Color.white.opacity(0.52),
            belly: Color.black,
            innerGlow: Color.white.opacity(0.72),
            specular: Color.white.opacity(0.82),
            bodyOpacityScale: 0.72,
            rimOpacityScale: 0.34,
            bellyOpacityScale: 0.28,
            specularOpacityScale: 0.48
        )
    }
}

private struct RailDragOverlayRootView: View {
    @ObservedObject var model: RailDragOverlayModel
    @ObservedObject var usageStore: UsageStore
    @ObservedObject var placement: PlacementStore

    var body: some View {
        GeometryReader { proxy in
            if let snapshot = model.snapshot {
                let baseWidth = RailMetrics.width(
                    scale: usageStore.railScale,
                    showRing: usageStore.railShowRing,
                    showMultiplier: usageStore.railShowMultiplier,
                    screenInnerPadding: usageStore.railScreenInnerPadding,
                    windowInnerPadding: usageStore.railWindowInnerPadding,
                    iconSize: usageStore.railIconSize,
                    titleWidth: usageStore.railTitleWidth,
                    timeWidth: usageStore.railTimeWidth
                )
                let baseHeight = RailMetrics.contentHeight(
                    entryCount: usageStore.railTargets().count,
                    scale: usageStore.railScale,
                    itemSpacing: usageStore.railItemSpacing,
                    innerPaddingY: usageStore.railInnerPaddingY,
                    showRing: usageStore.railShowRing,
                    showPercent: usageStore.railShowPercent,
                    showRemainingTime: usageStore.railShowRemainingTime,
                    remainingTimeFontSize: usageStore.railRemainingTimeFontSize,
                    iconSize: usageStore.railIconSize,
                    percentFontSize: usageStore.railPercentFontSize,
                    showTitle: usageStore.railShowTitle,
                    titleFontSize: usageStore.railAccountLabelFontSize
                )
                let railWidth = baseWidth + snapshot.canvasExtraWidth
                let screen = NSScreen.main ?? NSScreen.screens.first
                let visible = screen?.visibleFrame ?? NSRect(origin: .zero, size: proxy.size)
                let full = screen?.frame ?? NSRect(origin: .zero, size: proxy.size)
                let topInset = max(full.maxY - visible.maxY, 0)
                let leftInset = max(visible.minX - full.minX, 0)
                let rightInset = max(full.maxX - visible.maxX, 0)
                let travel = max(visible.height - baseHeight - 16, 0)
                let attachedCenterY = topInset + 8 + baseHeight * 0.5 + travel * CGFloat(snapshot.verticalPosition)
                let attachedCenterX = snapshot.edge == .left
                    ? leftInset + railWidth * 0.5
                    : proxy.size.width - rightInset - railWidth * 0.5
                let isAttached = snapshot.phase == .attached
                let centerX = isAttached ? attachedCenterX : snapshot.floatingCenterX
                let centerY = isAttached ? attachedCenterY : snapshot.floatingCenterY
                let freeDirection: CGFloat = snapshot.edge == .left ? 1 : -1
                let screenBoundaryX = snapshot.edge == .left ? leftInset : proxy.size.width - rightInset
                let effectiveEdgeStyle: RailEdgeStyle = usageStore.railMaterialMode == .bar3D ? .off : usageStore.railEdgeStyle
                let renderInset = RailMetrics.borderRenderPadding(
                    scale: usageStore.railScale,
                    edgeStyle: effectiveEdgeStyle,
                    edgeWidth: usageStore.railEdgeWidth,
                    glowRadius: usageStore.railGlowRadius
                )
                let screenOutset = RailMetrics.screenEdgeVisualOutset(
                    screenEdgeShape: usageStore.railScreenEdgeShape,
                    scallopDepth: usageStore.railScallopDepth,
                    scale: usageStore.railScale
                )
                let attachedRailFrameHeight = RailMetrics.renderedHeight(
                    baseHeight: baseHeight,
                    visualOutset: screenOutset,
                    borderPadding: renderInset
                )
                let floatingRailFrameHeight = RailMetrics.renderedHeight(
                    baseHeight: baseHeight,
                    visualOutset: 0,
                    borderPadding: renderInset
                )
                let neckGeometry = RailNeckGeometryResolver.resolve(
                    in: CGRect(x: 0, y: 0, width: railWidth, height: attachedRailFrameHeight),
                    edge: snapshot.edge,
                    screenEdgeAmount: usageStore.railScreenEdgeShape,
                    screenEdgeCurvature: usageStore.railScreenEdgeCurvature,
                    innerEdgeAmount: usageStore.railInnerShape,
                    cornerRadius: usageStore.railCornerRadius * usageStore.railScale,
                    scallopDepth: usageStore.railScallopDepth * usageStore.railScale,
                    smoothing: usageStore.railScallopSmoothing,
                    stretchAmount: Double(snapshot.shapeStretch),
                    neckAmount: Double(snapshot.neck),
                    kineticAmount: Double(snapshot.kinetic),
                    screenEdgeOutset: screenOutset,
                    renderInset: renderInset
                )
                let attachedRailMinY = attachedCenterY - attachedRailFrameHeight * 0.5
                let neckOrigin = CGPoint(
                    x: screenBoundaryX + freeDirection * neckGeometry.distanceFromScreen,
                    y: attachedRailMinY + neckGeometry.lowerSurfaceY
                )
                let floatingLocalRect = CGRect(x: 0, y: 0, width: railWidth, height: floatingRailFrameHeight)
                let floatingBody = FloatingRailGeometry.bodyRect(in: floatingLocalRect)
                let rupturePulse = snapshot.phase == .floating ? snapshot.breakPulse : 0
                let floatingVisualScaleX = FloatingRailGeometry.bodyScaleX(impact: Double(snapshot.settle))
                    * RailBreakVisualTransform.scaleX(for: rupturePulse)
                let floatingEmitterHalfWidth = min(
                    max(floatingBody.width * 0.30, 18),
                    max(floatingBody.width * 0.42, 18)
                ) * floatingVisualScaleX
                let floatingTensionSeed = snapshot.particleSeed ^ 0xF17_26A0_51D5_1A61
                let floatingTensionIntensity = FloatingSurfaceTensionGeometry.intensity(
                    stretch: snapshot.stretch,
                    kinetic: snapshot.kinetic,
                    breakPulse: rupturePulse
                )
                let floatingRenderedSurfaceYOffset: (CGFloat) -> CGFloat = { xOffset in
                    FloatingRailGeometry.visualUndersideOffsetFromCenter(
                        in: floatingLocalRect,
                        xOffset: xOffset,
                        impact: Double(snapshot.settle),
                        kinetic: Double(snapshot.kinetic),
                        breakPulse: rupturePulse
                    )
                }
                let floatingHangingSurfaceYOffset: (CGFloat) -> CGFloat = { xOffset in
                    floatingRenderedSurfaceYOffset(xOffset) - FloatingSurfaceTensionGeometry.bodyOverlap
                }
                let floatingDetachmentYOffset: (CGFloat) -> CGFloat = { xOffset in
                    floatingRenderedSurfaceYOffset(xOffset) + FloatingSurfaceTensionGeometry.sagOffset(
                        xOffset: xOffset,
                        halfWidth: floatingEmitterHalfWidth,
                        intensity: floatingTensionIntensity,
                        seed: floatingTensionSeed
                    )
                }
                let floatingDripOrigin = CGPoint(x: centerX, y: centerY)
                let continuousDripOrigin = isAttached ? neckOrigin : floatingDripOrigin
                let residueCenterY = topInset + 8 + baseHeight * 0.5 + travel * CGFloat(snapshot.anchorVerticalPosition)
                let anchorSplashOrigin = CGPoint(
                    x: screenBoundaryX + freeDirection * 3.5,
                    y: residueCenterY
                )

                ZStack {
                    if !isAttached, abs(snapshot.residue) > 0.012 {
                        let residueBulge = min(max(snapshot.residue, 0), 1.25)
                        let residueSnap = min(max(-snapshot.residue, 0), 0.65)
                        let residueWidth = max(20, 26 + 19 * residueBulge - 6 * residueSnap)
                        let residueHeight = max(32, 42 + 24 * residueBulge - 7 * residueSnap)
                        let residueCenterX = snapshot.edge == .left
                            ? leftInset + residueWidth * 0.5
                            : proxy.size.width - rightInset - residueWidth * 0.5
                        let residueShape = SurfaceResidueShape(edge: snapshot.edge, amount: snapshot.residue)

                        residueShape
                            .fill(ProviderBrand.railFill(theme: usageStore.theme, opacity: usageStore.railBackgroundOpacity))
                            .overlay {
                                residueShape.stroke(
                                    usageStore.theme == .pop
                                        ? Color(red: 0.76, green: 0.66, blue: 1.0).opacity(0.74)
                                        : Color.white.opacity(0.44),
                                    style: StrokeStyle(lineWidth: 0.8, lineCap: .round, lineJoin: .round)
                                )
                            }
                            .shadow(
                                color: usageStore.theme == .pop
                                    ? Color(red: 0.65, green: 0.52, blue: 1.0).opacity(0.24)
                                    : Color.white.opacity(0.10),
                                radius: 6
                            )
                            .frame(width: residueWidth, height: residueHeight)
                            .position(x: residueCenterX, y: residueCenterY)
                            .scaleEffect(
                                x: 1 + 0.10 * residueBulge - 0.07 * residueSnap + 0.10 * max(snapshot.breakPulse, 0),
                                y: 1 - 0.052 * residueBulge + 0.045 * residueSnap - 0.060 * max(snapshot.breakPulse, 0),
                                anchor: snapshot.edge == .left ? .leading : .trailing
                            )
                            .offset(y: 3.6 * max(snapshot.breakPulse, 0) - 1.8 * residueSnap)
                    }

                    RailView(
                        usageStore: usageStore,
                        placement: placement,
                        onTargetHover: { _, _ in },
                        onDragCanvasWidthChange: { _, _ in },
                        onDragVerticalPositionChange: { _ in },
                        onOpenSettings: {},
                        overlaySnapshot: snapshot,
                        interactionEnabled: false
                    )
                    .position(x: centerX, y: centerY)

                    if snapshot.phase == .floating {
                        FloatingSurfaceTensionFilm(
                            centerX: centerX,
                            centerY: centerY,
                            halfWidth: floatingEmitterHalfWidth,
                            intensity: floatingTensionIntensity,
                            seed: floatingTensionSeed,
                            surfaceYOffset: floatingRenderedSurfaceYOffset,
                            materialMode: usageStore.railMaterialMode,
                            theme: usageStore.theme,
                            backgroundOpacity: usageStore.railBackgroundOpacity
                        )
                        .frame(width: proxy.size.width, height: proxy.size.height)
                    }

                    if snapshot.emitsDroplets {
                        DragDropletField(
                            snapshot: snapshot,
                            origin: continuousDripOrigin,
                            emitterHalfWidth: isAttached ? 0 : floatingEmitterHalfWidth,
                            floatingSurfaceYOffset: isAttached ? nil : floatingHangingSurfaceYOffset,
                            floatingDetachmentYOffset: isAttached ? nil : floatingDetachmentYOffset,
                            materialMode: usageStore.railMaterialMode,
                            theme: usageStore.theme
                        )
                        .frame(width: proxy.size.width, height: proxy.size.height)
                    }

                    if snapshot.emitsBreakSplash {
                        BreakDropletField(
                            snapshot: snapshot,
                            freeOrigin: CGPoint(x: snapshot.breakOriginX, y: snapshot.breakOriginY),
                            anchorOrigin: anchorSplashOrigin,
                            materialMode: usageStore.railMaterialMode,
                            theme: usageStore.theme
                        )
                        .frame(width: proxy.size.width, height: proxy.size.height)
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            }
        }
        .allowsHitTesting(false)
    }
}

@MainActor
final class DockPanelController: NSObject {
    private let panel: NonActivatingPanel
    private let dragOverlayPanel: NonActivatingPanel
    private let dragOverlayModel = RailDragOverlayModel()
    private let placement: PlacementStore
    private let usageStore: UsageStore
    private let onOpenSettings: () -> Void
    private lazy var hoverPanel = HoverDetailPanelController(
        usageStore: usageStore,
        placement: placement,
        onPanelHoverChanged: { [weak self] inside in
            self?.handleHoverPanelHover(inside)
        }
    )
    private var cancellables = Set<AnyCancellable>()
    private var hoverHideTask: Task<Void, Never>?
    private var detailPanelHovered = false

    init(usageStore: UsageStore, placement: PlacementStore, onOpenSettings: @escaping () -> Void) {
        self.usageStore = usageStore
        self.placement = placement
        self.onOpenSettings = onOpenSettings

        let initialSize = RailMetrics.windowSize(
            entryCount: usageStore.railTargets().count,
            scale: usageStore.railScale,
            itemSpacing: usageStore.railItemSpacing,
            innerPaddingY: usageStore.railInnerPaddingY,
            showRing: usageStore.railShowRing,
            showPercent: usageStore.railShowPercent,
            showMultiplier: usageStore.railShowMultiplier,
            showRemainingTime: usageStore.railShowRemainingTime,
            remainingTimeFontSize: usageStore.railRemainingTimeFontSize,
            screenInnerPadding: usageStore.railScreenInnerPadding,
            windowInnerPadding: usageStore.railWindowInnerPadding,
            iconSize: usageStore.railIconSize,
            percentFontSize: usageStore.railPercentFontSize,
            showTitle: usageStore.railShowTitle,
            titleFontSize: usageStore.railAccountLabelFontSize,
            titleWidth: usageStore.railTitleWidth,
            timeWidth: usageStore.railTimeWidth
        )
        panel = NonActivatingPanel(
            contentRect: NSRect(origin: .zero, size: initialSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        dragOverlayPanel = NonActivatingPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        super.init()
        configurePanel()
        configureDragOverlayPanel()
        observeState()
    }

    func show() {
        resizeAndReposition()
        panel.orderFrontRegardless()
    }

    static func settingsPreviewTarget(from targets: [RailDisplayTarget]) -> RailDisplayTarget? {
        targets.first
    }

    var settingsPreviewTarget: RailDisplayTarget? {
        hoverPanel.visibleTarget
    }

    func showSettingsHoverPreview() {
        hoverHideTask?.cancel()
        hoverHideTask = nil
        detailPanelHovered = false
        guard let target = Self.settingsPreviewTarget(from: usageStore.railTargets()) else {
            hoverPanel.hide()
            return
        }
        hoverPanel.show(target: target, index: 0, anchorPanel: panel)
    }

    func hideSettingsHoverPreview() {
        hoverHideTask?.cancel()
        hoverHideTask = nil
        detailPanelHovered = false
        hoverPanel.hide()
    }

    func reposition() {
        resizeAndReposition()
    }

    private func basePanelSize() -> NSSize {
        RailMetrics.windowSize(
            entryCount: usageStore.railTargets().count,
            scale: usageStore.railScale,
            itemSpacing: usageStore.railItemSpacing,
            innerPaddingY: usageStore.railInnerPaddingY,
            showRing: usageStore.railShowRing,
            showPercent: usageStore.railShowPercent,
            showMultiplier: usageStore.railShowMultiplier,
            showRemainingTime: usageStore.railShowRemainingTime,
            remainingTimeFontSize: usageStore.railRemainingTimeFontSize,
            screenInnerPadding: usageStore.railScreenInnerPadding,
            windowInnerPadding: usageStore.railWindowInnerPadding,
            iconSize: usageStore.railIconSize,
            percentFontSize: usageStore.railPercentFontSize,
            showTitle: usageStore.railShowTitle,
            titleFontSize: usageStore.railAccountLabelFontSize,
            titleWidth: usageStore.railTitleWidth,
            timeWidth: usageStore.railTimeWidth
        )
    }

    private func screenEdgeVisualOutset() -> CGFloat {
        RailMetrics.screenEdgeVisualOutset(
            screenEdgeShape: usageStore.railScreenEdgeShape,
            scallopDepth: usageStore.railScallopDepth,
            scale: usageStore.railScale
        )
    }

    private func borderRenderPadding() -> CGFloat {
        RailMetrics.borderRenderPadding(
            scale: usageStore.railScale,
            edgeStyle: usageStore.railMaterialMode == .bar3D ? .off : usageStore.railEdgeStyle,
            edgeWidth: usageStore.railEdgeWidth,
            glowRadius: usageStore.railGlowRadius
        )
    }

    private func currentPanelSize() -> NSSize {
        var size = basePanelSize()
        size.height += (screenEdgeVisualOutset() + borderRenderPadding()) * 2
        return size
    }

    private func resizeAndReposition(animated: Bool = false) {
        guard let screen = screenForPlacement() else { return }
        let visible = screen.visibleFrame
        let baseSize = basePanelSize()
        let visualOutset = screenEdgeVisualOutset()
        let renderPadding = borderRenderPadding()
        let size = currentPanelSize()
        let topMargin: CGFloat = 8

        let x: CGFloat
        switch placement.edge {
        case .left:
            x = visible.minX
        case .right:
            x = visible.maxX - size.width
        }

        // Keep the nominal content position stable while Screen-edge Spread adds visual
        // breathing room above/below the panel. Dragging uses a transient position so it
        // can update at pointer frequency without persisting every frame.
        let verticalPosition = CGFloat(usageStore.railVerticalPosition)
        let travel = max(visible.height - baseSize.height - topMargin * 2, 0)
        let baseY = visible.maxY - baseSize.height - topMargin - travel * verticalPosition
        let y = baseY - visualOutset - renderPadding
        let frame = NSRect(
            x: x.rounded(),
            y: y.rounded(),
            width: size.width.rounded(),
            height: size.height.rounded()
        )
        panel.setFrame(frame, display: true)
    }

    private func configurePanel() {
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.ignoresMouseEvents = usageStore.railVisualOnlyMode
        panel.animationBehavior = .utilityWindow
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary
        ]

        let hostingView = FirstMouseHostingView(
            rootView: RailView(
                usageStore: usageStore,
                placement: placement,
                onTargetHover: { [weak self] target, inside in
                    self?.handleTargetHover(target, inside: inside)
                },
                onDragCanvasWidthChange: { _, _ in },
                onDragVerticalPositionChange: { _ in },
                onOpenSettings: onOpenSettings,
                onDragVisualStateChange: { [weak self] snapshot in
                    self?.setDragVisualState(snapshot)
                }
            )
            .background(Color.clear)
        )
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        hostingView.layer?.shouldRasterize = false
        hostingView.layer?.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        panel.contentView = hostingView
    }

    private func configureDragOverlayPanel() {
        dragOverlayPanel.isOpaque = false
        dragOverlayPanel.backgroundColor = .clear
        dragOverlayPanel.hasShadow = false
        dragOverlayPanel.level = .floating
        dragOverlayPanel.hidesOnDeactivate = false
        dragOverlayPanel.isMovable = false
        dragOverlayPanel.isMovableByWindowBackground = false
        dragOverlayPanel.ignoresMouseEvents = true
        dragOverlayPanel.animationBehavior = .none
        dragOverlayPanel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary
        ]

        let hostingView = NSHostingView(
            rootView: RailDragOverlayRootView(
                model: dragOverlayModel,
                usageStore: usageStore,
                placement: placement
            )
            .background(Color.clear)
        )
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        hostingView.layer?.shouldRasterize = false
        hostingView.layer?.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        dragOverlayPanel.contentView = hostingView
    }

    private func setDragVisualState(_ snapshot: RailDragVisualSnapshot?) {
        guard let snapshot else {
            dragOverlayModel.snapshot = nil
            dragOverlayPanel.orderOut(nil)
            return
        }
        guard let screen = screenForPlacement() else { return }
        if dragOverlayPanel.frame != screen.frame {
            dragOverlayPanel.setFrame(screen.frame, display: false)
        }
        if !dragOverlayPanel.isVisible {
            dragOverlayPanel.orderFrontRegardless()
        }
        // RailMotionRuntime already integrates spring/damping at high frequency. Applying a
        // second SwiftUI spring here creates phase lag and visible stepping, so render its
        // sampled state directly.
        dragOverlayModel.snapshot = snapshot
    }

    private func handleTargetHover(_ target: RailDisplayTarget, inside: Bool) {
        guard usageStore.railHoverEnabled && !usageStore.railVisualOnlyMode else {
            hoverPanel.hide()
            return
        }
        if inside {
            hoverHideTask?.cancel()
            hoverHideTask = nil
            guard let index = usageStore.railTargets().firstIndex(of: target) else { return }
            hoverPanel.show(target: target, index: index, anchorPanel: panel)
        } else {
            scheduleHoverHide(target: target)
        }
    }

    private func handleHoverPanelHover(_ inside: Bool) {
        detailPanelHovered = inside
        if inside {
            hoverHideTask?.cancel()
            hoverHideTask = nil
        } else {
            scheduleHoverHide()
        }
    }

    private func scheduleHoverHide(target: RailDisplayTarget? = nil) {
        hoverHideTask?.cancel()
        hoverHideTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 240_000_000)
            guard !Task.isCancelled, let self, !self.detailPanelHovered else { return }
            self.hoverPanel.hide(target: target)
        }
    }

    private func observeState() {
        placement.$edge
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.hoverHideTask?.cancel()
                self?.detailPanelHovered = false
                self?.hoverPanel.hide()
                self?.resizeAndReposition()
            }
            .store(in: &cancellables)

        usageStore.$settingsBubblePreviewRequested
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] requested in
                guard let self else { return }
                if requested {
                    self.showSettingsHoverPreview()
                } else {
                    self.hideSettingsHoverPreview()
                }
            }
            .store(in: &cancellables)

        usageStore.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.panel.ignoresMouseEvents = self.usageStore.railVisualOnlyMode
                    if (!self.usageStore.railHoverEnabled || self.usageStore.railVisualOnlyMode)
                        && !self.usageStore.settingsBubblePreviewRequested {
                        self.hoverHideTask?.cancel()
                        self.detailPanelHovered = false
                        self.hoverPanel.hide()
                    }
                    self.resizeAndReposition()
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(
            for: NSApplication.didChangeScreenParametersNotification
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] _ in
            guard let self else { return }
            self.hoverPanel.hide()
            self.resizeAndReposition()
            if self.dragOverlayPanel.isVisible, let screen = self.screenForPlacement() {
                self.dragOverlayPanel.setFrame(screen.frame, display: false)
            }
        }
        .store(in: &cancellables)
    }

    private func screenForPlacement() -> NSScreen? {
        NSScreen.main ?? NSScreen.screens.first
    }
}
