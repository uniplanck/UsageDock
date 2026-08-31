import AppKit
import SwiftUI

@MainActor
final class HoverDetailPanelController {
    private let usageStore: UsageStore
    private let placement: PlacementStore
    private let panel: NonActivatingPanel
    private let onPanelHoverChanged: (Bool) -> Void
    private(set) var visibleTarget: RailDisplayTarget?

    private var width: CGFloat {
        usageStore.resetTimeDisplayMode == .both ? 390 : 346
    }

    init(
        usageStore: UsageStore,
        placement: PlacementStore,
        onPanelHoverChanged: @escaping (Bool) -> Void
    ) {
        self.usageStore = usageStore
        self.placement = placement
        self.onPanelHoverChanged = onPanelHoverChanged
        self.panel = NonActivatingPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = false
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
    }

    func show(target: RailDisplayTarget, index: Int, anchorPanel: NSPanel) {
        visibleTarget = target
        let summary = usageStore.summary(for: target)
        let rowCount = max(1, min(summary.aggregates.count, 7))
        let height: CGFloat = summary.aggregates.isEmpty
            ? 184
            : min(430, 118 + CGFloat(rowCount) * 56)

        panel.contentView = NSHostingView(
            rootView: ProviderDetailView(
                target: target,
                edge: placement.edge,
                usageStore: usageStore
            )
            .frame(width: width, height: height)
            .environment(\.locale, usageStore.appLanguage.locale)
            .contentShape(Rectangle())
            .onHover { [onPanelHoverChanged] inside in
                onPanelHoverChanged(inside)
            }
        )

        let anchor = anchorPanel.frame
        let screen = anchorPanel.screen ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }
        let visible = screen.visibleFrame

        let x: CGFloat
        switch placement.edge {
        case .right:
            x = anchor.minX - width
        case .left:
            x = anchor.maxX
        }

        let rowHeight = RailMetrics.rowHeight(
            scale: usageStore.railScale,
            showRing: usageStore.railShowRing,
            showPercent: usageStore.railShowPercent,
            showRemainingTime: usageStore.railShowRemainingTime,
            remainingTimeFontSize: usageStore.railRemainingTimeFontSize,
            iconSize: usageStore.railIconSize,
            percentFontSize: usageStore.railPercentFontSize,
            showTitle: usageStore.railShowTitle,
            titleFontSize: usageStore.railAccountLabelFontSize
        )
        let topInset = RailMetrics.verticalPadding(scale: usageStore.railScale, showRing: usageStore.railShowRing)
        let spacing = RailMetrics.spacing(scale: usageStore.railScale, itemSpacing: usageStore.railItemSpacing)
        let rowCenterY = anchor.maxY - topInset - CGFloat(index) * (rowHeight + spacing) - rowHeight / 2
        let unclampedY = rowCenterY - height / 2
        let y = min(max(unclampedY, visible.minY + 8), visible.maxY - height - 8)

        panel.setFrame(
            NSRect(x: x.rounded(), y: y.rounded(), width: width, height: height),
            display: true
        )

        if !panel.isVisible {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.11
                panel.animator().alphaValue = 1
            }
        } else {
            panel.orderFrontRegardless()
        }
    }

    func hide(target: RailDisplayTarget? = nil) {
        if let target, visibleTarget != target { return }
        visibleTarget = nil
        onPanelHoverChanged(false)
        guard panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.08
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak panel] in
            panel?.orderOut(nil)
            panel?.alphaValue = 1
        })
    }
}
