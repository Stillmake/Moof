import SwiftUI

struct MoofNotificationView: View {
    @ObservedObject var item: MoofNotificationItem

    private let center = MoofNotificationCenter.shared

    var body: some View {
        MoofNotificationCard(
            notification: item.notification,
            dismissState: item.dismissState,
            close: { center.close(item.id) },
            copy: { center.copyMessage(item.id) },
            action: item.notification.action == nil ? nil : { center.performAction(item.id) }
        )
        .contentShape(.rect)
        .onTapGesture { center.performAction(item.id) }
        .onHover { center.setHovering(item.id, $0) }
    }
}

struct MoofNotificationCard: View {
    private static let cornerRadius: CGFloat = {
        if #available(macOS 26, *) { return 28 }
        return 20
    }()

    let notification: MoofNotification
    var dismissState: MoofNotificationItem.DismissState?
    var close: (() -> Void)?
    var copy: (() -> Void)?
    var action: (() -> Void)?

    private var layout: MoofNotificationLayout { MoofNotificationLayout(notification: notification) }
    private var tint: Color { notification.style.tint }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Self.cornerRadius)
        VStack(alignment: .leading, spacing: layout.cardSpacing) {
            header
            if let message = notification.message {
                Text(message)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
                    .frame(height: layout.messageRowHeight)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .background(tint.opacity(notification.style.isAlert ? 0.13 : 0.06), in: .rect(cornerRadius: 8))
            }
            HStack(spacing: 8) {
                if let action {
                    pillButton(notification.actionTitle, systemImage: "arrow.up.forward.app", action: action)
                }
                pillButton("Copy", systemImage: "doc.on.doc", action: copy)
            }
            .frame(height: layout.bottomBarHeight)
        }
        .padding(layout.cardPadding)
        .frame(width: MoofNotificationLayout.panelWidth, height: layout.panelHeight, alignment: .topLeading)
        .contentShape(shape)
        .overlay {
            shape
                .stroke(tint, lineWidth: notification.style == .critical ? 3 : 1)
                .blur(radius: 6)
                .clipShape(shape)
        }
        .background {
            if #available(macOS 26, *) {
                shape.fill(Color.white.opacity(0.0001)).glassEffect(.regular, in: shape)
            } else {
                ZStack {
                    shape.fill(.thinMaterial)
                    shape.fill(tint.opacity(notification.style == .success ? 0.04 : 0.1))
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle().fill(tint.opacity(0.2))
                Image(systemName: notification.style.symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(tint)
                    .symbolEffect(.pulse, isActive: notification.style == .critical)
            }
            .frame(width: layout.iconSize, height: layout.iconSize)

            VStack(alignment: .leading, spacing: 0) {
                Text(notification.title)
                    .font(.headline)
                    .lineLimit(1)
                    .help(notification.title)

                HStack(spacing: 8) {
                    Text(notification.subtitle ?? notification.style.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(tint)
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
        .frame(minHeight: layout.headerHeight, alignment: .top)
    }

    private var showsDismissIndicator: Bool {
        guard let dismissState else { return false }
        return dismissState.totalInterval > 0 && !dismissState.wasCancelledByHover
    }

    private var closeButton: some View {
        Button(action: { close?() }) {
            ZStack {
                Circle().fill(Color.secondary.opacity(0.08))
                Circle().stroke(Color.secondary.opacity(0.18), lineWidth: showsDismissIndicator ? 2 : 0)
                if showsDismissIndicator, let dismissState {
                    TimelineView(.periodic(from: .now, by: 0.1)) { context in
                        let remaining = dismissState.deadline.map { max($0.timeIntervalSince(context.date), 0) } ?? 0
                        let progress = min(max(remaining / dismissState.totalInterval, 0), 1)
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
                .background(Color.secondary.opacity(0.08), in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(action == nil)
        .foregroundStyle(.secondary)
    }
}
