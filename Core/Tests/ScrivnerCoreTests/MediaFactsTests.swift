import XCTest
@testable import ScrivnerCore

final class MediaFactsTests: XCTestCase {
    /// ExifTool's output for an audio file, a clip and a photo, as it prints them with `ExifToolOutput.arguments`.
    static let fixture = """
    [{ "SourceFile": "audio/audio-001.m4a",
       "QuickTime:CreateDate": "2026:11:23 04:57:10+00:00", "QuickTime:Duration": 551.04,
       "Keys:CreationDate": "2026:11:23 10:42:10+05:45", "Keys:Make": "Apple", "Keys:Model": "iPhone 17 Pro" },
     { "SourceFile": "video/clip-0001.mov",
       "QuickTime:CreateDate": "2026:11:23 05:04:20+00:00", "QuickTime:Duration": 48,
       "Keys:CreationDate": "2026:11:23 10:49:20+05:45", "Keys:GPSCoordinates": "27.7046 85.3076 1300",
       "Keys:Make": "Apple", "Keys:Model": "iPhone 17 Pro" },
     { "SourceFile": "photos/photo-0001.heic",
       "ExifIFD:DateTimeOriginal": "2026:11:23 10:45:15", "ExifIFD:OffsetTimeOriginal": "+05:45",
       "Composite:SubSecDateTimeOriginal": "2026:11:23 10:45:15.120+05:45",
       "GPS:GPSLatitudeRef": "N", "GPS:GPSLatitude": 27.7046, "GPS:GPSLongitudeRef": "E", "GPS:GPSLongitude": 85.3076,
       "GPS:GPSAltitudeRef": 0, "GPS:GPSAltitude": 1300,
       "IFD0:Make": "Apple", "IFD0:Model": "iPhone 17 Pro", "ExifIFD:LensModel": "iPhone 17 Pro back camera 6.765mm f/1.78" }]
    """

