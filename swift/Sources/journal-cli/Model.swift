// Model.swift — entries, assets, journals: queries shared by the commands.
import Foundation

struct Entry {
    var id: Int64
    var uuid: String?
    var date: String?
    var dateISO: String?
    var created: String?
    var updated: String?
    var title: String
    var text: String
    var chars: Int64
    var bookmarked: Bool
    var draft: Bool
    var synced: Bool
    var entryType: String?
    var dateSource: String?

    var json: [String: Any] {
        ["id": id, "uuid": uuid as Any, "date": date as Any, "date_iso": dateISO as Any,
         "created": created as Any, "updated": updated as Any,
         "title": title, "text": text, "chars": chars, "bookmarked": bookmarked,
         "draft": draft, "synced": synced,
         "entry_type": entryType as Any, "date_source": dateSource as Any]
    }
}

private let ENTRY_COLUMNS = """
    Z_PK, ZID, ZENTRYDATE, ZCREATEDDATE, ZUPDATEDDATE, ZTEXTLENGTH, ZFLAGGED, ZISDRAFT,
    ZISUPLOADEDTOCLOUD, ZENTRYTYPE, ZDATESOURCE, ZTITLE, ZTEXT
    """

private func entryFrom(_ r: [String: Any]) -> Entry {
    let dt = r.d("ZENTRYDATE")
    return Entry(id: r.i("Z_PK") ?? 0, uuid: uString(r.b("ZID")),
                 date: dt.map(fmtDate), dateISO: dt.map(isoDate),
                 created: r.d("ZCREATEDDATE").map(isoDate),
                 updated: r.d("ZUPDATEDDATE").map(isoDate),
                 title: rtfToText(r.b("ZTITLE")), text: rtfToText(r.b("ZTEXT")),
                 chars: r.i("ZTEXTLENGTH") ?? 0, bookmarked: r.flag("ZFLAGGED"),
                 draft: r.flag("ZISDRAFT"), synced: r.flag("ZISUPLOADEDTOCLOUD"),
                 entryType: r.s("ZENTRYTYPE"), dateSource: r.s("ZDATESOURCE"))
}

func fetch(_ db: DB, since: Date? = nil, until: Date? = nil, includeEmpty: Bool = false) -> [Entry] {
    let rows = db.query("""
        select \(ENTRY_COLUMNS)
        from ZJOURNALENTRYMO
        where coalesce(ZISFULLYREMOVED,0)=0 and coalesce(ZRECENTLYDELETED,0)=0
        order by ZENTRYDATE desc
        """)
    var out: [Entry] = []
    for r in rows {
        guard let ts = r.d("ZENTRYDATE") else { continue }
        let e = entryFrom(r)
        let d = Date(timeIntervalSince1970: ts + CORE_DATA_EPOCH)
        if let s = since, d < s { continue }
        if let u = until, d > u { continue }
        if !includeEmpty && e.text.isEmpty && e.title.isEmpty { continue }
        out.append(e)
    }
    return out
}

func fetchOne(_ db: DB, _ pk: Int64) -> Entry? {
    guard let r = db.one("select \(ENTRY_COLUMNS) from ZJOURNALENTRYMO where Z_PK=?", [pk])
    else { return nil }
    return entryFrom(r) // date stays nil when the row has none
}

// ---------------------------------------------------------------- assets

/// Metadata keys holding opaque archived blobs (MapKit items, map styling,
/// camera state, LPLinkMetadata, CLLocation routes). Their useful content is
/// decoded into named fields below; the base64 itself is only noise in an export.
private let OPAQUE_META_KEYS: Set<String> = ["mapItemData", "styleData", "mapCameraData", "data",
                                             "routeData"]

private func scrubMeta(_ v: Any) -> Any {
    if let d = v as? [String: Any] {
        var out: [String: Any] = [:]
        for (k, x) in d where !OPAQUE_META_KEYS.contains(k) { out[k] = scrubMeta(x) }
        return out
    }
    if let a = v as? [Any] { return a.map(scrubMeta) }
    return v
}

private func placeFrom(_ v: [String: Any]) -> [String: Any] {
    // Copy only keys that are present: wrapping a missing value `as Any` stores
    // an Optional, which then prints as "Optional(47.6)" in Markdown output.
    var p: [String: Any] = [:]
    if let n = v["placeName"] { p["name"] = n }
    if let lat = v["latitude"] { p["lat"] = lat }
    if let lon = v["longitude"] { p["lon"] = lon }
    if let c = v["city"] { p["city"] = c }
    if let t = v["typeOfPlace"] { p["type"] = t }
    return p
}

