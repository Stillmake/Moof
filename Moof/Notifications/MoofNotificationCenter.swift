import AppKit
import Combine
import Observation
import QuartzCore
import SwiftUI

@MainActor
final class MoofNotificationItem: ObservableObject, Identifiable {
    struct DismissState: Codable {
        var totalInterval: TimeInterval
        var remainingInterval: TimeInterval
        var deadline: Date?
        var wasCancelledByHover = false

        var isCountingDown: Bool { totalInterval > 0 && !wasCancelledByHover }

        /// Remaining fraction of the countdown, `1` at the start and `0` at dismissal.
        func progress(at date: Date) -> Double {
            let remaining = deadline.map { max($0.timeIntervalSince(date), 0) } ?? 0
            return min(max(remaining / totalInterval, 0), 1)
        }
    }

    let id: String
    @Published var notification: MoofNotification
    @Published var isHovering = false
    @Published var dismissState: DismissState?

    init(notification: MoofNotification) {
        self.id = notification.id
        self.notification = notification
    }
}

@MainActor
@Observable
final class MoofNotificationCenter {
    static let shared = MoofNotificationCenter()

    private(set) var items: [String: MoofNotificationItem] = [:]

    @ObservationIgnored private var panels: [String: MoofNotificationPanel] = [:]
    @ObservationIgnored private var dismissWorkItems: [String: DispatchWorkItem] = [:]
    @ObservationIgnored private var order: [String] = []
    @ObservationIgnored private var layoutMonitoring: AnyCancellable?
    @ObservationIgnored private var saveWorkItem: DispatchWorkItem?
    @ObservationIgnored private let preferences = MoofPreferences.shared

    private let topOffset: CGFloat = 24
    private let entranceOffset: CGFloat = 28
    private let itemSpacing: CGFloat = 12

    private init() {
        layoutMonitoring = Publishers.Merge(
            NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification),
            NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.activeSpaceDidChangeNotification)
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] _ in
            self?.layoutWindows(animatedNewID: nil, animateExisting: false)
        }
    }

    func handle(_ command: MoofCommand) {
        switch command {
        case .notify(let notification):
            show(notification)
        case .dismiss(let id):
            close(id)
        }
    }

    func show(_ notification: MoofNotification) {

        if let item = items[notification.id] {
            item.notification = notification
            item.dismissState = nil
            panels[notification.id]?.apply(notification)
            scheduleDismiss(notification.id)
            // Cards stack by time, so the replaced card moves after the others.
            order.removeAll { $0 == notification.id }
            order.append(notification.id)
            layoutWindows(animatedNewID: nil)
            scheduleSave()
            return
        }

        present(MoofNotificationItem(notification: notification))
    }

    /// Shows the cards saved by the previous run. Cards whose deadline
    /// passed while Moof was not running are dropped; the rest resume their countdowns.
    func restore() {
        assert(items.isEmpty, "Restore runs once, before any card is shown.")
        let now = Date()
        for record in MoofNotificationStore.load() {
            var dismissState = record.dismissState
            if let deadline = dismissState?.deadline {
                guard deadline > now else { continue }
                // `scheduleDismiss` resumes from the remaining interval and sets a new deadline.
                dismissState?.remainingInterval = deadline.timeIntervalSince(now)
                dismissState?.deadline = nil
            }
            let item = MoofNotificationItem(notification: record.notification)
            item.dismissState = dismissState
            present(item)
        }
        scheduleSave()
    }

    /// Writes the cards immediately, for app termination.
    func saveNow() {
        saveWorkItem?.cancel()
        saveWorkItem = nil
        MoofNotificationStore.save(order.compactMap { items[$0] }.map { .init(notification: $0.notification, dismissState: $0.dismissState) })
    }

    private func present(_ item: MoofNotificationItem) {
        items[item.id] = item
        scheduleDismiss(item.id)
        panels[item.id] = MoofNotificationPanel(item: item, screen: targetScreen())
        order.append(item.id)
        layoutWindows(animatedNewID: item.id)
        scheduleSave()
    }

    /// Coalesces bursts of changes, such as Preview All, into one write.
    private func scheduleSave() {
        saveWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor in self?.saveNow() }
        }
        saveWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: workItem)
    }

    func close(_ id: String) {
        dismissWorkItems[id]?.cancel()
        dismissWorkItems[id] = nil
        panels[id]?.close()
        panels[id] = nil
        items[id] = nil
        order.removeAll { $0 == id }
        layoutWindows(animatedNewID: nil, animateExisting: true)
        scheduleSave()
    }

    func performAction(_ id: String) {
        guard let url = items[id]?.notification.action else { return }
        NSWorkspace.shared.open(url)
        close(id)
    }

    func copy(_ id: String) {
        guard let notification = items[id]?.notification else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(notification.title + "\n" + notification.body, forType: .string)
    }

    func setHovering(_ id: String, _ hovering: Bool) {
        guard let item = items[id] else { return }
        item.isHovering = hovering
        guard hovering else { return }
        if item.dismissState?.wasCancelledByHover == false, let deadline = item.dismissState?.deadline {
            item.dismissState?.remainingInterval = max(deadline.timeIntervalSinceNow, 0)
            item.dismissState?.deadline = nil
            item.dismissState?.wasCancelledByHover = true
            scheduleSave()
        }
        dismissWorkItems[id]?.cancel()
        dismissWorkItems[id] = nil
    }

    private func layoutWindows(animatedNewID: String? = nil, animateExisting: Bool = true) {
        var screenOffsets: [ObjectIdentifier: CGFloat] = [:]
        for id in order {
            guard let panel = panels[id] else { continue }
            if !NSScreen.screens.contains(where: { $0 === panel.screen }) {
                panel.screen = targetScreen()
            }
            let screenID = ObjectIdentifier(panel.screen)
            let stackOffset = screenOffsets[screenID, default: 0]
            if id == animatedNewID {
                panel.showFromTop(topOffset: topOffset, stackOffset: stackOffset, entranceOffset: entranceOffset)
            } else {
                panel.position(topOffset: topOffset, stackOffset: stackOffset, animated: animateExisting)
            }
            screenOffsets[screenID, default: 0] = stackOffset + panel.cardSize.height + itemSpacing
        }
    }

    private func scheduleDismiss(_ id: String) {
        dismissWorkItems[id]?.cancel()
        guard let item = items[id], !item.isHovering, let delay = preferences.dismissDelay(for: item.notification),
            item.dismissState?.wasCancelledByHover != true
        else { return }

        let remainingDelay = item.dismissState.map(\.remainingInterval).flatMap { $0 > 0 ? $0 : nil } ?? delay
        item.dismissState = .init(
            totalInterval: item.dismissState?.totalInterval ?? delay,
            remainingInterval: remainingDelay,
            deadline: Date().addingTimeInterval(remainingDelay)
        )

        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                guard let self, self.items[id]?.isHovering == false else { return }
                self.close(id)
            }
        }
        dismissWorkItems[id] = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + remainingDelay, execute: workItem)
    }

    private func targetScreen() -> NSScreen {
        let mouseLocation = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) {
            return screen
        }
        guard let mainScreen = NSScreen.main else {
            assertionFailure("Expected at least one screen for notification placement.")
            return NSScreen.screens[0]
        }
        return mainScreen
    }
}

