import Foundation

public struct DiagnosticsEvent: Equatable, Sendable, Codable {
    public enum Category: String, Sendable, Codable {
        case bluetooth
        case protocolFrame
        case app
        case provider
        case media
        case persistence
        case recovery
    }

    public var id: UUID
    public var timestamp: Date
    public var category: Category
    public var redactedMessage: String
    public var metadata: [String: String]

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        category: Category,
        redactedMessage: String,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.timestamp = timestamp
        self.category = category
        self.redactedMessage = redactedMessage
        self.metadata = metadata
    }
}

public struct DiagnosticsRedactor: Sendable {
    public init() {}

    public func redacted(_ value: String) -> String {
        var result = value
        let prefixedPatterns = [
            #"(?i)(authorization:\s*bearer\s+)[A-Za-z0-9._\-]+"#,
            #"(?i)(api[_\- ]?key\s*[:=]\s*)[A-Za-z0-9._\-]+"#
        ]
        for pattern in prefixedPatterns {
            result = result.replacingOccurrences(
                of: pattern,
                with: "$1[REDACTED]",
                options: .regularExpression
            )
        }
        result = result.replacingOccurrences(
            of: #"sk-[A-Za-z0-9._\-]+"#,
            with: "[REDACTED]",
            options: .regularExpression
        )
        return result
    }

    public func export(events: [DiagnosticsEvent], includePrivateContent: Bool = false) -> DiagnosticsExport {
        let entries = events.map { event in
            DiagnosticsExport.Entry(
                timestamp: event.timestamp,
                category: event.category.rawValue,
                message: includePrivateContent ? event.redactedMessage : redacted(event.redactedMessage),
                metadata: includePrivateContent ? event.metadata : event.metadata.mapValues(redacted)
            )
        }
        return DiagnosticsExport(entries: entries, includesPrivateContent: includePrivateContent)
    }
}

public struct DiagnosticsExport: Equatable, Sendable, Codable {
    public struct Entry: Equatable, Sendable, Codable {
        public var timestamp: Date
        public var category: String
        public var message: String
        public var metadata: [String: String]

        public init(timestamp: Date, category: String, message: String, metadata: [String: String]) {
            self.timestamp = timestamp
            self.category = category
            self.message = message
            self.metadata = metadata
        }
    }

    public var entries: [Entry]
    public var includesPrivateContent: Bool

    public init(entries: [Entry], includesPrivateContent: Bool) {
        self.entries = entries
        self.includesPrivateContent = includesPrivateContent
    }

    public var previewLines: [String] {
        entries.map { "\($0.category): \($0.message)" }
    }
}
