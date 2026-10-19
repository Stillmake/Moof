import SwiftUI

/// The in-game message band: a dark translucent strip fading out at both ends, centered serif
/// text, a hairline divider, and gamepad-style prompts. The divider doubles as the countdown,
/// its lit span shrinking toward the center. Style colors, icons and height levels are ignored.
struct EldenRingCard: View {
    let notification: MoofNotification
    var dismissState: MoofNotificationItem.DismissState?
    var close: (() -> Void)?
    var copy: (() -> Void)?
    var action: (() -> Void)?

    private static let ivory = Color(red: 0.88, green: 0.85, blue: 0.76)
    private static let gold = Color(red: 0.74, green: 0.64, blue: 0.42)

    var body: some View {
        let size = MoofNotificationLayout(notification: notification).size
        let ink = notification.background.map { $0.isDark ? Self.ivory : Color.black } ?? Self.ivory
        let band = notification.background.map(Color.init(nsColor:)) ?? Color(red: 0.17, green: 0.155, blue: 0.13)
        let edgeFade = LinearGradient(
            stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.12), .init(color: .black, location: 0.88), .init(color: .clear, location: 1)],
            startPoint: .leading,
            endPoint: .trailing
        )
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                Text(notification.title)
                    .font(.system(size: 18, design: .serif))
                    .tracking(1.4)
                    .lineLimit(1)
                if let message = notification.message {
                    Text(message)
                        .font(.system(size: 13, design: .serif))
                        .tracking(0.6)
                        .opacity(0.72)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .textSelection(.enabled)
                }
            }
            .padding(.horizontal, 120)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            ZStack {
                Rectangle().fill(Self.gold.opacity(0.22))
                if let dismissState, dismissState.isCountingDown {
                    TimelineView(.animation) { context in
                        GeometryReader { proxy in
                            Rectangle()
                                .fill(Self.gold.opacity(0.8))
                                .frame(width: proxy.size.width * dismissState.progress(at: context.date))
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            .frame(height: 1)
            .padding(.horizontal, 72)

            HStack(spacing: 32) {
                if let action {
                    prompt("A", notification.actionTitle, action)
                }
                prompt("X", "Copy", copy)
                prompt("Y", "Close", close)
            }
            .frame(height: 46)
        }
        .foregroundStyle(ink)
        .shadow(color: .black.opacity(0.7), radius: 1.5, y: 1)
        .frame(width: size.width, height: size.height)
        .background {
            ZStack {
                LinearGradient(colors: [band.opacity(0.93), band.opacity(0.84), band.opacity(0.93)], startPoint: .top, endPoint: .bottom)
                VStack(spacing: 0) {
                    Rectangle().fill(.white.opacity(0.07)).frame(height: 1)
                    Spacer(minLength: 0)
                    Rectangle().fill(.black.opacity(0.45)).frame(height: 1)
                }
            }
            .mask(edgeFade)
        }
    }

    private func prompt(_ key: String, _ title: String, _ action: (() -> Void)?) -> some View {
        Button(action: { action?() }) {
            HStack(spacing: 4) {
                Text(key)
                    .font(.system(size: 11, weight: .medium, design: .serif))
                    .foregroundStyle(Self.gold)
                    .frame(width: 20, height: 20)
                    .overlay(Circle().stroke(Self.gold, lineWidth: 1.2))
                Text(":\(title)")
                    .font(.system(size: 14, design: .serif))
                    .tracking(0.8)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}
