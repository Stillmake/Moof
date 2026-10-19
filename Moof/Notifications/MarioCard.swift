import SwiftUI

/// A Mario-game dialog box: a slanted dark box with diagonal stripes and a white border, a white
/// speaker tab growing out of its top-left edge, bold text, and a bouncing ▼ that closes the card.
/// A white bar along the bottom edge is the countdown. Style colors and icons are ignored.
struct MarioCard: View {
    let notification: MoofNotification
    var dismissState: MoofNotificationItem.DismissState?
    var close: (() -> Void)?
    var copy: (() -> Void)?
    var action: (() -> Void)?

    var body: some View {
        // Inset from the panel so the border and tab shadows are not clipped by the window.
        let shadowMargin: CGFloat = 6
        let size = MoofNotificationLayout(notification: notification).size
        let card = CGSize(width: size.width - shadowMargin * 2, height: size.height - shadowMargin * 2)
        let ink = notification.background.map { $0.isDark ? Color.white : Color.black } ?? .white
        let fill = notification.background.map { Color(nsColor: $0).opacity(0.75) } ?? Color.black.opacity(0.62)
        let box = MarioDialogShape(part: .box)
        ZStack(alignment: .topLeading) {
            ZStack(alignment: .bottomLeading) {
                box.fill(fill)
                Canvas { context, size in
                    var stripes = Path()
                    for x in stride(from: -size.height, to: size.width, by: 16) {
                        stripes.move(to: CGPoint(x: x, y: size.height))
                        stripes.addLine(to: CGPoint(x: x + size.height, y: 0))
                    }
                    context.stroke(stripes, with: .color(ink.opacity(0.05)), lineWidth: 6)
                }
                if let dismissState, dismissState.isCountingDown {
                    TimelineView(.animation) { context in
                        GeometryReader { proxy in
                            Rectangle()
                                .fill(ink.opacity(0.85))
                                .frame(width: proxy.size.width * dismissState.progress(at: context.date), height: 4)
                                .frame(maxHeight: .infinity, alignment: .bottom)
                        }
                    }
                }
            }
            .clipShape(box)
            // Shadows on the white border and tab only, so the translucent box stays clear on light content.
            .overlay(box.stroke(.white.opacity(0.92), lineWidth: 2.5).shadow(color: .black.opacity(0.3), radius: 3, y: 1))

            MarioDialogShape(part: .tab).fill(.white).shadow(color: .black.opacity(0.3), radius: 3, y: 1)

            // Centered on the tab's sheared midline.
            Text(notification.source ?? notification.style.title)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.black)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, 16)
                .frame(width: MarioDialogShape.tabWidth, height: MarioDialogShape.tabHeight)
                .offset(x: MarioDialogShape.slant * (card.height - MarioDialogShape.tabHeight) / 2 + card.height * MarioDialogShape.slant / 2)

            Text([notification.title, notification.message].compactMap(\.self).joined(separator: " "))
                .font(Font(MoofNotificationLayout.marioFont))
                .lineSpacing(MoofNotificationLayout.marioLineSpacing)
                .lineLimit(MoofNotificationLayout.maxLines)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .foregroundStyle(ink)
                .padding(.leading, 52)
                .padding(.trailing, 160)
                .padding(.top, MarioDialogShape.tabHeight + 30)

            Button(action: { close?() }) {
                TimelineView(.animation) { context in
                    Image(systemName: "arrowtriangle.down.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(ink)
                        .offset(y: sin(context.date.timeIntervalSinceReferenceDate * 5) * 2.5)
                }
                .frame(width: 28, height: 28)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help("Close")
            .padding(.trailing, 38)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        }
        .frame(width: card.width, height: card.height)
        .padding(shadowMargin)
        .contextMenu {
            if let action {
                Button(notification.actionTitle, systemImage: "arrow.up.forward.app", action: action)
            }
            Button("Copy", systemImage: "doc.on.doc") { copy?() }
            Button("Close", systemImage: "xmark") { close?() }
        }
    }
}

/// The box and its speaker tab, both sheared by one transform over the whole card so the tab's
/// left edge continues the box's. The box's top-left corner is square and the tab sits flush on it,
/// overlapping only the border line.
private struct MarioDialogShape: Shape {
    enum Part { case box, tab }

    static let slant: CGFloat = 0.075
    static let tabWidth: CGFloat = 200
    static let tabHeight: CGFloat = 34

    let part: Part

    func path(in rect: CGRect) -> Path {
        let base = rect.insetBy(dx: rect.height * Self.slant / 2, dy: 0)
        let path =
            switch part {
            case .box:
                UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 10, bottomTrailingRadius: 10, topTrailingRadius: 10)
                    .path(in: CGRect(x: base.minX, y: base.minY + Self.tabHeight, width: base.width, height: base.height - Self.tabHeight))
            case .tab:
                UnevenRoundedRectangle(topLeadingRadius: 7, topTrailingRadius: 7)
                    .path(in: CGRect(x: base.minX - 1.25, y: base.minY, width: Self.tabWidth, height: Self.tabHeight + 1.25))
            }
        return path.applying(CGAffineTransform(a: 1, b: 0, c: -Self.slant, d: 1, tx: Self.slant * rect.midY, ty: 0))
    }
}
