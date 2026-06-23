import Foundation
import Darwin
import os

private let snapshotLogger = Logger(subsystem: "com.diegominetti.ai-usage-menubar", category: "UsageSnapshotStore")

enum UsageSnapshotStore {
    static let appGroupIdentifier = "group.com.diegominetti.ai-usage-menubar"
    private static let widgetBundleIdentifier = "com.diegominetti.ai-usage-menubar.widget"
    private static let snapshotRelativePath = "AI Usage/usage_snapshot.json"

    static var snapshotURL: URL {
        if let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) {
            return container
                .appendingPathComponent("Library/Application Support/AI Usage", isDirectory: true)
                .appendingPathComponent("usage_snapshot.json")
        }

        let fm = FileManager.default
        do {
            let support = try fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let dir = support.appendingPathComponent("ai-usage-tracker", isDirectory: true)
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            return dir.appendingPathComponent("usage_snapshot.json")
        } catch {
            return URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("usage_snapshot.json")
        }
    }

    static func load() -> UsageSnapshot? {
        let url = readableSnapshotURL()
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(UsageSnapshot.self, from: Data(contentsOf: url))
        } catch {
            snapshotLogger.error("Failed to load snapshot at \(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
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

    private static func readableSnapshotURL() -> URL {
        if let local = localApplicationSupportSnapshotURL(),
           FileManager.default.fileExists(atPath: local.path) {
            return local
        }

        if FileManager.default.fileExists(atPath: snapshotURL.path) {
            return snapshotURL
        }

        if let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) {
            let legacy = container.appendingPathComponent("usage_snapshot.json")
            if FileManager.default.fileExists(atPath: legacy.path) {
                return legacy
            }
        }

        return snapshotURL
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
            support.appendingPathComponent("ai-usage-tracker/usage_snapshot.json")
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
        try data.withUnsafeBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            let fd = open(url.path, O_WRONLY | O_CREAT | O_TRUNC, S_IRUSR | S_IWUSR | S_IRGRP | S_IROTH)
            guard fd >= 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            defer { close(fd) }

            var remaining = data.count
            var pointer = baseAddress
            while remaining > 0 {
                let written = write(fd, pointer, remaining)
                if written < 0 {
                    throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
                }
                remaining -= written
                pointer = pointer.advanced(by: written)
            }

            fchmod(fd, S_IRUSR | S_IWUSR | S_IRGRP | S_IROTH)
        }
    }

    private static func removeQuarantineMetadata(from url: URL) {
        url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return }
            _ = removexattr(path, "com.apple.provenance", 0)
            _ = removexattr(path, "com.apple.quarantine", 0)
        }
    }
}
