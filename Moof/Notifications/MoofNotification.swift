import AppKit
import SwiftUI

enum MoofTheme: String, CaseIterable {
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
    enum Style: String, CaseIterable {
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
    let subtitle: String?
    let message: String?
    let source: String?
    let style: Style
    let theme: MoofTheme
    /// Custom card color; the foreground then follows its `isDark`.
    let background: NSColor?
    /// `nil` falls back to the per-style preference; `0` keeps the card until dismissed.
    let duration: TimeInterval?
    let sound: NSSound.Name?
    let action: URL?
    let actionTitle: String
    let createdAt = Date()

    var keepsVisibleUntilDismissed: Bool {
        style == .critical || duration == 0
    }
}

enum MoofCommand {
    case notify(MoofNotification)
    case dismiss(id: String)
    case dismissAll

    init?(url: URL) {
        guard url.scheme?.lowercased() == "moof",
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return nil }

        var query: [String: String] = [:]
        for item in components.queryItems ?? [] {
            query[item.name.lowercased()] = item.value
        }

        func text(_ key: String) -> String? {
            query[key].flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
        }

        switch url.host?.lowercased() {
        case "notify":
            let style = MoofNotification.Style(rawValue: text("style")?.lowercased() ?? MoofNotification.Style.info.rawValue)
            assert(style != nil, "Unknown moof style \(query["style"] ?? ""); using info.")
            let theme = MoofTheme(rawValue: text("theme")?.lowercased() ?? MoofPreferences.shared.theme.rawValue)
            assert(theme != nil, "Unknown moof theme \(query["theme"] ?? ""); using the preference.")
            self = .notify(
                MoofNotification(
                    id: text("id") ?? UUID().uuidString,
                    title: text("title") ?? "Moof",
                    subtitle: text("subtitle"),
                    message: text("body") ?? text("message"),
                    source: text("source"),
                    style: style ?? .info,
                    theme: theme ?? MoofPreferences.shared.theme,
                    background: text("background").map(NSColor.init(hex:)),
                    duration: text("duration").flatMap(TimeInterval.init).map { min(max($0, 0), 3_600) },
                    sound: text("sound").map { NSSound.Name($0) },
                    action: text("action").flatMap(URL.init(string:)),
                    actionTitle: text("actiontitle") ?? "Open"
                )
            )
        case "dismiss":
            guard let id = text("id") else {
                assertionFailure("moof://dismiss requires an id.")
                return nil
            }
            self = .dismiss(id: id)
        case "dismiss-all", "clear":
            self = .dismissAll
        default:
            assertionFailure("Unknown moof command \(url.absoluteString).")
            return nil
        }
    }
}

/// Panel sizes: each theme's fixed chrome plus its text measured with TextKit, at most `maxLines`
/// lines. The cards draw the text with the same `NSFont`s, line spacing and kerning.
struct MoofNotificationLayout {
    static let maxLines = 4

    static let panelWidth: CGFloat = 540
    static let cardPadding: CGFloat = 14
    static let cardSpacing: CGFloat = 10
    static let headerHeight: CGFloat = 38
    static let iconSize: CGFloat = 30
    static let bottomBarHeight: CGFloat = 26
    static let messageFont = NSFont.monospacedSystemFont(ofSize: NSFont.preferredFont(forTextStyle: .caption1).pointSize, weight: .regular)

    static let eldenRingTitleFont = serif(size: 18)
    static let eldenRingMessageFont = serif(size: 13)
    static let marioFont = NSFont.systemFont(ofSize: 26, weight: .semibold)
    static let marioLineSpacing: CGFloat = 14
    static let hollowKnightFont = serif(size: 20)
    static let hollowKnightLineSpacing: CGFloat = 6

    let size: CGSize

    init(notification: MoofNotification) {
        let paragraph = [notification.title, notification.message].compactMap(\.self).joined(separator: " ")
        switch notification.theme {
        case .standard:
            // Message box: 6pt vertical and 8pt horizontal padding inside the card padding.
            let message = notification.message.map {
                Self.textHeight($0, font: Self.messageFont, width: Self.panelWidth - Self.cardPadding * 2 - 16) + 12 + Self.cardSpacing
            }
            size = CGSize(width: Self.panelWidth, height: Self.cardPadding * 2 + Self.headerHeight + Self.cardSpacing + (message ?? 0) + Self.bottomBarHeight)
        case .eldenRing:
            // 120pt side margins, 36pt above and below the text, then the divider and the 46pt prompt row.
            let title = Self.textHeight(notification.title, font: Self.eldenRingTitleFont, width: 520, kern: 1.4, maxLines: 1)
            let message = notification.message.map {
                10 + Self.textHeight($0, font: Self.eldenRingMessageFont, width: 520, kern: 0.6, maxLines: Self.maxLines - 1)
            }
            size = CGSize(width: 760, height: 36 + title + (message ?? 0) + 36 + 1 + 46)
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
