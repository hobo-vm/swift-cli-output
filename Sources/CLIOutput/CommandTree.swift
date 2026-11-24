import ArgumentParser

/// What a program's commands do about `--json`, read from the command types themselves, for a
/// usage text that lists it and a test that keeps a new command from going without.
public enum CommandTree {
    /// Each visible command with its name as typed after the root (`session list`). Depth-first,
    /// in declaration order, so nested commands follow their parent.
    public static func visibleCommandPaths(of command: any ParsableCommand.Type, prefix: String = "")
        -> [(path: String, command: any ParsableCommand.Type)] {
        command.configuration.subcommands
            .filter { $0.configuration.shouldDisplay }
            .flatMap { sub in
                let path = prefix + sub._commandName
                return [(path, sub)] + visibleCommandPaths(of: sub, prefix: path + " ")
            }
    }

    /// Which visible commands lack `--json` and which stream JSON Lines, read from each command's
    /// `OutputCommand` conformance and `jsonStyle`. A group only holds subcommands, so it's in
    /// neither list; nor is a `JSONPassthrough` command in the first.
    public static func jsonSupport(of root: any ParsableCommand.Type) -> (withoutJSON: [String], events: [String]) {
        var withoutJSON: [String] = []
        var events: [String] = []
        for (path, command) in visibleCommandPaths(of: root) {
            guard let outputCommand = command as? any OutputCommand.Type else {
                if command.configuration.subcommands.isEmpty && !(command is any JSONPassthrough.Type) { withoutJSON.append(path) }
                continue
            }
            if outputCommand.jsonStyle == .events { events.append(path) }
        }
        return (withoutJSON, events)
    }
}
