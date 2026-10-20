import SwiftUI

/// A Hollow Knight dialog: a dark, soft-edged panel with serif text, a fleur ornament straddling
/// its top edge and a smaller one on its bottom edge. The bottom fleur is the countdown, its lit
/// part shrinking toward the center. Clicking anywhere on the card closes it. On hover, serif Copy and
/// action buttons appear inside the panel above it, with the source at the row's leading edge.
/// Style colors and icons are ignored.
struct HollowKnightCard: View {
    let notification: MoofNotification
    var dismissState: MoofNotificationItem.DismissState?
    var isHovering = false
    var close: (() -> Void)?
    var copy: (() -> Void)?
    var action: (() -> Void)?

    var body: some View {
        let size = MoofNotificationLayout(notification: notification).size
        let ink = notification.background.map { $0.isDark ? Color.white : Color.black } ?? .white
        let panel = notification.background.map { Color(nsColor: $0).opacity(0.7) } ?? Color.black.opacity(0.58)
        let bottomFleur = Image("HollowKnightOrnamentBottom")
            .resizable()
            .scaledToFit()
            .frame(width: 230)
        ZStack(alignment: .top) {
            // Blurred inside the panel's margins so its feathered edge is not clipped by the window.
            RoundedRectangle(cornerRadius: 8)
                .fill(panel)
                .blur(radius: 6)
                .padding(.horizontal, 14)
                .padding(.top, 28)
                .padding(.bottom, 24)

            Text(notification.title + "\n" + notification.body)
                .font(Font(MoofNotificationLayout.hollowKnightFont))
                .lineSpacing(MoofNotificationLayout.hollowKnightLineSpacing)
                .lineLimit(MoofNotificationLayout.maxLines)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(ink)
                .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 44)
                .padding(.top, 64)

            // 4pt from the window edges so the ornament shadows are not clipped.
            Image("HollowKnightOrnamentTop")
                .resizable()
                .scaledToFit()
                .frame(width: 320)
                .foregroundStyle(ink)
                .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                .padding(.top, 4)

            Button(action: { close?() }) {
                ZStack {
                    bottomFleur.foregroundStyle(ink.opacity(0.25))
                    if let dismissState, dismissState.isCountingDown {
                        TimelineView(.animation) { context in
                            bottomFleur
                                .foregroundStyle(ink)
                                .mask {
                                    GeometryReader { proxy in
                                        Rectangle()
                                            .frame(width: proxy.size.width * dismissState.progress(at: context.date))
                                            .frame(maxWidth: .infinity)
                                    }
                                }
                        }
                    } else {
                        bottomFleur.foregroundStyle(ink)
                    }
                }
                .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help("Close")
            .padding(.bottom, 4)
            .frame(maxHeight: .infinity, alignment: .bottom)

            // Inside the panel, between the text (120pt from the bottom) and the bottom fleur
            // (41pt), inset 44pt like the text: the source on the left, the buttons on the right.
            HStack(alignment: .firstTextBaseline, spacing: 28) {
                if let source = notification.source {
                    Text(source)
                        .font(Font(MoofNotificationLayout.hollowKnightSourceFont))
                        .lineLimit(1)
                        .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                }
                Spacer(minLength: 0)
                if let action {
                    HollowKnightTextButton(title: notification.actionTitle, action: action)
                }
                HollowKnightTextButton(title: "Copy", action: copy)
            }
            .foregroundStyle(ink)
            .frame(maxHeight: .infinity, alignment: .bottom)
            .padding(.horizontal, 44)
            .padding(.bottom, 52)
            .opacity(isHovering ? 1 : 0)
            .allowsHitTesting(isHovering)
            .animation(.easeOut(duration: 0.15), value: isHovering)
        }
        .frame(width: size.width, height: size.height)
        // The action stays on its hover button.
        .contentShape(.rect)
        .onTapGesture { close?() }
    }
}

/// Serif text in the card's ink that shows a rounded-rectangle outline while the pointer is on it.
private struct HollowKnightTextButton: View {
    let title: String
    let action: (() -> Void)?

    @State private var isHovering = false

    var body: some View {
        Button(action: { action?() }) {
            Text(title)
                .font(.system(size: 16, design: .serif))
                .lineLimit(1)
                .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(.foreground, lineWidth: 1)
                        .opacity(isHovering ? 0.6 : 0)
                }
                .contentShape(.rect)
                // The outline extends past the label without moving it off the row's 44pt inset.
                .padding(.horizontal, -10)
                .padding(.vertical, -4)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
    }
}
