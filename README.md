# swift-cli-output

One output convention for command-line tools built on
[ArgumentParser](https://github.com/apple/swift-argument-parser): text for people by default, and
JSON with `--json`.

- A command returns one `Reply`, which holds a value (printed as JSON) and a text (printed for
  people). The shared `run()` prints the right one, so a command cannot print its result any
  other way.
- With `--json`, a command that finishes quickly prints one JSON document: pretty-printed, keys
  sorted, dates in ISO 8601.
- A command that streams or has progress prints JSON Lines instead: `{"event":"log","message":…}`
  for progress, the command's own events as `{"event":"<name>","<name>":…}`, and
  `{"event":"result","result":…}` if it ends with a result.
- A failure under `--json` prints `{"error":…}` (or `{"event":"error","error":…}`) on stdout and
  `Error: …` on stderr, and exits with 1, or with the error's own status if it is an
  `ExitStatusError`.
- In JSON mode nothing else reaches stdout: file descriptor 1 is pointed at stderr, so a child
  process's output cannot land in the JSON.
- Output never depends on whether stdout is a terminal.

## Use

```swift
.package(url: "https://github.com/hobo-vm/swift-cli-output", from: "0.1.0")
```

```swift
import ArgumentParser
import CLIOutput

struct List: OutputCommand {
    @Flag(name: .long, help: "Print JSON.") var json = false
    static let jsonStyle = Output.JSONStyle.document

    func execute(_ output: Output) async throws -> Reply {
        let items = try loadItems()
        let rows = items.map { [$0.name, $0.state] }
        return Reply(items, text: Table.format(header: ["NAME", "STATE"], rows: rows))
    }
}
```

A command with progress sets `jsonStyle` to `.events` and calls `output.log("…")` as it goes. A
command that streams calls `output.event("name", value, text: "…")` for each item.

`Table` lays a list out as aligned columns under a header, and prints nothing for an empty list.
`CommandTree.jsonSupport(of:)` lists the commands without `--json` and the ones that stream, for
a usage text or for a test that stops a new command going without.

## License

Apache 2.0. See [LICENSE](LICENSE).
