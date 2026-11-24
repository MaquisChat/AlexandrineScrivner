import Foundation

/// The worked example in `format/examples`: a short, invented market visit, built the same way the
/// app builds a real session. Tests compare it with the committed copy, so the example can never
/// drift away from what the code writes.
public enum ExampleSession {
    /// Writes the finished example session under `root` and returns its folder.
    ///
    /// Each media file is copied from `mediaFrom` (a folder holding it at the same relative path)
    /// when it is there. Otherwise a one-line text placeholder is written, which is enough for
    /// tests that only need the folder's shape. The copy kept in `format/examples` has real media,
    /// made by `format/tools/make-example-media.py`.
    ///
    /// The session is set where the local clock is not UTC (10:42 in the morning at UTC+05:45),
    /// so that every conversion between the two is exercised.
    public static func write(in root: URL, mediaFrom: URL? = nil) throws -> SessionFolder {
        let start = Instant(iso: "2026-11-23T04:57:10.120Z")!
        let offset = UTCOffset(seconds: 5 * 3600 + 45 * 60)
        func moment(_ seconds: Double) -> Moment {
            Moment(host: 5000 + seconds, wall: start.adding(milliseconds: Int64(seconds * 1000)),
                   utcOffset: offset, timeZone: "Asia/Kathmandu")
        }
        let stall = GeoPoint(lat: 27.7046, lon: 85.3076, alt: 1300, accuracyM: 5)

        var timeline = SessionTimeline(title: "Market visit", participants: ["P-014"], researcher: nil,
                                       device: DeviceInfo(model: "iPhone18,1", os: "iOS 27.1", app: "0.1.0"),
                                       startLocation: stall, at: moment(0), ids: SeededIdSource(seed: 2026))
        func next(_ kind: MediaKind, _ ext: String) -> String {
            SessionStore.nextFile(kind, ext: ext, in: timeline.manifest)
        }

        try timeline.startRecording(file: next(.audio, "m4a"), at: moment(0))
        try timeline.addText("P-014 has run the stall since 2009. Took it over from her aunt, who still does the early shift on Saturdays.", at: moment(65))
        try timeline.addPhoto(file: next(.photo, "heic"), gps: stall, at: moment(185))
        try timeline.addText("Prices are handwritten every morning. Says the card reader \"scares off the regulars\".", at: moment(228))
        let firstClip = try timeline.startClip(file: next(.video, "mov"), gps: stall, at: moment(430))
        try timeline.endClip(id: firstClip, by: .user, at: moment(478))
        try timeline.addText("Asked me not to photograph the ledger.", at: moment(512))

        try timeline.endRecording(by: .pause, at: moment(551))
        try timeline.setLocation(enabled: false, at: moment(560))
        try timeline.addText("Off the record: the lease runs out in March.", at: moment(600))
        let secondClip = try timeline.startClip(file: next(.video, "mov"), gps: nil, at: moment(640))
        try timeline.endClip(id: secondClip, by: .user, at: moment(652))

        try timeline.startRecording(file: next(.audio, "m4a"), at: moment(700))
        try timeline.addPhoto(file: next(.photo, "heic"), gps: nil, at: moment(760))
        try timeline.endRecording(by: .stop, at: moment(800))

        let folder = try SessionStore.create(timeline.manifest, in: root)
        for path in SessionStore.listedFiles(in: timeline.manifest) {
            let prepared = mediaFrom.map { SessionFolder(url: $0).url(forRelativePath: path) }
            if let prepared, FileManager.default.fileExists(atPath: prepared.path) {
                try FileManager.default.copyItem(at: prepared, to: folder.url(forRelativePath: path))
            } else {
                try Data("placeholder for \(path)\n".utf8).write(to: folder.url(forRelativePath: path))
            }
        }
        _ = try SessionStore.finalize(timeline.manifest, in: folder)
        return folder
    }
}
