// Media.swift — decoding archived link and workout-route payloads.
import Foundation
import CoreLocation
import LinkPresentation

/// Pull url/title back out of a link asset's archived LPLinkMetadata.
func decodeLinkPayload(_ meta: [String: Any]) -> (String?, String?) {
    guard let b64 = meta["data"] as? String,
          let raw = Data(base64Encoded: b64),
          let md = try? NSKeyedUnarchiver.unarchivedObject(ofClass: LPLinkMetadata.self,
                                                           from: raw) else { return (nil, nil) }
    return ((md.url ?? md.originalURL)?.absoluteString, md.title)
}

/// Decode a workoutRoute asset's routeData (base64 NSKeyedArchiver array of
/// CLLocation) into plain track points.
func decodeRoute(_ meta: [String: Any]) -> [[String: Any]]? {
    guard let b64 = meta["routeData"] as? String,
          let raw = Data(base64Encoded: b64),
          let locs = try? NSKeyedUnarchiver.unarchivedArrayOfObjects(ofClass: CLLocation.self,
                                                                     from: raw) else { return nil }
    let iso = ISO8601DateFormatter()
    return locs.map { l in
        var p: [String: Any] = ["lat": l.coordinate.latitude, "lon": l.coordinate.longitude,
                                "time": iso.string(from: l.timestamp)]
        if l.verticalAccuracy >= 0 { p["alt"] = l.altitude }
        if l.speed >= 0 { p["speed"] = l.speed }
        return p
    }
}
