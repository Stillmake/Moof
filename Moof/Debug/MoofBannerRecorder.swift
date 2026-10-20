#if DEBUG
import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Captures the README banner's scenes, driven by `scripts/make-banner.sh`: launched with
/// `-MoofBannerScenes <dir> -MoofBannerBackground <image>`, Moof shows the background in a window
/// under the menu bar, then for each theme shows real cards, waits until they are at rest, writes
/// one `scene-<n>.png` of its own windows, and quits. The script animates the stills, so the GIF
/// never depends on timing. Capturing its own windows needs no Screen Recording permission, and
/// the window server composites the Liquid Glass exactly as on screen.
@MainActor
enum MoofBannerRecorder {
    /// Starts recording when the launch arguments ask for it; the app then skips restoring cards.
    static func startIfRequested() -> Bool {
        let defaults = UserDefaults.standard
        guard let scenesPath = defaults.string(forKey: "MoofBannerScenes"),
            let backgroundPath = defaults.string(forKey: "MoofBannerBackground")
        else { return false }
        guard let background = NSImage(contentsOfFile: backgroundPath) else {
            assertionFailure("No banner background at \(backgroundPath).")
            return false
        }
        Task { await record(output: URL(fileURLWithPath: scenesPath, isDirectory: true), background: background) }
        return true
    }

    private static func record(output: URL, background: NSImage) async {
        let center = MoofNotificationCenter.shared
        let screen = NSScreen.main ?? NSScreen.screens[0]
        // 1360 × 522pt: half the background's 2720 × 1044px, so it fills the window at 2×.
        let size = CGSize(width: 1360, height: 522)
        let frame = CGRect(x: screen.visibleFrame.midX - size.width / 2, y: screen.visibleFrame.maxY - size.height, width: size.width, height: size.height)

        let window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        let imageView = NSImageView(image: background)
        imageView.imageScaling = .scaleAxesIndependently
        window.contentView = imageView
        // Just under the cards' `.statusBar` panels, so the glass samples the background.
        window.level = NSWindow.Level(NSWindow.Level.statusBar.rawValue - 1)
        window.orderFrontRegardless()

        try? FileManager.default.removeItem(at: output)
        try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let captureRect = CGRect(x: frame.minX, y: screen.frame.maxY - frame.maxY, width: frame.width, height: frame.height)

        // One still per scene, at rest: no countdowns (`duration=0`), and themed cards in their
        // hover state so Copy, the action and the source show.
        let scenes: [[String]] = [
            ["moof://notify?theme=hollow-knight&title=Backup%20finished.&body=All%201,204%20files%20are%20safe.&source=Time%20Machine&duration=0&action=https%3A%2F%2Fapple.com&actionTitle=Show"],
            ["moof://notify?theme=elden-ring&title=Deploy%20complete&body=Production%20is%20now%20running%20v0.2.0&source=CI&duration=0"],
            ["moof://notify?theme=mario&title=Pull%20request%20merged!&body=%2342%20Add%20a%20banner&source=GitHub&duration=0&action=https%3A%2F%2Fgithub.com&actionTitle=Open"],
            [
                "moof://notify?theme=default&style=success&title=Build%20succeeded&body=142%20tests%20passed%20in%208.3s&source=Xcode&duration=0",
                "moof://notify?theme=default&style=warning&title=Disk%20almost%20full&body=12%20GB%20left%20on%20Macintosh%20HD&source=System&duration=0",
                "moof://notify?theme=default&style=info&title=Review%20requested&body=Stillmake%2FMoof%20%2342%20Add%20a%20banner&source=GitHub&duration=0&action=https%3A%2F%2Fgithub.com&actionTitle=Review",
            ],
        ]
        for (index, scene) in scenes.enumerated() {
            let notifications = scene.compactMap { URL(string: $0).flatMap { try? MoofCommand(url: $0) } }
                .compactMap { if case .notify(let notification) = $0 { notification } else { nil } }
            assert(notifications.count == scene.count, "Every banner URL should parse.")
            // Center the stack in the background window.
            let stackHeight = notifications.map { MoofNotificationLayout(notification: $0).size.height }.reduce(0, +) + CGFloat(notifications.count - 1) * 12
            center.topOffset = (screen.visibleFrame.maxY - frame.maxY) + (size.height - stackHeight) / 2
            notifications.forEach(center.show)
            if notifications.first?.theme != .standard {
                notifications.forEach { center.setHovering($0.id, true) }
            }
            // Past the 0.22s entrance and 0.15s hover fades, with margin for the glass to settle.
            try? await Task.sleep(for: .seconds(1.5))

            // Front-to-back ids of this app's visible windows: the cards, then the background.
            // Windows not yet on screen have a negative number and no window-server id.
            let ours = Set(NSApp.windows.filter(\.isVisible).compactMap { CGWindowID(exactly: $0.windowNumber) })
            var ids = (CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? [])
                .compactMap { $0[kCGWindowNumber as String] as? CGWindowID }
                .filter(ours.contains)
                .map { UnsafeRawPointer(bitPattern: UInt($0)) }
            typealias CreateImage = @convention(c) (CGRect, CFArray, UInt32) -> Unmanaged<CGImage>?
            // `CGWindowListCreateImageFromArray` is unavailable in the macOS 15+ SDK but still exported.
            let createImage = unsafeBitCast(dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGWindowListCreateImageFromArray"), to: CreateImage.self)
            let array = CFArrayCreate(nil, &ids, ids.count, nil)!
            // kCGWindowImageBestResolution
            if let image = createImage(captureRect, array, 1 << 3)?.takeRetainedValue(),
                let destination = CGImageDestinationCreateWithURL(output.appending(path: "scene-\(index).png") as CFURL, UTType.png.identifier as CFString, 1, nil)
            {
                CGImageDestinationAddImage(destination, image, nil)
                CGImageDestinationFinalize(destination)
            } else {
                assertionFailure("Capturing banner scene \(index) failed.")
            }
            notifications.forEach { center.close($0.id) }
        }

        NSApp.terminate(nil)
    }
}
#endif
