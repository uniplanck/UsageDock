import AppKit
import Foundation
import SwiftUI

enum RailMetrics {
    static func width(
        scale: Double,
        showRing: Bool,
        showMultiplier: Bool,
        iconEdgeInset: Double = 0,
        iconSize: Double = 24,
        titleWidth: Double = 66,
        timeWidth: Double = 72
    ) -> CGFloat {
        let iconBlock = max(showRing ? 70 : 48, iconSize + (showRing ? 34 : 20))
        let textBlock = max(showMultiplier ? 64 : 54, titleWidth + 16, timeWidth + 16)
        let base = max(iconBlock, textBlock)
        let safeInset = effectiveIconEdgeInset(
            requested: iconEdgeInset,
            showRing: showRing,
            iconSize: iconSize
        )
        return max((CGFloat(base) + safeInset) * CGFloat(scale), 24)
    }

    static func minimumSafeIconEdgeInset(showRing: Bool, iconSize: Double) -> CGFloat {
        // Keep a real safety gutter, but allow the icon cluster to sit visibly closer to
        // the screen edge than F17.7's conservative 10pt ring minimum.
        let base: CGFloat = showRing ? 6 : 5
        let largeIconBonus = max(CGFloat(iconSize - 24) * 0.06, 0)
        return min(base + largeIconBonus, 10)
    }

