import ArgumentParser
import Foundation

/// Where a command's output goes. Text is for people. With `--json`, a command that finishes
/// quickly prints one JSON document, and one that streams or has progress (`jsonStyle` `.events`)
/// prints JSON Lines: `{"event":"log","message":…}` and the command's own events as it goes, then
/// `{"event":"result","result":…}` if it ends with a result. A failure is JSON on stdout too,
/// `{"error":…}` or `{"event":"error","error":…}`, and `Error: …` on stderr, so a script that
/// pipes stdout into a JSON tool still shows it. The exit status is then 1, or the error's own.
public struct Output: Sendable {
    public enum JSONStyle: Sendable { case document, events }
    public enum Format: Sendable { case text, document, events }

    public let format: Format
    /// Where text goes: stdout.
    private let textOutput: FileHandle
    /// Where JSON goes: the original stdout. In JSON mode fd 1 is pointed at stderr, so output that
    /// would otherwise land in the JSON (a child process's, a library's `print`) goes to stderr instead.
    private let jsonOutput: FileHandle
    private let errorOutput: FileHandle

    public init(json: Bool, style: JSONStyle) {
        let format = Self.format(json: json, style: style)
        if json {
            let original = FileHandle(fileDescriptor: dup(STDOUT_FILENO), closeOnDealloc: false)
            dup2(STDERR_FILENO, STDOUT_FILENO)
            self.init(format: format, text: .standardOutput, json: original, error: .standardError)
        } else {
            self.init(format: format, text: .standardOutput, json: .standardOutput, error: .standardError)
        }
    }

    /// An output that writes to the handles given and leaves the process's own alone, for tests.
    init(format: Format, text: FileHandle, json: FileHandle, error: FileHandle) {
        self.format = format
        textOutput = text
        jsonOutput = json
        errorOutput = error
    }

    static func format(json: Bool, style: JSONStyle) -> Format {
        switch (json, style) {
        case (false, _): .text
        case (true, .document): .document
        case (true, .events): .events
        }
    }

    public var isJSON: Bool { format != .text }

    /// Progress: a line of text, or a `log` event. A JSON document has no room for it, so it's dropped.
    public func log(_ message: String) {
        switch format {
        case .text: writeText(message)
        case .events: writeLine(LogEvent(message: message.trimmingCharacters(in: .whitespacesAndNewlines)))
        case .document: break
        }
    }

    /// One item of a stream: `text` for people, or the line `{"event":"<name>","<name>":<value>}`.
    /// A JSON document has no room for it, so it's dropped. `log`, `result` and `error` are taken.
    public func event(_ name: String, _ value: some Encodable, text: String?) {
        precondition(!["log", "result", "error"].contains(name), "\(name) is one of Output's own events")
        switch format {
        case .text: if let text { writeText(text) }
        case .events: writeLine(NamedEvent(name: name, value: value))
        case .document: break
        }
    }

    /// The command's outcome, printed once by `OutputCommand.run`.
    func result(_ reply: Reply) {
        emit(reply.value, text: reply.text)
    }

    /// Opens `Reply`'s `any Encodable` into a concrete type, which the generic `ResultEvent` needs.
    private func emit(_ value: some Encodable, text: String?) {
        switch format {
        case .text: if let text { writeText(text) }
        case .document: write(Self.encoded { try CLIJSON.document(value) })
        case .events: writeLine(ResultEvent(result: value))
        }
    }

    /// For a ^C handler: says what was left behind, as text or as an error in the JSON.
    public func interrupted(_ consequence: String) {
        switch format {
        case .text: writeText("\nInterrupted; \(consequence)")
        case .document, .events: failJSON("interrupted; \(consequence)")
        }
    }

    /// Runs a command's body and reports what it throws: as JSON and `Error: …` in JSON mode. In
    /// text mode an error is left to ArgumentParser, which prints `Error: …` and exits with 1,
    /// unless it has an exit status of its own, which ArgumentParser would not use.
    func reporting(_ body: () async throws -> Void) async throws {
        do {
            try await body()
        } catch let error where !(error is ExitCode) && !(error is CleanExit) {
            let status = (error as? any ExitStatusError)?.exitStatus
            if isJSON {
                failJSON(Self.message(of: error))
            } else if status != nil {
                writeError(Self.message(of: error))
            } else {
                throw error
            }
            throw ExitCode(status ?? 1)
        }
    }

    /// What ArgumentParser prints after `Error: ` for the same error.
    static func message(of error: any Error) -> String {
        (error as? any LocalizedError)?.errorDescription ?? String(describing: error)
    }

    private func failJSON(_ message: String) {
        switch format {
        case .text: return
        case .document: write(Self.encoded { try CLIJSON.document(["error": message]) })
        case .events: writeLine(ErrorEvent(error: message))
        }
        writeError(message)
    }

    private func writeError(_ message: String) {
        errorOutput.write(Data("Error: \(message)\n".utf8))
    }

    private struct LogEvent: Encodable {
        let event = "log"
        var message: String
    }

    private struct ResultEvent<Result: Encodable>: Encodable {
        let event = "result"
        var result: Result
    }

    private struct ErrorEvent: Encodable {
        let event = "error"
        var error: String
    }

    private struct NamedEvent<Value: Encodable>: Encodable {
        var name: String
        var value: Value

        struct Key: CodingKey {
            var stringValue: String
            var intValue: Int? { nil }
            init(stringValue: String) { self.stringValue = stringValue }
            init?(intValue: Int) { nil }
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: Key.self)
            try container.encode(name, forKey: Key(stringValue: "event"))
            try container.encode(value, forKey: Key(stringValue: name))
        }
    }

    /// Events arrive on several threads; each line goes out whole, at once (unbuffered, so a
    /// reader of a pipe sees progress as it happens).
    private static let lock = NSLock()

    private func writeLine(_ value: some Encodable) {
        write(Self.encoded { try CLIJSON.line(value) })
    }

    private func write(_ data: Data) {
        Self.lock.withLock { jsonOutput.write(data + Data("\n".utf8)) }
    }

    private func writeText(_ text: String) {
        Self.lock.withLock {
            // Anything `print` left in stdout's buffer goes first, to keep the order.
            fflush(stdout)
            textOutput.write(Data((text + "\n").utf8))
        }
    }

    /// A command's output types always encode; a failure here is a bug, not a user error.
    private static func encoded(_ encode: () throws -> Data) -> Data {
        do { return try encode() } catch { fatalError("can't encode output as JSON: \(error)") }
    }
}
