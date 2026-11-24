import ArgumentParser
import Foundation

/// A command that prints a result, and so supports `--json`. Conforming is the whole of its
/// `--json` support: the shared `run()` builds the `Output`, hands it to `execute` for progress,
/// prints the one `Reply` in the right format, and reports a thrown error as JSON. `execute` must
/// not print its result itself.
public protocol OutputCommand: AsyncParsableCommand {
    /// The command's `--json` flag, declared by each command for its own help text.
    var json: Bool { get }
    /// A JSON document, or JSON Lines events for a command that streams or has progress. No
    /// default: each command decides, since the wrong one drops its progress or breaks its format.
    static var jsonStyle: Output.JSONStyle { get }
    /// The style of this run, which is `jsonStyle` unless an option changes what the command
    /// prints: a stream that an option makes print once and exit is then a document.
    var jsonStyleOfRun: Output.JSONStyle { get }
    func execute(_ output: Output) async throws -> Reply
}

extension OutputCommand {
    public var jsonStyleOfRun: Output.JSONStyle { Self.jsonStyle }

    public func run() async throws {
        let output = Output(json: json, style: jsonStyleOfRun)
        try await output.reporting {
            let reply = try await execute(output)
            output.result(reply)
            if reply.exitStatus != 0 { throw ExitCode(reply.exitStatus) }
        }
    }
}

/// A command whose `--json` belongs to a program it runs, which prints the JSON itself.
public protocol JSONPassthrough {}

/// A command's outcome, for people (`text`, nil when the command's own output said it all) and
/// as JSON (`value`). A nonzero `exitStatus` ends the program with it once the outcome is
/// printed: for a result that is itself the bad news (a check that failed, a partial removal),
/// or a status passed through from a program the command ran.
public struct Reply {
    public let value: any Encodable
    public let text: String?
    public let exitStatus: Int32

    public init(_ value: some Encodable, text: String?, exitStatus: Int32 = 0) {
        self.value = value
        self.text = text
        self.exitStatus = exitStatus
    }
}

/// An error that ends the program with a status of its own, where any other error ends it with 1.
/// It is reported like any other: `Error: …` on stderr, and as JSON too under `--json`.
public protocol ExitStatusError: Error {
    var exitStatus: Int32 { get }
}
