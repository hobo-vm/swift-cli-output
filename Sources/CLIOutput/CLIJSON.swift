import Foundation

/// The JSON that `--json` prints: ISO 8601 dates, and sorted keys so the output diffs cleanly.
public enum CLIJSON {
    /// A whole document, pretty-printed, for a command that prints one result.
    public static func document(_ value: some Encodable) throws -> Data {
        try encoder(pretty: true).encode(value)
    }

    /// One line, no newline, for a command that streams events (JSON Lines).
    public static func line(_ value: some Encodable) throws -> Data {
        try encoder(pretty: false).encode(value)
    }

    private static func encoder(pretty: Bool) -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        if pretty { encoder.outputFormatting.insert(.prettyPrinted) }
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
