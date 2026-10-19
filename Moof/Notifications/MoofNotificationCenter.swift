import AppKit
import Combine
import Observation
import QuartzCore
import SwiftUI

@MainActor
final class MoofNotificationItem: ObservableObject, Identifiable {
    struct DismissState {
        var totalInterval: TimeInterval
        var remainingInterval: TimeInterval
        var deadline: Date?
        var wasCancelledByHover = false
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
        case .dismissAll:
            order.forEach(close)
        }
    }

    func show(_ notification: MoofNotification) {
        if let soundName = notification.sound {
            let sound = NSSound(named: soundName)
            assert(sound != nil, "Unknown system sound \(soundName); playing beep.")
            if sound?.play() != true { NSSound.beep() }
        }

        if let item = items[notification.id] {
            item.notification = notification
            item.dismissState = nil
            panels[notification.id]?.windowSize = MoofNotificationLayout(notification: notification).size
            scheduleDismiss(notification.id)
            layoutWindows(animatedNewID: nil)
            return
        }

        let item = MoofNotificationItem(notification: notification)
        items[item.id] = item
        scheduleDismiss(item.id)
        panels[item.id] = MoofNotificationPanel(item: item, screen: targetScreen())
        order.append(item.id)
        layoutWindows(animatedNewID: item.id)
    }

    func close(_ id: String) {
        dismissWorkItems[id]?.cancel()
        dismissWorkItems[id] = nil
        panels[id]?.close()
        panels[id] = nil
        items[id] = nil
        order.removeAll { $0 == id }
        layoutWindows(animatedNewID: nil, animateExisting: true)
    }

    func performAction(_ id: String) {
        guard let url = items[id]?.notification.action else { return }
        NSWorkspace.shared.open(url)
        close(id)
    }

    func copyMessage(_ id: String) {
        guard let notification = items[id]?.notification else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(notification.message ?? notification.title, forType: .string)
    }

    func setHovering(_ id: String, _ hovering: Bool) {
        guard let item = items[id] else { return }
        item.isHovering = hovering
        guard hovering else { return }
        if item.dismissState?.wasCancelledByHover == false, let deadline = item.dismissState?.deadline {
            item.dismissState?.remainingInterval = max(deadline.timeIntervalSinceNow, 0)
            item.dismissState?.deadline = nil
            item.dismissState?.wasCancelledByHover = true
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
            screenOffsets[screenID, default: 0] = stackOffset + panel.windowSize.height + itemSpacing
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

@MainActor
final class MoofNotificationPanel {
    var screen: NSScreen
    var windowSize: CGSize

    private let panel: NSPanel

    init(item: MoofNotificationItem, screen: NSScreen) {
        self.screen = screen
        self.windowSize = MoofNotificationLayout(notification: item.notification).size
        self.panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: windowSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.backgroundColor = .clear
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.isOpaque = false
        panel.isReleasedWhenClosed = false
        panel.level = item.notification.style == .critical ? .screenSaver : .statusBar
        panel.contentViewController = NSHostingController(rootView: MoofNotificationView(item: item))
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
            x: visibleFrame.midX - windowSize.width / 2,
            y: visibleFrame.maxY - topOffset - stackOffset - windowSize.height
        )
        return NSRect(origin: origin, size: windowSize)
    }
}
