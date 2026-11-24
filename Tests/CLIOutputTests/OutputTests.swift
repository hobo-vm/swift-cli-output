import ArgumentParser
import Foundation
import Testing

@testable import CLIOutput

/// An `Output` writing to pipes, and what was written to each once `finish` closes them.
private final class Capture {
    private let text = Pipe(), json = Pipe(), error = Pipe()
    let output: Output

    init(_ format: Output.Format) {
        output = Output(format: format, text: text.fileHandleForWriting, json: json.fileHandleForWriting,
                        error: error.fileHandleForWriting)
    }

    func finish() -> (text: String, json: String, error: String) {
        func read(_ pipe: Pipe) -> String {
            pipe.fileHandleForWriting.closeFile()
            return String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        }
        return (read(text), read(json), read(error))
    }
}

private struct Record: Encodable {
    var name = "a/b"
    var at = Date(timeIntervalSince1970: 0)
}

private struct Plain: Error, CustomStringConvertible {
    var description = "it broke"
}

private struct TimedOut: ExitStatusError, CustomStringConvertible {
    var exitStatus: Int32 = 2
    var description = "timed out"
}

/// The exit status `body` ends the program with: 0 when it returns, nil when its error is left to ArgumentParser.
private func status(_ output: Output, _ body: () async throws -> Void) async -> Int32? {
    do {
        try await output.reporting(body)
        return 0
    } catch let code as ExitCode {
        return code.rawValue
    } catch {
        return nil
    }
}

struct OutputTests {
    @Test func textPrintsTheReplysText() {
        let capture = Capture(.text)
        capture.output.log("working")
        capture.output.event("model", Record(), text: "one change")
        capture.output.result(Reply(Record(), text: "done"))
        let printed = capture.finish()
        #expect(printed.text == "working\none change\ndone\n")
        #expect(printed.json.isEmpty && printed.error.isEmpty)
    }

    @Test func aReplyWithoutTextPrintsNothing() {
        let capture = Capture(.text)
        capture.output.result(Reply(Record(), text: nil))
        #expect(capture.finish().text.isEmpty)
    }

    @Test func aDocumentIsTheValueAloneWithSortedKeysAndISODates() {
        let capture = Capture(.document)
        capture.output.log("working")
        capture.output.event("model", Record(), text: "one change")
        capture.output.result(Reply(Record(), text: "done"))
        let printed = capture.finish()
        #expect(printed.json == "{\n  \"at\" : \"1970-01-01T00:00:00Z\",\n  \"name\" : \"a/b\"\n}\n")
        #expect(printed.text.isEmpty && printed.error.isEmpty)
    }

