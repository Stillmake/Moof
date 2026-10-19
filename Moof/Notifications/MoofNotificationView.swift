import SwiftUI

struct MoofNotificationView: View {
    @ObservedObject var item: MoofNotificationItem

    private let center = MoofNotificationCenter.shared

    var body: some View {
        let close = { center.close(item.id) }
        let copy = { center.copyMessage(item.id) }
        let action = item.notification.action == nil ? nil : { center.performAction(item.id) }
        Group {
            switch item.notification.theme {
            case .standard:
                MoofNotificationCard(notification: item.notification, dismissState: item.dismissState, close: close, copy: copy, action: action)
            case .eldenRing:
                EldenRingCard(notification: item.notification, dismissState: item.dismissState, close: close, copy: copy, action: action)
            case .mario:
                MarioCard(notification: item.notification, dismissState: item.dismissState, close: close, copy: copy, action: action)
            case .hollowKnight:
                HollowKnightCard(notification: item.notification, dismissState: item.dismissState, close: close, copy: copy, action: action)
            }
        }
        .contentShape(.rect)
        .onTapGesture { center.performAction(item.id) }
        .onHover { center.setHovering(item.id, $0) }
    }
}

struct MoofNotificationCard: View {
    let notification: MoofNotification
    var dismissState: MoofNotificationItem.DismissState?
    var close: (() -> Void)?
    var copy: (() -> Void)?
    var action: (() -> Void)?

    private var foreground: Color? { notification.background.map { $0.isDark ? .white : .black } }
    private var accent: Color { foreground ?? notification.style.tint }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 28)
        VStack(alignment: .leading, spacing: MoofNotificationLayout.cardSpacing) {
            header
            if let message = notification.message {
                Text(message)
                    .font(Font(MoofNotificationLayout.messageFont))
                    .lineLimit(MoofNotificationLayout.maxLines)
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .background(accent.opacity(notification.style.isAlert ? 0.13 : 0.06), in: .rect(cornerRadius: 8))
            }
            HStack(spacing: 8) {
                if let action {
                    pillButton(notification.actionTitle, systemImage: "arrow.up.forward.app", action: action)
                }
                pillButton("Copy", systemImage: "doc.on.doc", action: copy)
            }
            .frame(height: MoofNotificationLayout.bottomBarHeight)
        }
        .padding(MoofNotificationLayout.cardPadding)
        .frame(width: MoofNotificationLayout.panelWidth, height: MoofNotificationLayout(notification: notification).size.height, alignment: .topLeading)
        .contentShape(shape)
        .foregroundStyle(foreground ?? .primary)
        .glassEffect(.regular.tint(notification.background.map(Color.init(nsColor:)) ?? notification.style.tint), in: shape)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle().fill(accent.opacity(0.2))
                Image(systemName: notification.style.symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(accent)
                    .symbolEffect(.pulse, isActive: notification.style == .critical)
            }
            .frame(width: MoofNotificationLayout.iconSize, height: MoofNotificationLayout.iconSize)

            VStack(alignment: .leading, spacing: 0) {
                Text(notification.title)
                    .font(.headline)
                    .lineLimit(1)
                    .help(notification.title)

                HStack(spacing: 8) {
                    Text(notification.subtitle ?? notification.style.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(accent)
                        .lineLimit(1)
                    if let source = notification.source {
                        metadataLabel(source, systemImage: "app.badge")
                    }
                    metadataLabel(notification.createdAt.formatted(date: .omitted, time: .shortened), systemImage: "clock")
                    if notification.keepsVisibleUntilDismissed {
                        metadataLabel("Pinned", systemImage: "pin.fill")
                    }
                }
            }

            Spacer(minLength: 0)

            closeButton
        }
        .frame(minHeight: MoofNotificationLayout.headerHeight, alignment: .top)
    }

    private var showsDismissIndicator: Bool { dismissState?.isCountingDown == true }

    private var closeButton: some View {
        Button(action: { close?() }) {
            ZStack {
                Circle().fill(.secondary.opacity(0.08))
                Circle().stroke(.secondary.opacity(0.18), lineWidth: showsDismissIndicator ? 2 : 0)
                if showsDismissIndicator, let dismissState {
                    TimelineView(.periodic(from: .now, by: 0.1)) { context in
                        let progress = dismissState.progress(at: context.date)
                        Circle()
                            .trim(from: 0, to: progress)
                            .stroke(
                                progress < 0.3 ? Color.red : progress < 0.5 ? .orange : .green,
                                style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                            )
                            .rotationEffect(.degrees(-90))
                    }
                }
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 24, height: 24)
            .contentShape(.rect)
            .animation(.default, value: showsDismissIndicator)
        }
        .buttonStyle(.plain)
        .help("Close")
    }

    private func metadataLabel(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .labelStyle(.titleAndIcon)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }

    private func pillButton(_ title: String, systemImage: String, action: (() -> Void)?) -> some View {
        Button(action: { action?() }) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.secondary.opacity(0.08), in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(action == nil)
        .foregroundStyle(.secondary)
    }
}
