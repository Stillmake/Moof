import SwiftUI

struct MoofNotificationCard: View {
    let notification: MoofNotification
    var dismissState: MoofNotificationItem.DismissState?
    var close: (() -> Void)?
    var copy: (() -> Void)?
    var action: (() -> Void)?

    private var foreground: Color? { notification.background.map { $0.isDark ? .white : .black } }
    private var accent: Color { foreground ?? notification.style.tint }
    private var glassTint: Color { notification.background.map(Color.init(nsColor:)) ?? notification.style.tint }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 28)
        VStack(alignment: .leading, spacing: MoofNotificationLayout.cardSpacing) {
            header
            Text(notification.body)
                .font(Font(MoofNotificationLayout.messageFont))
                .lineLimit(MoofNotificationLayout.maxLines)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(.primary)
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .background(accent.opacity(notification.style.isAlert ? 0.3 : 0.16), in: .rect(cornerRadius: 8))
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
        .foregroundStyle(foreground ?? .nsLabelColor)
        .glassEffect(.regular.tint(glassTint.opacity(0.2)), in: shape)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: notification.style.symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(accent)
                .symbolEffect(.pulse, isActive: notification.style == .critical)

            // The title keeps its width first; the source and time truncate before it does.
            Text(notification.title)
                .font(.headline)
                .lineLimit(1)
                .help(notification.title)
                .layoutPriority(1)
            Text([notification.source, notification.createdAt.formatted(date: .omitted, time: .shortened)].compactMap { $0.map { "· \($0)" } }.joined(separator: " "))
                .font(.headline)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer(minLength: 0)

            closeButton
        }
        .frame(height: MoofNotificationLayout.headerHeight)
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
                // Resizable, so the glyph's own bounds are centered rather than its font line box.
                Image(systemName: "xmark")
                    .resizable()
                    .scaledToFit()
                    .fontWeight(.semibold)
                    .frame(width: 9, height: 9)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 24, height: 24)
            .contentShape(.rect)
            .animation(.default, value: showsDismissIndicator)
        }
        .buttonStyle(.plain)
        .help("Close")
    }

    private func pillButton(_ title: String, systemImage: String, action: (() -> Void)?) -> some View {
        Button(action: { action?() }) {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                Text(title)
            }
            .font(.caption.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.nsLabelColor.opacity(0.1), in: Capsule())
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(action == nil)
        .foregroundStyle(Color.nsLabelColor)
    }
}
