import Foundation
import Darwin
import os

private let snapshotLogger = Logger(subsystem: "com.diegominetti.ai-usage-menubar", category: "UsageSnapshotStore")

enum UsageSnapshotStore {
    static let appGroupIdentifier = "group.com.diegominetti.ai-usage-menubar"
    private static let widgetBundleIdentifier = "com.diegominetti.ai-usage-menubar.widget.v2"
    private static let snapshotFileName = "usage_snapshot_v2.json"
    private static let legacySnapshotFileName = "usage_snapshot.json"
    private static let snapshotRelativePath = "AI Usage/\(snapshotFileName)"
    private static let legacySnapshotRelativePath = "AI Usage/\(legacySnapshotFileName)"

    static var snapshotURL: URL {
        let fm = FileManager.default
        do {
            let support = try fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let dir = support.appendingPathComponent("AI Usage", isDirectory: true)
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            return dir.appendingPathComponent(snapshotFileName)
        } catch {
            return URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(snapshotFileName)
        }
    }

    static func load() -> UsageSnapshot? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        for url in readableSnapshotURLs() where FileManager.default.fileExists(atPath: url.path) {
            do {
                return try decoder.decode(UsageSnapshot.self, from: Data(contentsOf: url))
            } catch {
                snapshotLogger.error("Failed to load snapshot at \(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }

        return nil
    }

    static func save(_ snapshot: UsageSnapshot) {
        do {
            try FileManager.default.createDirectory(
                at: snapshotURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(snapshot)
            try writeSharedSnapshotData(data, to: snapshotURL)
            removeQuarantineMetadata(from: snapshotURL.deletingLastPathComponent())
            removeQuarantineMetadata(from: snapshotURL)

            for url in additionalSnapshotURLs() {
                try? FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try? writeSharedSnapshotData(data, to: url)
                removeQuarantineMetadata(from: url.deletingLastPathComponent())
                removeQuarantineMetadata(from: url)
            }

            if let widgetURL = widgetContainerSnapshotURL() {
                try? FileManager.default.createDirectory(
                    at: widgetURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try? writeSharedSnapshotData(data, to: widgetURL)
                removeQuarantineMetadata(from: widgetURL.deletingLastPathComponent())
                removeQuarantineMetadata(from: widgetURL)
            }
        } catch {
            snapshotLogger.error("Failed to save snapshot: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func readableSnapshotURLs() -> [URL] {
        var urls: [URL] = []
        if let widgetURL = widgetContainerSnapshotURL() {
            urls.append(widgetURL)
        }
        urls.append(snapshotURL)
        if let local = localApplicationSupportSnapshotURL() {
            urls.append(local)
        }
        urls.append(contentsOf: additionalSnapshotURLs())
        urls.append(contentsOf: legacySnapshotURLs())
        return uniqueURLs(urls)
    }

    private static func uniqueURLs(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        return urls.filter { url in
            let path = url.standardizedFileURL.path
            return seen.insert(path).inserted
        }
    }

    private static func localApplicationSupportSnapshotURL() -> URL? {
        try? FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
            .appendingPathComponent(snapshotRelativePath)
    }

    private static func additionalSnapshotURLs() -> [URL] {
        guard let support = try? FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true) else {
            return []
        }
        return [
            support.appendingPathComponent(snapshotRelativePath),
            support.appendingPathComponent("ai-usage-tracker/\(snapshotFileName)")
        ]
    }

    private static func legacySnapshotURLs() -> [URL] {
        guard let support = try? FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false) else {
            return []
        }
        return [
            support.appendingPathComponent(legacySnapshotRelativePath),
            support.appendingPathComponent("ai-usage-tracker/\(legacySnapshotFileName)")
        ]
    }

    private static func widgetContainerSnapshotURL() -> URL? {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers")
            .appendingPathComponent(widgetBundleIdentifier)
            .appendingPathComponent("Data/Library/Application Support")
            .appendingPathComponent(snapshotRelativePath)
    }

    private static func writeSharedSnapshotData(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: [.atomic])
        try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
    }

    private static func removeQuarantineMetadata(from url: URL) {
        url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return }
            _ = removexattr(path, "com.apple.provenance", 0)
            _ = removexattr(path, "com.apple.quarantine", 0)
        }
    }
}
