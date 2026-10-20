import AppKit
import SwiftUI

enum MoofTheme: String, CaseIterable, Codable {
    case standard = "default"
    case eldenRing = "elden-ring"
    case mario
    case hollowKnight = "hollow-knight"

    var title: String {
        switch self {
        case .standard: "Default"
        case .eldenRing: "Elden Ring"
        case .mario: "Mario"
        case .hollowKnight: "Hollow Knight"
        }
    }
}

/// `moof://notify?title=…` payload. A repeated `id` replaces the card that is already on screen.
struct MoofNotification: Identifiable {
    enum Style: String, CaseIterable, Codable {
        case info, success, warning, error, critical

        var tint: Color {
            switch self {
            case .info: Color(nsColor: .systemBlue)
            case .success: Color(nsColor: .systemGreen)
            case .warning: Color(nsColor: .systemOrange)
            case .error, .critical: Color(nsColor: .systemRed)
            }
        }

        var symbol: String {
            switch self {
            case .info: "info.circle.fill"
            case .success: "checkmark.circle.fill"
            case .warning: "exclamationmark.triangle.fill"
            case .error: "xmark.circle.fill"
            case .critical: "bell.badge.fill"
            }
        }

        var title: String {
            switch self {
            case .info: "Info"
            case .success: "Success"
            case .warning: "Warning"
            case .error: "Error"
            case .critical: "Critical"
            }
        }

        var isAlert: Bool {
            self == .warning || self == .error || self == .critical
        }
    }

    let id: String
    let title: String
    let body: String
    let source: String?
    let style: Style
    let theme: MoofTheme
    /// Custom card color; the foreground then follows its `isDark`.
    let background: NSColor?
    /// `nil` falls back to the per-style preference; `0` keeps the card until dismissed.
    let duration: TimeInterval?
    let action: URL?
    let actionTitle: String
    /// Set on arrival; decoding restores the original time.
    var createdAt = Date()

    /// An id for a card whose sender gave none: 8 random uppercase hex digits. Ids only need to
    /// be unique among the few cards on screen, and stay short enough to type in `moof dismiss`.
    static func newID() -> String {
        String(format: "%08X", UInt32.random(in: .min ... .max))
    }
}

/// Encodes `background` as an sRGB hex string, the form `moof://notify` accepts.
extension MoofNotification: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, title, body, source, style, theme, background, duration, action, actionTitle, createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        body = try container.decode(String.self, forKey: .body)
        source = try container.decodeIfPresent(String.self, forKey: .source)
        style = try container.decode(Style.self, forKey: .style)
        theme = try container.decode(MoofTheme.self, forKey: .theme)
        background = try container.decodeIfPresent(String.self, forKey: .background).map(NSColor.init(hex:))
        duration = try container.decodeIfPresent(TimeInterval.self, forKey: .duration)
        action = try container.decodeIfPresent(URL.self, forKey: .action)
        actionTitle = try container.decode(String.self, forKey: .actionTitle)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(body, forKey: .body)
        try container.encodeIfPresent(source, forKey: .source)
        try container.encode(style, forKey: .style)
        try container.encode(theme, forKey: .theme)
        try container.encodeIfPresent(
            background.flatMap { $0.usingColorSpace(.sRGB) }.map {
                String(format: "%02X%02X%02X", Int(($0.redComponent * 255).rounded()), Int(($0.greenComponent * 255).rounded()), Int(($0.blueComponent * 255).rounded()))
            },
            forKey: .background
        )
        try container.encodeIfPresent(duration, forKey: .duration)
        try container.encodeIfPresent(action, forKey: .action)
        try container.encode(actionTitle, forKey: .actionTitle)
        try container.encode(createdAt, forKey: .createdAt)
    }
}

enum MoofCommand {
    case notify(MoofNotification)
    case dismiss(id: String)

    /// Why a `moof://` URL was rejected, in words the CLI prints as is.
    struct Failure: Error {
        let message: String
    }

    init(url: URL) throws {
        guard url.scheme?.lowercased() == "moof",
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { throw Failure(message: "not a moof:// URL: \(url.absoluteString)") }

        var query: [String: String] = [:]
        for item in components.queryItems ?? [] {
            query[item.name.lowercased()] = item.value
        }

        func text(_ key: String) -> String? {
            query[key].flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
        }

        switch url.host?.lowercased() {
        case "notify":
            guard let body = text("body") else { throw Failure(message: "notify requires a body") }
            let style = try text("style").map {
                guard let style = MoofNotification.Style(rawValue: $0.lowercased()) else {
                    throw Failure(message: "unknown style '\($0)'; use info, success, warning, error or critical")
                }
                return style
            }
            let theme = try text("theme").map {
                guard let theme = MoofTheme(rawValue: $0.lowercased()) else {
                    throw Failure(message: "unknown theme '\($0)'; use default, elden-ring, mario or hollow-knight")
                }
                return theme
            }
            let background = try text("background").map {
                guard $0.wholeMatch(of: /#?([0-9a-fA-F]{3}|[0-9a-fA-F]{6})/) != nil else {
                    throw Failure(message: "background '\($0)' is not a 3- or 6-digit hex color")
                }
                return NSColor(hex: $0)
            }
            let duration = try text("duration").map {
                guard let seconds = TimeInterval($0), (0...3_600).contains(seconds) else {
                    throw Failure(message: "duration '\($0)' must be 0 to 3600 seconds")
                }
                return seconds
            }
            let action = try text("action").map {
                guard let action = URL(string: $0), action.scheme != nil else {
                    throw Failure(message: "action '\($0)' is not a URL with a scheme")
                }
                return action
            }
            self = .notify(
                MoofNotification(
                    id: text("id") ?? MoofNotification.newID(),
                    title: text("title") ?? "Moof",
                    body: body,
                    source: text("source"),
                    style: style ?? .info,
                    theme: theme ?? MoofPreferences.shared.theme,
                    background: background,
                    duration: duration,
                    action: action,
                    actionTitle: text("actiontitle") ?? "Open"
                )
            )
        case "dismiss":
            guard let id = text("id") else { throw Failure(message: "dismiss requires an id") }
            self = .dismiss(id: id)
        default:
            throw Failure(message: "unknown command '\(url.host ?? "")'; use notify or dismiss")
        }
    }
}

