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
    let heightLevel: Int
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
            let height = text("height").flatMap(Int.init) ?? MoofPreferences.shared.defaultHeightLevel
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
                    heightLevel: min(max(height, MoofNotificationLayout.heightRange.lowerBound), MoofNotificationLayout.heightRange.upperBound),
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

struct MoofNotificationLayout {
    static let panelWidth: CGFloat = 540
    static let heightRange = 1...8

    let cardPadding: CGFloat = 14
    let cardSpacing: CGFloat = 10
    let headerHeight: CGFloat = 38
    let iconSize: CGFloat = 30
    let messageRowHeight: CGFloat
    let showsMessage: Bool
    let bottomBarHeight: CGFloat = 26
    let theme: MoofTheme

    init(notification: MoofNotification) {
        messageRowHeight = 25 + CGFloat(notification.heightLevel) * 28
        showsMessage = notification.message != nil
        theme = notification.theme
    }

    var panelHeight: CGFloat {
        ceil(cardPadding * 2 + headerHeight + cardSpacing + (showsMessage ? messageRowHeight + cardSpacing : 0) + bottomBarHeight)
    }

    /// Game themes are fixed boxes that ignore the height level.
    var size: CGSize {
        switch theme {
        case .standard: CGSize(width: Self.panelWidth, height: panelHeight)
        case .eldenRing: CGSize(width: 760, height: showsMessage ? 172 : 140)
        case .mario: CGSize(width: 732, height: 212)
        case .hollowKnight: CGSize(width: 720, height: 244)
        }
    }
}
