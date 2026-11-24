import Foundation

// The few things the session controller needs from the device. In the app each is a thin adapter
// around one of Apple's frameworks; in tests each is a fake. Nothing here imports those frameworks.

/// The device's clocks: the monotonic one that audio is stamped on, the wall clock and the time zone.
public protocol SessionClock: AnyObject {
    func now() -> Moment
}

/// The microphone, writing one audio file at a time.
public protocol AudioRecording: AnyObject {
    /// Starts writing a new audio file. Throws if the microphone cannot be had.
    func start(writingTo url: URL) throws
    /// Stops and returns the finished file's own length in milliseconds, or nil if it cannot be read.
    func stop() -> Int?
}

/// One reading from the location chip.
public struct LocationFix: Equatable, Sendable {
    public var lat: Double
    public var lon: Double
    public var alt: Double?
    /// In metres. Negative means the reading is not valid.
    public var horizontalAccuracyM: Double
    /// In metres. Negative or nil means the altitude is not valid.
    public var verticalAccuracyM: Double?
    public var at: Instant

    public init(lat: Double, lon: Double, alt: Double?, horizontalAccuracyM: Double, verticalAccuracyM: Double?, at: Instant) {
        self.lat = lat
        self.lon = lon
        self.alt = alt
        self.horizontalAccuracyM = horizontalAccuracyM
        self.verticalAccuracyM = verticalAccuracyM
        self.at = at
    }
}

public protocol LocationProviding: AnyObject {
    /// The most recent reading, if there has been one.
    var latest: LocationFix? { get }
}

/// Decides what place, if any, is stamped on something.
public enum Place {
    /// A reading older than this is not where the device is now.
    public static let freshForMs: Int64 = 60_000

    /// The place to stamp, or nil: location is off, there is no reading, the reading is not valid,
    /// or it is older than a minute. An altitude that is not valid is left out.
    public static func stamp(from fix: LocationFix?, enabled: Bool, now: Instant) -> GeoPoint? {
        guard enabled, let fix else { return nil }
        guard fix.horizontalAccuracyM >= 0, fix.horizontalAccuracyM.isFinite,
              fix.lat.isFinite, fix.lon.isFinite,
              (-90.0...90.0).contains(fix.lat), (-180.0...180.0).contains(fix.lon) else { return nil }
        guard abs(now.millisecondsSince1970 - fix.at.millisecondsSince1970) <= freshForMs else { return nil }
        var altitude: Double?
        if let alt = fix.alt, alt.isFinite, let vertical = fix.verticalAccuracyM, vertical >= 0 {
            altitude = alt
        }
        return GeoPoint(lat: fix.lat, lon: fix.lon, alt: altitude, accuracyM: fix.horizontalAccuracyM)
    }
}

/// Everything the camera needs to take one photo for a session: where to write it, and the
/// moment and place to write inside it. Made by `SessionController.preparePhoto()`.
public struct PhotoRequest: Equatable, Sendable {
    /// The photo's path as `session.json` will list it.
    public let file: String
    /// Where to write the file.
    public let url: URL
    /// When the shutter was pressed.
    public let moment: Moment
    /// The place to write inside the file, or nil for none.
    public let place: GeoPoint?
}
