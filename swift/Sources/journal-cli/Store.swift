// Store.swift — snapshot reads, RTF, asset metadata, JSON output.
import Foundation
import AppKit

// ---------------------------------------------------------------- snapshot

/// Read-only access: copy db + -wal + -shm aside so the live store is never touched.
/// The live files are only ever opened for reading (by the copy); every query
/// runs against the temp copy, which is deleted afterwards.
func withSnapshot<T>(_ body: (DB) -> T) -> T {
    let fm = FileManager.default
    guard fm.fileExists(atPath: DB_PATH) else { die("store not found at \(DB_PATH)") }
    let tmp = NSTemporaryDirectory() + "journal-cli." + uid()
    try? fm.createDirectory(atPath: tmp, withIntermediateDirectories: true)
    defer { try? fm.removeItem(atPath: tmp) }
    let base = URL(fileURLWithPath: DB_PATH).lastPathComponent
    for suf in ["", "-wal", "-shm"] {
        let src = DB_PATH + suf
        if fm.fileExists(atPath: src) {
            do { try fm.copyItem(atPath: src, toPath: tmp + "/" + base + suf) }
            catch {
                die("permission denied. Grant Full Disk Access to this terminal, then relaunch it.")
            }
        }
    }
    return body(DB(path: tmp + "/" + base))
}

// ---------------------------------------------------------------- RTF

func rtfToText(_ blob: Data?) -> String {
    guard let blob = blob, !blob.isEmpty else { return "" }
    guard let att = NSAttributedString(rtf: blob, documentAttributes: nil) else { return "" }
    return att.string.trimmingCharacters(in: .whitespacesAndNewlines)
}

// ---------------------------------------------------------------- asset metadata

/// Journal asset metadata: version byte 0x01 + JSON; 0x02 + UUID = Core Data
/// external-storage ref into .moments_SUPPORT/_EXTERNAL_DATA/.
func parseMeta(_ b: Data?) -> [String: Any]? {
    guard let b = b, !b.isEmpty else { return nil }
    if b.first == 0x02 {
        var t = b.dropFirst()
        while t.last == 0 { t = t.dropLast() }
        guard let ref = String(data: t, encoding: .ascii) else { return nil }
        return ["ref": ref]
    }
    let body = b.first == 0x01 ? b.dropFirst() : b[...]
    return (try? JSONSerialization.jsonObject(with: Data(body))) as? [String: Any]
}

func resolveMeta(_ b: Data?) -> [String: Any]? {
    guard let p = parseMeta(b) else { return nil }
    if p.count == 1, let ref = p["ref"] as? String {
        let f = externalDataDir() + "/" + ref
        if let raw = FileManager.default.contents(atPath: f),
           var ext = (try? JSONSerialization.jsonObject(with: raw)) as? [String: Any] {
            ext["_external"] = ref
            return ext
        }
    }
    return p
}

// ---------------------------------------------------------------- JSON output

func jsonData(_ obj: Any) -> Data {
    try! JSONSerialization.data(withJSONObject: obj,
        options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
}

func printJSON(_ obj: Any) {
    print(String(data: jsonData(obj), encoding: .utf8)!)
}
