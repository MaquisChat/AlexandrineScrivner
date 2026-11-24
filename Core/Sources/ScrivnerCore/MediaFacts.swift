import Foundation

/// What a media file says about itself, as read by ExifTool. This is what the research workbench
/// sees when it imports the file, so the session checker compares it with `session.json`.
public struct MediaFacts: Equatable, Sendable {
    /// Photos: the EXIF original date and time, with sub-seconds and offset when the file has them.
    public var original: ExifDate?
    /// Audio and video: the QuickTime creation time.
    public var created: ExifDate?
    /// Audio and video: Apple's creation-date key, which carries the local offset.
    public var creationDate: ExifDate?
    /// Where the file says it was made, read from where spec 6.3 puts it: the EXIF GPS tags of a
    /// photo, or Apple's location key of a clip. `accuracyM` is always nil; files do not carry it.
    public var location: GeoPoint?
    /// Any other tag in the file that holds a place, as `Group:Tag`, sorted. The workbench reads a
    /// place from whichever part of a file holds one, so a place tucked away here still counts.
    /// Also lists Apple's location key when it is there but cannot be read.
    public var strayLocationTags: [String] = []
    public var make: String?
    public var model: String?
    public var lens: String?
    public var durationMs: Int?
    /// Apple's Live Photo identifier. A session's files must not have one.
    public var contentIdentifier: String?
    /// Set when ExifTool could not read the file.
    public var error: String?

    public init() {}
}

public struct ExifToolOutputError: Error, Equatable {
    public let message: String
}

/// Reads what ExifTool prints when run with `arguments` followed by file names.
public enum ExifToolOutput {
    /// Everything before the file names on ExifTool's command line.
    ///
    /// `-n` gives plain numbers, `-G1` names each tag's group, and `QuickTimeUTC` makes ExifTool treat
    /// QuickTime times as UTC, which is how the files are written. `-a` with the four location tags
    /// asked for without a group lists a place wherever in the file it is kept.
    public static let arguments: [String] = [
        "-json", "-n", "-G1", "-api", "QuickTimeUTC=1", "-a",
        "-GPSLatitude", "-GPSLongitude", "-GPSCoordinates", "-GPSPosition",
        "-ExifIFD:DateTimeOriginal", "-ExifIFD:OffsetTimeOriginal", "-Composite:SubSecDateTimeOriginal",
        "-GPS:GPSLatitude", "-GPS:GPSLatitudeRef", "-GPS:GPSLongitude", "-GPS:GPSLongitudeRef",
        "-GPS:GPSAltitude", "-GPS:GPSAltitudeRef",
        "-IFD0:Make", "-IFD0:Model", "-ExifIFD:LensModel",
        "-QuickTime:CreateDate", "-QuickTime:Duration",
        "-Keys:CreationDate", "-Keys:GPSCoordinates", "-Keys:Make", "-Keys:Model",
        "-ContentIdentifier", "-ExifTool:Error",
    ]

    /// Keyed by `SourceFile` exactly as ExifTool printed it.
    public static func parse(_ json: String) throws -> [String: MediaFacts] {
        let root: JSONValue
        do {
            root = try JSONValue.parse(json)
        } catch {
            throw ExifToolOutputError(message: "ExifTool's output is not JSON")
        }
        guard case .array(let entries) = root else {
            throw ExifToolOutputError(message: "ExifTool's output is not a list of files")
        }
        var result: [String: MediaFacts] = [:]
        for entry in entries {
            guard case .object(let pairs) = entry, let source = text(entry["SourceFile"]) else {
                throw ExifToolOutputError(message: "ExifTool's output has an entry with no file name")
            }
            result[source] = facts(from: entry, pairs: pairs)
        }
        return result
    }

