import Logging

/// Shared CLI logger.
///
/// Status and findings go through swift-log to stderr so stdout stays clean
/// for deliverable output (the diagnose report, `--format json`, `--print`).
/// The lazy static bootstraps the logging system exactly once on first use
enum Log {
    static let logger: Logger = {
        LoggingSystem.bootstrap { label in
            var handler = StreamLogHandler.standardError(label: label)
            handler.logLevel = .info
            return handler
        }
        return Logger(label: "module-graph-doctor")
    }()
}
