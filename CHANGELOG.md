# Changelog

## 2.0.0 (read-only fork)

Forked from [omarshahine/apple-journal-cli](https://github.com/omarshahine/apple-journal-cli)
1.4.0. Versions below are the upstream history.

### Removed: every write path

- Commands `write`, `edit`, `delete`, `restore`, `empty`, `repair-locations`,
  `sync-journals`, `sandbox` and `render`. Calling one exits 1 with
  `'<cmd>' was removed`.
- The write helpers, backup and risk-acknowledgment code, Markdown-to-RTF
  rendering, image resizing and Photos lookup.
- `DB.exec()`. Connections open `SQLITE_OPEN_READONLY` with
  `PRAGMA query_only=1`, and only ever against a temp snapshot.
- `reference/` (Python implementation), `skills/dayone-import/`, the npm
  package and the release workflow that published to npm and Homebrew.

### Changed: export

- `--format json` is now the default, and `journal.json` is an object
  (`export`, `journals`, `entries`) instead of a bare array.
- Attachments are copied to `DIR/attachments/` (`--attachments none` to
  skip). Re-runs skip files already present with the same size.
- Entries carry `date_iso`, `created`, `updated`, `entry_type`,
  `date_source`, `journals[]` and a flat `places[]`.
- Assets carry their full decoded `metadata` minus opaque archived blobs, so
  contact, music, workout, motion and state-of-mind assets are no longer
  reduced to a bare type. Workout routes decode to `route[]` points.
- `--since`, `--until` and `--include-empty` work on `export`.
- `export` refuses a target inside Journal's container.

### Fixed

- Markdown export printed coordinates as `Optional(47.6)`.
- A `genericMap` whose `visitsData` is a single object, not a list, lost its place.

## 1.4.0

### Added — an entry can belong to more than one journal

Journal's membership table is many-to-many, and the app lists an entry under
every journal it belongs to. The CLI can now express that
([#11](https://github.com/omarshahine/apple-journal-cli/pull/11), thanks
[@rodchristiansen](https://github.com/rodchristiansen)):

- `write` accepts repeated `--journal` (and `--add-journal`).
- `edit --add-journal NAME` adds a membership and leaves the others alone;
  `edit --remove-journal NAME` drops one. Both repeat.
- `edit --journal` still *moves* the entry, replacing every membership;
  repeat it to land in several. Mixing it with `--add-journal` or
  `--remove-journal` is refused rather than guessed at.
- `edit --add-journal` to the default journal is refused: the default holds
  every entry that is in no other journal, so there is no membership to add.
  (`write` naming the default journal just creates the entry there.)

The journal flags take one name each. `edit --journal Travel 42` reads `42` as
the entry id, not as a second journal.

### Fixed — short journal names

Journal names are now read from the length prefixes of the journal's CRDT blob
instead of a scan for printable runs
([#8](https://github.com/omarshahine/apple-journal-cli/pull/8), thanks
[@adeolonoh](https://github.com/adeolonoh)). A name shorter than three
characters, such as "TV", used to come back as whatever replica-id bytes sat
next to it (and changed between runs), so `--journal TV` could not address it.
Non-ASCII names, which the Swift scan dropped, now decode too.

### Fixed — Python reference dates off by the UTC offset

`reference/journal-cli.py` now stores entry dates as the true instant, as the
Swift build does; it had shifted every date it wrote by the local UTC offset
([#12](https://github.com/omarshahine/apple-journal-cli/pull/12)). CI now runs
both implementations under UTC and America/Los_Angeles, so a timezone bug can
no longer hide behind UTC runners. The shipped binary was not affected.

## 1.3.0

### Fixed — `--location-presentation off` was erasing locations

**If you used `--location-presentation off` on 1.2.0, run
`journal-cli repair-locations --live`.** Your coordinates are not lost.

1.2.0 wrote `off` as `ZISHIDDEN=1` on the map asset. Apple Journal does not
model the map card that way: it reads such an asset as absent entirely, so the
entry ends up with **no map card *and* no Places entry** — the location is
effectively gone from the app.

Journal keeps a map's Off state only in the entry's own CRDT, whose key table
reads `title`, `gridAssetIDs`, `slimAssetID`, `hiddenAssetIDs`,
`assetPlacement`. An Off map is listed under `hiddenAssetIDs` there and its
asset row stays byte-identical to a large one (`ZISSLIM=0, ZISHIDDEN=0`).
Measured against a live store of 5,000+ assets: `ZISHIDDEN` is `0` on every
asset of every type, and on all 39 entries whose CRDT carries `hiddenAssetIDs`
the asset rows still read `ZISHIDDEN=0`.

Authoring CRDTs is out of scope, so `off` is not ours to write.
`--location-presentation` now accepts `small` and `large`; `off` exits 1 with
an explanation instead of silently destroying locations.

Reported by [@tonywalker23](https://x.com/tonywalker23).

### Added — `repair-locations`

Repairs map assets written by 1.2.0's `off`, in place. The coordinates were
only masked, never deleted, so no re-import is needed:

```sh
journal-cli repair-locations --dry-run         # count what is affected
journal-cli repair-locations --live            # restore as small maps
journal-cli repair-locations --to large --live
```

It also clears `ZISUPLOADEDTOCLOUD` on both the repaired assets and their
entries, so the correction reaches your other devices rather than staying
local.

### Fixed — test suite no longer depends on the seed store

`tests/test_write.sh` hardcoded a journal named "Test Journal", so seven
journal-targeting tests failed for anyone running it against a real library
instead of the synthetic fixture. It now resolves the journal's actual name.

## 1.2.0

> [!WARNING]
> `--location-presentation off` in this release **removes the location from
> Journal entirely**, including the Places index. Upgrade to 1.3.0 and run
> `journal-cli repair-locations --live`.

- `--location-presentation` for `write` and `edit` (see the 1.3.0 note above).

## 1.1.0

- `--markdown` renders bodies and titles into Journal's own rich text.
- `render` subcommand: Markdown to RTF on stdout, writes nothing.

## 1.0.x

- Initial release: read, search, export, write, edit, delete/restore,
  journals, media, Live Photos, links, locations, audio transcripts.