/// Panel sizes: each theme's fixed chrome plus its text measured with TextKit, at most `maxLines`
/// lines. The cards draw the text with the same `NSFont`s, line spacing and kerning.
struct MoofNotificationLayout {
    static let maxLines = 4

    static let panelWidth: CGFloat = 540
    /// Transparent window margin around the default card, room for its glass shadow.
    static let glassShadowMargin: CGFloat = 32
    static let cardPadding: CGFloat = 14
    static let cardSpacing: CGFloat = 10
    static let headerHeight: CGFloat = 24
    static let bottomBarHeight: CGFloat = 26
    static let messageFont = NSFont.systemFont(ofSize: 13)

    static let eldenRingTitleFont = serif(size: 20)
    static let eldenRingMessageFont = serif(size: 13)
    static let eldenRingSourceFont = serif(size: 11)
    static let marioFont = NSFont.systemFont(ofSize: 26, weight: .semibold)
    static let marioLineSpacing: CGFloat = 14
    static let hollowKnightFont = serif(size: 20)
    static let hollowKnightLineSpacing: CGFloat = 6
    static let hollowKnightSourceFont = serif(size: 14)

    let size: CGSize

    init(notification: MoofNotification) {
        let paragraph = notification.title + "\n" + notification.body
        switch notification.theme {
        case .standard:
            // Body box: 6pt vertical and 8pt horizontal padding inside the card padding.
            let body = Self.textHeight(notification.body, font: Self.messageFont, width: Self.panelWidth - Self.cardPadding * 2 - 16) + 12
            size = CGSize(width: Self.panelWidth, height: Self.cardPadding * 2 + Self.headerHeight + Self.cardSpacing + body + Self.cardSpacing + Self.bottomBarHeight)
        case .eldenRing:
            // 120pt side margins, 36pt above and below the text, then the divider and the 46pt prompt row.
            let title = Self.textHeight(notification.title, font: Self.eldenRingTitleFont, width: 520, kern: 0.3, maxLines: 1)
            let body = Self.textHeight(notification.body, font: Self.eldenRingMessageFont, width: 520, kern: 0.6, maxLines: Self.maxLines - 1)
            size = CGSize(width: 760, height: 36 + title + 10 + body + 36 + 1 + 46)
        case .mario:
            // 6pt shadow margins, the 34pt tab, 30pt above the text and 52pt below it for the ▼.
            let text = Self.textHeight(paragraph, font: Self.marioFont, width: 720 - 52 - 160, lineSpacing: Self.marioLineSpacing)
            size = CGSize(width: 732, height: 12 + 34 + 30 + text + 52)
        case .hollowKnight:
            // 64pt down to the text under the top fleur, 120pt below it for the panel and bottom fleur.
            let text = Self.textHeight(paragraph, font: Self.hollowKnightFont, width: 720 - 88, lineSpacing: Self.hollowKnightLineSpacing)
            size = CGSize(width: 720, height: 64 + text + 120)
        }
    }

    static func textHeight(_ string: String, font: NSFont, width: CGFloat, lineSpacing: CGFloat = 0, kern: CGFloat = 0, maxLines: Int = maxLines) -> CGFloat {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = lineSpacing
        let storage = NSTextStorage(string: string, attributes: [.font: font, .kern: kern, .paragraphStyle: paragraphStyle])
        let container = NSTextContainer(size: CGSize(width: width, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        container.maximumNumberOfLines = maxLines
        let manager = NSLayoutManager()
        manager.addTextContainer(container)
        storage.addLayoutManager(manager)
        // Layout is lazy; `usedRect` alone reports zero.
        manager.ensureLayout(for: container)
        return ceil(manager.usedRect(for: container).height)
    }

    private static func serif(size: CGFloat) -> NSFont {
        let descriptor = NSFont.systemFont(ofSize: size).fontDescriptor.withDesign(.serif)
        assert(descriptor != nil, "The system serif design should exist; using the default design.")
        return descriptor.flatMap { NSFont(descriptor: $0, size: size) } ?? .systemFont(ofSize: size)
    }
}