/// Liquid Glass drops its tint unless its window has active appearance, which a non-activating
/// panel never gets; reporting it here keeps the tint on every card.
private final class ActiveAppearancePanel: NSPanel {
    @objc func _hasActiveAppearance() -> Bool { true }
}

@MainActor
final class MoofNotificationPanel {
    var screen: NSScreen
    /// The card's own size; the window adds `shadowMargin` on every side.
    var cardSize: CGSize
    private var shadowMargin: CGFloat = 0

    private let panel: NSPanel

    init(item: MoofNotificationItem, screen: NSScreen) {
        self.screen = screen
        self.cardSize = MoofNotificationLayout(notification: item.notification).size
        self.panel = ActiveAppearancePanel(
            contentRect: NSRect(origin: .zero, size: cardSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.backgroundColor = .clear
        // Cards draw their own edges and shadows; the window shadow would add a system outline.
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.isOpaque = false
        panel.isReleasedWhenClosed = false
        panel.level = item.notification.style == .critical ? .screenSaver : .statusBar
        panel.contentViewController = NSHostingController(rootView: MoofNotificationView(item: item))
        apply(item.notification)
    }

    func apply(_ notification: MoofNotification) {
        cardSize = MoofNotificationLayout(notification: notification).size
        shadowMargin = notification.theme == .standard ? MoofNotificationLayout.glassShadowMargin : 0
    }

    func close() {
        panel.contentViewController = nil
        panel.close()
    }

    func position(topOffset: CGFloat, stackOffset: CGFloat, animated: Bool) {
        let targetFrame = frame(topOffset: topOffset, stackOffset: stackOffset)
        if animated {
            animate(to: targetFrame, duration: 0.16)
        } else {
            setFrameWithoutAnimation(targetFrame, alpha: panel.alphaValue)
        }
    }

    func showFromTop(topOffset: CGFloat, stackOffset: CGFloat, entranceOffset: CGFloat) {
        let targetFrame = frame(topOffset: topOffset, stackOffset: stackOffset)
        setFrameWithoutAnimation(targetFrame.offsetBy(dx: 0, dy: entranceOffset), alpha: 0)
        panel.orderFrontRegardless()
        animate(to: targetFrame, duration: 0.22)
    }

    private func animate(to targetFrame: NSRect, duration: TimeInterval) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
            panel.animator().setFrame(targetFrame, display: true)
        }
    }

    private func setFrameWithoutAnimation(_ frame: NSRect, alpha: CGFloat) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            context.allowsImplicitAnimation = false
            panel.setFrame(frame, display: false)
            panel.alphaValue = alpha
        }
    }

    private func frame(topOffset: CGFloat, stackOffset: CGFloat) -> NSRect {
        let visibleFrame = screen.visibleFrame
        let origin = NSPoint(
            x: visibleFrame.midX - cardSize.width / 2,
            y: visibleFrame.maxY - topOffset - stackOffset - cardSize.height
        )
        return NSRect(origin: origin, size: cardSize).insetBy(dx: -shadowMargin, dy: -shadowMargin)
    }
}
