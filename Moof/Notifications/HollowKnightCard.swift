import SwiftUI

/// A Hollow Knight dialog: a dark, soft-edged panel with serif text, a fleur ornament straddling
/// its top edge and a smaller one on its bottom edge. The bottom fleur is the countdown, its lit
/// part shrinking toward the center. Clicking anywhere on the card closes it. On hover, serif Copy and
/// action buttons appear inside the panel above it, and the source left of the top fleur. Style
/// colors and icons are ignored.
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

            // Inside the panel's top margin, clear of the 320pt top fleur.
            if let source = notification.source {
                Text(source)
                    .font(Font(MoofNotificationLayout.hollowKnightSourceFont))
                    .lineLimit(1)
                    .foregroundStyle(ink)
                    .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                    .frame(maxWidth: 140, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 44)
                    .padding(.top, 36)
                    .opacity(isHovering ? 1 : 0)
                    .animation(.easeOut(duration: 0.15), value: isHovering)
            }

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
            // (41pt), right-aligned with the text's 44pt inset.
            HStack(spacing: 28) {
                if let action {
                    textButton(notification.actionTitle, action)
                }
                textButton("Copy", copy)
            }
            .foregroundStyle(ink)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .padding(.trailing, 44)
            .padding(.bottom, 52)
            .opacity(isHovering ? 1 : 0)
            .allowsHitTesting(isHovering)
            .animation(.easeOut(duration: 0.15), value: isHovering)
        }
        .frame(width: size.width, height: size.height)
        // Takes the tap before the outer card's action tap; the action stays on its hover button.
        .contentShape(.rect)
        .onTapGesture { close?() }
    }

    private func textButton(_ title: String, _ action: (() -> Void)?) -> some View {
        Button(action: { action?() }) {
            Text(title)
                .font(.system(size: 16, design: .serif))
                .lineLimit(1)
                .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}
