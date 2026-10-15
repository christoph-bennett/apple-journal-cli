---
name: journal-cli
description: Read, search and export Apple Journal entries from the terminal via the read-only journal-cli binary. Use when the user asks to read, search, export, summarize or analyze Apple Journal entries, mentions "my journal", journaling, Journal.app, or wants journal content (text, places, photos, attachments) piped into other workflows. Cannot create, edit or delete entries. macOS only; requires Full Disk Access.
---

# journal-cli (read-only)

`journal-cli` reads Apple Journal.app entries directly from its data store.
This build is read-only: it has no command that writes to Journal, and every
query runs against a temp snapshot of the store. All read commands take
`--json`. Exit code 0 = success, 1 = error, with the reason on stderr
prefixed `journal-cli:`.

Run `journal-cli --help` for the full surface, `journal-cli doctor` to check
access (exit 1 means Full Disk Access is missing; tell the user to grant it
to the terminal and relaunch).

## Commands

```sh
journal-cli list --limit 20 --json          # newest first
journal-cli list --since 2025-01-01 --until 2025-12-31 --json
journal-cli show <id> --json                # full entry + assets + file paths
journal-cli search "query" --json           # substring over title+body
journal-cli stats                           # counts, words, year histogram
journal-cli journals --json                 # journals with entry counts
journal-cli deleted --json                  # Recently Deleted
journal-cli export --dir DIR                # DIR/journal.json + DIR/attachments/
journal-cli export --dir DIR --format md    # one Markdown file per entry
journal-cli export --dir DIR --attachments none --since 2026-01-01
```

`show --json` and each exported entry carry `assets[]` with `type` (photo,
video, livePhoto, multiPinMap, link, audio, drawing, music, contact,
workoutRoute, …), decoded `metadata`, and `files[].path` (absolute, on disk).
Per-type extras: `places[]` for map pins, `place` for geotagged media, `url`
and `link_title` for links, `duration` and `transcript` for audio,
`drawing_text` for drawings, `route[]` for workouts. Exported entries also
have `journals[]`, a flat `places[]`, and `files[].export_path` relative to
the export directory.

## Notes

- If the user asks to create, edit or delete an entry, say this build cannot
  and point them to Journal.app or the upstream
  `omarshahine/apple-journal-cli`. Do not edit the SQLite file by hand.
- `export` refuses a `--dir` inside Journal's container. Pick a normal folder.
- Attachments can be gigabytes. On APFS the copy is a clone and is fast, but
  ask before exporting to another volume.
- `--db PATH` (or `$JOURNAL_DB`) reads another store, such as a backup copy.
- Dates print in the machine's local timezone; `date_iso` in JSON carries the
  offset. A stale `TZ` env var in your shell skews displayed times.