func assetsFor(_ db: DB, _ pk: Int64) -> [[String: Any]] {
    var out: [[String: Any]] = []
    for r in db.query("""
        select Z_PK, ZID, ZASSETTYPE, ZSOURCE, ZCREATEDDATE, ZISHIDDEN, ZASSETMETADATA
        from ZJOURNALENTRYASSETMO where ZENTRY=? order by Z_PK
        """, [pk]) {
        let m = resolveMeta(r.b("ZASSETMETADATA")) ?? [:]
        let type = r.s("ZASSETTYPE") ?? "?"
        var a: [String: Any] = ["id": r.i("Z_PK") ?? 0, "uuid": uString(r.b("ZID")) as Any,
                                "type": type, "source": r.s("ZSOURCE") as Any,
                                "created": r.d("ZCREATEDDATE").map(isoDate) as Any,
                                "hidden": r.flag("ZISHIDDEN"),
                                "metadata": scrubMeta(m)]
        switch type {
        case "multiPinMap", "genericMap":
            // visitsData is normally a list of visits; one genericMap in the
            // wild carries a single visit dict instead.
            var visits = (m["visitsData"] as? [[String: Any]]) ?? []
            if let one = m["visitsData"] as? [String: Any] { visits = [one] }
            a["places"] = visits.filter { $0["latitude"] != nil }.map(placeFrom)
        case "audio":
            if let d = m["duration"] { a["duration"] = d }
            let segs = (m["transcriptSegments"] as? [[String: Any]]) ?? []
            let words = segs.compactMap { $0["text"] as? String }.filter { !$0.isEmpty }
            if !words.isEmpty { a["transcript"] = words.joined(separator: " ") }
        case "drawing":
            if let ic = (m["indexableContent"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines), !ic.isEmpty {
                a["drawing_text"] = ic
            }
        case "workoutRoute":
            if let route = decodeRoute(m) { a["route"] = route }
        case "link":
            let (url, title) = decodeLinkPayload(m)
            if let url = url { a["url"] = url }
            if let title = title { a["link_title"] = title }
        default:
            if m["latitude"] != nil { a["place"] = placeFrom(m) }
        }
        var files: [[String: Any]] = []
        for f in db.query("""
            select ZFILEPATH, ZNAME, ZINDEX from ZJOURNALENTRYASSETFILEATTACHMENTMO
            where ZASSET=? order by ZINDEX
            """, [r.i("Z_PK") ?? 0]) {
            guard let p = f.s("ZFILEPATH"), !p.isEmpty else { continue }
            let full = p.hasPrefix("/") ? p : attachDir() + "/" + p
            let size = (try? FileManager.default.attributesOfItem(atPath: full)[.size]) as? Int64
            files.append(["path": full, "relative_path": p, "name": f.s("ZNAME") as Any,
                          "exists": size != nil, "bytes": size as Any])
        }
        a["files"] = files
        out.append(a)
    }
    return out
}

/// Entry pk -> journal pks, from Journal's many-to-many membership table.
/// Entries with no row belong to the default journal only.
func memberships(_ db: DB) -> [Int64: [Int64]] {
    var out: [Int64: [Int64]] = [:]
    for r in db.query("select Z_5ENTRIES as e, Z_6JOURNALS as j from Z_5JOURNALS order by 2") {
        out[r.i("e") ?? 0, default: []].append(r.i("j") ?? 0)
    }
    return out
}

// ---------------------------------------------------------------- journals

struct JournalRow { var pk: Int64; var name: String; var isDefault: Bool }

// A journal's name lives in its ZMERGEABLEATTRIBUTES CRDT blob: an 8-byte
// "crdt" + version header, then protobuf. The attribute strings sit in the
// field 6 submessage as repeated length-delimited values (field 2), laid out
// as alternating value/key pairs -- "TV", "title", "Sand", "color", and so on.
//
// Reading the lengths matters. Scanning for runs of printable bytes instead
// drops any name shorter than the run threshold and then reports whichever
// binary noise happens to sit next to "title" -- and since the replica ids in
// the same blob change as iCloud touches the record, that name is not even
// stable between two runs of the same command.

/// Read one base-128 varint, advancing `i`. nil if it runs off the end.
private func crdtVarint(_ b: [UInt8], _ i: inout Int) -> UInt64? {
    var value: UInt64 = 0, shift: UInt64 = 0
    while i < b.count {
        let byte = b[i]
        i += 1
        value |= UInt64(byte & 0x7f) << shift
        if byte & 0x80 == 0 { return value }
        shift += 7
        if shift > 63 { return nil }
    }
    return nil
}

/// Payloads of every length-delimited `field` at this nesting level, in order.
private func crdtFields(_ b: [UInt8], _ field: Int) -> [[UInt8]] {
    var out: [[UInt8]] = []
    var i = 0
    while i < b.count {
        guard let key = crdtVarint(b, &i) else { return out }
        let number = Int(key >> 3)
        switch key & 7 {
        case 0: if crdtVarint(b, &i) == nil { return out }   // varint
        case 1: i += 8                                       // 64-bit
        case 5: i += 4                                       // 32-bit
        case 2:                                              // length-delimited
            guard let n = crdtVarint(b, &i), n <= UInt64(b.count - i) else { return out }
            let end = i + Int(n)
            if number == field { out.append(Array(b[i ..< end])) }
            i = end
        default: return out                                  // group/unknown wire type
        }
        if i > b.count { return out }
    }
    return out
}

func journalName(fromCRDT blob: Data) -> String? {
    let bytes = [UInt8](blob)
    guard bytes.count > 8 else { return nil }
    var strings: [String] = []
    for submessage in crdtFields(Array(bytes[8...]), 6) {
        for s in crdtFields(submessage, 2) {
            strings.append(String(decoding: s, as: UTF8.self))
        }
    }
    // Walk the value/key pairs rather than searching for "title", so a
    // journal actually named "title" reports its own name and not the key.
    var i = 0
    while i + 1 < strings.count {
        if strings[i + 1] == "title" { return strings[i] }
        i += 2
    }
    return nil
}

func journalRows(_ db: DB) -> [JournalRow] {
    var out: [JournalRow] = []
    for r in db.query("""
        select Z_PK, ZMERGEABLEATTRIBUTES, ZSORTCATEGORY from ZJOURNALMO
        where coalesce(ZUSERDELETED,0)=0 order by Z_PK
        """) {
        var name = "Journal" // the built-in default has no CRDT blob
        var isDefault = false
        if let blob = r.b("ZMERGEABLEATTRIBUTES") {
            if let n = journalName(fromCRDT: blob) { name = n }
        } else if let sc = r.d("ZSORTCATEGORY"), sc < 0 {
            isDefault = true
        }
        out.append(JournalRow(pk: r.i("Z_PK") ?? 0, name: name, isDefault: isDefault))
    }
    return out
}
