import AppKit
import Foundation
import SwiftUI

struct SpaceSurfaceStar: Equatable {
    let center: CGPoint
    let radius: CGFloat
    let opacity: Double
    let coolTint: Bool
}

enum SpaceSurfaceGeometry {
    static let seed: UInt64 = 0x5A0C_EF17_2609_0401

    static func stars(in size: CGSize, count: Int = 36) -> [SpaceSurfaceStar] {
        guard size.width > 0, size.height > 0, count > 0 else { return [] }
        return (0..<count).map { index in
            let starSeed = seed ^ (UInt64(index + 1) &* 0x9E37_79B9_7F4A_7C15)
            let x = CGFloat(RailDragDropletEmitter.unit(starSeed, salt: 1)) * size.width
            let y = CGFloat(RailDragDropletEmitter.unit(starSeed, salt: 2)) * size.height
            let radius = 0.32 + CGFloat(RailDragDropletEmitter.unit(starSeed, salt: 3)) * 0.72
            let opacity = 0.075 + RailDragDropletEmitter.unit(starSeed, salt: 4) * 0.16
            return SpaceSurfaceStar(
                center: CGPoint(x: x, y: y),
                radius: radius,
                opacity: opacity,
                coolTint: RailDragDropletEmitter.unit(starSeed, salt: 5) > 0.68
            )
        }
    }
}

private struct SpaceSurfaceDetail: View {
    let scale: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                RadialGradient(
                    colors: [
                        Color(red: 0.35, green: 0.23, blue: 0.68).opacity(0.13),
                        Color(red: 0.12, green: 0.18, blue: 0.44).opacity(0.055),
                        Color.clear
                    ],
                    center: UnitPoint(x: 0.28, y: 0.62),
                    startRadius: 0,
                    endRadius: max(proxy.size.width, proxy.size.height) * 0.72
                )
                .blur(radius: 10 * scale)

                RadialGradient(
                    colors: [
                        Color(red: 0.34, green: 0.57, blue: 0.92).opacity(0.075),
                        Color.clear
                    ],
                    center: UnitPoint(x: 0.76, y: 0.31),
                    startRadius: 0,
                    endRadius: max(proxy.size.width, proxy.size.height) * 0.48
                )
                .blur(radius: 7 * scale)

                Canvas { context, size in
                    for star in SpaceSurfaceGeometry.stars(in: size) {
                        let diameter = max(star.radius * 2 * CGFloat(scale), 0.55)
                        let rect = CGRect(
                            x: star.center.x - diameter * 0.5,
                            y: star.center.y - diameter * 0.5,
                            width: diameter,
                            height: diameter
                        )
                        let color = star.coolTint
                            ? Color(red: 0.70, green: 0.78, blue: 1.0)
                            : Color.white
                        context.fill(Path(ellipseIn: rect), with: .color(color.opacity(star.opacity)))
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }
}

struct RailHorizontalLayout {
    let screenInset: CGFloat
    let windowInset: CGFloat
    let contentScaleX: CGFloat
}

enum RailMetrics {
    static func contentWidth(
        showRing: Bool,
        showMultiplier: Bool,
        iconSize: Double = 24,
        titleWidth: Double = 66,
        timeWidth: Double = 72
    ) -> CGFloat {
        let iconBlock = max(showRing ? 70 : 48, iconSize + (showRing ? 34 : 20))
        let textBlock = max(showMultiplier ? 64 : 54, titleWidth + 16, timeWidth + 16)
        return CGFloat(max(iconBlock, textBlock))
    }

    static func minimumSafeHorizontalInset(showRing: Bool, iconSize: Double) -> CGFloat {
        let base: CGFloat = showRing ? 2 : 1
        let largeIconBonus = max(CGFloat(iconSize - 24) * 0.035, 0)
        return min(base + largeIconBonus, 4)
    }

    static func width(
        scale: Double,
        showRing: Bool,
        showMultiplier: Bool,
        screenInnerPadding: Double = 0,
        windowInnerPadding: Double = 0,
        iconSize: Double = 24,
        titleWidth: Double = 66,
        timeWidth: Double = 72
    ) -> CGFloat {
        let safe = minimumSafeHorizontalInset(showRing: showRing, iconSize: iconSize)
        let screen = max(CGFloat(screenInnerPadding), safe)
        let window = max(CGFloat(windowInnerPadding), safe)
        let base = contentWidth(
            showRing: showRing,
            showMultiplier: showMultiplier,
            iconSize: iconSize,
            titleWidth: titleWidth,
            timeWidth: timeWidth
        )
        return max((base + screen + window) * CGFloat(scale), 24)
    }

    static func clampedHorizontalLayout(
        availableWidth: CGFloat,
        scale: Double,
        showRing: Bool,
        showMultiplier: Bool,
        iconSize: Double,
        titleWidth: Double,
        timeWidth: Double,
        desiredScreenInset: Double,
        desiredWindowInset: Double,
        screenEdgeAmount: Double,
        stretch: CGFloat,
        neck: CGFloat,
        detach: CGFloat
    ) -> RailHorizontalLayout {
        let scale = CGFloat(scale)
        let baseSafe = minimumSafeHorizontalInset(showRing: showRing, iconSize: iconSize) * scale
        let deformation = min(max(stretch, 0), 1.4)
        let neck = min(max(neck, 0), 1)
        let detach = min(max(detach, 0), 1)
        let edge = min(max(abs(CGFloat(screenEdgeAmount)), 0), 1)
        let screenSafety = baseSafe + (1.25 + 1.6 * edge + 4.6 * neck + 1.8 * deformation) * scale
        let windowSafety = baseSafe + (1.4 + 2.8 * neck + 3.2 * deformation + 1.2 * detach) * scale
        let requestedScreen = max(CGFloat(desiredScreenInset) * scale, screenSafety)
        let requestedWindow = max(CGFloat(desiredWindowInset) * scale, windowSafety)
        let contentWidth = contentWidth(
            showRing: showRing,
            showMultiplier: showMultiplier,
            iconSize: iconSize,
            titleWidth: titleWidth,
            timeWidth: timeWidth
        ) * scale
        let requestedTotal = requestedScreen + requestedWindow
        let contentScaleX = min(max((availableWidth - requestedTotal) / max(contentWidth, 1), 0.50), 1)
        let renderedContentWidth = contentWidth * contentScaleX
        let freeSpace = max(availableWidth - renderedContentWidth, 0)

        guard freeSpace > 0 else {
            return RailHorizontalLayout(screenInset: 0, windowInset: 0, contentScaleX: contentScaleX)
        }
        guard requestedTotal <= freeSpace else {
            let ratio = requestedScreen / max(requestedTotal, 1)
            return RailHorizontalLayout(
                screenInset: freeSpace * ratio,
                windowInset: freeSpace * (1 - ratio),
                contentScaleX: contentScaleX
            )
        }

        let extra = freeSpace - requestedTotal
        let screenShare = min(max(0.46 - 0.18 * deformation - 0.08 * detach, 0.20), 0.50)
        return RailHorizontalLayout(
            screenInset: requestedScreen + extra * screenShare,
            windowInset: requestedWindow + extra * (1 - screenShare),
            contentScaleX: contentScaleX
        )
    }

    static func compensatedDragContentOffset(
        semanticOffset: CGFloat,
        dragDirection: CGFloat,
        contentTravel: CGFloat,
        canvasExtraWidth: CGFloat,
        railWidth: CGFloat,
        renderedContentWidth: CGFloat,
        borderPadding: CGFloat
    ) -> CGFloat {
        // The overlay keeps the screen-side edge fixed by moving the expanded panel center by
        // canvasExtraWidth/2. Subtract that built-in motion before applying contentTravel;
        // otherwise the content effectively moves twice and gets clipped by the canonical mask.
        let compensatedTravel = max(contentTravel - canvasExtraWidth * 0.5, 0)
        let desired = semanticOffset + dragDirection * compensatedTravel
        let safety = max(borderPadding + 1, 1)
        let maxOffset = max(railWidth * 0.5 - renderedContentWidth * 0.5 - safety, 0)
        return min(max(desired, -maxOffset), maxOffset)
    }

    static func rowHeight(
        scale: Double,
        showRing: Bool,
        showPercent: Bool,
        showRemainingTime: Bool = false,
        remainingTimeFontSize: Double = 8.5,
        iconSize: Double = 24,
        percentFontSize: Double = 12,
        showTitle: Bool = true,
        titleFontSize: Double = 11
    ) -> CGFloat {
        var base = CGFloat(max(showRing ? 50 : 34, iconSize + (showRing ? 20 : 10))) + 8
        if showPercent { base += max(15, CGFloat(percentFontSize) + 4) }
        if showRemainingTime { base += max(14, CGFloat(remainingTimeFontSize) + 4) }
        if showTitle { base += max(14, CGFloat(titleFontSize) + 4) }
        return max(base * CGFloat(scale), showRing ? 36 : 22)
    }

    static func edgePadding(scale: Double, amount: Double) -> CGFloat {
        CGFloat(amount) * CGFloat(scale)
    }

    static func borderRenderPadding(
        scale: Double,
        edgeStyle: RailEdgeStyle,
        edgeWidth: Double,
        glowRadius: Double = 0
    ) -> CGFloat {
        guard edgeStyle != .off else { return 0 }
        let scaledWidth = CGFloat(edgeWidth * scale)
        let scaledGlow = CGFloat(max(glowRadius, 0) * scale)
        let glowAllowance: CGFloat
        switch edgeStyle {
        case .off, .simple:
            glowAllowance = 0
        case .soft:
            glowAllowance = scaledGlow * 0.46
        case .neon:
            glowAllowance = scaledGlow * 0.82
        case .glass:
            glowAllowance = scaledGlow * 0.52
        }
        let styleAllowance: CGFloat = edgeStyle == .glass ? 1.6 : 1.0
        return min(max(scaledWidth * 1.25 + glowAllowance + styleAllowance, 2.5), 16)
    }

    static func screenEdgeVisualOutset(
        screenEdgeShape: Double,
        scallopDepth: Double,
        scale: Double
    ) -> CGFloat {
        let spread = CGFloat(max(screenEdgeShape, 0))
        guard spread > 0 else { return 0 }
        let scaledDepth = CGFloat(scallopDepth * scale)
        let fullSpread = min(max(scaledDepth * 2.8, 28 * CGFloat(scale)), 88 * CGFloat(scale))
        return fullSpread * spread
    }

    static func renderedHeight(
        baseHeight: CGFloat,
        visualOutset: CGFloat,
        borderPadding: CGFloat
    ) -> CGFloat {
        baseHeight + max(visualOutset, 0) * 2 + max(borderPadding, 0) * 2
    }

    static func spacing(scale: Double, itemSpacing: Double) -> CGFloat {
        CGFloat(itemSpacing) * CGFloat(scale)
    }

    static func contentHeight(
        entryCount: Int,
        scale: Double,
        itemSpacing: Double,
        innerPaddingY: Double = 10,
        showRing: Bool,
        showPercent: Bool,
        showRemainingTime: Bool = false,
        remainingTimeFontSize: Double = 8.5,
        iconSize: Double = 24,
        percentFontSize: Double = 12,
        showTitle: Bool = true,
        titleFontSize: Double = 11
    ) -> CGFloat {
        let count = max(entryCount, 1)
        let rows = CGFloat(count) * rowHeight(
            scale: scale,
            showRing: showRing,
            showPercent: showPercent,
            showRemainingTime: showRemainingTime,
            remainingTimeFontSize: remainingTimeFontSize,
            iconSize: iconSize,
            percentFontSize: percentFontSize,
            showTitle: showTitle,
            titleFontSize: titleFontSize
        )
        let gaps = CGFloat(max(count - 1, 0)) * spacing(scale: scale, itemSpacing: itemSpacing)
        return rows
            + gaps
            + edgePadding(scale: scale, amount: innerPaddingY) * 2
    }

    static func windowSize(
        entryCount: Int,
        scale: Double,
        itemSpacing: Double,
        innerPaddingY: Double = 10,
        showRing: Bool,
        showPercent: Bool,
        showMultiplier: Bool,
        showRemainingTime: Bool = false,
        remainingTimeFontSize: Double = 8.5,
        screenInnerPadding: Double = 0,
        windowInnerPadding: Double = 0,
        iconSize: Double = 24,
        percentFontSize: Double = 12,
        showTitle: Bool = true,
        titleFontSize: Double = 11,
        titleWidth: Double = 66,
        timeWidth: Double = 72
    ) -> CGSize {
        CGSize(
            width: width(
                scale: scale,
                showRing: showRing,
                showMultiplier: showMultiplier,
                screenInnerPadding: screenInnerPadding,
                windowInnerPadding: windowInnerPadding,
                iconSize: iconSize,
                titleWidth: titleWidth,
                timeWidth: timeWidth
            ),
            height: contentHeight(
                entryCount: entryCount,
                scale: scale,
                itemSpacing: itemSpacing,
                innerPaddingY: innerPaddingY,
                showRing: showRing,
                showPercent: showPercent,
                showRemainingTime: showRemainingTime,
                remainingTimeFontSize: remainingTimeFontSize,
                iconSize: iconSize,
                percentFontSize: percentFontSize,
                showTitle: showTitle,
                titleFontSize: titleFontSize
            )
        )
    }
}

struct RailDragVisualSnapshot: Equatable {
    let phase: RailDragPhase
    let edge: DockEdge
    let verticalPosition: Double
    let anchorVerticalPosition: Double
    let rawProgress: CGFloat
    let canvasExtraWidth: CGFloat
    let stretch: CGFloat
    let detach: CGFloat
    let settle: CGFloat
    let sideProgress: CGFloat
    let contentTravel: CGFloat
    let kinetic: CGFloat
    let shapeStretch: CGFloat
    let neck: CGFloat
    let breakPulse: CGFloat
    let floatingCenterX: CGFloat
    let floatingCenterY: CGFloat
    let residue: CGFloat
    let wetting: CGFloat
    let dragStartedAt: TimeInterval
    let particleSeed: UInt64
    let grabX: CGFloat
    let grabY: CGFloat
    let dragVelocityX: CGFloat
    let dragVelocityY: CGFloat
    let dragVelocitySampledAt: TimeInterval
    let emitsDroplets: Bool
    let breakStartedAt: TimeInterval
    let breakVelocityX: CGFloat
    let breakVelocityY: CGFloat
    let breakOriginX: CGFloat
    let breakOriginY: CGFloat
    let emitsBreakSplash: Bool
}

struct RailView: View {
    @ObservedObject var usageStore: UsageStore
    @ObservedObject var placement: PlacementStore
    let onTargetHover: (RailDisplayTarget, Bool) -> Void
    let onDragCanvasWidthChange: (CGFloat, Bool) -> Void
    let onDragVerticalPositionChange: (Double?) -> Void
    let onOpenSettings: () -> Void
    var onDragVisualStateChange: (RailDragVisualSnapshot?) -> Void = { _ in }
    var overlaySnapshot: RailDragVisualSnapshot? = nil
    var interactionEnabled: Bool = true

