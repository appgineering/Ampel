import Foundation
import os

/// os.Logger, mirrored to a file.
///
/// The unified log is fine when you have a terminal and know the incantation.
/// A colleague reporting a crash has neither, and the unified log cannot be
/// read back by an unprivileged app, so anything Ampel wants to be able to ask
/// for later has to be written somewhere a person can find and attach.
struct Log: Sendable {
    static let subsystem = "com.appgineering.ampel"

    static var fileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".ampel/ampel.log")
    }

    private let logger: os.Logger
    private let category: String

    init(_ category: String) {
        self.category = category
        self.logger = Logger(subsystem: Self.subsystem, category: category)
    }

    func debug(_ message: String) {
        logger.debug("\(message, privacy: .public)")
        Self.write("DEBUG", category, message)
    }

    func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
        Self.write("INFO", category, message)
    }

    func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
        Self.write("ERROR", category, message)
    }

    // MARK: - File

    /// Serial, so interleaved writes from the watcher queue stay whole lines.
    private static let queue = DispatchQueue(label: "com.appgineering.ampel.log")
    private static let maximumBytes = 512 * 1024

    private static let stamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter
    }()

    private static func write(_ level: String, _ category: String, _ message: String) {
        let line = "\(stamp.string(from: Date())) \(level) [\(category)] \(message)\n"
        queue.async {
            let url = fileURL
            let manager = FileManager.default
            try? manager.createDirectory(at: url.deletingLastPathComponent(),
                                         withIntermediateDirectories: true)

            // One rotation, so a long running app cannot fill the disk but the
            // previous session's tail survives a restart.
            if let size = try? manager.attributesOfItem(atPath: url.path)[.size] as? Int,
               size > maximumBytes {
                let previous = url.deletingLastPathComponent().appendingPathComponent("ampel.log.1")
                try? manager.removeItem(at: previous)
                try? manager.moveItem(at: url, to: previous)
            }

            guard let data = line.data(using: .utf8) else { return }
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            } else {
                try? data.write(to: url)
            }
        }
    }
}
