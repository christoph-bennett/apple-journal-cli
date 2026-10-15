"""Seed the schema-only fixture: Core Data bookkeeping, three journals, and a
few synthetic entries with assets for the read/export tests.

Contains zero personal data. Invoked by make-fixture.sh.
"""
import json, os, sqlite3, sys, uuid

db = sqlite3.connect(sys.argv[1])

# Core Data primary-key bookkeeping the CLI relies on
for ent, name in [(1, "AppStorageMO"),
                  (2, "JournalEntryAssetAttachmentMO"),
                  (3, "JournalEntryAssetFileAttachmentMO"),
                  (4, "JournalEntryAssetMO"),
                  (5, "JournalEntryMO"),
                  (6, "JournalMO"),
                  (7, "SyncDataMO")]:
    db.execute("insert into Z_PRIMARYKEY (Z_ENT, Z_NAME, Z_SUPER, Z_MAX) values (?,?,0,0)",
               (ent, name))

# The built-in default journal: no CRDT blob, negative sort category
db.execute("""insert into ZJOURNALMO
              (Z_PK, Z_ENT, Z_OPT, ZISUPLOADEDTOCLOUD, ZSORTCATEGORY, ZSORTORDER, ZUSERDELETED, ZID)
              values (1, 6, 1, 1, -10, 1, 0, ?)""",
           (uuid.UUID("01000000-0000-0000-0000-000000000000").bytes,))

def _len_delimited(field, payload):
    """One protobuf length-delimited record: tag byte, varint length, bytes."""
    out = bytearray([(field << 3) | 2])
    n = len(payload)
    while True:
        b = n & 0x7f
        n >>= 7
        out.append(b | (0x80 if n else 0))
        if not n:
            break
    return bytes(out) + payload


def journal_crdt(name, color="Blue", icon="book.fill"):
    """A CRDT attribute blob shaped the way Journal.app writes one.

    Real blobs are an 8-byte "crdt" + version header followed by protobuf.
    The attributes live in the field 6 submessage: 48 bytes of replica ids
    (field 1), then the values and their keys alternating as length-delimited
    strings (field 2) -- "Test Journal", "title", "Blue", "color", and so on.

    Worth encoding faithfully rather than approximating: a fixture that only
    lays printable words next to each other will pass for a parser that scans
    for printable runs while telling you nothing about whether real blobs
    still decode.
    """
    body = _len_delimited(1, b"\x00" * 48)
    for s in (name, "title", color, "color", icon, "icon"):
        body += _len_delimited(2, s.encode("utf-8"))
    return b"crdt\x07\x00\x00\x00" + _len_delimited(6, body)


# A second journal named "Test Journal" so journal-targeting tests run.
blob = journal_crdt("Test Journal")
db.execute("""insert into ZJOURNALMO
              (Z_PK, Z_ENT, Z_OPT, ZISUPLOADEDTOCLOUD, ZSORTCATEGORY, ZSORTORDER, ZUSERDELETED,
               ZID, ZMERGEABLEATTRIBUTES)
              values (2, 6, 1, 1, 0, 0, 0, ?, ?)""",
           (uuid.uuid4().bytes, blob))
# A third journal with a two-character name. Short names are the case a
# printable-run scan of the blob gets wrong: too short to survive the scan's
# minimum run length, so the name silently becomes whichever bytes of the
# neighbouring replica ids happen to be printable.
db.execute("""insert into ZJOURNALMO
              (Z_PK, Z_ENT, Z_OPT, ZISUPLOADEDTOCLOUD, ZSORTCATEGORY, ZSORTORDER, ZUSERDELETED,
               ZID, ZMERGEABLEATTRIBUTES)
              values (3, 6, 1, 1, 0, 0, 0, ?, ?)""",
           (uuid.uuid4().bytes, journal_crdt("TV", color="Sand", icon="sparkles.tv.fill")))
db.execute("update Z_PRIMARYKEY set Z_MAX=3 where Z_NAME='JournalMO'")

# ---------------------------------------------------------------- entries
# The read-only build has no write commands, so test data goes in here.
CD_EPOCH = 978307200
ATTACH = os.path.join(os.path.dirname(sys.argv[1]), "Attachments")