    @State private var hoveredTarget: RailDisplayTarget?
    @State private var dragStartVerticalPosition: Double?
    @State private var dragStartGlobalX: CGFloat?
    @State private var dragOriginEdge: DockEdge?
    @State private var breakAnchorVerticalPosition: Double?
    @State private var dragPhase: RailDragPhase = .attached
    @State private var motionRuntime = RailMotionRuntime()
    @State private var crossedScreenCenter = false
    @State private var suppressUntilGestureEnds = false
    @State private var inputVisualSuppressed = false
    @State private var settleSequence = 0
    @State private var settleTask: Task<Void, Never>?
    @State private var breakPulseTask: Task<Void, Never>?
    @State private var mouseReleaseWatchTask: Task<Void, Never>?
    @State private var dragVisualStartedAt: TimeInterval = 0
    @State private var dragParticleSeed: UInt64 = 0
    @State private var lastGrabPoint: CGPoint = .zero
    @State private var dragVelocityTracker = RailDragVelocityTracker()
    @State private var breakVisualStartedAt: TimeInterval = 0
    @State private var breakVelocity: CGVector = .zero
    @State private var breakOrigin: CGPoint = .zero

    private var targets: [RailDisplayTarget] { usageStore.railTargets() }
    private var scale: CGFloat { CGFloat(usageStore.railScale) }
    private var effectiveEdge: DockEdge { overlaySnapshot?.edge ?? placement.edge }
    private var effectiveCanvasExtraWidth: CGFloat { overlaySnapshot?.canvasExtraWidth ?? 0 }
    private var dragDirection: CGFloat { effectiveEdge == .left ? 1 : -1 }
    private var contentBaseWidth: CGFloat {
        RailMetrics.contentWidth(
            showRing: usageStore.railShowRing,
            showMultiplier: usageStore.railShowMultiplier,
            iconSize: usageStore.railIconSize,
            titleWidth: usageStore.railTitleWidth,
            timeWidth: usageStore.railTimeWidth
        ) * scale
    }
    private var baseRailWidth: CGFloat {
        RailMetrics.width(
            scale: usageStore.railScale,
            showRing: usageStore.railShowRing,
            showMultiplier: usageStore.railShowMultiplier,
            screenInnerPadding: usageStore.railScreenInnerPadding,
            windowInnerPadding: usageStore.railWindowInnerPadding,
            iconSize: usageStore.railIconSize,
            titleWidth: usageStore.railTitleWidth,
            timeWidth: usageStore.railTimeWidth
        )
    }
    private var currentRailWidth: CGFloat { baseRailWidth + effectiveCanvasExtraWidth }
    private var baseRailHeight: CGFloat {
        RailMetrics.contentHeight(
            entryCount: targets.count,
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
    }
    private var screenEdgeVisualOutset: CGFloat {
        RailMetrics.screenEdgeVisualOutset(
            screenEdgeShape: usageStore.railScreenEdgeShape,
            scallopDepth: usageStore.railScallopDepth,
            scale: usageStore.railScale
        )
    }
    private var effectiveEdgeStyle: RailEdgeStyle {
        usageStore.railMaterialMode == .bar3D ? .off : usageStore.railEdgeStyle
    }
    private var borderRenderPadding: CGFloat {
        RailMetrics.borderRenderPadding(
            scale: usageStore.railScale,
            edgeStyle: effectiveEdgeStyle,
            edgeWidth: usageStore.railEdgeWidth,
            glowRadius: usageStore.railGlowRadius
        )
    }
    private var effectiveVisualOutset: CGFloat {
        guard let overlaySnapshot else { return screenEdgeVisualOutset }
        switch overlaySnapshot.phase {
        case .attached:
            return screenEdgeVisualOutset
        case .wetting:
            return screenEdgeVisualOutset * RailDragPresentation.smoothStep01(overlaySnapshot.wetting)
        case .floating, .returning, .docking:
            return 0
        }
    }
    private var dragPresentation: RailDragPresentation {
        guard let overlaySnapshot else {
            return RailDragPresentation(
                phase: .attached,
                rawProgress: 0,
                canvasExtraWidth: 0,
                stretch: 0,
                detach: 0,
                settle: 0,
                sideProgress: 0,
                contentTravel: 0,
                kinetic: 0,
                breakPulse: 0,
                wetting: 0
            )
        }
        return RailDragPresentation(
            phase: overlaySnapshot.phase,
            rawProgress: overlaySnapshot.rawProgress,
            canvasExtraWidth: overlaySnapshot.canvasExtraWidth,
            stretch: overlaySnapshot.stretch,
            detach: overlaySnapshot.detach,
            settle: overlaySnapshot.settle,
            sideProgress: overlaySnapshot.sideProgress,
            contentTravel: overlaySnapshot.contentTravel,
            kinetic: overlaySnapshot.kinetic,
            breakPulse: overlaySnapshot.breakPulse,
            wetting: overlaySnapshot.wetting
        )
    }

    private var horizontalLayout: RailHorizontalLayout {
        RailMetrics.clampedHorizontalLayout(
            availableWidth: currentRailWidth,
            scale: usageStore.railScale,
            showRing: usageStore.railShowRing,
            showMultiplier: usageStore.railShowMultiplier,
            iconSize: usageStore.railIconSize,
            titleWidth: usageStore.railTitleWidth,
            timeWidth: usageStore.railTimeWidth,
            desiredScreenInset: usageStore.railScreenInnerPadding,
            desiredWindowInset: usageStore.railWindowInnerPadding,
            screenEdgeAmount: usageStore.railScreenEdgeShape,
            stretch: dragPresentation.shapeStretch,
            neck: dragPresentation.neck,
            detach: dragPresentation.detach
        )
    }
    private var contentDeformation: RailContentDeformation {
        RailContentDeformationField.resolve(
            stretch: dragPresentation.stretch,
            neck: dragPresentation.neck,
            kinetic: dragPresentation.kinetic,
            detach: dragPresentation.detach,
            scale: scale,
            attached: dragPresentation.phase == .attached
        )
    }
    private var contentAttachedAnchor: UnitPoint {
        effectiveEdge == .left ? .leading : .trailing
    }
    private var semanticContentOffset: CGFloat {
        let baseOffset = dragDirection * (horizontalLayout.screenInset - horizontalLayout.windowInset) * 0.5
        switch dragPresentation.phase {
        case .attached:
            return baseOffset + dragDirection * contentDeformation.freeSideTranslation
        case .wetting:
            return baseOffset * dragPresentation.wettingSpread
        case .floating, .returning, .docking:
            return 0
        }
    }
    private var attachedNeckGeometry: RailNeckMinimumGeometry? {
        guard dragPresentation.phase == .attached else { return nil }
        return RailNeckGeometryResolver.resolve(
            in: CGRect(
                x: 0,
                y: 0,
                width: currentRailWidth,
                height: baseRailHeight + screenEdgeVisualOutset * 2 + borderRenderPadding * 2
            ),
            edge: effectiveEdge,
            screenEdgeAmount: usageStore.railScreenEdgeShape,
            screenEdgeCurvature: usageStore.railScreenEdgeCurvature,
            innerEdgeAmount: usageStore.railInnerShape,
            cornerRadius: usageStore.railCornerRadius * usageStore.railScale,
            scallopDepth: usageStore.railScallopDepth * usageStore.railScale,
            smoothing: usageStore.railScallopSmoothing,
            stretchAmount: Double(dragPresentation.shapeStretch),
            neckAmount: Double(dragPresentation.neck),
            kineticAmount: Double(dragPresentation.kinetic),
            screenEdgeOutset: screenEdgeVisualOutset,
            renderInset: borderRenderPadding
        )
    }
    private var contentOffsetX: CGFloat {
        guard dragPresentation.phase == .attached else { return semanticContentOffset }
        let renderedWidth = contentBaseWidth
            * horizontalLayout.contentScaleX
            * contentDeformation.groupScaleX
        let compensated = RailMetrics.compensatedDragContentOffset(
            semanticOffset: semanticContentOffset,
            dragDirection: dragDirection,
            contentTravel: dragPresentation.contentTravel,
            canvasExtraWidth: effectiveCanvasExtraWidth,
            railWidth: currentRailWidth,
            renderedContentWidth: renderedWidth,
            borderPadding: borderRenderPadding
        )
        guard let neck = attachedNeckGeometry else { return compensated }
        let bodyTarget = RailContentBodyPlacement.targetOffset(
            railWidth: currentRailWidth,
            renderedContentWidth: renderedWidth,
            neckDistanceFromScreen: neck.distanceFromScreen,
            edge: effectiveEdge,
            freeSideWeight: contentDeformation.bodyPlacementWeight,
            borderPadding: borderRenderPadding
        )
        let weight = contentDeformation.bodyPlacementWeight
        return compensated + (bodyTarget - compensated) * weight
    }
    private var shouldShowRailVisual: Bool {
        overlaySnapshot != nil || !inputVisualSuppressed
    }

    var body: some View {
        ZStack {
            railBackground
                .contentShape(Rectangle())
                .gesture(backgroundDragGesture)

            VStack(
                spacing: RailMetrics.spacing(scale: usageStore.railScale, itemSpacing: usageStore.railItemSpacing)
                    * contentDeformation.spacingScale
            ) {
                ForEach(targets) { target in
                    let summary = usageStore.summary(for: target)
                    let accentHex = usageStore.accentHex(for: target)
                    let percentSource = usageStore.railPercentSource(for: target)
                    let outerRingSource = usageStore.railOuterRingSource(for: target)
                    let innerRingSource = usageStore.railInnerRingSource(for: target)
                    let timeSource = usageStore.railTimeSource(for: target)
                    ProviderUsageTile(
                        target: target,
                        summary: summary,
                        displayName: usageStore.displayName(for: target),
                        displayPercent: usageStore.railDisplayPercent(for: target, source: percentSource),
                        outerRingPercent: usageStore.railDisplayPercent(for: target, source: outerRingSource),
                        innerRingPercent: usageStore.railDisplayPercent(for: target, source: innerRingSource),
                        remainingResetDate: usageStore.railResetDate(for: target, source: timeSource),
                        presentationMode: usageStore.presentationMode,
                        multiplier: usageStore.displayMultiplier(for: target),
                        accentHex: accentHex,
                        isHovered: usageStore.railHoverEnabled && !usageStore.railVisualOnlyMode && hoveredTarget == target,
                        showPercent: usageStore.railShowPercent,
                        showRing: usageStore.railShowRing,
                        showOuterRing: outerRingSource != .none,
                        showInnerRing: innerRingSource != .none,
                        showRemainingTime: usageStore.railShowRemainingTime,
                        dayDigits: usageStore.railDayDigits,
                        hourDigits: usageStore.railHourDigits,
                        minuteDigits: usageStore.railMinuteDigits,
                        showHours: usageStore.railShowHours,
                        showMinutes: usageStore.railShowMinutes,
                        autoHideZeroDays: usageStore.railAutoHideZeroDays,
                        autoHideZeroHours: usageStore.railAutoHideZeroHours,
                        showMultiplier: usageStore.railShowMultiplier,
                        backplateEnabled: usageStore.railBackplateEnabled,
                        autoContrast: usageStore.railAutoContrast,
                        theme: usageStore.theme,
                        iconSize: CGFloat(usageStore.railIconSize),
                        percentFontSize: CGFloat(usageStore.railPercentFontSize),
                        accountLabelFontSize: CGFloat(usageStore.railAccountLabelFontSize),
                        remainingTimeFontSize: CGFloat(usageStore.railRemainingTimeFontSize),
                        showTitle: usageStore.railShowTitle,
                        titleWidth: CGFloat(usageStore.railTitleWidth),
                        timeWidth: CGFloat(usageStore.railTimeWidth),
                        scale: scale
                    )
                    .frame(height: RailMetrics.rowHeight(
                        scale: usageStore.railScale,
                        showRing: usageStore.railShowRing,
                        showPercent: usageStore.railShowPercent,
                        showRemainingTime: usageStore.railShowRemainingTime,
                        remainingTimeFontSize: usageStore.railRemainingTimeFontSize,
                        iconSize: usageStore.railIconSize,
                        percentFontSize: usageStore.railPercentFontSize,
                        showTitle: usageStore.railShowTitle,
                        titleFontSize: usageStore.railAccountLabelFontSize
                    ))
                    .contentShape(Rectangle())
                    .simultaneousGesture(backgroundDragGesture)
                    .onTapGesture {
                        _ = usageStore.openWeb(for: target)
                    }
                    .onHover { inside in
                        guard usageStore.railHoverEnabled else {
                            hoveredTarget = nil
                            onTargetHover(target, false)
                            return
                        }
                        withAnimation(.easeOut(duration: 0.13)) {
                            hoveredTarget = inside ? target : (hoveredTarget == target ? nil : hoveredTarget)
                        }
                        onTargetHover(target, inside)
                    }
                    .help(usageStore.webURL(for: target).map { "Open \($0.absoluteString)" } ?? "No web URL configured")
                }
            }
            .padding(.vertical, RailMetrics.edgePadding(scale: usageStore.railScale, amount: usageStore.railInnerPaddingY))
            .frame(width: contentBaseWidth)
            .scaleEffect(
                x: horizontalLayout.contentScaleX * dragPresentation.wettingContentScaleX * contentDeformation.groupScaleX,
                y: dragPresentation.wettingContentScaleY * contentDeformation.groupScaleY,
                anchor: dragPresentation.phase == .attached ? contentAttachedAnchor : .center
            )
            .rotation3DEffect(
                .degrees((effectiveEdge == .right ? 1.0 : -1.0) * contentDeformation.perspectiveDegrees),
                axis: (x: 0, y: 1, z: 0),
                anchor: dragPresentation.phase == .attached ? contentAttachedAnchor : .center,
                perspective: 0.42
            )
            .frame(maxWidth: .infinity, alignment: .center)
            .offset(x: contentOffsetX)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .mask { railContentMask }
        }
        .scaleEffect(
            x: dragPresentation.ruptureScaleX,
            y: dragPresentation.ruptureScaleY,
            anchor: .center
        )
        .offset(y: dragPresentation.ruptureYOffset)
        .frame(
            width: currentRailWidth,
            height: RailMetrics.renderedHeight(
                baseHeight: baseRailHeight,
                visualOutset: effectiveVisualOutset,
                borderPadding: borderRenderPadding
            )
        )
        .opacity(shouldShowRailVisual ? 1 : 0)
        .allowsHitTesting(
            interactionEnabled &&
            !usageStore.railVisualOnlyMode &&
            (!inputVisualSuppressed || dragStartVerticalPosition != nil)
        )
        .contextMenu {
            Button {
                onOpenSettings()
            } label: {
                Label("Settings…", systemImage: "slider.horizontal.3")
            }

            Menu("Display Account") {
                displayAccountMenu()
            }

            Menu("Accounts") {
                ForEach(usageStore.providerOrder) { provider in
                    providerAccountMenu(provider)
                }
            }

            Divider()

            Button {
                placement.edge = placement.edge == .right ? .left : .right
            } label: {
                Label(
                    placement.edge == .right ? "Move to Left" : "Move to Right",
                    systemImage: placement.edge == .right ? "rectangle.lefthalf.inset.filled" : "rectangle.righthalf.inset.filled"
                )
            }

            Divider()

            Button {
                Task { await usageStore.refreshLiveUsage() }
            } label: {
                Label(usageStore.isRefreshing ? "Refreshing…" : "Refresh Now", systemImage: "arrow.clockwise")
            }
            .disabled(usageStore.isRefreshing)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("UsageDock")
        .environment(\.locale, usageStore.appLanguage.locale)
    }

    private func canonicalRailShape(
        stretch: Double,
        neck: Double,
        kinetic: Double = 0
    ) -> EdgeRailShape {
        EdgeRailShape(
            edge: effectiveEdge,
            screenEdgeAmount: usageStore.railScreenEdgeShape,
            screenEdgeCurvature: usageStore.railScreenEdgeCurvature,
            innerEdgeAmount: usageStore.railInnerShape,
            cornerRadius: usageStore.railCornerRadius * usageStore.railScale,
            scallopDepth: usageStore.railScallopDepth * usageStore.railScale,
            scallopRadius: usageStore.railScallopRadius * usageStore.railScale,
            smoothing: usageStore.railScallopSmoothing,
            stretchAmount: stretch,
            neckAmount: neck,
            kineticAmount: kinetic,
            screenEdgeOutset: screenEdgeVisualOutset,
            renderInset: borderRenderPadding
        )
    }

    @ViewBuilder
    private var railContentMask: some View {
        switch dragPresentation.phase {
        case .attached:
            canonicalRailShape(
                stretch: Double(dragPresentation.shapeStretch),
                neck: Double(dragPresentation.neck),
                kinetic: Double(dragPresentation.kinetic)
            )
            .fill(Color.white)
        case .wetting:
            canonicalRailShape(stretch: 0, neck: 0)
                .fill(Color.white)
        case .floating, .returning, .docking:
            FloatingRailShape(
                impact: Double(dragPresentation.settle),
                kinetic: Double(dragPresentation.kinetic)
            )
            .fill(Color.white)
        }
    }

    @ViewBuilder
    private var railBackground: some View {
        if dragPresentation.phase == .attached {
            let shape = canonicalRailShape(
                stretch: Double(dragPresentation.shapeStretch),
                neck: Double(dragPresentation.neck),
                kinetic: Double(dragPresentation.kinetic)
            )
            railSurface(shape)
        } else if dragPresentation.phase == .wetting {
            let spread = dragPresentation.wettingSpread
            let contact = dragPresentation.wettingContact
            let finalShape = canonicalRailShape(stretch: 0, neck: 0)
            let contactDrop = FloatingRailShape(
                impact: Double(dragPresentation.settle),
                kinetic: Double(dragPresentation.kinetic)
            )
            let contactAnchor: UnitPoint = effectiveEdge == .left ? .leading : .trailing

            ZStack {
                railSurface(contactDrop)
                    .scaleEffect(
                        x: 1 - 0.44 * contact,
                        y: 1 - 0.20 * contact,
                        anchor: contactAnchor
                    )
                    .opacity(Double(1 - spread))

                railSurface(finalShape)
                    .scaleEffect(
                        x: 0.24 + 0.76 * spread,
                        y: 0.54 + 0.46 * spread,
                        anchor: contactAnchor
                    )
                    .opacity(Double(spread))
                    .blur(radius: max((1 - spread) * 1.2, 0))
            }
        } else {
            let floatingShape = FloatingRailShape(
                impact: Double(dragPresentation.settle),
                kinetic: Double(dragPresentation.kinetic)
            )
            railSurface(floatingShape)
                .scaleEffect(
                    x: FloatingRailGeometry.bodyScaleX(impact: Double(dragPresentation.settle)),
                    y: FloatingRailGeometry.bodyScaleY(impact: Double(dragPresentation.settle)),
                    anchor: .center
                )
        }
    }

    @ViewBuilder
    private func railSurface(_ shape: EdgeRailShape) -> some View {
        shape
            .fill(ProviderBrand.railFill(theme: usageStore.theme, opacity: usageStore.railBackgroundOpacity))
            .overlay { materialDepth(shape) }
            .overlay { attachedEdgeDecoration(shape) }
    }

    @ViewBuilder
    private func railSurface<S: Shape>(_ shape: S) -> some View {
        shape
            .fill(ProviderBrand.railFill(theme: usageStore.theme, opacity: usageStore.railBackgroundOpacity))
            .overlay { materialDepth(shape) }
            .overlay { edgeDecoration(shape) }
    }

    @ViewBuilder
    private func materialDepth<S: Shape>(_ shape: S) -> some View {
        let s = usageStore.railScale
        switch usageStore.railMaterialMode {
        case .standard:
            shape.fill(
                LinearGradient(
                    colors: usageStore.theme == .light
                        ? [Color.white.opacity(0.48), Color.white.opacity(0.10), Color.black.opacity(0.10)]
                        : [Color.white.opacity(0.13), Color.clear, Color.black.opacity(0.34)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            EmptyView()
        case .waterdrop:
            shape.fill(
                LinearGradient(
                    colors: [Color.white.opacity(0.34), Color.white.opacity(0.06), Color.black.opacity(0.28)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            shape.fill(
                RadialGradient(
                    colors: [Color.white.opacity(0.34), Color.white.opacity(0.06), Color.clear],
                    center: .topLeading,
                    startRadius: 0,
                    endRadius: 150 * s
                )
            )
            EmptyView()
        case .space:
            shape.fill(
                LinearGradient(
                    colors: [
                        Color(red: 0.035, green: 0.045, blue: 0.13).opacity(0.97),
                        Color(red: 0.13, green: 0.065, blue: 0.24).opacity(0.84),
                        Color(red: 0.015, green: 0.022, blue: 0.075).opacity(0.88)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            shape.fill(
                RadialGradient(
                    colors: [Color(red: 0.48, green: 0.58, blue: 1.0).opacity(0.17), Color.clear],
                    center: .topTrailing,
                    startRadius: 0,
                    endRadius: 140 * s
                )
            )
            SpaceSurfaceDetail(scale: s)
                .mask(shape.fill(Color.white))
        case .bar3D:
            shape.fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.34),
                        Color.white.opacity(0.08),
                        Color.black.opacity(0.12),
                        Color.black.opacity(0.42)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            shape.fill(
                LinearGradient(
                    colors: [Color.white.opacity(0.18), Color.clear, Color.black.opacity(0.24)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .offset(y: 0.55 * s)
            .mask(shape.fill(Color.white))
        }
    }

    @ViewBuilder
    private func edgeDecoration<S: Shape>(_ path: S) -> some View {
        let color = railEdgeColor
        switch effectiveEdgeStyle {
        case .off:
            EmptyView()
        case .simple:
            path.stroke(
                color.opacity(usageStore.railEdgeOpacity),
                style: StrokeStyle(lineWidth: max(usageStore.railEdgeWidth * usageStore.railScale, 0.35), lineCap: .round, lineJoin: .round)
            )
        case .soft:
            path.stroke(
                color.opacity(usageStore.railEdgeOpacity),
                style: StrokeStyle(lineWidth: max(usageStore.railEdgeWidth * usageStore.railScale, 0.4), lineCap: .round, lineJoin: .round)
            )
            .shadow(color: color.opacity(usageStore.railGlowOpacity), radius: usageStore.railGlowRadius * usageStore.railScale)
        case .neon:
            path.stroke(
                color.opacity(min(1, usageStore.railEdgeOpacity + 0.14)),
                style: StrokeStyle(lineWidth: max(usageStore.railEdgeWidth * usageStore.railScale, 0.55), lineCap: .round, lineJoin: .round)
            )
            .shadow(color: color.opacity(min(0.9, usageStore.railGlowOpacity + 0.18)), radius: max(3, usageStore.railGlowRadius * usageStore.railScale))
        case .glass:
            path.stroke(
                glassEdgeColor.opacity(max(usageStore.railEdgeOpacity, 0.46)),
                style: StrokeStyle(
                    lineWidth: max(usageStore.railEdgeWidth * usageStore.railScale * 1.10, 0.66),
                    lineCap: .round,
                    lineJoin: .round
                )
            )
            .shadow(
                color: glassEdgeColor.opacity(max(usageStore.railGlowOpacity * 0.62, 0.10)),
                radius: max(usageStore.railGlowRadius * 0.58 * usageStore.railScale, 0.55)
            )
        }
    }

    @ViewBuilder
    private func attachedEdgeDecoration(_ path: EdgeRailShape) -> some View {
        let color = railEdgeColor
        let scale = usageStore.railScale
        let desiredWidth = max(usageStore.railEdgeWidth * scale, 0.35)
        let insideWidth = desiredWidth * 2
        let visibleBorder = EdgeRailVisibleBorderShape(base: path)

        switch effectiveEdgeStyle {
        case .off:
            EmptyView()
        case .simple:
            visibleBorder.stroke(
                color.opacity(usageStore.railEdgeOpacity),
                style: StrokeStyle(lineWidth: insideWidth, lineCap: .round, lineJoin: .round)
            )
            .mask { path.fill(Color.white) }
        case .soft:
            visibleBorder.stroke(
                color.opacity(usageStore.railEdgeOpacity),
                style: StrokeStyle(lineWidth: max(insideWidth, 0.8), lineCap: .round, lineJoin: .round)
            )
            .mask { path.fill(Color.white) }
            .shadow(color: color.opacity(usageStore.railGlowOpacity), radius: usageStore.railGlowRadius * scale)
        case .neon:
            visibleBorder.stroke(
                color.opacity(min(1, usageStore.railEdgeOpacity + 0.14)),
                style: StrokeStyle(lineWidth: max(insideWidth, 1.1), lineCap: .round, lineJoin: .round)
            )
            .mask { path.fill(Color.white) }
            .shadow(color: color.opacity(min(0.9, usageStore.railGlowOpacity + 0.18)), radius: max(3, usageStore.railGlowRadius * scale))
        case .glass:
            visibleBorder.stroke(
                glassEdgeColor.opacity(max(usageStore.railEdgeOpacity, 0.46)),
                style: StrokeStyle(lineWidth: max(insideWidth * 1.10, 1.16), lineCap: .round, lineJoin: .round)
            )
            .mask { path.fill(Color.white) }
            .shadow(
                color: glassEdgeColor.opacity(max(usageStore.railGlowOpacity * 0.62, 0.10)),
                radius: max(usageStore.railGlowRadius * 0.58 * scale, 0.55)
            )
        }
    }

    private var railEdgeColor: Color {
        switch usageStore.railBorderColorMode {
        case .automatic:
            return ProviderBrand.border(theme: usageStore.theme)
        case .accountAccent:
            guard let first = targets.first else { return ProviderBrand.border(theme: usageStore.theme) }
            return ProviderBrand.color(hex: usageStore.accentHex(for: first))
                ?? ProviderBrand.glow(for: first.provider, theme: usageStore.theme)
        case .providerAccent:
            guard let provider = targets.first?.provider else { return ProviderBrand.border(theme: usageStore.theme) }
            return ProviderBrand.color(hex: usageStore.providerAccentHex[provider])
                ?? ProviderBrand.glow(for: provider, theme: usageStore.theme)
        case .custom:
            return ProviderBrand.color(hex: usageStore.railBorderCustomHex)
                ?? ProviderBrand.border(theme: usageStore.theme)
        }
    }

    private var glassEdgeColor: Color {
        switch usageStore.theme {
        case .light:
            return Color.black.opacity(0.48)
        case .pop:
            return Color(red: 0.76, green: 0.66, blue: 1.0).opacity(0.92)
        case .dark, .monochrome, .transparentFloating:
            return Color.white.opacity(0.88)
        }
    }

    private var backgroundDragGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                guard interactionEnabled, !usageStore.railVisualOnlyMode, !suppressUntilGestureEnds else { return }
                guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
                let now = ProcessInfo.processInfo.systemUptime

                if dragStartVerticalPosition == nil {
                    settleTask?.cancel()
                    settleTask = nil
                    breakPulseTask?.cancel()
                    breakPulseTask = nil
                    settleSequence += 1
                    dragStartVerticalPosition = usageStore.railVerticalPosition
                    dragStartGlobalX = NSEvent.mouseLocation.x
                    dragOriginEdge = placement.edge
                    breakAnchorVerticalPosition = usageStore.railVerticalPosition
                    dragPhase = .attached
                    dragVisualStartedAt = Date.timeIntervalSinceReferenceDate
                    dragParticleSeed = UInt64.random(in: UInt64.min...UInt64.max)
                    lastGrabPoint = overlayLocalMousePoint(screen: screen)
                    dragVelocityTracker.begin(translation: value.translation, timestamp: now)
                    breakVisualStartedAt = 0
                    breakVelocity = .zero
                    breakOrigin = .zero
                    inputVisualSuppressed = true
                    let originCenter = overlayCenter(
                        edge: placement.edge,
                        verticalPosition: usageStore.railVerticalPosition,
                        screen: screen
                    )
                    motionRuntime.begin(
                        verticalPosition: usageStore.railVerticalPosition,
                        originCenter: originCenter,
                        timestamp: now
                    )
                }

                let visibleFrame = screen.visibleFrame
                lastGrabPoint = overlayLocalMousePoint(screen: screen)
                _ = dragVelocityTracker.update(translation: value.translation, timestamp: now)
                let verticalTravel = max(visibleFrame.height - baseRailHeight - 16, 1)
                let verticalDelta = Double(value.translation.height / verticalTravel)
                let verticalTarget = min(
                    max((dragStartVerticalPosition ?? usageStore.railVerticalPosition) + verticalDelta, 0),
                    1
                )
                let originEdge = dragOriginEdge ?? placement.edge
                let screenWidth = max(visibleFrame.width, 1)
                let pointerX = (dragStartGlobalX ?? NSEvent.mouseLocation.x) + value.translation.width
                let pointerOutwardDistance: CGFloat
                switch originEdge {
                case .left:
                    pointerOutwardDistance = pointerX - visibleFrame.minX
                case .right:
                    pointerOutwardDistance = visibleFrame.maxX - pointerX
                }
                let screenProgress = min(max(pointerOutwardDistance / screenWidth, 0), 1)
                let outwardTranslation = originEdge == .left ? value.translation.width : -value.translation.width
                let outwardDistance = max(outwardTranslation, 0)
                let floatingTarget = clampedFloatingCenter(
                    originEdge: originEdge,
                    verticalPosition: dragStartVerticalPosition ?? usageStore.railVerticalPosition,
                    translation: value.translation,
                    screen: screen
                )

                switch dragPhase {
                case .attached:
                    let frame = motionRuntime.updateDrag(
                        outwardDistance: outwardDistance,
                        screenProgress: screenProgress,
                        screenWidth: screenWidth,
                        verticalTarget: verticalTarget,
                        timestamp: now
                    )
                    publishDragVisual(
                        phase: .attached,
                        edge: originEdge,
                        frame: frame,
                        sideProgress: min(screenProgress / RailMotionRuntime.surfaceBreakThreshold, 1)
                    )

                    if screenProgress >= RailMotionRuntime.surfaceBreakThreshold {
                        dragPhase = .floating
                        breakAnchorVerticalPosition = verticalTarget
                        breakVisualStartedAt = Date.timeIntervalSinceReferenceDate
                        breakVelocity = dragVelocityTracker.velocity
                        breakOrigin = floatingTarget
                        let breakFrame = motionRuntime.breakSurface(
                            floatingCenter: floatingTarget,
                            verticalPosition: verticalTarget,
                            timestamp: now
                        )
                        publishDragVisual(
                            phase: .floating,
                            edge: originEdge,
                            frame: breakFrame,
                            sideProgress: 0
                        )
                        startSurfaceBreakPulse(edge: originEdge)

                        if screenProgress >= RailMotionRuntime.dockThreshold {
                            triggerDockTransfer(from: originEdge, screen: screen)
                        }
                    }

                case .floating:
                    let frame = motionRuntime.updateFloating(
                        floatingCenter: floatingTarget,
                        verticalPosition: verticalTarget,
                        timestamp: now
                    )
                    let freeProgress = min(
                        max(
                            (screenProgress - RailMotionRuntime.surfaceBreakThreshold) /
                            (RailMotionRuntime.dockThreshold - RailMotionRuntime.surfaceBreakThreshold),
                            0
                        ),
                        1
                    )
                    publishDragVisual(
                        phase: .floating,
                        edge: originEdge,
                        frame: frame,
                        sideProgress: freeProgress
                    )
                    if screenProgress >= RailMotionRuntime.dockThreshold {
                        triggerDockTransfer(from: originEdge, screen: screen)
                    }

                case .returning, .docking, .wetting:
                    break
                }
            }
            .onEnded { _ in
                if suppressUntilGestureEnds {
                    suppressUntilGestureEnds = false
                    crossedScreenCenter = false
                    return
                }

                guard let screen = NSScreen.main ?? NSScreen.screens.first else {
                    finishOverlayInteraction()
                    return
                }
                let now = ProcessInfo.processInfo.systemUptime
                let finalVerticalPosition = motionRuntime.targetVerticalPosition
                let releaseEdge = dragOriginEdge ?? placement.edge

                switch dragPhase {
                case .attached:
                    if abs(finalVerticalPosition - usageStore.railVerticalPosition) > 0.000_001 {
                        usageStore.railVerticalPosition = finalVerticalPosition
                    }
                    settleSequence += 1
                    let sequence = settleSequence
                    let releaseFrame = motionRuntime.release(timestamp: now)
                    resetGestureTracking()
                    publishDragVisual(
                        phase: .attached,
                        edge: releaseEdge,
                        frame: releaseFrame,
                        sideProgress: 0
                    )
                    startAttachedSettle(edge: releaseEdge, sequence: sequence)

                case .floating:
                    breakPulseTask?.cancel()
                    breakPulseTask = nil
                    if abs(finalVerticalPosition - usageStore.railVerticalPosition) > 0.000_001 {
                        usageStore.railVerticalPosition = finalVerticalPosition
                    }
                    dragPhase = .returning
                    settleSequence += 1
                    let sequence = settleSequence
                    let returnCenter = overlayCenter(
                        edge: releaseEdge,
                        verticalPosition: finalVerticalPosition,
                        screen: screen
                    )
                    let returnFrame = motionRuntime.beginReturn(
                        to: returnCenter,
                        verticalPosition: finalVerticalPosition,
                        timestamp: now
                    )
                    resetGestureTracking()
                    publishDragVisual(
                        phase: .returning,
                        edge: releaseEdge,
                        frame: returnFrame,
                        sideProgress: 0
                    )
                    startFloatingSettle(
                        phase: .returning,
                        edge: releaseEdge,
                        destination: nil,
                        sequence: sequence
                    )

                case .returning, .docking, .wetting:
                    break
                }
            }
    }

    private func triggerDockTransfer(from originEdge: DockEdge, screen: NSScreen) {
        guard dragPhase == .floating, !crossedScreenCenter, !suppressUntilGestureEnds else { return }
        crossedScreenCenter = true
        suppressUntilGestureEnds = true
        dragPhase = .docking
        breakPulseTask?.cancel()
        breakPulseTask = nil
        settleTask?.cancel()
        settleTask = nil
        settleSequence += 1
        let sequence = settleSequence
        let destination: DockEdge = originEdge == .left ? .right : .left
        let finalVerticalPosition = motionRuntime.targetVerticalPosition
        let incomingVelocity = motionRuntime.outwardVelocity
        let dockCenter = overlayCenter(
            edge: destination,
            verticalPosition: finalVerticalPosition,
            screen: screen
        )
        let dockFrame = motionRuntime.beginDock(
            to: dockCenter,
            verticalPosition: finalVerticalPosition,
            incomingVelocity: incomingVelocity,
            timestamp: ProcessInfo.processInfo.systemUptime
        )
        publishDragVisual(
            phase: .docking,
            edge: originEdge,
            frame: dockFrame,
            sideProgress: 1
        )
        startFloatingSettle(
            phase: .docking,
            edge: originEdge,
            destination: destination,
            sequence: sequence
        )
    }

    private func publishDragVisual(
        phase: RailDragPhase,
        edge: DockEdge,
        frame: RailMotionFrame,
        sideProgress: CGFloat
    ) {
        let presentation = RailDragPresentation(
            phase: phase,
            rawProgress: frame.rawProgress,
            canvasExtraWidth: frame.canvasExtraWidth,
            stretch: frame.stretch,
            detach: frame.detach,
            settle: frame.impact,
            sideProgress: sideProgress,
            contentTravel: frame.contentTravel,
            kinetic: frame.kinetic,
            breakPulse: frame.breakPulse,
            wetting: frame.wetting
        )
        let velocitySampledAt = ProcessInfo.processInfo.systemUptime
        let liveVelocity = dragVelocityTracker.decayedVelocity(at: velocitySampledAt)
        onDragVisualStateChange(
            RailDragVisualSnapshot(
                phase: phase,
                edge: edge,
                verticalPosition: frame.verticalPosition,
                anchorVerticalPosition: breakAnchorVerticalPosition ?? dragStartVerticalPosition ?? frame.verticalPosition,
                rawProgress: frame.rawProgress,
                canvasExtraWidth: frame.canvasExtraWidth,
                stretch: frame.stretch,
                detach: frame.detach,
                settle: frame.impact,
                sideProgress: sideProgress,
                contentTravel: frame.contentTravel,
                kinetic: frame.kinetic,
                shapeStretch: presentation.shapeStretch,
                neck: presentation.neck,
                breakPulse: frame.breakPulse,
                floatingCenterX: frame.floatingCenterX,
                floatingCenterY: frame.floatingCenterY,
                residue: frame.residue,
                wetting: frame.wetting,
                dragStartedAt: dragVisualStartedAt,
                particleSeed: dragParticleSeed,
                grabX: lastGrabPoint.x,
                grabY: lastGrabPoint.y,
                dragVelocityX: liveVelocity.dx,
                dragVelocityY: liveVelocity.dy,
                dragVelocitySampledAt: velocitySampledAt,
                emitsDroplets: usageStore.railDropletsEnabled
                    && (phase == .attached || phase == .floating)
                    && dragStartVerticalPosition != nil
                    && !suppressUntilGestureEnds,
                breakStartedAt: breakVisualStartedAt,
                breakVelocityX: breakVelocity.dx,
                breakVelocityY: breakVelocity.dy,
                breakOriginX: breakOrigin.x,
                breakOriginY: breakOrigin.y,
                emitsBreakSplash: usageStore.railDropletsEnabled
                    && breakVisualStartedAt > 0
                    && Date.timeIntervalSinceReferenceDate - breakVisualStartedAt <= RailBreakDropletEmitter.maxLifetime
                    && phase != .attached
                    && phase != .wetting
            )
        )
    }

    private func startSurfaceBreakPulse(edge: DockEdge) {
        breakPulseTask?.cancel()
        let sequence = settleSequence
        breakPulseTask = Task { @MainActor in
            var frameCount = 0
            while !Task.isCancelled, settleSequence == sequence, dragPhase == .floating, frameCount < 84 {
                let frame = motionRuntime.tickFloating(timestamp: ProcessInfo.processInfo.systemUptime)
                publishDragVisual(phase: .floating, edge: edge, frame: frame, sideProgress: 0)
                frameCount += 1
                let particlesFinished = breakVisualStartedAt <= 0
                    || Date.timeIntervalSinceReferenceDate - breakVisualStartedAt > RailBreakDropletEmitter.maxLifetime
                if frameCount > 20,
                   particlesFinished,
                   abs(frame.residue) < 0.025,
                   frame.impact < 0.025,
                   abs(frame.breakPulse) < 0.025 {
                    break
                }
                // F17.20 keeps the short post-break particle lifetime alive at display-rate,
                // then fully stops. No TimelineView remains once the overlay is dismissed.
                try? await Task.sleep(nanoseconds: 16_666_667)
            }
            if settleSequence == sequence { breakPulseTask = nil }
        }
    }

    private func startAttachedSettle(edge: DockEdge, sequence: Int) {
        settleTask?.cancel()
        settleTask = Task { @MainActor in
            var frameCount = 0
            while !Task.isCancelled, settleSequence == sequence, frameCount < 120 {
                let frame = motionRuntime.stepTowardRest(timestamp: ProcessInfo.processInfo.systemUptime)
                publishDragVisual(phase: .attached, edge: edge, frame: frame, sideProgress: 0)
                frameCount += 1
                if frameCount > 4, motionRuntime.isSettled { break }
                try? await Task.sleep(nanoseconds: 8_333_333)
            }
            guard !Task.isCancelled, settleSequence == sequence else { return }
            finishOverlayInteraction()
            settleTask = nil
        }
    }

    private func startFloatingSettle(
        phase: RailDragPhase,
        edge: DockEdge,
        destination: DockEdge?,
        sequence: Int
    ) {
        settleTask?.cancel()
        settleTask = Task { @MainActor in
            var frameCount = 0
            while !Task.isCancelled, settleSequence == sequence, frameCount < 150 {
                let frame: RailMotionFrame
                switch phase {
                case .returning:
                    frame = motionRuntime.stepReturn(timestamp: ProcessInfo.processInfo.systemUptime)
                case .docking:
                    frame = motionRuntime.stepDock(timestamp: ProcessInfo.processInfo.systemUptime)
                case .attached, .floating, .wetting:
                    return
                }
                publishDragVisual(
                    phase: phase,
                    edge: edge,
                    frame: frame,
                    sideProgress: phase == .docking ? 1 : 0
                )
                frameCount += 1
                if frameCount > 8, motionRuntime.isFloatingSettled { break }
                try? await Task.sleep(nanoseconds: 8_333_333)
            }
            guard !Task.isCancelled, settleSequence == sequence else { return }

            if let destination {
                let finalVerticalPosition = motionRuntime.targetVerticalPosition
                dragPhase = .wetting
                let wettingFrame = motionRuntime.beginWetting(
                    verticalPosition: finalVerticalPosition,
                    incomingVelocity: motionRuntime.outwardVelocity,
                    timestamp: ProcessInfo.processInfo.systemUptime
                )
                publishDragVisual(
                    phase: .wetting,
                    edge: destination,
                    frame: wettingFrame,
                    sideProgress: 1
                )
                settleTask = nil
                startWettingSettle(edge: destination, sequence: sequence)
                return
            }
            finishOverlayInteraction()
            settleTask = nil
        }
    }

    private func startWettingSettle(edge: DockEdge, sequence: Int) {
        settleTask?.cancel()
        settleTask = Task { @MainActor in
            var frameCount = 0
            while !Task.isCancelled, settleSequence == sequence, frameCount < 150 {
                let frame = motionRuntime.stepWetting(timestamp: ProcessInfo.processInfo.systemUptime)
                publishDragVisual(
                    phase: .wetting,
                    edge: edge,
                    frame: frame,
                    sideProgress: 1
                )
                frameCount += 1
                if frameCount > 28, motionRuntime.isWettingSettled { break }
                try? await Task.sleep(nanoseconds: 8_333_333)
            }
            guard !Task.isCancelled, settleSequence == sequence else { return }
            let finalVerticalPosition = motionRuntime.targetVerticalPosition
            if abs(finalVerticalPosition - usageStore.railVerticalPosition) > 0.000_001 {
                usageStore.railVerticalPosition = finalVerticalPosition
            }
            placement.edge = edge
            startMouseReleaseWatch()
            finishOverlayInteraction(preserveSuppression: true)
            settleTask = nil
        }
    }

    private func overlayCenter(edge: DockEdge, verticalPosition: Double, screen: NSScreen) -> CGPoint {
        let visible = screen.visibleFrame
        let full = screen.frame
        let leftInset = max(visible.minX - full.minX, 0)
        let rightInset = max(full.maxX - visible.maxX, 0)
        let topInset = max(full.maxY - visible.maxY, 0)
        let verticalTravel = max(visible.height - baseRailHeight - 16, 0)
        let centerY = topInset + 8 + baseRailHeight * 0.5 + verticalTravel * CGFloat(verticalPosition)
        let centerX = edge == .left
            ? leftInset + baseRailWidth * 0.5
            : full.width - rightInset - baseRailWidth * 0.5
        return CGPoint(x: centerX, y: centerY)
    }

    private func overlayLocalMousePoint(screen: NSScreen) -> CGPoint {
        let mouse = NSEvent.mouseLocation
        let frame = screen.frame
        return CGPoint(
            x: min(max(mouse.x - frame.minX, 0), frame.width),
            y: min(max(frame.maxY - mouse.y, 0), frame.height)
        )
    }

    private func clampedFloatingCenter(
        originEdge: DockEdge,
        verticalPosition: Double,
        translation: CGSize,
        screen: NSScreen
    ) -> CGPoint {
        let start = overlayCenter(edge: originEdge, verticalPosition: verticalPosition, screen: screen)
        let halfWidth = baseRailWidth * 0.5
        let halfHeight = baseRailHeight * 0.5
        let x = min(max(start.x + translation.width, halfWidth + 8), screen.frame.width - halfWidth - 8)
        let y = min(max(start.y + translation.height, halfHeight + 8), screen.frame.height - halfHeight - 8)
        return CGPoint(x: x, y: y)
    }

    private func startMouseReleaseWatch() {
        mouseReleaseWatchTask?.cancel()
        mouseReleaseWatchTask = Task { @MainActor in
            while !Task.isCancelled, NSEvent.pressedMouseButtons & 1 != 0 {
                try? await Task.sleep(nanoseconds: 25_000_000)
            }
            guard !Task.isCancelled else { return }
            suppressUntilGestureEnds = false
            crossedScreenCenter = false
            mouseReleaseWatchTask = nil
        }
    }

    private func finishOverlayInteraction(preserveSuppression: Bool = false) {
        onDragVisualStateChange(nil)
        inputVisualSuppressed = false
        dragPhase = .attached
        breakAnchorVerticalPosition = nil
        breakPulseTask?.cancel()
        breakPulseTask = nil
        resetGestureTracking(keepSuppression: preserveSuppression)
    }

    private func resetGestureTracking(keepSuppression: Bool = false) {
        dragStartVerticalPosition = nil
        dragStartGlobalX = nil
        dragOriginEdge = nil
        crossedScreenCenter = false
        if !keepSuppression {
            suppressUntilGestureEnds = false
        }
    }

    @ViewBuilder
    private func displayAccountMenu() -> some View {
        let candidates = usageStore.displayAccountCandidates()
        if candidates.isEmpty {
            Label("Choose up to 3 accounts in Settings", systemImage: "person.2")
                .foregroundStyle(.secondary)
        } else {
            ForEach(candidates) { account in
                let state = usageStore.displayAuthenticationState(for: account)
                Button {
                    usageStore.selectDisplayAccount(account.id)
                } label: {
                    Label(
                        "\(account.provider.displayName) · \(account.name)",
                        systemImage: usageStore.isActiveDisplayAccount(account.id) ? "checkmark.circle.fill" : "circle"
                    )
                }
                .disabled(state != .valid)

                if state == .required {
                    Label("Authentication required", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                } else if state == .checking {
                    Label("Waiting for live authentication", systemImage: "clock")
                        .foregroundStyle(.secondary)
                }
            }
        }

        Divider()
        Button {
            onOpenSettings()
        } label: {
            Label("Manage Display Accounts…", systemImage: "person.crop.circle.badge.checkmark")
        }
    }

    @ViewBuilder
    private func providerAccountMenu(_ provider: ProviderID) -> some View {
        Menu(provider.displayName) {
            if provider.supportsProfileLogin {
                Button {
                    _ = usageStore.launchLoginProfile(provider: provider)
                } label: {
                    Label(
                        provider == .antigravity ? "Open Antigravity Login" : "Login New Profile",
                        systemImage: "person.crop.circle.badge.plus"
                    )
                }
            }

            if usageStore.canRegisterCurrentSession(provider: provider) {
                Button {
                    if usageStore.registerCurrentSessionAccount(provider: provider) {
                        Task { await usageStore.refreshLiveUsage() }
                    }
                } label: {
                    Label("Add Current Login", systemImage: "person.crop.circle.badge.checkmark")
                }
            }

            if !provider.supportsProfileLogin && !provider.supportsLiveUsage {
                Label("Login unavailable", systemImage: "lock")
            }

            let accounts = usageStore.visibleAccounts(for: provider)
            if !accounts.isEmpty {
                Divider()
                ForEach(accounts) { account in
                    Menu(account.name) {
                        Button {
                            if let target = RailDisplayTarget.account(id: account.id, provider: provider) as RailDisplayTarget? {
                                _ = usageStore.openWeb(for: target)
                            }
                        } label: {
                            Label("Open Web", systemImage: "safari")
                        }

                        Button {
                            onOpenSettings()
                        } label: {
                            Label("Edit…", systemImage: "pencil")
                        }

                        Button(role: .destructive) {
                            usageStore.removeAccount(id: account.id)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        }
    }
}

struct RailContentDeformation: Equatable {
    let neckZone: CGFloat
    let midZone: CGFloat
    let freeSideZone: CGFloat
    let groupScaleX: CGFloat
    let groupScaleY: CGFloat
    let spacingScale: CGFloat
    let freeSideTranslation: CGFloat
    let bodyPlacementWeight: CGFloat
    let perspectiveDegrees: Double
}

enum RailContentDeformationField {
    static func resolve(
        stretch: CGFloat,
        neck: CGFloat,
        kinetic: CGFloat,
        detach: CGFloat,
        scale: CGFloat,
        attached: Bool
    ) -> RailContentDeformation {
        guard attached else {
            return RailContentDeformation(
                neckZone: 0,
                midZone: 0,
                freeSideZone: 0,
                groupScaleX: 1,
                groupScaleY: 1,
                spacingScale: 1,
                freeSideTranslation: 0,
                bodyPlacementWeight: 0,
                perspectiveDegrees: 0
            )
        }

        let s = min(max(stretch, 0), 1.34)
        let n = min(max(neck, 0), 1)
        let k = min(max(kinetic, 0), 1)
        let d = min(max(detach, 0), 1)
        let raw = min(max(s * 0.62 + n * 0.42 + k * 0.12 - d * 0.035, 0), 1)
        let tension = smoothStep(raw)

        // Three-zone field: the throat deliberately receives very little deformation,
        // the middle eases into motion, and the free/inward side carries most of the
        // stretch. This keeps icons out of the hourglass waist while the visual body can
        // still pinch aggressively there.
        let neckZone = tension * 0.18
        let midZone = smoothStep(min(max((tension - 0.04) / 0.96, 0), 1)) * 0.58
        let freeSideZone = smoothStep(min(max((tension - 0.01) / 0.99, 0), 1))
        // F17.21: deform the content cluster as one body. Individual provider icons/tiles
        // stay internally rigid; the outer cluster carries the mochi stretch and translation.
        let groupScaleX = 1 + 0.014 * neckZone + 0.090 * midZone + 0.225 * freeSideZone
        let groupScaleY = 1 - 0.010 * neckZone - 0.030 * midZone - 0.060 * freeSideZone
        let spacingScale = 1 + 0.055 * midZone + 0.060 * freeSideZone
        let freeSideTranslation = scale * (0.8 * neckZone + 3.4 * midZone + 8.5 * freeSideZone)
        let bodyPlacementWeight = min(max(0.12 * midZone + 0.88 * freeSideZone, 0), 1)
        let perspective = Double(2.0 * midZone + 3.4 * freeSideZone)

        return RailContentDeformation(
            neckZone: neckZone,
            midZone: midZone,
            freeSideZone: freeSideZone,
            groupScaleX: groupScaleX,
            groupScaleY: groupScaleY,
            spacingScale: spacingScale,
            freeSideTranslation: freeSideTranslation,
            bodyPlacementWeight: bodyPlacementWeight,
            perspectiveDegrees: perspective
        )
    }

    private static func smoothStep(_ value: CGFloat) -> CGFloat {
        let t = min(max(value, 0), 1)
        return t * t * (3 - 2 * t)
    }
}

struct RailNeckMinimumGeometry: Equatable {
    let distanceFromScreen: CGFloat
    let upperSurfaceY: CGFloat
    let lowerSurfaceY: CGFloat
    let centerY: CGFloat
    let thickness: CGFloat
}

struct EdgeRailSemanticProfile: Equatable {
    let valley: CGFloat
    let outwardSpread: CGFloat
    let inwardBubble: CGFloat

    static func resolve(screenEdgeAmount: Double, screenEdgeCurvature: Double) -> EdgeRailSemanticProfile {
        let shape = min(max(CGFloat(screenEdgeAmount), -1), 1)
        let valleyOnlyCurvature = min(max(CGFloat(screenEdgeCurvature), -1), 0)
        return EdgeRailSemanticProfile(
            valley: -valleyOnlyCurvature,
            outwardSpread: max(shape, 0),
            inwardBubble: max(-shape, 0)
        )
    }
}

enum RailNeckGeometryResolver {
    static func resolve(
        in rect: CGRect,
        edge: DockEdge,
        screenEdgeAmount: Double,
        screenEdgeCurvature: Double,
        innerEdgeAmount: Double,
        cornerRadius: Double,
        scallopDepth: Double,
        smoothing: Double,
        stretchAmount: Double,
        neckAmount: Double,
        kineticAmount: Double,
        screenEdgeOutset: CGFloat,
        renderInset: CGFloat
    ) -> RailNeckMinimumGeometry {
        let stretch = min(max(CGFloat(stretchAmount), 0), 1.2)
        let neck = min(max(CGFloat(neckAmount), 0), 1)
        let kinetic = min(max(CGFloat(kineticAmount), 0), 1)
        let semantic = EdgeRailSemanticProfile.resolve(
            screenEdgeAmount: screenEdgeAmount,
            screenEdgeCurvature: screenEdgeCurvature
        )
        let valley = semantic.valley
        let outwardSpread = semantic.outwardSpread
        let inwardBubble = semantic.inwardBubble
        let visualOutset = max(screenEdgeOutset, 0)
        let safeRenderInset = max(renderInset, 0)
        let nominalMinY = rect.minY + visualOutset + safeRenderInset
        let nominalMaxY = rect.maxY - visualOutset - safeRenderInset
        let nominalHeight = max(nominalMaxY - nominalMinY, 1)
        let centerY = (nominalMinY + nominalMaxY) * 0.5
        let baseRadius = min(CGFloat(cornerRadius), rect.width * 0.42, nominalHeight * 0.18)
        let radius = max(2, baseRadius * (1 - 0.28 * neck))
        let baseDepth = min(CGFloat(scallopDepth), nominalHeight * 0.30)
        let depth = min(baseDepth * (1 + 0.20 * stretch + 0.26 * neck), nominalHeight * 0.36)
        let screenRaw = shapeInset(screenEdgeAmount, depth: depth)
        let innerRaw = shapeInset(innerEdgeAmount, depth: depth)
        let baseline = min(screenRaw, innerRaw)
        let screenInset = screenRaw - baseline
        let freeEndCompression = min(
            nominalHeight * (0.014 * stretch + 0.018 * neck + 0.008 * kinetic),
            nominalHeight * 0.055
        )
        let innerInset = min(innerRaw - baseline + freeEndCompression, nominalHeight * 0.16)
        let pinchCurve = CGFloat(pow(Double(neck), 1.18))
        let screenLobePinch = min(
            nominalHeight * (0.018 * stretch + 0.070 * pinchCurve + 0.080 * inwardBubble),
            nominalHeight * 0.160
        )
        let screenTopY = min(nominalMinY - visualOutset + screenInset + screenLobePinch, centerY - 2)
        let screenBottomY = max(nominalMaxY + visualOutset - screenInset - screenLobePinch, centerY + 2)
        let innerTopY = nominalMinY + innerInset
        let innerBottomY = nominalMaxY - innerInset
        let span = max(rect.width - radius, 1)
        let concavity = min(
            max(
                0.54 + 0.16 * outwardSpread + 0.34 * inwardBubble + 0.14 * neck + 0.05 * stretch
                    + 0.34 * valley,
                0.18
            ),
            0.98
        )
        let stretchNormalized = min(max(stretch / 1.05, 0), 1)
        let stretchRoundness = stretchNormalized * stretchNormalized * (3 - 2 * stretchNormalized)
        let neckRun = min(
            max(
                span * (
                    0.18 +
                    0.065 * outwardSpread -
                    0.045 * inwardBubble +
                    0.160 * neck +
                    0.120 * stretchRoundness +
                    0.035 * kinetic +
                    0.075 * valley
                ),
                radius * (1.10 - 0.35 * inwardBubble)
            ),
            span * 0.56
        )
        let throatProgress = min(
            max(0.72 + 0.18 * concavity + 0.14 * valley + 0.05 * inwardBubble, 0.46),
            0.96
        )
        let tensionRaw = min(max(neck * 0.68 + stretchRoundness * 0.54 + kinetic * 0.10, 0), 1)
        let surfaceTension = tensionRaw * tensionRaw * (3 - 2 * tensionRaw)
        let throatPinch = min(
            nominalHeight * (
                0.030 * stretch +
                0.365 * pinchCurve +
                0.045 * surfaceTension +
                0.014 * kinetic
            ),
            nominalHeight * 0.405
        )
        let minimumHalfGap = max(0.90, 1.70 - 0.80 * surfaceTension)
        let upperY = min(
            screenTopY + (innerTopY - screenTopY) * throatProgress + throatPinch,
            centerY - minimumHalfGap
        )
        let lowerY = max(
            screenBottomY + (innerBottomY - screenBottomY) * throatProgress - throatPinch,
            centerY + minimumHalfGap
        )
        return RailNeckMinimumGeometry(
            distanceFromScreen: neckRun,
            upperSurfaceY: upperY,
            lowerSurfaceY: lowerY,
            centerY: (upperY + lowerY) * 0.5,
            thickness: max(lowerY - upperY, 0)
        )
    }

    private static func shapeInset(_ amount: Double, depth: CGFloat) -> CGFloat {
        let normalized = min(max(CGFloat(amount), -1), 1)
        return depth * (0.5 - normalized * 0.5)
    }
}

enum RailContentBodyPlacement {
    static func targetOffset(
        railWidth: CGFloat,
        renderedContentWidth: CGFloat,
        neckDistanceFromScreen: CGFloat,
        edge: DockEdge,
        freeSideWeight: CGFloat,
        borderPadding: CGFloat
    ) -> CGFloat {
        let width = max(railWidth, 1)
        let direction: CGFloat = edge == .left ? 1 : -1
        let screenX: CGFloat = edge == .left ? 0 : width
        let freeTipX: CGFloat = edge == .left ? width : 0
        let neckX = screenX + direction * min(max(neckDistanceFromScreen, 0), width)
        let bodyProgress = min(max(0.56 + 0.12 * freeSideWeight, 0.56), 0.70)
        let rawCenter = neckX + (freeTipX - neckX) * bodyProgress
        let safety = max(borderPadding + 1, 1)
        let half = min(max(renderedContentWidth * 0.5, 0), width * 0.5)
        let minCenter = min(half + safety, width * 0.5)
        let maxCenter = max(width - half - safety, width * 0.5)
        let clampedCenter = min(max(rawCenter, minCenter), maxCenter)
        return clampedCenter - width * 0.5
    }
}

enum RailBreakVisualTransform {
    static func scaleX(for pulse: CGFloat) -> CGFloat {
        let (splash, rebound) = components(for: pulse)
        return 1 + 0.16 * splash - 0.070 * rebound
    }

    static func scaleY(for pulse: CGFloat) -> CGFloat {
        let (splash, rebound) = components(for: pulse)
        return 1 - 0.105 * splash + 0.075 * rebound
    }

    static func yOffset(for pulse: CGFloat) -> CGFloat {
        let (splash, rebound) = components(for: pulse)
        return 5.5 * splash - 2.0 * rebound
    }

    private static func components(for pulse: CGFloat) -> (splash: CGFloat, rebound: CGFloat) {
        let clamped = min(max(pulse, -1), 1)
        return (max(clamped, 0), max(-clamped, 0))
    }
}

private struct RailDragPresentation {
    let phase: RailDragPhase
    let rawProgress: CGFloat
    let canvasExtraWidth: CGFloat
    let stretch: CGFloat
    let detach: CGFloat
    let settle: CGFloat
    let sideProgress: CGFloat
    let contentTravel: CGFloat
    let kinetic: CGFloat
    let breakPulse: CGFloat
    let wetting: CGFloat

    private var clampedStretch: CGFloat { min(max(stretch, 0), 1.34) }
    private var clampedDetach: CGFloat { min(max(detach, 0), 1) }
    private var clampedKinetic: CGFloat { min(max(kinetic, 0), 1) }
    private var clampedSettle: CGFloat { min(max(settle, 0), 1) }
    private var signedBreakPulse: CGFloat {
        guard phase == .floating else { return 0 }
        return min(max(breakPulse, -1), 1)
    }

    static func smoothStep01(_ value: CGFloat) -> CGFloat {
        let t = min(max(value, 0), 1)
        return t * t * (3 - 2 * t)
    }

    var wettingContact: CGFloat {
        guard phase == .wetting else { return 0 }
        return Self.smoothStep01(min(max(wetting / 0.20, 0), 1))
    }

    var wettingSpread: CGFloat {
        guard phase == .wetting else { return phase == .attached ? 1 : 0 }
        return Self.smoothStep01(min(max((wetting - 0.10) / 0.90, 0), 1))
    }

    var wettingContentScaleX: CGFloat {
        guard phase == .wetting else { return 1 }
        return 1 - 0.16 * wettingContact + 0.16 * wettingSpread
    }

    var wettingContentScaleY: CGFloat {
        guard phase == .wetting else { return 1 }
        return 1 - 0.07 * wettingContact + 0.07 * wettingSpread
    }

    var ruptureScaleX: CGFloat { RailBreakVisualTransform.scaleX(for: signedBreakPulse) }

    var ruptureScaleY: CGFloat { RailBreakVisualTransform.scaleY(for: signedBreakPulse) }

    var ruptureYOffset: CGFloat { RailBreakVisualTransform.yOffset(for: signedBreakPulse) }

    var neck: CGFloat {
        let t = min(max((clampedStretch - 0.14) / 0.86, 0), 1)
        let curved = t * t * (3 - 2 * t)
        return min(curved * (1 + clampedDetach * 0.12) + clampedKinetic * 0.08, 1)
    }

    var shapeStretch: CGFloat {
        let rawTension = min(max(rawProgress, 0), 1.18)
        return min(
            max(
                clampedStretch * (1 - 0.04 * clampedDetach) +
                rawTension * 0.18 +
                clampedKinetic * 0.10 +
                clampedSettle * 0.045,
                0
            ),
            1.36
        )
    }

    var iconHorizontalStretch: CGFloat {
        let stretchScale = 1 + 0.54 * clampedStretch + 0.15 * neck + 0.12 * clampedKinetic
        let detachRelaxation = 0.035 * clampedDetach
        return min(max(stretchScale - detachRelaxation + 0.05 * clampedSettle, 1), 1.88)
    }

    var iconVerticalScale: CGFloat {
        min(
            max(
                1 - 0.060 * clampedStretch - 0.038 * neck - 0.030 * clampedKinetic + 0.022 * clampedSettle,
                0.83
            ),
            1.05
        )
    }

    var textTracking: CGFloat {
        min(
            max(1.7 * clampedStretch + 0.52 * neck + 0.58 * clampedKinetic - 0.16 * clampedDetach, 0),
            3.4
        )
    }

    private var attachedContentTension: CGFloat {
        guard phase == .attached else { return 0 }
        return Self.smoothStep01(min(max(neck * 0.78 + clampedStretch * 0.30, 0), 1))
    }

    // Individual rings only do a mild local deformation while attached. The whole
    // content stack gets one shared perspective/taper so icon, rings and text remain
    // a single mass and follow the large-free-end / small-screen-end liquid body.
    var iconLocalHorizontalStretch: CGFloat {
        guard phase == .attached else { return iconHorizontalStretch }
        return 1 + 0.10 * attachedContentTension
    }

    var iconLocalVerticalScale: CGFloat {
        guard phase == .attached else { return iconVerticalScale }
        return 1 - 0.055 * attachedContentTension
    }

    var contentPerspectiveDegrees: Double {
        Double(17 * attachedContentTension)
    }

    var contentGroupScaleX: CGFloat {
        1 + 0.075 * attachedContentTension
    }

    var contentGroupScaleY: CGFloat {
        1 - 0.18 * attachedContentTension
    }
}

enum FloatingRailGeometry {
    static func bodyRect(in rect: CGRect) -> CGRect {
        let inset = max(1.2, min(rect.width, rect.height) * 0.018)
        return rect.insetBy(dx: inset, dy: inset)
    }

    static func cornerRadius(in rect: CGRect, impact: Double, kinetic: Double) -> CGFloat {
        let body = bodyRect(in: rect)
        let impactAmount = min(max(CGFloat(impact), 0), 1)
        let kineticAmount = min(max(CGFloat(kinetic), 0), 1)
        return max(
            min(
                body.width * (0.31 + 0.035 * kineticAmount),
                body.height * (0.16 + 0.015 * impactAmount)
            ),
            7
        )
    }

    static func undersideY(in rect: CGRect, x: CGFloat, impact: Double, kinetic: Double) -> CGFloat {
        let body = bodyRect(in: rect)
        let radius = min(cornerRadius(in: rect, impact: impact, kinetic: kinetic), body.width * 0.5, body.height * 0.5)
        let clampedX = min(max(x, body.minX), body.maxX)
        if clampedX >= body.minX + radius, clampedX <= body.maxX - radius {
            return body.maxY
        }
        let centerX = clampedX < body.midX ? body.minX + radius : body.maxX - radius
        let dx = clampedX - centerX
        let arcY = sqrt(max(radius * radius - dx * dx, 0))
        return body.maxY - radius + arcY
    }

    static func undersideOffsetFromCenter(
        in rect: CGRect,
        xOffset: CGFloat,
        impact: Double,
        kinetic: Double
    ) -> CGFloat {
        undersideY(
            in: rect,
            x: rect.midX + xOffset,
            impact: impact,
            kinetic: kinetic
        ) - rect.midY
    }

    static func bodyScaleX(impact: Double) -> CGFloat {
        1 + min(max(CGFloat(impact), 0), 1) * 0.055
    }

    static func bodyScaleY(impact: Double) -> CGFloat {
        1 - min(max(CGFloat(impact), 0), 1) * 0.030
    }

    static func visualUndersideOffsetFromCenter(
        in rect: CGRect,
        xOffset: CGFloat,
        impact: Double,
        kinetic: Double,
        breakPulse: CGFloat
    ) -> CGFloat {
        let innerScaleX = bodyScaleX(impact: impact)
        let innerScaleY = bodyScaleY(impact: impact)
        let ruptureScaleX = RailBreakVisualTransform.scaleX(for: breakPulse)
        let ruptureScaleY = RailBreakVisualTransform.scaleY(for: breakPulse)
        let visualScaleX = max(innerScaleX * ruptureScaleX, 0.01)
        let localXOffset = xOffset / visualScaleX
        let localSurface = undersideOffsetFromCenter(
            in: rect,
            xOffset: localXOffset,
            impact: impact,
            kinetic: kinetic
        )
        return localSurface * innerScaleY * ruptureScaleY
            + RailBreakVisualTransform.yOffset(for: breakPulse)
    }
}

enum FloatingSurfaceTensionGeometry {
    static let bodyOverlap: CGFloat = 1.8

    static func intensity(stretch: CGFloat, kinetic: CGFloat, breakPulse: CGFloat) -> CGFloat {
        let stretchAmount = min(max(stretch, 0), 1)
        let kineticAmount = min(max(kinetic, 0), 1)
        let pulseAmount = max(min(max(breakPulse, -1), 1), 0)
        return min(max(0.44 + 0.22 * stretchAmount + 0.24 * kineticAmount + 0.16 * pulseAmount, 0.42), 1)
    }

    static func sagOffset(
        xOffset: CGFloat,
        halfWidth: CGFloat,
        intensity: CGFloat,
        seed: UInt64
    ) -> CGFloat {
        let safeHalfWidth = max(halfWidth, 1)
        let normalizedX = xOffset / safeHalfWidth
        guard abs(normalizedX) <= 1 else { return 0 }

        let amount = min(max(intensity, 0), 1)
        let edgeEnvelope = CGFloat(pow(Double(max(1 - abs(normalizedX), 0)), 0.64))
        let film = (0.72 + 0.88 * amount) * edgeEnvelope
        let jitter = CGFloat(RailDragDropletEmitter.unit(seed, salt: 41) - 0.5) * 0.12
        let centers: [CGFloat] = [-0.61 + jitter * 0.50, -0.19 - jitter * 0.35, 0.17 + jitter, 0.58 - jitter * 0.42]
        let widths: [CGFloat] = [0.19, 0.23, 0.30, 0.21]
        let baseAmplitudes: [CGFloat] = [3.8, 5.1, 8.4, 4.6]
        let amplitudeScale = 0.60 + 0.40 * amount
        var lobeSag: CGFloat = 0

        for index in centers.indices {
            let width = max(widths[index], 0.05)
            let distance = abs((normalizedX - centers[index]) / width)
            guard distance < 1 else { continue }
            let t = 1 - distance * distance
            let seedScale = 0.88 + 0.22 * CGFloat(RailDragDropletEmitter.unit(seed, salt: UInt64(50 + index)))
            lobeSag = max(lobeSag, baseAmplitudes[index] * amplitudeScale * seedScale * t * t)
        }
        return film + lobeSag
    }

    static func maxSag(halfWidth: CGFloat, intensity: CGFloat, seed: UInt64) -> CGFloat {
        let safeHalfWidth = max(halfWidth, 1)
        return (0...48).reduce(CGFloat.zero) { current, index in
            let progress = CGFloat(index) / 48
            let xOffset = -safeHalfWidth + safeHalfWidth * 2 * progress
            return max(
                current,
                sagOffset(xOffset: xOffset, halfWidth: safeHalfWidth, intensity: intensity, seed: seed)
            )
        }
    }
}

private struct FloatingRailShape: Shape {
    var impact: Double
    var kinetic: Double

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(impact, kinetic) }
        set {
            impact = newValue.first
            kinetic = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let body = FloatingRailGeometry.bodyRect(in: rect)
        let radius = FloatingRailGeometry.cornerRadius(in: rect, impact: impact, kinetic: kinetic)
        return RoundedRectangle(cornerRadius: radius, style: .continuous).path(in: body)
    }
}

struct EdgeRailShape: Shape {
    let edge: DockEdge
    let screenEdgeAmount: Double
    let screenEdgeCurvature: Double
    let innerEdgeAmount: Double
    let cornerRadius: Double
    let scallopDepth: Double
    let scallopRadius: Double
    let smoothing: Double
    var stretchAmount: Double
    var neckAmount: Double
    var kineticAmount: Double = 0
    let screenEdgeOutset: CGFloat
    let renderInset: CGFloat

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(stretchAmount, neckAmount) }
        set {
            stretchAmount = newValue.first
            neckAmount = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        EdgeRailGeometry.path(
            in: rect,
            edge: edge,
            screenEdgeAmount: screenEdgeAmount,
            screenEdgeCurvature: screenEdgeCurvature,
            innerEdgeAmount: innerEdgeAmount,
            cornerRadius: cornerRadius,
            scallopDepth: scallopDepth,
            scallopRadius: scallopRadius,
            smoothing: smoothing,
            stretchAmount: stretchAmount,
            neckAmount: neckAmount,
            kineticAmount: kineticAmount,
            screenEdgeOutset: screenEdgeOutset,
            renderInset: renderInset
        )
    }

    func visibleBorderPath(in rect: CGRect) -> Path {
        EdgeRailGeometry.path(
            in: rect,
            edge: edge,
            screenEdgeAmount: screenEdgeAmount,
            screenEdgeCurvature: screenEdgeCurvature,
            innerEdgeAmount: innerEdgeAmount,
            cornerRadius: cornerRadius,
            scallopDepth: scallopDepth,
            scallopRadius: scallopRadius,
            smoothing: smoothing,
            stretchAmount: stretchAmount,
            neckAmount: neckAmount,
            kineticAmount: kineticAmount,
            screenEdgeOutset: screenEdgeOutset,
            renderInset: renderInset,
            omitAttachedDisplayEdgeBorder: true
        )
    }
}

struct EdgeRailVisibleBorderShape: Shape {
    var base: EdgeRailShape

    var animatableData: AnimatablePair<Double, Double> {
        get { base.animatableData }
        set { base.animatableData = newValue }
    }

    func path(in rect: CGRect) -> Path {
        base.visibleBorderPath(in: rect)
    }
}

private enum EdgeRailGeometry {
    static func path(
        in rect: CGRect,
        edge: DockEdge,
        screenEdgeAmount: Double,
        screenEdgeCurvature: Double,
        innerEdgeAmount: Double,
        cornerRadius: Double,
        scallopDepth: Double,
        scallopRadius: Double,
        smoothing: Double,
        stretchAmount: Double,
        neckAmount: Double,
        kineticAmount: Double,
        screenEdgeOutset: CGFloat,
        renderInset: CGFloat,
        omitAttachedDisplayEdgeBorder: Bool = false
    ) -> Path {
        let stretch = min(max(CGFloat(stretchAmount), 0), 1.2)
        let neck = min(max(CGFloat(neckAmount), 0), 1)
        let kinetic = min(max(CGFloat(kineticAmount), 0), 1)
        let semantic = EdgeRailSemanticProfile.resolve(
            screenEdgeAmount: screenEdgeAmount,
            screenEdgeCurvature: screenEdgeCurvature
        )
        let valley = semantic.valley
        let outwardSpread = semantic.outwardSpread
        let inwardBubble = semantic.inwardBubble
        let visualOutset = max(screenEdgeOutset, 0)
        let safeRenderInset = max(renderInset, 0)
        let nominalMinY = rect.minY + visualOutset + safeRenderInset
        let nominalMaxY = rect.maxY - visualOutset - safeRenderInset
        let nominalHeight = max(nominalMaxY - nominalMinY, 1)
        let centerY = (nominalMinY + nominalMaxY) * 0.5
        let baseRadius = min(CGFloat(cornerRadius), rect.width * 0.42, nominalHeight * 0.18)
        let radius = max(2, baseRadius * (1 - 0.28 * neck))
        let baseDepth = min(CGFloat(scallopDepth), nominalHeight * 0.30)
        let depth = min(baseDepth * (1 + 0.20 * stretch + 0.26 * neck), nominalHeight * 0.36)
        // F17.26: the old Smoothness control barely moved one throat handle and the
        // legacy Curve radius never participated in canonical geometry at all. Keep the
        // persisted fields for compatibility, but make the live contour deterministic.
        let canonicalBlend: CGFloat = 0.72
        let blend = min(canonicalBlend + 0.20 * stretch + 0.14 * neck, 1)
        let screenRaw = shapeInset(screenEdgeAmount, depth: depth)
        let innerRaw = shapeInset(innerEdgeAmount, depth: depth)
        let baseline = min(screenRaw, innerRaw)
        let screenInset = screenRaw - baseline
        // Preserve visible volume in the leading droplet. The bridge gets thin while the
        // free head remains round, closer to a liquid surface under tension than rubber.
        let freeEndCompression = min(
            nominalHeight * (0.014 * stretch + 0.018 * neck + 0.008 * kinetic),
            nominalHeight * 0.055
        )
        let innerInset = min(innerRaw - baseline + freeEndCompression, nominalHeight * 0.16)
        let pinchCurve = CGFloat(pow(Double(neck), 1.18))
        // Keep a visible liquid lobe attached to the Mac edge. The strong pinch belongs in
        // the throat between the edge and the body, not at the screen endpoint itself.
        let screenLobePinch = min(
            nominalHeight * (0.018 * stretch + 0.070 * pinchCurve + 0.080 * inwardBubble),
            nominalHeight * 0.160
        )
        let screenTopY = min(nominalMinY - visualOutset + screenInset + screenLobePinch, centerY - 2)
        let screenBottomY = max(nominalMaxY + visualOutset - screenInset - screenLobePinch, centerY + 2)
        let innerTopY = nominalMinY + innerInset
        let innerBottomY = nominalMaxY - innerInset
        let span = max(rect.width - radius, 1)

        // The attached display edge is valley-only. Positive legacy curvature is neutralized,
        // while negative screen-edge shape becomes a short speech-bubble-like attachment.
        // Corner radius remains an interior-facing body control rather than rounding the Mac edge.
        let concavity = min(
            max(
                0.54 + 0.16 * outwardSpread + 0.34 * inwardBubble + 0.14 * neck + 0.05 * stretch
                    + 0.34 * valley,
                0.18
            ),
            0.98
        )
        let stretchNormalized = min(max(stretch / 1.05, 0), 1)
        let stretchRoundness = stretchNormalized * stretchNormalized * (3 - 2 * stretchNormalized)
        let tensionRaw = min(max(neck * 0.68 + stretchRoundness * 0.54 + kinetic * 0.10, 0), 1)
        let surfaceTension = tensionRaw * tensionRaw * (3 - 2 * tensionRaw)
        let liquidRoundness = min(max(neck * 0.58 + stretchRoundness * 0.72 + kinetic * 0.12, 0), 1)
        let neckRun = min(
            max(
                span * (
                    0.18 +
                    0.065 * outwardSpread -
                    0.045 * inwardBubble +
                    0.160 * neck +
                    0.120 * stretchRoundness +
                    0.035 * kinetic +
                    0.075 * valley
                ),
                radius * (1.10 - 0.35 * inwardBubble)
            ),
            span * 0.56
        )
        let bodyArcSpan = max(span - neckRun, 1)
        // Shift apparent mass toward the free head as tension rises. The leading end
        // becomes a bulb while the bridge narrows, which reads much more like a droplet.
        let bodyBellyProgress = 0.58 + 0.13 * surfaceTension
        // Carry the valley intent into the body without introducing an attached-edge mountain.
        let bodyBellyVerticalFactor = max(
            0.040,
            0.20 - 0.135 * surfaceTension - 0.025 * kinetic + 0.025 * valley
        )
        let bodyBellyTangentX = min(
            bodyArcSpan * (0.15 + 0.14 * surfaceTension),
            bodyArcSpan * 0.31
        )
        let throatProgress = min(
            max(0.72 + 0.18 * concavity + 0.14 * valley + 0.05 * inwardBubble, 0.46),
            0.96
        )
        // As the bridge stretches, the waist tangent becomes increasingly horizontal.
        // This makes the two halves read as rounded droplets joined by a thin liquid neck
        // instead of two long diagonal lines meeting at a pinch point.
        let throatTangentX = min(
            max(
                span * (0.072 + 0.025 * blend + 0.070 * surfaceTension),
                bodyArcSpan * (0.18 + 0.15 * surfaceTension)
            ),
            min(
                neckRun * (0.50 + 0.32 * surfaceTension),
                bodyArcSpan * 0.48
            )
        )
        // Keep the joined cubics on the same horizontal tangent at the throat.
        // This removes the tiny visible shoulder/kink that showed up in the outlined rail.
        let throatTangentY: CGFloat = 0
        // Keep the droplet head rounded even as the bridge gets thinner. The cap tangent
        // stays bounded by its local radius, while the long body arc gets its own belly point.
        let bodyCornerTangent = min(
            max(radius * (0.62 + 0.20 * surfaceTension + 0.06 * valley), 2),
            radius * 0.94
        )
        let freeCapControlY = min(
            max(
                (innerBottomY - innerTopY) * (
                    0.29 + 0.11 * surfaceTension + 0.035 * kinetic + 0.025 * valley
                ),
                radius * 1.25
            ),
            nominalHeight * 0.38
        )
        let topScreenHandleY = min(
            max(
                abs(innerTopY - screenTopY) * (0.42 + 0.16 * liquidRoundness + 0.18 * valley),
                nominalHeight * (0.025 + 0.020 * concavity + 0.045 * liquidRoundness + 0.025 * valley)
            ),
            nominalHeight * (0.13 + 0.055 * liquidRoundness)
        )
        let bottomScreenHandleY = min(
            max(
                abs(screenBottomY - innerBottomY) * (0.42 + 0.16 * liquidRoundness + 0.18 * valley),
                nominalHeight * (0.025 + 0.020 * concavity + 0.045 * liquidRoundness + 0.025 * valley)
            ),
            nominalHeight * (0.13 + 0.055 * liquidRoundness)
        )

        var path = Path()
        switch edge {
        case .right:
            let screenX = rect.maxX
            let innerX = rect.minX
            let topScreen = CGPoint(x: screenX, y: screenTopY)
            let topInner = CGPoint(x: innerX + radius, y: innerTopY)
            let bottomInner = CGPoint(x: innerX + radius, y: innerBottomY)
            let bottomScreen = CGPoint(x: screenX, y: screenBottomY)

            let throatPinch = min(
                nominalHeight * (
                    0.030 * stretch +
                    0.365 * pinchCurve +
                    0.045 * surfaceTension +
                    0.014 * kinetic
                ),
                nominalHeight * 0.405
            )
            let minimumHalfGap = max(0.90, 1.70 - 0.80 * surfaceTension)
            let topThroat = CGPoint(
                x: screenX - neckRun,
                y: min(topScreen.y + (topInner.y - topScreen.y) * throatProgress + throatPinch, centerY - minimumHalfGap)
            )
            let bottomThroat = CGPoint(
                x: screenX - neckRun,
                y: max(bottomScreen.y + (bottomInner.y - bottomScreen.y) * throatProgress - throatPinch, centerY + minimumHalfGap)
            )

            path.move(to: topScreen)
            path.addCurve(
                to: topThroat,
                control1: CGPoint(x: screenX, y: topScreen.y + topScreenHandleY),
                control2: CGPoint(x: topThroat.x + throatTangentX, y: topThroat.y - throatTangentY)
            )
            let topBelly = CGPoint(
                x: topThroat.x - bodyArcSpan * bodyBellyProgress,
                y: topInner.y + (topThroat.y - topInner.y) * bodyBellyVerticalFactor
            )
            let bottomBelly = CGPoint(
                x: bottomThroat.x - bodyArcSpan * bodyBellyProgress,
                y: bottomInner.y - (bottomInner.y - bottomThroat.y) * bodyBellyVerticalFactor
            )
            path.addCurve(
                to: topBelly,
                control1: CGPoint(x: topThroat.x - throatTangentX, y: topThroat.y + throatTangentY),
                control2: CGPoint(x: topBelly.x + bodyBellyTangentX, y: topBelly.y)
            )
            path.addCurve(
                to: topInner,
                control1: CGPoint(x: topBelly.x - bodyBellyTangentX, y: topBelly.y),
                control2: CGPoint(x: topInner.x + bodyCornerTangent, y: topInner.y)
            )
            let freeTip = CGPoint(x: innerX, y: centerY)
            path.addCurve(
                to: freeTip,
                control1: CGPoint(x: topInner.x - bodyCornerTangent, y: topInner.y),
                control2: CGPoint(x: freeTip.x, y: centerY - freeCapControlY)
            )
            path.addCurve(
                to: bottomInner,
                control1: CGPoint(x: freeTip.x, y: centerY + freeCapControlY),
                control2: CGPoint(x: bottomInner.x - bodyCornerTangent, y: bottomInner.y)
            )
            path.addCurve(
                to: bottomBelly,
                control1: CGPoint(x: bottomInner.x + bodyCornerTangent, y: bottomInner.y),
                control2: CGPoint(x: bottomBelly.x - bodyBellyTangentX, y: bottomBelly.y)
            )
            path.addCurve(
                to: bottomThroat,
                control1: CGPoint(x: bottomBelly.x + bodyBellyTangentX, y: bottomBelly.y),
                control2: CGPoint(x: bottomThroat.x - throatTangentX, y: bottomThroat.y - throatTangentY)
            )
            path.addCurve(
                to: bottomScreen,
                control1: CGPoint(x: bottomThroat.x + throatTangentX, y: bottomThroat.y + throatTangentY),
                control2: CGPoint(x: screenX, y: bottomScreen.y - bottomScreenHandleY)
            )
            if !omitAttachedDisplayEdgeBorder {
                path.addLine(to: topScreen)
            }

        case .left:
            let screenX = rect.minX
            let innerX = rect.maxX
            let topScreen = CGPoint(x: screenX, y: screenTopY)
            let topInner = CGPoint(x: innerX - radius, y: innerTopY)
            let bottomInner = CGPoint(x: innerX - radius, y: innerBottomY)
            let bottomScreen = CGPoint(x: screenX, y: screenBottomY)

            let throatPinch = min(
                nominalHeight * (
                    0.030 * stretch +
                    0.365 * pinchCurve +
                    0.045 * surfaceTension +
                    0.014 * kinetic
                ),
                nominalHeight * 0.405
            )
            let minimumHalfGap = max(0.90, 1.70 - 0.80 * surfaceTension)
            let topThroat = CGPoint(
                x: screenX + neckRun,
                y: min(topScreen.y + (topInner.y - topScreen.y) * throatProgress + throatPinch, centerY - minimumHalfGap)
            )
            let bottomThroat = CGPoint(
                x: screenX + neckRun,
                y: max(bottomScreen.y + (bottomInner.y - bottomScreen.y) * throatProgress - throatPinch, centerY + minimumHalfGap)
            )

            path.move(to: topScreen)
            path.addCurve(
                to: topThroat,
                control1: CGPoint(x: screenX, y: topScreen.y + topScreenHandleY),
                control2: CGPoint(x: topThroat.x - throatTangentX, y: topThroat.y - throatTangentY)
            )
            let topBelly = CGPoint(
                x: topThroat.x + bodyArcSpan * bodyBellyProgress,
                y: topInner.y + (topThroat.y - topInner.y) * bodyBellyVerticalFactor
            )
            let bottomBelly = CGPoint(
                x: bottomThroat.x + bodyArcSpan * bodyBellyProgress,
                y: bottomInner.y - (bottomInner.y - bottomThroat.y) * bodyBellyVerticalFactor
            )
            path.addCurve(
                to: topBelly,
                control1: CGPoint(x: topThroat.x + throatTangentX, y: topThroat.y + throatTangentY),
                control2: CGPoint(x: topBelly.x - bodyBellyTangentX, y: topBelly.y)
            )
            path.addCurve(
                to: topInner,
                control1: CGPoint(x: topBelly.x + bodyBellyTangentX, y: topBelly.y),
                control2: CGPoint(x: topInner.x - bodyCornerTangent, y: topInner.y)
            )
            let freeTip = CGPoint(x: innerX, y: centerY)
            path.addCurve(
                to: freeTip,
                control1: CGPoint(x: topInner.x + bodyCornerTangent, y: topInner.y),
                control2: CGPoint(x: freeTip.x, y: centerY - freeCapControlY)
            )
            path.addCurve(
                to: bottomInner,
                control1: CGPoint(x: freeTip.x, y: centerY + freeCapControlY),
                control2: CGPoint(x: bottomInner.x + bodyCornerTangent, y: bottomInner.y)
            )
            path.addCurve(
                to: bottomBelly,
                control1: CGPoint(x: bottomInner.x - bodyCornerTangent, y: bottomInner.y),
                control2: CGPoint(x: bottomBelly.x + bodyBellyTangentX, y: bottomBelly.y)
            )
            path.addCurve(
                to: bottomThroat,
                control1: CGPoint(x: bottomBelly.x - bodyBellyTangentX, y: bottomBelly.y),
                control2: CGPoint(x: bottomThroat.x + throatTangentX, y: bottomThroat.y - throatTangentY)
            )
            path.addCurve(
                to: bottomScreen,
                control1: CGPoint(x: bottomThroat.x - throatTangentX, y: bottomThroat.y + throatTangentY),
                control2: CGPoint(x: screenX, y: bottomScreen.y - bottomScreenHandleY)
            )
            if !omitAttachedDisplayEdgeBorder {
                path.addLine(to: topScreen)
            }
        }

        if !omitAttachedDisplayEdgeBorder {
            path.closeSubpath()
        }
        return path
    }

    private static func shapeInset(_ amount: Double, depth: CGFloat) -> CGFloat {
        let normalized = min(max(CGFloat(amount), -1), 1)
        return depth * (0.5 - normalized * 0.5)
    }
}

private struct ProviderUsageTile: View {
    let target: RailDisplayTarget
    let summary: ProviderUsageSummary
    let displayName: String
    let displayPercent: Double?
    let outerRingPercent: Double?
    let innerRingPercent: Double?
    let remainingResetDate: Date?
    let presentationMode: UsagePresentationMode
    let multiplier: Int?
    let accentHex: String?
    let isHovered: Bool
    let showPercent: Bool
    let showRing: Bool
    let showOuterRing: Bool
    let showInnerRing: Bool
    let showRemainingTime: Bool
    let dayDigits: RailDigitWidth
    let hourDigits: RailDigitWidth
    let minuteDigits: RailDigitWidth
    let showHours: Bool
    let showMinutes: Bool
    let autoHideZeroDays: Bool
    let autoHideZeroHours: Bool
    let showMultiplier: Bool
    let backplateEnabled: Bool
    let autoContrast: Bool
    let theme: UsageDockTheme
    let iconSize: CGFloat
    let percentFontSize: CGFloat
    let accountLabelFontSize: CGFloat
    let remainingTimeFontSize: CGFloat
    let showTitle: Bool
    let titleWidth: CGFloat
    let timeWidth: CGFloat
    let scale: CGFloat

    private var outerProgress: Double { min(max(outerRingPercent ?? 0, 0), 1) }
    private var innerProgress: Double { min(max(innerRingPercent ?? 0, 0), 1) }
    private var percentText: String { displayPercent.map { "\(Int(($0 * 100).rounded()))%" } ?? "--" }
    private var isAccount: Bool { if case .account = target { return true }; return false }
    private var effectiveRing: Bool { showRing && (showOuterRing || showInnerRing) }
    private var iconFrameSize: CGFloat { max(showRing ? 50 : 34, iconSize + (showRing ? 20 : 10)) * scale }

    var body: some View {
        VStack(spacing: 3 * scale) {
            ZStack {
                if isHovered {
                    Ellipse()
                        .fill(ProviderBrand.glow(for: summary.provider, customHex: accentHex, theme: theme).opacity(0.16))
                        .frame(width: iconFrameSize + 8 * scale, height: iconFrameSize + 8 * scale)
                        .blur(radius: 5 * scale)
                }

                if effectiveRing {
                    if showOuterRing {
                        Ellipse()
                            .stroke(ProviderBrand.ringTrack(theme: theme), lineWidth: max(3.2 * scale, 1.3))
                        Ellipse()
                            .trim(from: 0, to: outerProgress)
                            .stroke(
                                ProviderBrand.gradient(for: summary.provider, customHex: accentHex, theme: theme),
                                style: StrokeStyle(lineWidth: max(3.5 * scale, 1.5), lineCap: .round)
                            )
                            .rotationEffect(.degrees(-90))
                    }

                    if showInnerRing {
                        Ellipse()
                            .stroke(ProviderBrand.ringTrack(theme: theme).opacity(0.72), lineWidth: max(2.5 * scale, 1.1))
                            .padding(6 * scale)
                        Ellipse()
                            .trim(from: 0, to: innerProgress)
                            .stroke(
                                ProviderBrand.gradient(for: summary.provider, customHex: accentHex, theme: theme).opacity(0.72),
                                style: StrokeStyle(lineWidth: max(2.8 * scale, 1.2), lineCap: .round)
                            )
                            .rotationEffect(.degrees(-90))
                            .padding(6 * scale)
                    }

                    Ellipse()
                        .fill(ProviderBrand.surface(theme: theme, opacity: isHovered ? 1.0 : 0.58))
                        .padding((showInnerRing ? 12 : 7) * scale)
                } else if isHovered || backplateEnabled {
                    Ellipse().fill(ProviderBrand.surface(theme: theme, opacity: isHovered ? 1.0 : 0.72))
                }

                ProviderIcon(
                    provider: summary.provider,
                    size: iconSize * scale,
                    accentHex: accentHex,
                    theme: theme
                )
                .scaleEffect(isHovered ? 1.06 : 1)
            }
            // Keep each tile internally rigid. F17.21 applies all liquid deformation to
            // the outer provider cluster so icons do not independently distort in the neck.
            .frame(width: iconFrameSize, height: iconFrameSize)
            .overlay(alignment: .bottomTrailing) {
                if showMultiplier, let multiplier {
                    Text("×\(multiplier)")
                        .font(.system(size: 8.8 * scale, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(ProviderBrand.primaryText(theme: theme))
                        .padding(.horizontal, 4 * scale)
                        .padding(.vertical, 2 * scale)
                        .background(ProviderBrand.surface(theme: theme, opacity: 1), in: Capsule())
                        .overlay { Capsule().stroke(ProviderBrand.border(theme: theme), lineWidth: 0.7) }
                        .offset(x: 4 * scale, y: 3 * scale)
                }
            }
            .frame(width: iconFrameSize, height: iconFrameSize)

            if showPercent {
                Text(percentText)
                    .font(.system(size: percentFontSize * scale, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(displayPercent == nil ? ProviderBrand.tertiaryText(theme: theme) : ProviderBrand.primaryText(theme: theme))
                    .shadow(color: ProviderBrand.contrastShadow(theme: theme, enabled: autoContrast), radius: autoContrast ? 1.3 : 0)
            }

            if showRemainingTime {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    Text(remainingTimeText(now: context.date) ?? "--")
                        .font(.system(size: remainingTimeFontSize * scale, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(remainingResetDate == nil ? ProviderBrand.tertiaryText(theme: theme) : ProviderBrand.secondaryText(theme: theme))
                        .lineLimit(1)
                        .frame(width: timeWidth * scale)
                        .shadow(color: ProviderBrand.contrastShadow(theme: theme, enabled: autoContrast), radius: autoContrast ? 1.0 : 0)
                }
            }

            if isAccount && showTitle {
                Text(displayName)
                    .font(.system(size: accountLabelFontSize * scale, weight: .medium, design: .rounded))
                    .foregroundStyle(ProviderBrand.secondaryText(theme: theme))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: titleWidth * scale)
                    .shadow(color: ProviderBrand.contrastShadow(theme: theme, enabled: autoContrast), radius: autoContrast ? 1.1 : 0)
            }
        }
        .padding(backplateEnabled && !showRing ? 3 * scale : 0)
        .background {
            if backplateEnabled && theme == .transparentFloating {
                RoundedRectangle(cornerRadius: 10 * scale, style: .continuous)
                    .fill(ProviderBrand.surface(theme: theme, opacity: 0.76))
            }
        }
        .scaleEffect(isHovered ? 1.025 : 1)
        .animation(.easeOut(duration: 0.13), value: isHovered)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isAccount ? "\(summary.provider.displayName), \(displayName)" : summary.provider.displayName)
        .accessibilityValue("\(presentationMode.label) \(percentText)")
    }

    private func remainingTimeText(now: Date) -> String? {
        guard let remainingResetDate else { return nil }
        let totalMinutes = max(Int(remainingResetDate.timeIntervalSince(now) / 60), 0)
        let days = totalMinutes / 1_440
        let hours = (totalMinutes % 1_440) / 60
        let minutes = totalMinutes % 60
        var parts: [String] = []

        if !(autoHideZeroDays && days == 0) {
            parts.append("\(timerValue(days, width: dayDigits))d")
        }
        if showHours && !(autoHideZeroHours && hours == 0) {
            parts.append("\(timerValue(hours, width: hourDigits))h")
        }
        if showMinutes || (days == 0 && hours == 0) {
            parts.append("\(timerValue(minutes, width: minuteDigits))m")
        }
        if parts.isEmpty {
            parts.append("\(timerValue(minutes, width: minuteDigits))m")
        }
        return parts.joined(separator: " ")
    }

    private func timerValue(_ value: Int, width: RailDigitWidth) -> String {
        width == .two ? String(format: "%02d", value) : "\(value)"
    }
}
