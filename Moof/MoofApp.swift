import SwiftUI

@main
struct MoofApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
        } label: {
            Image(systemName: "bell.and.waves.left.and.right.fill")
        }

        Settings {
            SettingsView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            guard let command = MoofCommand(url: url) else { continue }
            MoofNotificationCenter.shared.handle(command)
        }
    }
}

struct MenuBarView: View {
    private let center = MoofNotificationCenter.shared

    var body: some View {
        Menu("Send Test") {
            ForEach(MoofNotification.Style.allCases, id: \.self) { style in
                Button(style.title) {
                    let url = URL(string: "moof://notify?title=Moof%20Test&body=This%20is%20a%20\(style.rawValue)%20alert.&style=\(style.rawValue)&source=Moof")
                    guard let url, let command = MoofCommand(url: url) else {
                        assertionFailure("Test URL should parse.")
                        return
                    }
                    center.handle(command)
                }
            }
        }
        Button("Dismiss All") { center.handle(.dismissAll) }
            .disabled(center.items.isEmpty)
        Divider()
        SettingsLink { Text("Settings…") }
            .keyboardShortcut(",")
        Button("Quit Moof") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}

struct SettingsView: View {
    @Bindable private var preferences = MoofPreferences.shared

    var body: some View {
        Form {
            Section("Floating Card") {
                Stepper(value: $preferences.standardDismissDelay, in: 0...3_600) {
                    LabeledContent("Info / success dismiss", value: preferences.standardDismissDelay == 0 ? "Never" : "\(preferences.standardDismissDelay)s")
                }
                Stepper(value: $preferences.alertDismissDelay, in: 0...3_600) {
                    LabeledContent("Warning / error dismiss", value: preferences.alertDismissDelay == 0 ? "Never" : "\(preferences.alertDismissDelay)s")
                }
                Stepper(value: $preferences.defaultHeightLevel, in: MoofNotificationLayout.heightRange) {
                    LabeledContent("Default height", value: "Level \(preferences.defaultHeightLevel)")
                }
            }

            Section("URL Scheme") {
                Text(
                    """
                    moof://notify?title=…&body=…&subtitle=…&source=…
                      style=info|success|warning|error|critical
                      background=<hex>     custom card color
                      id=<string>          same id replaces the card
                      duration=<seconds>   0 or sticky=1 keeps it
                      height=1…8  sound=<NSSound name>
                      action=<url>  actionTitle=…
                    moof://dismiss?id=<string>
                    moof://dismiss-all
                    """
                )
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
    }
}
