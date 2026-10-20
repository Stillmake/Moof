import SwiftUI

/// The in-game message band: a dark translucent strip rimmed by needle hairlines, centered serif
/// text, a needle divider, and gamepad-style prompts. The divider doubles as the countdown,
/// its lit span shrinking toward the center. The source shows at the prompt row's leading edge on
/// hover. Style colors and icons are ignored.
struct EldenRingCard: View {
    let notification: MoofNotification
    var dismissState: MoofNotificationItem.DismissState?
    var isHovering = false
    var close: (() -> Void)?
    var copy: (() -> Void)?
    var action: (() -> Void)?

    private static let ivory = Color(red: 0.94, green: 0.93, blue: 0.88)
    private static let gold = Color(red: 0.74, green: 0.64, blue: 0.42)
    private static let needle = Color(red: 0.94, green: 0.93, blue: 0.83)

    var body: some View {
        let size = MoofNotificationLayout(notification: notification).size
        let ink = notification.background.map { $0.isDark ? Self.ivory : Color.black } ?? Self.ivory
        let band = notification.background.map(Color.init(nsColor:)) ?? Color(red: 0.2, green: 0.195, blue: 0.178)
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                Text(notification.title)
                    .font(Font(MoofNotificationLayout.eldenRingTitleFont))
                    .kerning(0.3)
                    .lineLimit(1)
                    .fixedSize(horizontal: false, vertical: true)
                Text(notification.body)
                    .font(Font(MoofNotificationLayout.eldenRingMessageFont))
                    .kerning(0.6)
                    .opacity(0.72)
                    .lineLimit(MoofNotificationLayout.maxLines - 1)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 120)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            ZStack {
                EldenRingNeedle().fill(Self.needle.opacity(0.35))
                if let dismissState, dismissState.isCountingDown {
                    TimelineView(.animation) { context in
                        GeometryReader { proxy in
                            EldenRingNeedle()
                                .fill(Self.needle.opacity(0.85))
                                .frame(width: proxy.size.width * dismissState.progress(at: context.date))
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            .frame(height: 2)
            .padding(.horizontal, 12)

            HStack(spacing: 14) {
                if let action {
                    prompt("A", notification.actionTitle, action)
                }
                prompt("X", "Copy", copy)
                prompt("Y", "Close", close)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .overlay(alignment: .leading) {
                if let source = notification.source {
                    Text(source.uppercased())
                        .font(Font(MoofNotificationLayout.eldenRingSourceFont))
                        .kerning(2)
                        .lineLimit(1)
                        .foregroundStyle(Self.gold)
                        // Clear of the band's 4% edge fade and of the centered prompts.
                        .frame(maxWidth: 180, alignment: .leading)
                        .padding(.leading, 32)
                        .opacity(isHovering ? 1 : 0)
                        .animation(.easeOut(duration: 0.15), value: isHovering)
                }
            }
        }
        .foregroundStyle(ink)
        .shadow(color: .black.opacity(0.5), radius: 1, y: 0.5)
        .frame(width: size.width, height: size.height)
        .background {
            // Needle hairlines on the top and bottom rims, each casting a soft glow inward.
            ZStack {
                band.opacity(0.85)
                // Glow falloffs sampled from the in-game panel: a near-exponential decay from each rim.
                VStack(spacing: 0) {
                    LinearGradient(
                        stops: [
                            .init(color: Self.needle.opacity(0.6), location: 0),
                            .init(color: Self.needle.opacity(0.42), location: 0.17),
                            .init(color: Self.needle.opacity(0.28), location: 0.33),
                            .init(color: Self.needle.opacity(0.17), location: 0.5),
                            .init(color: Self.needle.opacity(0.09), location: 0.67),
                            .init(color: Self.needle.opacity(0.03), location: 0.83),
                            .init(color: .clear, location: 1),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 6)
                    Spacer(minLength: 0)
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: Self.needle.opacity(0.03), location: 0.14),
                            .init(color: Self.needle.opacity(0.07), location: 0.29),
                            .init(color: Self.needle.opacity(0.16), location: 0.43),
                            .init(color: Self.needle.opacity(0.28), location: 0.57),
                            .init(color: Self.needle.opacity(0.44), location: 0.71),
                            .init(color: Self.needle.opacity(0.6), location: 0.86),
                            .init(color: Self.needle.opacity(0.7), location: 1),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 7)
                }
                VStack(spacing: 0) {
                    EldenRingNeedle().fill(Self.needle.opacity(0.85)).frame(height: 1.5)
                    Spacer(minLength: 0)
                    EldenRingNeedle().fill(Self.needle.opacity(0.75)).frame(height: 1.5)
                }
            }
            .mask(
                LinearGradient(
                    stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.04), .init(color: .black, location: 0.96), .init(color: .clear, location: 1)], startPoint: .leading,
                    endPoint: .trailing))
        }
    }

    private func prompt(_ key: String, _ title: String, _ action: (() -> Void)?) -> some View {
        Button(action: { action?() }) {
            HStack(spacing: 3) {
                // Text centers its line box and advance, not its ink; draw the outline centered by its bounds.
                EldenRingGlyph(character: key, size: 13)
                    .fill(Self.gold)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(.black.opacity(0.35)))
                    .overlay(Circle().stroke(Self.gold, lineWidth: 1.8))
                Text(":\(title)")
                    .font(.system(size: 17, design: .serif))
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

/// A horizontal hairline that swells to full thickness quickly and tapers to points at both ends.
private struct EldenRingNeedle: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addQuadCurve(to: CGPoint(x: rect.midX, y: rect.minY), control: CGPoint(x: rect.minX + rect.width * 0.1, y: rect.minY))
            path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.midY), control: CGPoint(x: rect.maxX - rect.width * 0.1, y: rect.minY))
            path.addQuadCurve(to: CGPoint(x: rect.midX, y: rect.maxY), control: CGPoint(x: rect.maxX - rect.width * 0.1, y: rect.maxY))
            path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.midY), control: CGPoint(x: rect.minX + rect.width * 0.1, y: rect.maxY))
        }
    }
}

/// A single semibold serif character's outline, its ink bounds centered in the rect.
private struct EldenRingGlyph: Shape {
    let character: String
    let size: CGFloat

    func path(in rect: CGRect) -> Path {
        let font = NSFont(descriptor: NSFont.systemFont(ofSize: size, weight: .semibold).fontDescriptor.withDesign(.serif)!, size: size)!
        var glyph = CGGlyph()
        let found = CTFontGetGlyphsForCharacters(font, Array(character.utf16), &glyph, 1)
        assert(found, "No glyph for \(character) in \(font.fontName).")
        guard let outline = CTFontCreatePathForGlyph(font, glyph, nil) else { return Path() }
        let bounds = outline.boundingBoxOfPath
        // Core Text outlines are y-up; flip, then move the ink center onto the rect center.
        let transform = CGAffineTransform(translationX: rect.midX - bounds.midX, y: rect.midY + bounds.midY).scaledBy(x: 1, y: -1)
        return Path(outline.copy(using: [transform]) ?? outline)
    }
}
