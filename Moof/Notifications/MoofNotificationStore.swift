import Foundation

/// The cards on screen, saved as JSON in Application Support so a relaunch restores them.
enum MoofNotificationStore {
    /// One card in stack order. A counting-down card keeps its absolute `deadline`, so time spent
    /// while Moof was not running still counts; a hover-paused card keeps its remaining interval.
    struct Record: Codable {
        let notification: MoofNotification
        let dismissState: MoofNotificationItem.DismissState?
    }

    static let url: URL = {
        let bundleID = Bundle.main.bundleIdentifier
        assert(bundleID != nil, "Moof should have a bundle identifier; using Moof.")
        return URL.applicationSupportDirectory
            .appending(path: bundleID ?? "Moof", directoryHint: .isDirectory)
            .appending(path: "notifications.json", directoryHint: .notDirectory)
    }()

    /// The saved records, or none when there is no file yet. An unreadable file is dropped.
    static func load() -> [Record] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode([Record].self, from: data)
        } catch {
            assertionFailure("Unreadable \(url.path): \(error); starting empty.")
            return []
        }
    }

    static func save(_ records: [Record]) {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try encoder.encode(records).write(to: url, options: .atomic)
        } catch {
            assertionFailure("Saving \(url.path) failed: \(error)")
        }
    }
}
