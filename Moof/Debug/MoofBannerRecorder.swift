#if DEBUG
import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// Captures stills of real cards, driven by `scripts/make-banner.sh` and `scripts/make-screenshots.sh`:
/// launched with `-MoofBannerScenes <dir>` or `-MoofScreenshotScenes <dir>`, plus `-MoofBannerBackground
/// <image>`, Moof shows the background in a window under the menu bar, then for each scene shows real
/// cards, waits until they are at rest, writes one opaque `scene-<n>.png` of its own windows, and quits.
/// Capturing its own windows needs no Screen Recording permission, and the window server composites
/// the Liquid Glass exactly as on screen.
///
/// Banner mode fills 1360 × 522pt, half the README background's pixels. Screenshot mode fills
/// 1440 × 900pt, which at 2× is the App Store's largest Mac size, 2880 × 1800px (16:10), with a
/// headline over the aspect-filled background; App Store Connect rejects alpha, hence opaque stills.
@MainActor
enum MoofBannerRecorder {
    private struct Scene {
        var urls: [String]
        var headline: String? = nil
    }

    /// Starts recording when the launch arguments ask for it; the app then skips restoring cards.
    static func startIfRequested() -> Bool {
        let defaults = UserDefaults.standard
        let screenshotsPath = defaults.string(forKey: "MoofScreenshotScenes")
        guard let scenesPath = screenshotsPath ?? defaults.string(forKey: "MoofBannerScenes"),
            let backgroundPath = defaults.string(forKey: "MoofBannerBackground")
        else { return false }
        guard let background = NSImage(contentsOfFile: backgroundPath) else {
            assertionFailure("No banner background at \(backgroundPath).")
            return false
        }
        Task {
            if screenshotsPath != nil {
                await record(
                    output: URL(fileURLWithPath: scenesPath, isDirectory: true), background: background, size: CGSize(width: 1440, height: 900),
                    scenes: [
                        Scene(
                            urls: [
                                "moof://notify?theme=default&style=success&title=Build%20succeeded&body=142%20tests%20passed%20in%208.3s&source=Xcode&duration=0",
                                "moof://notify?theme=default&style=warning&title=Disk%20almost%20full&body=12%20GB%20left%20on%20Macintosh%20HD&source=System&duration=0",
                                "moof://notify?theme=default&style=error&title=Deploy%20failed&body=Health%20check%20timed%20out%20on%20api-2&source=CI&duration=0&action=https%3A%2F%2Fgithub.com&actionTitle=Logs",
                            ],
                            headline: "Notifications from any script"
                        ),
                        Scene(
                            urls: ["moof://notify?theme=hollow-knight&title=Backup%20finished.&body=All%201,204%20files%20are%20safe.&source=Time%20Machine&duration=0&action=https%3A%2F%2Fapple.com&actionTitle=Show"],
                            headline: "Themes drawn after the games you love"
                        ),
                        Scene(
                            urls: ["moof://notify?theme=elden-ring&title=Deploy%20complete&body=Production%20is%20now%20running%20v0.2.0&source=CI&duration=0"],
                            headline: "One command: moof notify"
                        ),
                        Scene(
                            urls: ["moof://notify?theme=mario&title=Pull%20request%20merged!&body=%2342%20Add%20a%20banner&source=GitHub&duration=0&action=https%3A%2F%2Fgithub.com&actionTitle=Open"],
                            headline: "Actions that open what matters"
                        ),
                    ]
                )
            } else {
                await record(
                    output: URL(fileURLWithPath: scenesPath, isDirectory: true), background: background, size: CGSize(width: 1360, height: 522),
                    scenes: [
                        Scene(urls: ["moof://notify?theme=hollow-knight&title=Backup%20finished.&body=All%201,204%20files%20are%20safe.&source=Time%20Machine&duration=0&action=https%3A%2F%2Fapple.com&actionTitle=Show"]),
                        Scene(urls: ["moof://notify?theme=elden-ring&title=Deploy%20complete&body=Production%20is%20now%20running%20v0.2.0&source=CI&duration=0"]),
                        Scene(urls: ["moof://notify?theme=mario&title=Pull%20request%20merged!&body=%2342%20Add%20a%20banner&source=GitHub&duration=0&action=https%3A%2F%2Fgithub.com&actionTitle=Open"]),
                        Scene(urls: [
                            "moof://notify?theme=default&style=success&title=Build%20succeeded&body=142%20tests%20passed%20in%208.3s&source=Xcode&duration=0",
                            "moof://notify?theme=default&style=warning&title=Disk%20almost%20full&body=12%20GB%20left%20on%20Macintosh%20HD&source=System&duration=0",
                            "moof://notify?theme=default&style=info&title=Review%20requested&body=Stillmake%2FMoof%20%2342%20Add%20a%20banner&source=GitHub&duration=0&action=https%3A%2F%2Fgithub.com&actionTitle=Review",
                        ]),
                    ]
                )
            }
            NSApp.terminate(nil)
        }
        return true
    }

