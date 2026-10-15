# apple-journal-cli (read-only fork)

> **Fork of [omarshahine/apple-journal-cli](https://github.com/omarshahine/apple-journal-cli)
> by Omar Shahine.** This fork removes every command that writes to Apple
> Journal and turns the tool into a read and export utility. If you want to
> create or edit entries from the terminal, use the original.

**Read and export Apple Journal entries from the terminal.** Text, titles,
journals, places, photos, videos, Live Photos, audio transcripts, workouts,
music, contacts and the rest of Journal's asset types, exported to one JSON
file plus a folder with every attachment. Native Swift, no dependencies,
macOS 14+.

Apple Journal has no public API and no export format worth scripting against.
journal-cli reads the app's own data store from a temporary copy, so the
live store is never opened by SQLite at all.

```
$ journal-cli export --dir ~/journal-export
Wrote 1340 entries to /Users/you/journal-export/journal.json
attachments: 1820 copied, 0 already present, 0 missing in store
```

## What changed from the original

- Removed: `write`, `edit`, `delete`, `restore`, `empty`, `repair-locations`,
  `sync-journals`, `sandbox`, `render`, the Day One importer, the Python
  reference implementation, and the npm/Homebrew release pipeline. Calling a
  removed command exits 1 with `'<cmd>' was removed`.
- The SQLite layer has no `exec()`. Connections open `SQLITE_OPEN_READONLY`
  with `PRAGMA query_only=1`, and they only ever open a temp snapshot.
- `export` defaults to JSON and copies attachments next to it. It now covers
  every asset type, journal membership, a flat `places` list per entry,
  decoded workout routes, and ISO 8601 timestamps with UTC offset.
- `export` refuses any `--dir` inside Journal's container.
- Fixed: Markdown export printed coordinates as `Optional(47.6)`.

## Install

```sh
git clone https://github.com/christoph-bennett/apple-journal-cli && cd apple-journal-cli/swift
swift build -c release && cp .build/release/journal-cli /usr/local/bin/
```

Grant **Full Disk Access** to your terminal (System Settings > Privacy &
Security), then:

```sh
journal-cli doctor
```

The binary keeps the name `journal-cli`. If you also have the original
installed, put this build somewhere else on your `PATH` or rename it.

## Commands

```sh
journal-cli list --limit 20 --full            # --full prints bodies
journal-cli list --since 2025-01-01 --until 2025-12-31 --json
journal-cli show 95 --json                    # entry + assets + attachment paths
journal-cli search tokyo
journal-cli stats                             # counts, words, by-year histogram
journal-cli journals                          # journals with entry counts
journal-cli deleted                           # Recently Deleted
journal-cli export --dir ~/journal-export     # JSON + attachments
journal-cli export --dir ~/md --format md     # one .md per entry, YAML frontmatter
journal-cli version
```

Every command reads from a temp snapshot of `moments.sqlite` plus its `-wal`
and `-shm` files, so it is safe to run while Journal.app is open. `--db PATH`
(or `$JOURNAL_DB`) points at another store, such as a backup copy.

## Export

```sh
journal-cli export --dir DIR [--format json|md] [--attachments copy|none]
                   [--since YYYY-MM-DD] [--until YYYY-MM-DD] [--include-empty]
```

With the defaults you get:

```
DIR/
├── journal.json
└── attachments/<entryUUID>/<assetUUID>/<file>
```

Attachments are copied, never moved, keeping Journal's own folder layout.
On APFS the copy is a clone, so 2 GB of photos takes a couple of seconds and
no extra disk space until something changes. Re-running an export skips files
already present with the same size.

`journal.json` looks like this (trimmed):

```json
{
  "export": { "format": "journal-cli-export", "version": 1, "tool": "journal-cli 2.0.0",
              "exported_at": "2026-10-15T08:02:22Z", "attachments": "copy", "entry_count": 1340 },
  "journals": [ { "id": 1, "name": "Journal", "default": true } ],
  "entries": [
    {
      "id": 1056, "uuid": "…", "date": "2026-01-02 07:34:09",
      "date_iso": "2026-01-02T07:34:09+01:00", "created": "…", "updated": "…",
      "title": "", "text": "plain text of the entry", "chars": 412,
      "bookmarked": false, "draft": false, "synced": true,
      "entry_type": "blankEntry", "date_source": "custom",
      "journals": [ { "id": 1, "name": "Journal" } ],
      "places": [ { "name": "…", "city": "…", "lat": 44.67, "lon": 8.46,
                    "type": "…", "asset_type": "multiPinMap" } ],
      "assets": [
        { "id": 700, "uuid": "…", "type": "photo", "source": "…", "created": "…",
          "hidden": false, "metadata": { "date": 0, "placeName": "…", "latitude": 44.67 },
          "place": { "name": "…", "lat": 44.67, "lon": 8.46 },
          "files": [ { "name": "image", "path": "/Users/…/Attachments/…/IMG.jpeg",
                       "relative_path": "…/IMG.jpeg", "export_path": "attachments/…/IMG.jpeg",
                       "bytes": 812345, "exists": true } ] }
      ]
    }
  ]
}
```

Notes on the fields:

- `text` and `title` are plain text converted from Journal's RTF. Bold,
  lists and other formatting are not carried over.
- `places` merges map pins (`multiPinMap`, `genericMap`) with the location
  stored on photos and videos. `asset_type` says where each one came from.
- `metadata` is the asset's decoded metadata with opaque archived blobs
  removed (MapKit items, map styling, camera state, link archives, route
  archives). Their useful content appears as named fields instead:
  - `workoutRoute` assets get `route`: a list of `{lat, lon, alt, speed, time}` points.
  - `link` assets get `url` and `link_title` when the archive has them.
  - `audio` assets get `duration` and `transcript`.
  - `drawing` assets get `drawing_text`, the handwriting recognition text.
- `files[].path` is the original location in Journal's container, and
  `export_path` is relative to the export directory. It is missing when
  `--attachments none` is used.
- Entries in Recently Deleted are not exported. `deleted --json` lists them.

## Safety model

| Layer | Behavior |
|---|---|
| Snapshot | every command copies `db`+`-wal`+`-shm` to a temp dir and queries the copy; the copy is deleted afterwards |
| SQLite | `SQLITE_OPEN_READONLY` + `PRAGMA query_only=1`; the wrapper has no `exec()` |
| Commands | all write commands are gone from the binary; their names exit 1 |
| Export target | refused anywhere inside `~/Library/Group Containers/group.com.apple.moments` or next to `--db` |
| Tests | the suite fingerprints every file of the fixture store before and after and fails on any change, and greps the sources for write SQL |

## How it works

Journal's store is a Core Data SQLite database:

```
~/Library/Group Containers/group.com.apple.moments/Library/moments.sqlite
```

"moments" is Journal's internal codename, which is why searching for
"journal" never finds it. Entry text is plain RTF in `ZJOURNALENTRYMO.ZTEXT`
and is not encrypted. The encrypted CloudKit records under the app container
are only the sync cache.

| Data | Storage |
|---|---|
| entries | `ZJOURNALENTRYMO`; text/title as RTF blobs; Core Data epoch timestamps |
| assets | `ZJOURNALENTRYASSETMO`: photo, video, livePhoto, multiPinMap, genericMap, link, audio, drawing, contact, music, stateOfMind, workoutRoute, workoutIcon, motionActivity, streakEvent |
| files | `ZJOURNALENTRYASSETFILEATTACHMENTMO` → `Attachments/<entryUUID>/<assetUUID>/…` |
| asset metadata | one version byte `0x01` + JSON; `0x02` + UUID = Core Data external storage in `.moments_SUPPORT/_EXTERNAL_DATA/` |
| links | base64 `NSKeyedArchiver`-archived `LPLinkMetadata` inside the asset metadata |
| workout routes | base64 `NSKeyedArchiver` array of `CLLocation` |
| journals | `ZJOURNALMO` (names live in each journal's CRDT merge blob) + `Z_5JOURNALS` join; entries with no join row belong to the default journal |

Journal also keeps a CRDT copy of app-typed entry text in
`ZMERGEABLEATTRIBUTES`. This fork reads the RTF copy, which matches what the
app shows.

## Development

```sh
cd swift && swift build -c release
DB=$(tests/make-fixture.sh /tmp/jfixture)   # synthetic store, no personal data
JOURNAL_SEED="$DB" tests/test_read.sh
```

CI runs the suite under UTC and America/Los_Angeles.

## License

MIT, same as the original. See [LICENSE](LICENSE).
