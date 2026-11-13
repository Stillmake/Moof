import AppKit
import SwiftUI

@MainActor
final class MoofWeChatWindowController: NSWindowController, NSWindowDelegate {
    static let shared = MoofWeChatWindowController()
    private static let contentWidth: CGFloat = 430

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: Self.contentWidth, height: 420),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "WeChat"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        let hostingController = NSHostingController(
            rootView: MoofWeChatView(
                wechat: .shared,
                close: { [weak self] in self?.window?.close() },
                sizeToFit: { [weak self] in self?.requestSizeToFit() }
            )
        )
        hostingController.sizingOptions = []
        window.contentViewController = hostingController
        window.contentMinSize = NSSize(width: Self.contentWidth, height: 220)
        if !window.setFrameUsingName("MoofWeChatWindow") {
            window.center()
        }
        window.setFrameAutosaveName("MoofWeChatWindow")
        sizeToFit()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func present() {
        if MoofWeChat.shared.isPaired {
            if !MoofWeChat.shared.isConnected {
                MoofWeChat.shared.beginContextCapture()
            }
        } else if !MoofWeChat.shared.isLoggingIn {
            MoofWeChat.shared.beginLogin()
        }
        window?.deminiaturize(nil)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        requestSizeToFit()
    }

    func windowWillClose(_ notification: Notification) {
        MoofWeChat.shared.cancelLogin()
    }

    private func requestSizeToFit() {
        DispatchQueue.main.async { [weak self] in
            self?.sizeToFit()
        }
    }

    private func sizeToFit() {
        guard let window, let contentView = window.contentViewController?.view else { return }
        contentView.layoutSubtreeIfNeeded()
        let fittingSize = contentView.fittingSize
        guard fittingSize.height.isFinite, fittingSize.height > 0 else { return }
        let height = min(max(fittingSize.height.rounded(.up), 220), 760)
        guard abs(window.contentLayoutRect.height - height) > 0.5 else { return }
        let top = window.frame.maxY
        window.setContentSize(NSSize(width: Self.contentWidth, height: height))
        var frame = window.frame
        frame.origin.y = top - frame.height
        window.setFrame(frame, display: true)
    }
}

private struct MoofWeChatView: View {
    @Bindable var wechat: MoofWeChat
    let close: () -> Void
    let sizeToFit: () -> Void

    @State private var confirmsDisconnect = false