    private static func record(output: URL, background: NSImage, size: CGSize, scenes: [Scene]) async {
        let center = MoofNotificationCenter.shared
        let screen = NSScreen.main ?? NSScreen.screens[0]
        assert(screen.visibleFrame.width >= size.width && screen.visibleFrame.height >= size.height, "The screen is too small for a \(size) capture.")
        let frame = CGRect(x: screen.visibleFrame.midX - size.width / 2, y: screen.visibleFrame.maxY - size.height, width: size.width, height: size.height)

        let window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        // Just under the cards' `.statusBar` panels, so the glass samples the background.
        window.level = NSWindow.Level(NSWindow.Level.statusBar.rawValue - 1)

        try? FileManager.default.removeItem(at: output)
        try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let captureRect = CGRect(x: frame.minX, y: screen.frame.maxY - frame.maxY, width: frame.width, height: frame.height)

        // One still per scene, at rest: no countdowns (`duration=0`), and themed cards in their
        // hover state so Copy, the action and the source show.
        for (index, scene) in scenes.enumerated() {
            window.contentView = NSHostingView(
                rootView: Image(nsImage: background).resizable().aspectRatio(contentMode: .fill)
                    .frame(width: size.width, height: size.height).clipped()
                    .overlay(alignment: .top) {
                        if let headline = scene.headline {
                            Text(headline).font(.system(size: 64, weight: .bold)).foregroundStyle(.white)
                                .shadow(color: .black.opacity(0.35), radius: 16, y: 4).padding(.top, 150)
                        }
                    }
            )
            window.orderFrontRegardless()

            let notifications = scene.urls.compactMap { URL(string: $0).flatMap { try? MoofCommand(url: $0) } }
                .compactMap { if case .notify(let notification) = $0 { notification } else { nil } }
            assert(notifications.count == scene.urls.count, "Every scene URL should parse.")
            // Center the stack in the background window, or in the part below the headline.
            let stackHeight = notifications.map { MoofNotificationLayout(notification: $0).size.height }.reduce(0, +) + CGFloat(notifications.count - 1) * 12
            let stackTop = scene.headline == nil ? 0 : size.height * 0.34
            center.topOffset = (screen.visibleFrame.maxY - frame.maxY) + stackTop + (size.height - stackTop - stackHeight) / 2
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
            // kCGWindowImageBestResolution; redrawn into an alpha-less context, since the background is opaque.
            if let image = createImage(captureRect, array, 1 << 3)?.takeRetainedValue(),
                let context = CGContext(
                    data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                    space: image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
                ),
                let destination = CGImageDestinationCreateWithURL(output.appending(path: "scene-\(index).png") as CFURL, UTType.png.identifier as CFString, 1, nil)
            {
                context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
                CGImageDestinationAddImage(destination, context.makeImage()!, nil)
                CGImageDestinationFinalize(destination)
            } else {
                assertionFailure("Capturing scene \(index) failed.")
            }
            notifications.forEach { center.close($0.id) }
        }
    }
}
#endif
