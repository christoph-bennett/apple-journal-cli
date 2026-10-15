// journal-cli — read and export Apple Journal entries straight from its Core Data store.
//
// Read-only fork of omarshahine/apple-journal-cli: every command works on a
// temp snapshot of the store, and the SQLite layer has no write path at all.
//
// Store: ~/Library/Group Containers/group.com.apple.moments/Library/moments.sqlite
// ("moments" is Journal's internal codename.) Requires Full Disk Access.
import Foundation

let VERSION = "2.0.0"

let HELP = """
USAGE: journal-cli [--db PATH] <command> [options]

Read and export Apple Journal entries from the local Core Data store.
Read-only: this build has no command, flag or code path that writes to Journal.

  list      [--limit N] [--since D] [--until D] [--include-empty] [--full] [--json]
  show      <id> [--json]
  search    <query> [--limit N] [--full] [--json]
  export    --dir DIR [--format json|md] [--attachments copy|none]
            [--since D] [--until D] [--include-empty]
            json (default): DIR/journal.json with entries, text, journals,
            places and every asset's metadata; attachments are copied to
            DIR/attachments/ unless --attachments none
  stats
  journals  [--json]
  deleted   [--json]
  doctor
  version
"""

var argv = Array(CommandLine.arguments.dropFirst())

// global --db (also honored via $JOURNAL_DB)
if let i = argv.firstIndex(of: "--db") {
    guard i + 1 < argv.count else { die("--db needs a value") }
    DB_PATH = (argv[i + 1] as NSString).expandingTildeInPath
    argv.removeSubrange(i...(i + 1))
}

guard let cmd = argv.first, cmd != "--help", cmd != "-h", cmd != "help" else {
    print(HELP)
    exit(argv.first == nil ? 1 : 0)
}
let rest = Array(argv.dropFirst())

let REMOVED: Set<String> = ["write", "edit", "delete", "restore", "empty", "repair-locations",
                            "sync-journals", "sandbox", "render"]
if REMOVED.contains(cmd) {
    die("'\(cmd)' was removed: this is a read-only build of journal-cli.")
}

let boolFlags: Set<String> = ["--json", "--full", "--include-empty"]
let valueFlags: Set<String> = ["--limit", "--since", "--until", "--dir", "--format", "--attachments"]

let a = Args(rest, valueFlags: valueFlags, boolFlags: boolFlags)

switch cmd {
case "list":     cmdList(a)
case "show":     cmdShow(a)
case "search":   cmdSearch(a)
case "export":   cmdExport(a)
case "stats":    cmdStats(a)
case "journals": cmdJournals(a)
case "deleted":  cmdDeleted(a)
case "doctor":   cmdDoctor(a)
case "version", "--version": print("journal-cli \(VERSION) (read-only)")
default:
    die("unknown command '\(cmd)'\n\n\(HELP)")
}
