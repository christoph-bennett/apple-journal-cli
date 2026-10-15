#!/usr/bin/env bash
# Read/export tests for the read-only build. Runs against the synthetic
# fixture from make-fixture.sh, never the real Journal store, and fails if
# any command changes a byte of the fixture.
#
# Usage: JOURNAL_SEED=/path/to/fixture/moments.sqlite tests/test_read.sh
# JOURNAL_CLI overrides the binary under test (default: the release build).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
CLI="${JOURNAL_CLI:-$HERE/../swift/.build/release/journal-cli}"
DB="${JOURNAL_SEED:?set JOURNAL_SEED to a fixture store (tests/make-fixture.sh DIR)}"
STORE_DIR="$(dirname "$DB")"
OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT
echo "testing: $CLI against $DB"

pass=0; fail=0
ok()   { pass=$((pass + 1)); echo "  ok   $1"; }
bad()  { fail=$((fail + 1)); echo "  FAIL $1"; }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi }
jc()   { "$CLI" --db "$DB" "$@"; }
# Run a Python one-liner against a JSON file: pyj FILE 'expression using d'
pyj()  { python3 -I -c "import json,sys; d=json.load(open(sys.argv[1])); print($2)" "$1"; }

fingerprint() {
  (cd "$STORE_DIR" && find . -type f -print0 | sort -z | xargs -0 shasum)
}
BEFORE="$(fingerprint)"

echo "T1 list / show / search"
jc list --json > "$OUT/list.json"
check "list skips Recently Deleted" '[ "$(pyj "$OUT/list.json" "len(d)")" = 2 ]'
check "list newest first" '[ "$(pyj "$OUT/list.json" "d[0][\"id\"]")" = 2 ]'
jc show 1 --json > "$OUT/show.json"
check "show decodes RTF title" '[ "$(pyj "$OUT/show.json" "d[\"title\"]")" = "Fixture title" ]'
check "show has map place" \
  '[ "$(pyj "$OUT/show.json" "[p for a in d[\"assets\"] for p in a.get(\"places\",[])][0][\"name\"]")" = "Fixture Place" ]'
check "show scrubs opaque blobs" \
  '[ "$(pyj "$OUT/show.json" "\"mapItemData\" in json.dumps(d)")" = False ]'
check "search finds entry" '[ "$(jc search "second fixture" --json | python3 -I -c "import json,sys; print(len(json.load(sys.stdin)))")" = 1 ]'

echo "T2 journals / deleted / stats"
check "journals lists all three" '[ "$(jc journals --json | python3 -I -c "import json,sys; print(len(json.load(sys.stdin)))")" = 3 ]'
check "deleted lists the deleted entry" '[ "$(jc deleted --json | python3 -I -c "import json,sys; print(len(json.load(sys.stdin)))")" = 1 ]'
check "stats runs" 'jc stats >/dev/null'

echo "T3 JSON export"
jc export --dir "$OUT/x" > "$OUT/export.log"
J="$OUT/x/journal.json"
check "journal.json written" '[ -s "$J" ]'
check "export header" '[ "$(pyj "$J" "d[\"export\"][\"format\"]")" = journal-cli-export ]'
check "two live entries exported" '[ "$(pyj "$J" "len(d[\"entries\"])")" = 2 ]'
check "entry text multi-line" \
  '[ "$(pyj "$J" "[e for e in d[\"entries\"] if e[\"id\"]==1][0][\"text\"].count(chr(10))")" = 1 ]'
check "journal membership" \
  '[ "$(pyj "$J" "[e for e in d[\"entries\"] if e[\"id\"]==1][0][\"journals\"][0][\"name\"]")" = "Test Journal" ]'
check "default journal for unassigned" \
  '[ "$(pyj "$J" "[e for e in d[\"entries\"] if e[\"id\"]==2][0][\"journals\"][0][\"name\"]")" = Journal ]'
check "places flattened (map + photo)" \
  '[ "$(pyj "$J" "len([e for e in d[\"entries\"] if e[\"id\"]==1][0][\"places\"])")" = 2 ]'
check "non-media asset metadata kept" \
  '[ "$(pyj "$J" "[a for e in d[\"entries\"] for a in e[\"assets\"] if a[\"type\"]==\"music\"][0][\"metadata\"][\"song\"]")" = "Fixture Song" ]'
check "date_iso has offset" '[ -n "$(pyj "$J" "d[\"entries\"][0][\"date_iso\"]" | grep -E "[+-][0-9]{2}:[0-9]{2}$|Z$")" ]'
REL="$(pyj "$J" "[f for e in d[\"entries\"] for a in e[\"assets\"] for f in a[\"files\"]][0][\"export_path\"]")"
check "attachment copied" '[ -f "$OUT/x/$REL" ] && cmp -s "$OUT/x/$REL" "$STORE_DIR/Attachments/${REL#attachments/}"'
check "re-export skips present files" \
  '"$CLI" --db "$DB" export --dir "$OUT/x" | grep -q "0 copied, 1 already present"'
jc export --dir "$OUT/n" --attachments none >/dev/null
check "--attachments none copies nothing" '[ ! -e "$OUT/n/attachments" ]'
jc export --dir "$OUT/s" --since 2026-01-02 >/dev/null
check "--since filters" '[ "$(pyj "$OUT/s/journal.json" "len(d[\"entries\"])")" = 1 ]'

echo "T4 Markdown export"
jc export --dir "$OUT/md" --format md >/dev/null
MD="$(ls "$OUT"/md/*-1-*.md 2>/dev/null | head -1)"
check "md file per entry" '[ "$(ls "$OUT"/md/*.md | wc -l | tr -d " ")" = 2 ]'
check "md has locations" 'grep -q "lat: 48.2" "$MD"'
check "md has no Optional() leak" '! grep -q "Optional(" "$OUT"/md/*.md'
check "md links copied attachment" 'grep -q "](attachments/" "$MD"'

echo "T5 read-only guarantees"
for c in write edit delete restore empty repair-locations sync-journals sandbox render; do
  check "'$c' is removed" '! jc $c --live 2>&1 >/dev/null | grep -qv "was removed"; ! jc $c >/dev/null 2>&1'
done
check "export into the store dir is refused" '! jc export --dir "$STORE_DIR/inside" >/dev/null 2>&1'
check "nothing created in store dir" '[ ! -e "$STORE_DIR/inside" ]'
check "fixture store byte-identical" '[ "$(fingerprint)" = "$BEFORE" ]'
check "no write SQL in sources" \
  '! grep -rniE "\b(insert into|update [a-z_]+ set|delete from|drop table|sqlite3_exec\(h, \"(insert|update|delete))" "$HERE/../swift/Sources"'

echo; echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