    var body: some View {
        VStack(spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: wechat.isConnected ? "checkmark.circle.fill" : "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(wechat.isConnected ? Color.green : Color.accentColor)
                    .symbolRenderingMode(.hierarchical)
                VStack(alignment: .leading, spacing: 2) {
                    Text(wechat.isConnected ? "WeChat" : "Connect WeChat")
                        .font(.title2.weight(.semibold))
                    Text("Send Moof notifications to your WeChat.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            if wechat.isConnected {
                VStack(spacing: 16) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.green)
                    Text("Connected to WeChat")
                        .font(.title3.weight(.semibold))
                    Text("Notifications can now be delivered to the WeChat account that scanned the QR code.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let accountID = wechat.credential?.accountID {
                        Text(accountID)
                            .font(.caption.monospaced())
                            .foregroundStyle(.tertiary)
                            .textSelection(.enabled)
                    }
                    Toggle("Also Send to WeChat", isOn: $wechat.mirrorNotifications)
                        .toggleStyle(.switch)
                    if !wechat.mirrorNotifications {
                        Text("Sending is off. Turn this on to mirror notifications to WeChat.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    if let problem = wechat.problem {
                        Text(problem)
                            .font(.callout)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    HStack {
                        Button("Disconnect…", role: .destructive) { confirmsDisconnect = true }
                        Spacer()
                        Button("Done") { close() }
                            .keyboardShortcut(.defaultAction)
                    }
                }
                .padding(.vertical, 8)
            } else {
                if wechat.isLoggingIn, let qrImage = wechat.qrImage {
                    Image(nsImage: qrImage)
                        .resizable()
                        .interpolation(.none)
                        .frame(width: 260, height: 260)
                        .padding(12)
                        .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                        }
                        .accessibilityLabel("WeChat login QR code")
                }

                switch wechat.phase {
                case .idle:
                    Image(systemName: "qrcode")
                        .font(.system(size: 44))
                        .foregroundStyle(.secondary)
                    Text("Moof is not connected to WeChat.")
                        .font(.headline)
                    HStack {
                        Button("Cancel") { close() }
                        Spacer()
                        Button("Connect") { wechat.beginLogin() }
                            .keyboardShortcut(.defaultAction)
                    }
                case .starting:
                    ProgressView()
                        .controlSize(.large)
                    Text("Requesting a login QR code…")
                        .foregroundStyle(.secondary)
                    HStack {
                        Spacer()
                        Button("Cancel") { close() }
                    }
                case .scanning:
                    Text("Scan with WeChat")
                        .font(.headline)
                    Text("Open WeChat on your phone and scan the code above.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                    HStack {
                        Button("Cancel") { close() }
                        Spacer()
                        Button("New QR Code") { wechat.beginLogin() }
                    }
                case .scanned:
                    ProgressView()
                        .controlSize(.small)
                    Text("Confirm in WeChat")
                        .font(.headline)
                    Text("Approve the login on your phone.")
                        .foregroundStyle(.secondary)
                    HStack {
                        Spacer()
                        Button("Cancel") { close() }
                    }
                case .awaitingMessage:
                    Image(systemName: "1.circle.fill")
                        .font(.system(size: 42))
                        .foregroundStyle(Color.accentColor)
                    Text("Send a message from WeChat")
                        .font(.headline)
                    Text("Open the newly connected bot in WeChat and send any message, such as “Hello”. This creates the delivery token WeChat requires for notifications. The message content is not stored.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let accountID = wechat.credential?.accountID {
                        Text(accountID)
                            .font(.caption.monospaced())
                            .foregroundStyle(.tertiary)
                            .textSelection(.enabled)
                    }
                    ProgressView()
                        .controlSize(.small)
                    Text("Waiting for your message…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    if let problem = wechat.problem {
                        Text(problem)
                            .font(.callout)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    HStack {
                        if wechat.isPaired {
                            Button("Disconnect…", role: .destructive) { confirmsDisconnect = true }
                        }
                        Spacer()
                        Button("Close") { close() }
                    }
                case .pinRequired, .pinRejected:
                    Text(wechat.phase == .pinRequired ? "Enter the PIN from WeChat" : "That PIN didn’t match")
                        .font(.headline)
                    Text(
                        wechat.phase == .pinRequired
                            ? "If WeChat shows a number, enter it here to finish connecting."
                            : "Check the number on your phone and try again."
                    )
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    HStack {
                        TextField("PIN", text: $wechat.verificationCode)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 180)
                            .onSubmit { wechat.submitVerificationCode() }
                        Button("Continue") { wechat.submitVerificationCode() }
                            .keyboardShortcut(.defaultAction)
                            .disabled(wechat.verificationCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    HStack {
                        Button("Cancel") { close() }
                        Spacer()
                        Button("New QR Code") { wechat.beginLogin() }
                    }
                case .verifying:
                    ProgressView()
                        .controlSize(.small)
                    Text("Checking the PIN…")
                        .foregroundStyle(.secondary)
                    HStack {
                        Spacer()
                        Button("Cancel") { close() }
                    }
                case .failed(let message):
                    Image(systemName: "xmark.octagon.fill")
                        .font(.system(size: 42))
                        .foregroundStyle(.red)
                    Text("Couldn’t connect")
                        .font(.headline)
                    Text(message)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        if wechat.isPaired {
                            Button("Disconnect…", role: .destructive) { confirmsDisconnect = true }
                        }
                        Spacer()
                        Button("Close") { close() }
                        Button("Try Again") { wechat.beginLogin() }
                            .keyboardShortcut(.defaultAction)
                    }
                case .connected:
                    EmptyView()
                }
            }
        }
        .padding(24)
        .frame(width: 430)
        .onAppear(perform: sizeToFit)
        .onChange(of: wechat.phase) { _, _ in sizeToFit() }
        .onChange(of: wechat.problem) { _, _ in sizeToFit() }
        .onChange(of: wechat.mirrorNotifications) { _, _ in sizeToFit() }
        .confirmationDialog("Disconnect WeChat?", isPresented: $confirmsDisconnect) {
            Button("Disconnect", role: .destructive) { wechat.disconnect() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Moof will remove the stored tokens. You can pair again at any time.")
        }
    }
}
