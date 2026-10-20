import ServiceManagement
import SwiftUI

@main
struct MoofApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    static let cliReference = """
        moof notify --title <text> --body <text> [--source <text>]
          --style info|success|warning|error|critical
          --theme default|elden-ring|mario|hollow-knight
          --background <hex>     custom card color; text adapts to it
          --id <string>          same id replaces the card on screen
          --duration <seconds>   0 keeps it until dismissed
          --sound <NSSound name>  text over 4 lines ends with …
          --action <url>  --actionTitle <text>
        moof dismiss --id <string>
        moof dismiss-all
        """

    /// Run as the `moof` CLI (`moof notify --title Hi --duration 0`): forward each `--key value`
    /// pair as a `moof://` URL query item to the app and exit before any scene starts. Invoked
    /// through the `moof` symlink it never starts the app UI, even without a command.
    init() {
        let commands = ["notify", "dismiss", "dismiss-all", "clear"]
        let arguments = CommandLine.arguments.dropFirst()
        let isSymlinkInvocation = URL(fileURLWithPath: CommandLine.arguments[0]).lastPathComponent == "moof"
        guard isSymlinkInvocation || arguments.first.map(commands.contains) == true else { return }
        guard let command = arguments.first else {
            print(
                "moof — show a floating Moof notification card.\n\nUsage: moof notify --title <text> [options]\n       moof dismiss --id <string>\n       moof dismiss-all\n\nRun `moof --help` for all options."
            )
            exit(0)
        }
        if ["-h", "--help", "help"].contains(command) {
            print("moof — show a floating Moof notification card.\n\n\(Self.cliReference)\n\nExample: moof notify --title \"Build done\" --body \"All green\" --style success")
            exit(0)
        }
        guard commands.contains(command) else {
            FileHandle.standardError.write(Data("moof: unknown command '\(command)'. Run `moof --help`.\n".utf8))
            exit(2)
        }
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+?#")
        var rest = arguments.dropFirst()
        var items: [URLQueryItem] = []
        while let argument = rest.popFirst() {
            guard argument.hasPrefix("--"), argument.count > 2, let value = rest.popFirst() else {
                FileHandle.standardError.write(Data("moof: expected --<key> <value>, got \(argument)\n".utf8))
                exit(2)
            }
            items.append(URLQueryItem(name: String(argument.dropFirst(2)), value: value.addingPercentEncoding(withAllowedCharacters: allowed)))
        }
        var components = URLComponents()
        components.scheme = "moof"
        components.host = command
        components.percentEncodedQueryItems = items.isEmpty ? nil : items
        guard let url = components.url else {
            FileHandle.standardError.write(Data("moof: could not build a URL\n".utf8))
            exit(2)
        }
        let open = Process()
        open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        open.arguments = ["-g", url.absoluteString]
        do {
            try open.run()
        } catch {
            FileHandle.standardError.write(Data("moof: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
        open.waitUntilExit()
        exit(open.terminationStatus)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
        } label: {
            Image(systemName: "dog.fill")
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
    @Bindable private var preferences = MoofPreferences.shared
    @State private var isCLIInstalled = Self.cliLinksThisBuild

    private static var cliLinksThisBuild: Bool {
        (try? FileManager.default.destinationOfSymbolicLink(atPath: "/usr/local/bin/moof")) == Bundle.main.executablePath
    }
    @State private var opensAtLogin = SMAppService.mainApp.status == .enabled
    private let center = MoofNotificationCenter.shared

    var body: some View {
        let dismissDelays = [0, 3, 5, 10, 30, 60, 300]
        Group {
            Menu("Preview", systemImage: "eye") {
                ForEach(MoofNotification.Style.allCases, id: \.self) { style in
                    Button(style.title, systemImage: style.symbol) { showPreview(style) }
                }
            }
            Button("Dismiss All", systemImage: "xmark.circle") { center.handle(.dismissAll) }
                .disabled(center.items.isEmpty)
            #if DEBUG
            Button("Preview All", systemImage: "rectangle.stack") {
                Task {
                    for style in MoofNotification.Style.allCases {
                        showPreview(style)
                        try? await Task.sleep(for: .seconds(0.5))
                    }
                }
            }
            #endif
            Divider()
            Picker("Theme", systemImage: "paintpalette", selection: $preferences.theme) {
                ForEach(MoofTheme.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            Picker("Info / Success Dismiss", systemImage: "timer", selection: $preferences.standardDismissDelay) {
                ForEach(dismissDelays, id: \.self) { Text($0 == 0 ? "Never" : "\($0)s").tag($0) }
            }
            Picker("Warning / Error Dismiss", systemImage: "exclamationmark.triangle", selection: $preferences.alertDismissDelay) {
                ForEach(dismissDelays, id: \.self) { Text($0 == 0 ? "Never" : "\($0)s").tag($0) }
            }
            Divider()
            Button("Open at Login", systemImage: "power.circle") {
                do {
                    try opensAtLogin ? SMAppService.mainApp.unregister() : SMAppService.mainApp.register()
                } catch {
                    assertionFailure("Open at Login failed: \(error)")
                }
                opensAtLogin = SMAppService.mainApp.status == .enabled
            }
            .badge(opensAtLogin ? Text("✓") : nil)
            // Links /usr/local/bin/moof to this build's executable, which `MoofApp.init()` runs as the CLI.
            Button("Command Line Tool…", systemImage: "terminal") {
                guard let executable = Bundle.main.executablePath, !executable.contains("\"") else {
                    assertionFailure("Executable path is missing or contains a quote.")
                    return
                }
                let script = "do shell script \"mkdir -p /usr/local/bin && ln -sf \" & quoted form of \"\(executable)\" & \" /usr/local/bin/moof\" with administrator privileges"
                var error: NSDictionary?
                NSAppleScript(source: script)?.executeAndReturnError(&error)
                var components = URLComponents(string: "moof://notify?source=Moof")!
                components.queryItems! +=
                    error.map {
                        [
                            URLQueryItem(name: "title", value: "Install failed"), URLQueryItem(name: "body", value: "\($0[NSAppleScript.errorMessage] ?? "Unknown error")"),
                            URLQueryItem(name: "style", value: "error"),
                        ]
                    } ?? [
                        URLQueryItem(name: "title", value: "moof installed"), URLQueryItem(name: "body", value: "/usr/local/bin/moof → \(executable)"), URLQueryItem(name: "style", value: "success"),
                    ]
                guard let url = components.url, let command = MoofCommand(url: url) else {
                    assertionFailure("Install result URL should parse.")
                    return
                }
                center.handle(command)
                if error == nil { isCLIInstalled = true }
            }
            .badge(isCLIInstalled ? Text("✓") : nil)
            Button("Copy Prompt", systemImage: "doc.on.clipboard") {
                isCLIInstalled = Self.cliLinksThisBuild
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(
                    isCLIInstalled
                        ? "To notify me on macOS, run the `moof` command:\n\(MoofApp.cliReference)"
                        : """
                        To notify me on macOS, run `open -g "<url>"` with one of these Moof URLs (URL-encode values):
                        moof://notify?title=<text>&body=<text>[&source=<text>]
                          &style=info|success|warning|error|critical
                          &theme=default|elden-ring|mario|hollow-knight
                          &background=<hex>      custom card color; text adapts to it
                          &id=<string>           same id replaces the card on screen
                          &duration=<seconds>    0 keeps it until dismissed
                          &sound=<NSSound name>  text over 4 lines ends with …
                          &action=<url>  &actionTitle=<text>
                        moof://dismiss?id=<string>
                        moof://dismiss-all
                        """,
                    forType: .string
                )
            }
            Divider()
            Button("Quit Moof", systemImage: "xmark.rectangle") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
        .labelStyle(.titleAndIcon)
    }

    private func showPreview(_ style: MoofNotification.Style) {
        let url = URL(
            string:
                "moof://notify?title=Moof%20Test&body=This%20is%20a%20\(style.rawValue)%20alert.&style=\(style.rawValue)&source=Moof&action=https%3A%2F%2Fgithub.com%2FStillmake%2FMoof&actionTitle=GitHub"
        )
        guard let url, let command = MoofCommand(url: url) else {
            assertionFailure("Test URL should parse.")
            return
        }
        center.handle(command)
    }
}
