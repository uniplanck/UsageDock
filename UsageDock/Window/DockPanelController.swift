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
        let strength = min(max(abs(amount), 0), 1.25)
        let midY = rect.midY
        let topY = rect.minY + rect.height * (0.16 + 0.06 * (1 - min(strength, 1)))
        let bottomY = rect.maxY - rect.height * (0.16 + 0.06 * (1 - min(strength, 1)))
        let bulge = rect.width * (0.52 + 0.26 * min(strength, 1))
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
                    iconEdgeInset: usageStore.railIconEdgeInset,
                    iconSize: usageStore.railIconSize,
                    titleWidth: usageStore.railTitleWidth,
                    timeWidth: usageStore.railTimeWidth
                )
                let baseHeight = RailMetrics.contentHeight(
                    entryCount: usageStore.railTargets().count,
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

                ZStack {
                    if !isAttached, abs(snapshot.residue) > 0.012 {
                        let residueStrength = min(abs(snapshot.residue), 1.25)
                        let residueWidth = 26 + 18 * residueStrength
                        let residueHeight = 42 + 22 * residueStrength
                        let residueCenterY = topInset + 8 + baseHeight * 0.5 + travel * CGFloat(snapshot.anchorVerticalPosition)
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
                                x: 1 + 0.08 * residueStrength,
                                y: 1 - 0.045 * residueStrength,
                                anchor: snapshot.edge == .left ? .leading : .trailing
                            )
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
            showRing: usageStore.railShowRing,
            showPercent: usageStore.railShowPercent,
            showMultiplier: usageStore.railShowMultiplier,
            showRemainingTime: usageStore.railShowRemainingTime,
            remainingTimeFontSize: usageStore.railRemainingTimeFontSize,
            iconEdgeInset: usageStore.railIconEdgeInset,
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

    func reposition() {
        resizeAndReposition()
    }

    private func basePanelSize() -> NSSize {
        RailMetrics.windowSize(
            entryCount: usageStore.railTargets().count,
            scale: usageStore.railScale,
            itemSpacing: usageStore.railItemSpacing,
            showRing: usageStore.railShowRing,
            showPercent: usageStore.railShowPercent,
            showMultiplier: usageStore.railShowMultiplier,
            showRemainingTime: usageStore.railShowRemainingTime,
            remainingTimeFontSize: usageStore.railRemainingTimeFontSize,
            iconEdgeInset: usageStore.railIconEdgeInset,
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

    private func currentPanelSize() -> NSSize {
        var size = basePanelSize()
        size.height += screenEdgeVisualOutset() * 2
        return size
    }

    private func resizeAndReposition(animated: Bool = false) {
        guard let screen = screenForPlacement() else { return }
        let visible = screen.visibleFrame
        let baseSize = basePanelSize()
        let visualOutset = screenEdgeVisualOutset()
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
        let y = baseY - visualOutset
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

        usageStore.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.panel.ignoresMouseEvents = self.usageStore.railVisualOnlyMode
                    if !self.usageStore.railHoverEnabled || self.usageStore.railVisualOnlyMode {
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