    static func effectiveIconEdgeInset(
        requested: Double,
        showRing: Bool,
        iconSize: Double
    ) -> CGFloat {
        max(CGFloat(requested), minimumSafeIconEdgeInset(showRing: showRing, iconSize: iconSize))
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

    static func verticalPadding(scale: Double, showRing: Bool) -> CGFloat {
        (showRing ? 10 : 6) * CGFloat(scale)
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

    static func spacing(scale: Double, itemSpacing: Double) -> CGFloat {
        CGFloat(itemSpacing) * CGFloat(scale)
    }

    static func contentHeight(
        entryCount: Int,
        scale: Double,
        itemSpacing: Double,
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
        return rows + gaps + verticalPadding(scale: scale, showRing: showRing) * 2
    }

    static func windowSize(
        entryCount: Int,
        scale: Double,
        itemSpacing: Double,
        showRing: Bool,
        showPercent: Bool,
        showMultiplier: Bool,
        showRemainingTime: Bool = false,
        remainingTimeFontSize: Double = 8.5,
        iconEdgeInset: Double = 0,
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
                iconEdgeInset: iconEdgeInset,
                iconSize: iconSize,
                titleWidth: titleWidth,
                timeWidth: timeWidth
            ),
            height: contentHeight(
                entryCount: entryCount,
                scale: scale,
                itemSpacing: itemSpacing,
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
    let floatingCenterX: CGFloat
    let floatingCenterY: CGFloat
    let residue: CGFloat
    let wetting: CGFloat
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

    private var targets: [RailDisplayTarget] { usageStore.railTargets() }
    private var scale: CGFloat { CGFloat(usageStore.railScale) }
    private var effectiveEdge: DockEdge { overlaySnapshot?.edge ?? placement.edge }
    private var effectiveCanvasExtraWidth: CGFloat { overlaySnapshot?.canvasExtraWidth ?? 0 }
    private var dragDirection: CGFloat { effectiveEdge == .left ? 1 : -1 }
    private var baseRailWidth: CGFloat {
        RailMetrics.width(
            scale: usageStore.railScale,
            showRing: usageStore.railShowRing,
            showMultiplier: usageStore.railShowMultiplier,
            iconEdgeInset: usageStore.railIconEdgeInset,
            iconSize: usageStore.railIconSize,
            titleWidth: usageStore.railTitleWidth,
            timeWidth: usageStore.railTimeWidth
        )
    }
    private var effectiveIconEdgeInset: CGFloat {
        RailMetrics.effectiveIconEdgeInset(
            requested: usageStore.railIconEdgeInset,
            showRing: usageStore.railShowRing,
            iconSize: usageStore.railIconSize
        )
    }
    private var baseRailHeight: CGFloat {
        RailMetrics.contentHeight(
            entryCount: targets.count,
            scale: usageStore.railScale,
            itemSpacing: usageStore.railItemSpacing,
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
            wetting: overlaySnapshot.wetting
        )
    }

    private var shouldShowRailVisual: Bool {
        overlaySnapshot != nil || !inputVisualSuppressed
    }

    var body: some View {
        ZStack {
            railBackground
                .contentShape(Rectangle())
                .gesture(backgroundDragGesture)

            VStack(spacing: RailMetrics.spacing(scale: usageStore.railScale, itemSpacing: usageStore.railItemSpacing)) {
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
                        scale: scale,
                        mochiHorizontalStretch: dragPresentation.iconLocalHorizontalStretch,
                        mochiVerticalScale: dragPresentation.iconLocalVerticalScale,
                        mochiTextTracking: dragPresentation.textTracking
                    )
                    .offset(
                        x: dragPresentation.phase == .attached
                            ? (effectiveEdge == .right ? -1 : 1) * effectiveIconEdgeInset * scale
                            : dragPresentation.phase == .wetting
                                ? (effectiveEdge == .right ? -1 : 1) * effectiveIconEdgeInset * scale * dragPresentation.wettingSpread
                                : 0
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
            .padding(.vertical, RailMetrics.verticalPadding(scale: usageStore.railScale, showRing: usageStore.railShowRing))
            .frame(width: baseRailWidth)
            .scaleEffect(
                x: dragPresentation.wettingContentScaleX * dragPresentation.contentGroupScaleX,
                y: dragPresentation.wettingContentScaleY * dragPresentation.contentGroupScaleY,
                anchor: .center
            )
            .rotation3DEffect(
                .degrees((effectiveEdge == .right ? 1.0 : -1.0) * dragPresentation.contentPerspectiveDegrees),
                axis: (x: 0, y: 1, z: 0),
                anchor: .center,
                perspective: 0.50
            )
            .frame(
                maxWidth: .infinity,
                alignment: dragPresentation.phase == .attached
                    ? (effectiveEdge == .left ? .leading : .trailing)
                    : .center
            )
            .offset(
                x: dragPresentation.phase == .attached
                    ? dragDirection * dragPresentation.contentTravel
                    : 0
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .mask { railContentMask }
        }
        .frame(
            width: baseRailWidth + effectiveCanvasExtraWidth,
            height: baseRailHeight + effectiveVisualOutset * 2
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

    @ViewBuilder
    private var railContentMask: some View {
        if dragPresentation.phase == .attached {
            EdgeRailShape(
                edge: effectiveEdge,
                screenEdgeAmount: usageStore.railScreenEdgeShape,
                innerEdgeAmount: usageStore.railInnerShape,
                cornerRadius: usageStore.railCornerRadius * usageStore.railScale,
                scallopDepth: usageStore.railScallopDepth * usageStore.railScale,
                scallopRadius: usageStore.railScallopRadius * usageStore.railScale,
                smoothing: usageStore.railScallopSmoothing,
                stretchAmount: Double(dragPresentation.shapeStretch),
                neckAmount: Double(dragPresentation.neck),
                screenEdgeOutset: screenEdgeVisualOutset
            )
            .fill(Color.white)
        } else {
            Rectangle().fill(Color.white)
        }
    }

    @ViewBuilder
    private var railBackground: some View {
        if dragPresentation.phase == .attached {
            let shape = EdgeRailShape(
                edge: effectiveEdge,
                screenEdgeAmount: usageStore.railScreenEdgeShape,
                innerEdgeAmount: usageStore.railInnerShape,
                cornerRadius: usageStore.railCornerRadius * usageStore.railScale,
                scallopDepth: usageStore.railScallopDepth * usageStore.railScale,
                scallopRadius: usageStore.railScallopRadius * usageStore.railScale,
                smoothing: usageStore.railScallopSmoothing,
                stretchAmount: Double(dragPresentation.shapeStretch),
                neckAmount: Double(dragPresentation.neck),
                screenEdgeOutset: screenEdgeVisualOutset
            )
            let freeBorder = EdgeRailFreeBorderShape(
                edge: effectiveEdge,
                screenEdgeAmount: usageStore.railScreenEdgeShape,
                innerEdgeAmount: usageStore.railInnerShape,
                cornerRadius: usageStore.railCornerRadius * usageStore.railScale,
                scallopDepth: usageStore.railScallopDepth * usageStore.railScale,
                scallopRadius: usageStore.railScallopRadius * usageStore.railScale,
                smoothing: usageStore.railScallopSmoothing,
                stretchAmount: Double(dragPresentation.shapeStretch),
                neckAmount: Double(dragPresentation.neck),
                screenEdgeOutset: screenEdgeVisualOutset
            )

            shape
                .fill(ProviderBrand.railFill(theme: usageStore.theme, opacity: usageStore.railBackgroundOpacity))
                .overlay {
                    if usageStore.theme != .transparentFloating && usageStore.railBackgroundOpacity > 0.02 {
                        shape
                            .fill(
                                LinearGradient(
                                    colors: usageStore.theme == .light
                                        ? [Color.white.opacity(0.36), Color.clear, Color.black.opacity(0.04)]
                                        : [Color.white.opacity(0.055), Color.clear, Color.black.opacity(0.20)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                }
                .overlay { edgeDecoration(freeBorder) }
        } else if dragPresentation.phase == .wetting {
            let spread = dragPresentation.wettingSpread
            let contact = dragPresentation.wettingContact
            let finalShape = EdgeRailShape(
                edge: effectiveEdge,
                screenEdgeAmount: usageStore.railScreenEdgeShape,
                innerEdgeAmount: usageStore.railInnerShape,
                cornerRadius: usageStore.railCornerRadius * usageStore.railScale,
                scallopDepth: usageStore.railScallopDepth * usageStore.railScale,
                scallopRadius: usageStore.railScallopRadius * usageStore.railScale,
                smoothing: usageStore.railScallopSmoothing,
                stretchAmount: 0,
                neckAmount: 0,
                screenEdgeOutset: screenEdgeVisualOutset
            )
            let finalBorder = EdgeRailFreeBorderShape(
                edge: effectiveEdge,
                screenEdgeAmount: usageStore.railScreenEdgeShape,
                innerEdgeAmount: usageStore.railInnerShape,
                cornerRadius: usageStore.railCornerRadius * usageStore.railScale,
                scallopDepth: usageStore.railScallopDepth * usageStore.railScale,
                scallopRadius: usageStore.railScallopRadius * usageStore.railScale,
                smoothing: usageStore.railScallopSmoothing,
                stretchAmount: 0,
                neckAmount: 0,
                screenEdgeOutset: screenEdgeVisualOutset
            )
            let contactDrop = FloatingRailShape(
                impact: Double(dragPresentation.settle),
                kinetic: Double(dragPresentation.kinetic)
            )
            let contactAnchor: UnitPoint = effectiveEdge == .left ? .leading : .trailing

            ZStack {
                contactDrop
                    .fill(ProviderBrand.railFill(theme: usageStore.theme, opacity: usageStore.railBackgroundOpacity))
                    .overlay { edgeDecoration(contactDrop) }
                    .scaleEffect(
                        x: 1 - 0.44 * contact,
                        y: 1 - 0.20 * contact,
                        anchor: contactAnchor
                    )
                    .opacity(Double(1 - spread))

                finalShape
                    .fill(ProviderBrand.railFill(theme: usageStore.theme, opacity: usageStore.railBackgroundOpacity))
                    .overlay {
                        if usageStore.theme != .transparentFloating && usageStore.railBackgroundOpacity > 0.02 {
                            finalShape.fill(
                                LinearGradient(
                                    colors: usageStore.theme == .light
                                        ? [Color.white.opacity(0.36), Color.clear, Color.black.opacity(0.04)]
                                        : [Color.white.opacity(0.065), Color.clear, Color.black.opacity(0.21)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        }
                    }
                    .overlay { edgeDecoration(finalBorder) }
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
            floatingShape
                .fill(ProviderBrand.railFill(theme: usageStore.theme, opacity: usageStore.railBackgroundOpacity))
                .overlay {
                    floatingShape.fill(
                        LinearGradient(
                            colors: usageStore.theme == .light
                                ? [Color.white.opacity(0.42), Color.clear, Color.black.opacity(0.04)]
                                : [Color.white.opacity(0.085), Color.clear, Color.black.opacity(0.24)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                }
                .overlay { edgeDecoration(floatingShape) }
                .scaleEffect(
                    x: 1 + dragPresentation.settle * 0.055,
                    y: 1 - dragPresentation.settle * 0.030,
                    anchor: .center
                )
        }
    }

    @ViewBuilder
    private func edgeDecoration<S: Shape>(_ path: S) -> some View {
        let color = railEdgeColor
        switch usageStore.railEdgeStyle {
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
                glassEdgeColor.opacity(max(usageStore.railGlowOpacity * 0.34, 0.10)),
                style: StrokeStyle(
                    lineWidth: max(usageStore.railEdgeWidth * usageStore.railScale * 2.15, 1.15),
                    lineCap: .round,
                    lineJoin: .round
                )
            )
            .blur(radius: max(usageStore.railGlowRadius * usageStore.railScale * 0.16, 0.45))

            path.stroke(
                glassEdgeColor.opacity(max(usageStore.railEdgeOpacity, 0.46)),
                style: StrokeStyle(
                    lineWidth: max(usageStore.railEdgeWidth * usageStore.railScale, 0.58),
                    lineCap: .round,
                    lineJoin: .round
                )
            )
            .shadow(
                color: glassEdgeColor.opacity(usageStore.railGlowOpacity * 0.62),
                radius: usageStore.railGlowRadius * 0.58 * usageStore.railScale
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
                floatingCenterX: frame.floatingCenterX,
                floatingCenterY: frame.floatingCenterY,
                residue: frame.residue,
                wetting: frame.wetting
            )
        )
    }

    private func startSurfaceBreakPulse(edge: DockEdge) {
        breakPulseTask?.cancel()
        let sequence = settleSequence
        breakPulseTask = Task { @MainActor in
            var frameCount = 0
            while !Task.isCancelled, settleSequence == sequence, dragPhase == .floating, frameCount < 54 {
                let frame = motionRuntime.tickFloating(timestamp: ProcessInfo.processInfo.systemUptime)
                publishDragVisual(phase: .floating, edge: edge, frame: frame, sideProgress: 0)
                frameCount += 1
                if frameCount > 18, abs(frame.residue) < 0.025, frame.impact < 0.025 { break }
                try? await Task.sleep(nanoseconds: 8_333_333)
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
    private func providerAccountMenu(_ provider: ProviderID) -> some View {
        Menu(provider.displayName) {
            if UsageDockDistributionPolicy.allowsDevelopmentAccounts {
                Button {
                    usageStore.addAccount(provider: provider)
                    onOpenSettings()
                } label: {
                    Label("Add Account", systemImage: "plus")
                }
            }

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

            if UsageDockDistributionPolicy.allowsDevelopmentAccounts {
                if provider == .codex {
                    Menu("Add Synthetic") {
                        Button("×1") { usageStore.addSyntheticAccount(provider: .codex, multiplier: 1) }
                        Button("×5") { usageStore.addSyntheticAccount(provider: .codex, multiplier: 5) }
                        Button("×20") { usageStore.addSyntheticAccount(provider: .codex, multiplier: 20) }
                    }
                } else {
                    Button {
                        usageStore.addSyntheticAccount(provider: provider, multiplier: provider == .claude ? 20 : 1)
                    } label: {
                        Label(provider == .claude ? "Add Synthetic ×20" : "Add Synthetic", systemImage: "sparkles")
                    }
                }
            } else if !provider.supportsProfileLogin && !provider.supportsLiveUsage {
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
    let wetting: CGFloat

    private var clampedStretch: CGFloat { min(max(stretch, 0), 1.34) }
    private var clampedDetach: CGFloat { min(max(detach, 0), 1) }
    private var clampedKinetic: CGFloat { min(max(kinetic, 0), 1) }
    private var clampedSettle: CGFloat { min(max(settle, 0), 1) }

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
        let impactAmount = min(max(CGFloat(impact), 0), 1)
        let kineticAmount = min(max(CGFloat(kinetic), 0), 1)
        let inset = max(1.2, min(rect.width, rect.height) * 0.018)
        let body = rect.insetBy(dx: inset, dy: inset)
        let radius = min(
            body.width * (0.31 + 0.035 * kineticAmount),
            body.height * (0.16 + 0.015 * impactAmount)
        )
        return RoundedRectangle(cornerRadius: max(radius, 7), style: .continuous).path(in: body)
    }
}

private struct EdgeRailShape: Shape {
    let edge: DockEdge
    let screenEdgeAmount: Double
    let innerEdgeAmount: Double
    let cornerRadius: Double
    let scallopDepth: Double
    let scallopRadius: Double
    let smoothing: Double
    var stretchAmount: Double
    var neckAmount: Double
    let screenEdgeOutset: CGFloat

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
            innerEdgeAmount: innerEdgeAmount,
            cornerRadius: cornerRadius,
            scallopDepth: scallopDepth,
            scallopRadius: scallopRadius,
            smoothing: smoothing,
            stretchAmount: stretchAmount,
            neckAmount: neckAmount,
            screenEdgeOutset: screenEdgeOutset,
            closesScreenEdge: true
        )
    }
}

private struct EdgeRailFreeBorderShape: Shape {
    let edge: DockEdge
    let screenEdgeAmount: Double
    let innerEdgeAmount: Double
    let cornerRadius: Double
    let scallopDepth: Double
    let scallopRadius: Double
    let smoothing: Double
    var stretchAmount: Double
    var neckAmount: Double
    let screenEdgeOutset: CGFloat

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
            innerEdgeAmount: innerEdgeAmount,
            cornerRadius: cornerRadius,
            scallopDepth: scallopDepth,
            scallopRadius: scallopRadius,
            smoothing: smoothing,
            stretchAmount: stretchAmount,
            neckAmount: neckAmount,
            screenEdgeOutset: screenEdgeOutset,
            closesScreenEdge: false
        )
    }
}

private enum EdgeRailGeometry {
    static func path(
        in rect: CGRect,
        edge: DockEdge,
        screenEdgeAmount: Double,
        innerEdgeAmount: Double,
        cornerRadius: Double,
        scallopDepth: Double,
        scallopRadius: Double,
        smoothing: Double,
        stretchAmount: Double,
        neckAmount: Double,
        screenEdgeOutset: CGFloat,
        closesScreenEdge: Bool
    ) -> Path {
        let stretch = min(max(CGFloat(stretchAmount), 0), 1.2)
        let neck = min(max(CGFloat(neckAmount), 0), 1)
        let visualOutset = max(screenEdgeOutset, 0)
        let nominalMinY = rect.minY + visualOutset
        let nominalMaxY = rect.maxY - visualOutset
        let nominalHeight = max(nominalMaxY - nominalMinY, 1)
        let centerY = (nominalMinY + nominalMaxY) * 0.5
        let baseRadius = min(CGFloat(cornerRadius), rect.width * 0.42, nominalHeight * 0.18)
        let radius = max(2, baseRadius * (1 - 0.28 * neck))
        let baseDepth = min(CGFloat(scallopDepth), nominalHeight * 0.30)
        let depth = min(baseDepth * (1 + 0.20 * stretch + 0.26 * neck), nominalHeight * 0.36)
        let baseBlend = min(max(CGFloat(smoothing), 0), 1)
        let blend = min(baseBlend + 0.20 * stretch + 0.14 * neck, 1)
        let screenRaw = shapeInset(screenEdgeAmount, depth: depth)
        let innerRaw = shapeInset(innerEdgeAmount, depth: depth)
        let baseline = min(screenRaw, innerRaw)
        let screenInset = screenRaw - baseline
        let freeEndCompression = min(nominalHeight * (0.025 * stretch + 0.045 * neck), nominalHeight * 0.10)
        let innerInset = min(innerRaw - baseline + freeEndCompression, nominalHeight * 0.18)
        let pinchCurve = CGFloat(pow(Double(neck), 1.18))
        // Keep a visible liquid lobe attached to the Mac edge. The strong pinch belongs in
        // the throat between the edge and the body, not at the screen endpoint itself.
        let screenLobePinch = min(
            nominalHeight * (0.018 * stretch + 0.070 * pinchCurve),
            nominalHeight * 0.090
        )
        let screenTopY = min(nominalMinY - visualOutset + screenInset + screenLobePinch, centerY - 2)
        let screenBottomY = max(nominalMaxY + visualOutset - screenInset - screenLobePinch, centerY + 2)
        let innerTopY = nominalMinY + innerInset
        let innerBottomY = nominalMaxY - innerInset
        let span = max(rect.width - radius, 1)
        let edgeShapeStrength = min(max(abs(CGFloat(screenEdgeAmount)), 0), 1)

        // The reference silhouette is not a hill attached to the screen. The material first
        // scoops inward beside the screen (a concave throat), then opens into a broad rounded
        // body. Two cubics share one tangent at the throat, so the transition stays smooth
        // without the polygonal joint that appeared in the older shoulder implementation.
        let concavity = min(
            0.54 + 0.22 * edgeShapeStrength + 0.14 * neck + 0.05 * stretch,
            0.92
        )
        let stretchNormalized = min(max(stretch / 1.05, 0), 1)
        let stretchRoundness = stretchNormalized * stretchNormalized * (3 - 2 * stretchNormalized)
        let liquidRoundness = min(max(neck * 0.62 + stretchRoundness * 0.62, 0), 1)
        let neckRun = min(
            max(
                span * (
                    0.18 +
                    0.055 * edgeShapeStrength +
                    0.145 * neck +
                    0.105 * stretchRoundness
                ),
                radius * 1.10
            ),
            span * 0.52
        )
        let bodyArcSpan = max(span - neckRun, 1)
        let bodyBellyProgress = 0.54 + 0.08 * liquidRoundness
        let bodyBellyVerticalFactor = max(0.10, 0.24 - 0.12 * liquidRoundness)
        let bodyBellyTangentX = min(
            bodyArcSpan * (0.12 + 0.11 * liquidRoundness),
            bodyArcSpan * 0.25
        )
        let throatProgress = min(0.72 + 0.18 * concavity, 0.90)
        // As the bridge stretches, the waist tangent becomes increasingly horizontal.
        // This makes the two halves read as rounded droplets joined by a thin liquid neck
        // instead of two long diagonal lines meeting at a pinch point.
        let throatTangentX = min(
            max(
                span * (0.070 + 0.025 * blend + 0.055 * liquidRoundness),
                bodyArcSpan * (0.16 + 0.13 * liquidRoundness)
            ),
            min(
                neckRun * (0.48 + 0.30 * liquidRoundness),
                bodyArcSpan * 0.44
            )
        )
        let throatTangentYBase = max(nominalHeight * (0.010 + 0.012 * blend), 1.25)
        let throatTangentY = throatTangentYBase * (1 - 0.96 * liquidRoundness)
        // Keep the droplet head rounded even as the bridge gets thinner. The cap tangent
        // stays bounded by its local radius, while the long body arc gets its own belly point.
        let bodyCornerTangent = min(
            max(radius * (0.58 + 0.18 * liquidRoundness), 2),
            radius * 0.90
        )
        let freeCapControlY = min(
            max(
                (innerBottomY - innerTopY) * (0.24 + 0.080 * liquidRoundness),
                radius * 1.18
            ),
            nominalHeight * 0.30
        )
        let topScreenHandleY = min(
            max(
                abs(innerTopY - screenTopY) * (0.42 + 0.16 * liquidRoundness),
                nominalHeight * (0.025 + 0.020 * concavity + 0.045 * liquidRoundness)
            ),
            nominalHeight * (0.13 + 0.055 * liquidRoundness)
        )
        let bottomScreenHandleY = min(
            max(
                abs(screenBottomY - innerBottomY) * (0.42 + 0.16 * liquidRoundness),
                nominalHeight * (0.025 + 0.020 * concavity + 0.045 * liquidRoundness)
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
                nominalHeight * (0.030 * stretch + 0.300 * pinchCurve),
                nominalHeight * 0.335
            )
            let topThroat = CGPoint(
                x: screenX - neckRun,
                y: min(topScreen.y + (topInner.y - topScreen.y) * throatProgress + throatPinch, centerY - 2)
            )
            let bottomThroat = CGPoint(
                x: screenX - neckRun,
                y: max(bottomScreen.y + (bottomInner.y - bottomScreen.y) * throatProgress - throatPinch, centerY + 2)
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
            if closesScreenEdge { path.addLine(to: topScreen) }

        case .left:
            let screenX = rect.minX
            let innerX = rect.maxX
            let topScreen = CGPoint(x: screenX, y: screenTopY)
            let topInner = CGPoint(x: innerX - radius, y: innerTopY)
            let bottomInner = CGPoint(x: innerX - radius, y: innerBottomY)
            let bottomScreen = CGPoint(x: screenX, y: screenBottomY)

            let throatPinch = min(
                nominalHeight * (0.030 * stretch + 0.300 * pinchCurve),
                nominalHeight * 0.335
            )
            let topThroat = CGPoint(
                x: screenX + neckRun,
                y: min(topScreen.y + (topInner.y - topScreen.y) * throatProgress + throatPinch, centerY - 2)
            )
            let bottomThroat = CGPoint(
                x: screenX + neckRun,
                y: max(bottomScreen.y + (bottomInner.y - bottomScreen.y) * throatProgress - throatPinch, centerY + 2)
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
            if closesScreenEdge { path.addLine(to: topScreen) }
        }

        if closesScreenEdge { path.closeSubpath() }
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
    let mochiHorizontalStretch: CGFloat
    let mochiVerticalScale: CGFloat
    let mochiTextTracking: CGFloat

    private var outerProgress: Double { min(max(outerRingPercent ?? 0, 0), 1) }
    private var innerProgress: Double { min(max(innerRingPercent ?? 0, 0), 1) }
    private var percentText: String { displayPercent.map { "\(Int(($0 * 100).rounded()))%" } ?? "--" }
    private var isAccount: Bool { if case .account = target { return true }; return false }
    private var effectiveRing: Bool { showRing && (showOuterRing || showInnerRing) }
    private var iconFrameSize: CGFloat { max(showRing ? 50 : 34, iconSize + (showRing ? 20 : 10)) * scale }
    private var iconFrameWidth: CGFloat { iconFrameSize * max(mochiHorizontalStretch, 1) }
    private var iconFrameHeight: CGFloat { iconFrameSize * min(max(mochiVerticalScale, 0.76), 1.04) }

    var body: some View {
        VStack(spacing: 3 * scale) {
            ZStack {
                if isHovered {
                    Ellipse()
                        .fill(ProviderBrand.glow(for: summary.provider, customHex: accentHex, theme: theme).opacity(0.16))
                        .frame(width: iconFrameWidth + 8 * scale, height: iconFrameHeight + 8 * scale)
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
            // Ring, progress arcs, surface and provider mark deform as one cluster.
            // Keeping one affine transform prevents the concentric pieces from stretching apart.
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
            .scaleEffect(
                x: max(mochiHorizontalStretch, 1),
                y: min(max(mochiVerticalScale, 0.76), 1.04),
                anchor: .center
            )
            .frame(width: iconFrameWidth, height: iconFrameHeight)

            if showPercent {
                Text(percentText)
                    .font(.system(size: percentFontSize * scale, weight: .semibold, design: .rounded))
                    .tracking(mochiTextTracking * scale)
                    .monospacedDigit()
                    .foregroundStyle(displayPercent == nil ? ProviderBrand.tertiaryText(theme: theme) : ProviderBrand.primaryText(theme: theme))
                    .shadow(color: ProviderBrand.contrastShadow(theme: theme, enabled: autoContrast), radius: autoContrast ? 1.3 : 0)
            }

            if showRemainingTime {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    Text(remainingTimeText(now: context.date) ?? "--")
                        .font(.system(size: remainingTimeFontSize * scale, weight: .medium, design: .rounded))
                        .tracking(mochiTextTracking * 0.72 * scale)
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
                    .tracking(mochiTextTracking * 0.62 * scale)
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