    @Test func eventsAreOneLineEach() {
        let capture = Capture(.events)
        capture.output.log(" working\n")
        capture.output.event("model", Record(), text: "one change")
        capture.output.result(Reply(Record(), text: "done"))
        let record = #"{"at":"1970-01-01T00:00:00Z","name":"a/b"}"#
        #expect(capture.finish().json == """
            {"event":"log","message":"working"}
            {"event":"model","model":\(record)}
            {"event":"result","result":\(record)}

            """)
    }

    @Test func anErrorInTextIsLeftToArgumentParser() async {
        let capture = Capture(.text)
        #expect(await status(capture.output) { throw Plain() } == nil)
        let printed = capture.finish()
        #expect(printed.text.isEmpty && printed.error.isEmpty)
    }

    @Test func anErrorWithItsOwnStatusInTextIsPrintedAndExitsWithIt() async {
        let capture = Capture(.text)
        #expect(await status(capture.output) { throw TimedOut() } == 2)
        let printed = capture.finish()
        #expect(printed.error == "Error: timed out\n")
        #expect(printed.text.isEmpty)
    }

    @Test func anErrorInADocumentIsJSONAndOnStderr() async {
        let capture = Capture(.document)
        #expect(await status(capture.output) { throw Plain() } == 1)
        let printed = capture.finish()
        #expect(printed.json == "{\n  \"error\" : \"it broke\"\n}\n")
        #expect(printed.error == "Error: it broke\n")
    }

    @Test func anErrorInEventsIsAnErrorEventAndKeepsItsStatus() async {
        let capture = Capture(.events)
        #expect(await status(capture.output) { throw TimedOut() } == 2)
        let printed = capture.finish()
        #expect(printed.json == #"{"error":"timed out","event":"error"}"# + "\n")
        #expect(printed.error == "Error: timed out\n")
    }

    @Test func anExitCodeIsNotAnErrorToReport() async {
        for format in [Output.Format.text, .document, .events] {
            let capture = Capture(format)
            #expect(await status(capture.output) { throw ExitCode(3) } == 3)
            let printed = capture.finish()
            #expect(printed.json.isEmpty && printed.error.isEmpty && printed.text.isEmpty)
        }
    }

    @Test func aLocalizedErrorGivesItsDescription() {
        struct Localized: LocalizedError {
            var errorDescription: String? { "the reason" }
        }
        #expect(Output.message(of: Localized()) == "the reason")
        #expect(Output.message(of: ValidationError("bad option")) == "bad option")
    }

    @Test func interruptedSaysWhatWasLeft() {
        let text = Capture(.text)
        text.output.interrupted("the VM is still running")
        #expect(text.finish().text == "\nInterrupted; the VM is still running\n")

        let events = Capture(.events)
        events.output.interrupted("the VM is still running")
        let printed = events.finish()
        #expect(printed.json == #"{"error":"interrupted; the VM is still running","event":"error"}"# + "\n")
        #expect(printed.error == "Error: interrupted; the VM is still running\n")
    }

    @Test func theFormatFollowsTheFlagAndTheStyle() {
        #expect(Output.format(json: false, style: .events) == .text)
        #expect(Output.format(json: true, style: .document) == .document)
        #expect(Output.format(json: true, style: .events) == .events)
    }
}

struct TableTests {
    @Test func columnsLineUpAndLinesHaveNoTrailingSpaces() {
        #expect(Table.format([["NAME", "STATE", "NOTE"], ["a", "running", ""], ["longer", "off", "x"]]) == """
            NAME    STATE    NOTE
            a       running
            longer  off      x
            """)
    }

    @Test func anEmptyListPrintsNothing() {
        #expect(Table.format(header: ["NAME"], rows: []) == nil)
        #expect(Table.format(header: ["NAME"], rows: [["a"]]) == "NAME\na")
        #expect(Table.format([]) == "")
    }
}

struct CommandTreeTests {
    struct Root: ParsableCommand {
        static let configuration = CommandConfiguration(subcommands: [Plain.self, Quick.self, Group.self, Hidden.self, Passed.self])
    }

    /// Holds subcommands and has no `--json` of its own, so it's in neither list.
    struct Group: ParsableCommand {
        static let configuration = CommandConfiguration(subcommands: [Streamed.self, Once.self])
    }

    struct Plain: ParsableCommand {}

    struct Hidden: ParsableCommand {
        static let configuration = CommandConfiguration(shouldDisplay: false)
    }

    struct Passed: ParsableCommand, JSONPassthrough {}

    struct Quick: OutputCommand {
        var json = false
        static let jsonStyle = Output.JSONStyle.document
        func execute(_ output: Output) async throws -> Reply { Reply(0, text: nil) }
    }

    struct Streamed: OutputCommand {
        var json = false
        static let jsonStyle = Output.JSONStyle.events
        func execute(_ output: Output) async throws -> Reply { Reply(0, text: nil) }
    }

    /// A stream that an option makes a document.
    struct Once: OutputCommand {
        var json = false
        var once = true
        static let jsonStyle = Output.JSONStyle.events
        var jsonStyleOfRun: Output.JSONStyle { once ? .document : .events }
        func execute(_ output: Output) async throws -> Reply { Reply(0, text: nil) }
    }

    @Test func listsTheCommandsWithoutJSONAndTheOnesThatStream() {
        let support = CommandTree.jsonSupport(of: Root.self)
        #expect(support.withoutJSON == ["plain"])
        #expect(support.events == ["group streamed", "group once"])
        #expect(CommandTree.visibleCommandPaths(of: Root.self).map(\.path)
            == ["plain", "quick", "group", "group streamed", "group once", "passed"])
    }

    @Test func theStyleOfARunIsTheCommandsUnlessItSaysOtherwise() {
        #expect(Streamed().jsonStyleOfRun == .events)
        #expect(Once().jsonStyleOfRun == .document)
    }
}