    private static func facts(from entry: JSONValue, pairs: [(key: String, value: JSONValue)]) -> MediaFacts {
        var facts = MediaFacts()

        // The composite carries the fraction and the offset; the bare sub-second tag is printed as a
        // number, which loses leading zeros, so it is not used.
        if let composite = string(entry["Composite:SubSecDateTimeOriginal"]).flatMap(ExifDate.init) {
            facts.original = composite
        } else if let plain = string(entry["ExifIFD:DateTimeOriginal"]).flatMap(ExifDate.init) {
            let offset = plain.offset ?? string(entry["ExifIFD:OffsetTimeOriginal"]).flatMap(UTCOffset.init(string:))
            facts.original = ExifDate(local: plain.local, offset: offset, hasFraction: plain.hasFraction)
        }
        facts.created = string(entry["QuickTime:CreateDate"]).flatMap(ExifDate.init)
        facts.creationDate = string(entry["Keys:CreationDate"]).flatMap(ExifDate.init)

        if let latitude = number(entry["GPS:GPSLatitude"]), let longitude = number(entry["GPS:GPSLongitude"]) {
            let south = string(entry["GPS:GPSLatitudeRef"])?.uppercased().hasPrefix("S") ?? false
            let west = string(entry["GPS:GPSLongitudeRef"])?.uppercased().hasPrefix("W") ?? false
            var altitude = number(entry["GPS:GPSAltitude"])
            // 1 and 3 both mean below the reference level.
            if let value = altitude, let reference = number(entry["GPS:GPSAltitudeRef"]), reference == 1 || reference == 3 {
                altitude = -abs(value)
            }
            facts.location = GeoPoint(lat: south ? -abs(latitude) : latitude, lon: west ? -abs(longitude) : longitude,
                                      alt: altitude, accuracyM: nil)
        } else if let coordinates = string(entry["Keys:GPSCoordinates"]) {
            let parts = coordinates.split(separator: " ").map { Double($0) }
            if (2...3).contains(parts.count), !parts.contains(where: { $0 == nil || !($0!.isFinite) }),
               let latitude = parts[0], let longitude = parts[1] {
                facts.location = GeoPoint(lat: latitude, lon: longitude, alt: parts.count == 3 ? parts[2] : nil, accuracyM: nil)
            }
        }

        facts.make = text(entry["IFD0:Make"]) ?? text(entry["Keys:Make"])
        facts.model = text(entry["IFD0:Model"]) ?? text(entry["Keys:Model"])
        facts.lens = text(entry["ExifIFD:LensModel"])
        // A file written in pieces can report a length of 0 until it is finished off: that is "not known".
        if let seconds = number(entry["QuickTime:Duration"]), seconds > 0, seconds < 1_000_000_000 {
            facts.durationMs = Int((seconds * 1000).rounded())
        }
        // A place anywhere else in the file. The Composite tags only repeat what another tag says.
        let placeTags: Set<String> = ["GPSLatitude", "GPSLongitude", "GPSCoordinates", "GPSPosition"]
        for (key, _) in pairs {
            let parts = key.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2, placeTags.contains(parts[1]) else { continue }
            if parts[0] == "Composite" || parts[0] == "GPS" { continue }
            if key == "Keys:GPSCoordinates" && facts.location != nil { continue }
            facts.strayLocationTags.append(key)
        }
        facts.strayLocationTags.sort()

        facts.contentIdentifier = pairs.first { $0.key.hasSuffix(":ContentIdentifier") }.flatMap { text($0.value) }
        facts.error = text(entry["ExifTool:Error"])
        return facts
    }

    private static func string(_ value: JSONValue?) -> String? {
        if case .string(let text)? = value { return text }
        return nil
    }

    /// Names and messages. ExifTool prints a name that looks like a number as a number.
    private static func text(_ value: JSONValue?) -> String? {
        switch value {
        case .string(let text)?: return text
        case .int(let whole)?: return String(whole)
        case .double(let number)?: return "\(number)"
        default: return nil
        }
    }

    private static func number(_ value: JSONValue?) -> Double? {
        switch value {
        case .int(let whole)?: return Double(whole)
        case .double(let number)?: return number
        default: return nil
        }
    }
}