def rtf(text):
    return ("{\\rtf1\\ansi\\deff0 {\\fonttbl {\\f0 Helvetica;}}\\f0 "
            + text.replace("\n", "\\par ") + "}").encode()


def meta(obj):
    return b"\x01" + json.dumps(obj).encode()


def entry(pk, when, title, text, flagged=0, deleted=0):
    db.execute("""insert into ZJOURNALENTRYMO
                  (Z_PK, Z_ENT, Z_OPT, ZID, ZENTRYDATE, ZCREATEDDATE, ZUPDATEDDATE, ZTITLE, ZTEXT,
                   ZTEXTLENGTH, ZFLAGGED, ZISDRAFT, ZISUPLOADEDTOCLOUD, ZRECENTLYDELETED,
                   ZISFULLYREMOVED, ZENTRYTYPE, ZDATESOURCE)
                  values (?,5,1,?,?,?,?,?,?,?,?,0,1,?,0,'blankEntry','custom')""",
               (pk, uuid.uuid4().bytes, when - CD_EPOCH, when - CD_EPOCH, when - CD_EPOCH,
                rtf(title) if title else None, rtf(text), len(text), flagged, deleted))
    return db.execute("select ZID from ZJOURNALENTRYMO where Z_PK=?", (pk,)).fetchone()[0]


def asset(pk, entry_pk, kind, m):
    aid = uuid.uuid4()
    db.execute("""insert into ZJOURNALENTRYASSETMO
                  (Z_PK, Z_ENT, Z_OPT, ZENTRY, ZID, ZASSETTYPE, ZSOURCE, ZCREATEDDATE,
                   ZASSETMETADATA, ZISHIDDEN)
                  values (?,4,1,?,?,?,'fixture',0,?,0)""",
               (pk, entry_pk, aid.bytes, kind, meta(m)))
    return aid


# Dates are noon UTC so they keep their calendar day in any timezone the
# --since test runs under (CI runs UTC and America/Los_Angeles).
# 1: text + map pin + photo with a real file, member of "Test Journal"
e1 = entry(1, 1767268800, "Fixture title", "First line of the fixture entry.\nSecond line.", flagged=1)
asset(1, 1, "multiPinMap", {"visitsData": [
    {"placeName": "Fixture Place", "city": "Testville", "latitude": 48.2, "longitude": 15.6,
     "mapItemData": "AAAA"}]})
a2 = asset(2, 1, "photo", {"latitude": 47.1, "longitude": 15.4, "placeName": "Photo Spot",
                           "date": 0})
rel = f"{uuid.UUID(bytes=e1)}".upper() + "/" + str(a2).upper() + "/image.jpg"
os.makedirs(os.path.join(ATTACH, os.path.dirname(rel)), exist_ok=True)
with open(os.path.join(ATTACH, rel), "wb") as f:
    f.write(b"\xff\xd8\xff\xe0fixture-not-a-real-jpeg\xff\xd9")
db.execute("""insert into ZJOURNALENTRYASSETFILEATTACHMENTMO
              (Z_PK, Z_ENT, Z_OPT, ZASSET, ZID, ZFILEPATH, ZNAME, ZINDEX)
              values (1,3,1,2,?,?,'image',0)""", (uuid.uuid4().bytes, rel))
asset(3, 1, "music", {"song": "Fixture Song", "artistName": "Fixture Band"})
db.execute("insert into Z_5JOURNALS (Z_5ENTRIES, Z_6JOURNALS) values (1, 2)")

# 2: plain text, default journal
entry(2, 1767355200, None, "Second fixture entry, no title.")

# 3: in Recently Deleted -- must not appear in list/export
entry(3, 1767441600, None, "Deleted fixture entry.", deleted=1)

for name, mx in [("JournalEntryMO", 3), ("JournalEntryAssetMO", 3),
                 ("JournalEntryAssetFileAttachmentMO", 1)]:
    db.execute("update Z_PRIMARYKEY set Z_MAX=? where Z_NAME=?", (mx, name))
db.commit()
