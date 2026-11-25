import AppKit
import SwiftUI

private let windowSize = NSSize(width: 460, height: 420)

@MainActor
final class MoofTelegramWindowController: NSWindowController, NSWindowDelegate {
    static let shared = MoofTelegramWindowController()

    private init() {
        let contentSize = windowSize
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Telegram"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        window.contentViewController = NSHostingController(
            rootView: MoofTelegramView(
                telegram: .shared,
                close: { [weak self] in self?.window?.close() }
            )
        )
        window.contentMinSize = contentSize
        window.contentMaxSize = contentSize
        if !window.setFrameUsingName("MoofTelegramWindow") {
            window.center()
        }
        window.setFrameAutosaveName("MoofTelegramWindow")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func present() {
        window?.deminiaturize(nil)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        MoofTelegram.shared.cancelPairing()
    }
}

private struct MoofTelegramView: View {
    @Bindable var telegram: MoofTelegram
    let close: () -> Void

    @State private var token = ""
    @State private var confirmsDisconnect = false

    var header: some View {
        HStack(spacing: 12) {
            Image(systemName: telegram.isConnected ? "checkmark.circle.fill" : "paperplane.circle.fill")
                .font(.system(size: 28))
                .foregroundStyle(telegram.isConnected ? Color.green : Color.accentColor)
                .symbolRenderingMode(.hierarchical)
            VStack(alignment: .leading, spacing: 2) {
                Text(telegram.isConnected ? "Telegram" : "Connect Telegram")
                    .font(.title2.weight(.semibold))
                Text("Send Moof notifications through your Telegram bot.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            header
            Spacer(minLength: 0)

            if let credential = telegram.credential {
                VStack(spacing: 16) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.green)
                    Text("Connected to Telegram")
                        .font(.title3.weight(.semibold))
                    Text("Notifications can now be delivered to \(credential.chatName).")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("@\(credential.botUsername)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.tertiary)
                        .textSelection(.enabled)
                    Toggle("Also Send to Telegram", isOn: $telegram.mirrorNotifications)
                        .toggleStyle(.switch)
                    if !telegram.mirrorNotifications {
                        Text("Sending is off. Turn this on to mirror notifications to Telegram.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Button {
                        telegram.sendTestMessage()
                    } label: {
                        Label("Test Message", systemImage: "paperplane")
                    }
                    if let problem = telegram.problem {
                        Text(problem)
                            .font(.callout)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    HStack {
                        Button("Disconnect…", role: .destructive) { confirmsDisconnect = true }
                        Spacer()
                        Button("Done") { close() }
                            .keyboardShortcut(.defaultAction)
                    }
                }
            } else {
                switch telegram.phase {
                case .validating:
                    Spacer(minLength: 0)
                    ProgressView()
                        .controlSize(.large)
                    Text("Checking the bot token…")
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    HStack {
                        Spacer()
                        Button("Cancel") { close() }
                    }
                case .awaitingCode(let username, let pairingCode):
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.tint)
                    HStack(spacing: 4) {
                        Text("Message")
                        Button("@\(username)") {
                            guard let url = URL(string: "https://t.me/\(username)") else {
                                assertionFailure("Telegram generated an invalid bot username.")
                                return
                            }
                            NSWorkspace.shared.open(url)
                        }
                        .buttonStyle(.link)
                    }
                    .font(.title3.weight(.semibold))
                    Text("Open the bot’s private chat, press Start if needed, then send this code:")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(pairingCode)
                        .font(.system(size: 24, design: .monospaced).weight(.semibold))
                        .textSelection(.enabled)
                    ProgressView()
                        .controlSize(.small)
                    Text("Waiting for the code…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    HStack {
                        Button("Use Another Token") { telegram.cancelPairing() }
                        Spacer()
                        Button("Copy Code") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(pairingCode, forType: .string)
                        }
                        Button("Open Telegram") {
                            guard let url = URL(string: "https://t.me/\(username)") else {
                                assertionFailure("Telegram generated an invalid bot username.")
                                return
                            }
                            NSWorkspace.shared.open(url)
                        }
                        .keyboardShortcut(.defaultAction)
                    }
                case .idle, .failed, .connected:
                    if case .failed(let message) = telegram.phase {
                        Text(message)
                            .font(.callout)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text("Create a bot with @BotFather, then paste the token it gives you.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Link("Open @BotFather", destination: URL(string: "https://t.me/BotFather")!)
                    SecureField("Bot token", text: $token)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { telegram.connect(botToken: token) }
                    Text("Moof then waits for the one-time code and discovers the chat automatically.")
                        .font(.callout)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    HStack {
                        Button("Cancel") { close() }
                        Spacer()
                        Button("Connect") { telegram.connect(botToken: token) }
                            .keyboardShortcut(.defaultAction)
                            .disabled(token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
        }
        .padding(18)
        .frame(width: windowSize.width, height: windowSize.height, alignment: .top)
        .buttonBorderShape(.capsule)
        .confirmationDialog("Disconnect Telegram?", isPresented: $confirmsDisconnect) {
            Button("Disconnect", role: .destructive) {
                token = ""
                telegram.disconnect()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Moof will remove the saved bot token and chat.")
        }
    }
}