    func testReadsAudioClipAndPhoto() throws {
        let facts = try ExifToolOutput.parse(Self.fixture)
        XCTAssertEqual(facts.count, 3)
        let audio = try XCTUnwrap(facts["audio/audio-001.m4a"])
        XCTAssertEqual(audio.created?.instant?.iso, "2026-11-23T04:57:10.000Z")
        XCTAssertEqual(audio.creationDate?.instant?.iso, "2026-11-23T04:57:10.000Z")
        XCTAssertEqual(audio.creationDate?.offset?.string, "+05:45")
        XCTAssertEqual(audio.durationMs, 551_040)
        XCTAssertNil(audio.location); XCTAssertNil(audio.original)
        XCTAssertEqual(audio.make, "Apple"); XCTAssertEqual(audio.model, "iPhone 17 Pro")
        let clip = try XCTUnwrap(facts["video/clip-0001.mov"])
        XCTAssertEqual(clip.location, GeoPoint(lat: 27.7046, lon: 85.3076, alt: 1300, accuracyM: nil))
        XCTAssertEqual(clip.durationMs, 48_000)
        let photo = try XCTUnwrap(facts["photos/photo-0001.heic"])
        XCTAssertEqual(photo.original?.instant?.iso, "2026-11-23T05:00:15.120Z")
        XCTAssertEqual(photo.original?.hasFraction, true)
        XCTAssertEqual(photo.location, GeoPoint(lat: 27.7046, lon: 85.3076, alt: 1300, accuracyM: nil))
        XCTAssertEqual(photo.make, "Apple"); XCTAssertEqual(photo.model, "iPhone 17 Pro")
        XCTAssertEqual(photo.lens, "iPhone 17 Pro back camera 6.765mm f/1.78")
        XCTAssertNil(photo.error); XCTAssertNil(photo.contentIdentifier)
    }
    func testPhotoWithoutSubSecondsOrOffset() throws {
        let facts = try ExifToolOutput.parse(#"[{"SourceFile":"p.heic","ExifIFD:DateTimeOriginal":"2026:11:23 10:45:15"}]"#)
        XCTAssertEqual(facts["p.heic"]?.original?.local.iso, "2026-11-23T10:45:15.000Z")
        XCTAssertNil(facts["p.heic"]?.original?.offset)
        XCTAssertEqual(facts["p.heic"]?.original?.hasFraction, false)
        // An offset tag without the composite still gives the offset.
        let withOffset = try ExifToolOutput.parse(#"[{"SourceFile":"p.heic","ExifIFD:DateTimeOriginal":"2026:11:23 10:45:15","ExifIFD:OffsetTimeOriginal":"-03:00"}]"#)
        XCTAssertEqual(withOffset["p.heic"]?.original?.instant?.iso, "2026-11-23T13:45:15.000Z")
    }
    func testQuickTimeDatesInAnotherSystemZone() throws {
        // The same audio file read on a machine set to UTC+1.
        let facts = try ExifToolOutput.parse(#"[{"SourceFile":"a.m4a","QuickTime:CreateDate":"2026:11:23 05:57:10+01:00"}]"#)
        XCTAssertEqual(facts["a.m4a"]?.created?.instant?.iso, "2026-11-23T04:57:10.000Z")
    }
    func testHemispheresAndBelowSeaLevel() throws {
        let facts = try ExifToolOutput.parse(#"[{"SourceFile":"p.heic","GPS:GPSLatitudeRef":"S","GPS:GPSLatitude":33.9,"GPS:GPSLongitudeRef":"W","GPS:GPSLongitude":70.6,"GPS:GPSAltitudeRef":1,"GPS:GPSAltitude":12.5},{"SourceFile":"c.mov","Keys:GPSCoordinates":"-33.9 -70.6"}]"#)
        XCTAssertEqual(facts["p.heic"]?.location, GeoPoint(lat: -33.9, lon: -70.6, alt: -12.5, accuracyM: nil))
        XCTAssertEqual(facts["c.mov"]?.location, GeoPoint(lat: -33.9, lon: -70.6, alt: nil, accuracyM: nil))
    }
    func testErrorsAndLivePhotoIdentifier() throws {
        let facts = try ExifToolOutput.parse(#"[{"SourceFile":"x.heic","ExifTool:Error":"File format error"},{"SourceFile":"y.mov","Keys:ContentIdentifier":"ABC-123"},{"SourceFile":"z.heic","Apple:ContentIdentifier":"DEF-456"}]"#)
        XCTAssertEqual(facts["x.heic"]?.error, "File format error")
        XCTAssertEqual(facts["y.mov"]?.contentIdentifier, "ABC-123")
        XCTAssertEqual(facts["z.heic"]?.contentIdentifier, "DEF-456")
    }
    func testValuesOfTheWrongTypeCountAsAbsent() throws {
        let facts = try ExifToolOutput.parse(#"[{"SourceFile":"p.heic","ExifIFD:DateTimeOriginal":20261123,"GPS:GPSLatitude":"north","GPS:GPSLongitude":5,"IFD0:Model":17,"QuickTime:Duration":"long","Keys:GPSCoordinates":"here"}]"#)
        let p = try XCTUnwrap(facts["p.heic"])
        XCTAssertNil(p.original); XCTAssertNil(p.location); XCTAssertNil(p.durationMs)
        XCTAssertEqual(p.model, "17")   // a model name that looks like a number is still a name
    }
    func testNotJSONThrows() {
        XCTAssertThrowsError(try ExifToolOutput.parse("exiftool: command not found"))
        XCTAssertThrowsError(try ExifToolOutput.parse(#"{"SourceFile":"a"}"#))
        XCTAssertThrowsError(try ExifToolOutput.parse(#"[{"NoSourceFile":"a"}]"#))
        XCTAssertEqual(try ExifToolOutput.parse("[]").count, 0)
    }
    func testArgumentsAskForNumbersAndGroups() {
        XCTAssertEqual(Array(ExifToolOutput.arguments.prefix(5)), ["-json", "-n", "-G1", "-api", "QuickTimeUTC=1"])
        for tag in ["-Keys:CreationDate", "-Composite:SubSecDateTimeOriginal", "-ContentIdentifier", "-ExifTool:Error"] {
            XCTAssertTrue(ExifToolOutput.arguments.contains(tag), tag)
        }
    }
    func testAPlaceAnywhereInTheFileIsNoticed() throws {
        // The workbench reads a place from whichever part of a file holds one, so the checker has to notice them all.
        let facts = try ExifToolOutput.parse(#"""
        [{"SourceFile":"clip.mov","UserData:GPSCoordinates":"27.7046 85.3076 1300","Composite:GPSLatitude":27.7046,"Composite:GPSLongitude":85.3076,"Composite:GPSPosition":"27.7046 85.3076"},
         {"SourceFile":"photo.heic","XMP-exif:GPSLatitude":27.7046,"XMP-exif:GPSLongitude":85.3076},
         {"SourceFile":"audio.m4a","ItemList:GPSCoordinates":"27.7046 85.3076"},
         {"SourceFile":"usual.mov","Keys:GPSCoordinates":"27.7046 85.3076 1300","Composite:GPSLatitude":27.7046},
         {"SourceFile":"garbled.mov","Keys:GPSCoordinates":"somewhere"},
         {"SourceFile":"none.mov","QuickTime:Duration":3}]
        """#)
        XCTAssertEqual(facts["clip.mov"]?.strayLocationTags, ["UserData:GPSCoordinates"])
        XCTAssertNil(facts["clip.mov"]?.location)
        XCTAssertEqual(facts["photo.heic"]?.strayLocationTags, ["XMP-exif:GPSLatitude", "XMP-exif:GPSLongitude"])
        XCTAssertEqual(facts["audio.m4a"]?.strayLocationTags, ["ItemList:GPSCoordinates"])
        XCTAssertEqual(facts["usual.mov"]?.strayLocationTags, [])         // where spec 6.3 wants it; the Composite tags only repeat it
        XCTAssertNotNil(facts["usual.mov"]?.location)
        XCTAssertEqual(facts["garbled.mov"]?.strayLocationTags, ["Keys:GPSCoordinates"])   // there, but not readable: still a place
        XCTAssertNil(facts["garbled.mov"]?.location)
        XCTAssertEqual(facts["none.mov"]?.strayLocationTags, [])
        for argument in ["-a", "-GPSLatitude", "-GPSLongitude", "-GPSCoordinates", "-GPSPosition"] {
            XCTAssertTrue(ExifToolOutput.arguments.contains(argument), argument)
        }
    }
    func testALengthOfZeroIsNotKnown() throws {
        // A file written in pieces for crash safety can say its length is 0 until it is finished off.
        let facts = try ExifToolOutput.parse(#"[{"SourceFile":"a.m4a","QuickTime:Duration":0},{"SourceFile":"b.m4a","QuickTime:Duration":0.0}]"#)
        XCTAssertNil(facts["a.m4a"]?.durationMs); XCTAssertNil(facts["b.m4a"]?.durationMs)
    }
    func testBothWaysOfSayingBelowSeaLevel() throws {
        let facts = try ExifToolOutput.parse(#"[{"SourceFile":"p.heic","GPS:GPSLatitude":1,"GPS:GPSLongitude":2,"GPS:GPSAltitudeRef":3,"GPS:GPSAltitude":40}]"#)
        XCTAssertEqual(facts["p.heic"]?.location?.alt, -40)
    }
}
