import XCTest
@testable import ScrivnerCore

final class WarningsTests: XCTestCase {
    let now = Instant(iso: "2026-11-24T09:00:00.000Z")!
    func after(days: Int = 0, hours: Int = 0, minutes: Int = 0) -> Instant {
        now.adding(milliseconds: Int64(days) * 86_400_000 + Int64(hours) * 3_600_000 + Int64(minutes) * 60_000)
    }

    func testInstallWarningStates() {
        let five = InstallWarning.state(expires: after(days: 5, hours: 3), now: now)
        XCTAssertEqual(five, .daysLeft(5)); XCTAssertEqual(five.text, "This install stops working in 5 days"); XCTAssertFalse(five.isUrgent)
        let three = InstallWarning.state(expires: after(days: 3), now: now)
        XCTAssertEqual(three, .daysLeft(3)); XCTAssertFalse(three.isUrgent)
        let two = InstallWarning.state(expires: after(days: 2, hours: 23), now: now)
        XCTAssertEqual(two, .daysLeft(2)); XCTAssertTrue(two.isUrgent)
        let one = InstallWarning.state(expires: after(days: 1, hours: 2), now: now)
        XCTAssertEqual(one, .daysLeft(1)); XCTAssertEqual(one.text, "This install stops working tomorrow"); XCTAssertTrue(one.isUrgent)
        let today = InstallWarning.state(expires: after(hours: 3), now: now)
        XCTAssertEqual(today, .endsToday); XCTAssertEqual(today.text, "This install stops working today"); XCTAssertTrue(today.isUrgent)
        let gone = InstallWarning.state(expires: after(minutes: -1), now: now)
        XCTAssertEqual(gone, .expired); XCTAssertEqual(gone.text, "This install has stopped working. Reinstall it from the Mac."); XCTAssertTrue(gone.isUrgent)
        let unknown = InstallWarning.state(expires: nil, now: now)
        XCTAssertEqual(unknown, .unknown); XCTAssertEqual(unknown.text, ""); XCTAssertFalse(unknown.isUrgent)
    }
    func testExpiryIsFoundInsideAProfile() {
        var profile = Data([0x30, 0x82, 0x1F, 0x00, 0xFF, 0x00, 0x80])     // signed wrapper: not text
        profile.append(Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0"><dict>
        \t<key>CreationDate</key>
        \t<date>2026-11-24T10:15:00Z</date>
        \t<key>ExpirationDate</key>
        \t<date>2026-12-01T10:15:00Z</date>
        \t<key>Name</key><string>iOS Team Provisioning Profile</string>
        </dict></plist>
        """.utf8))
        profile.append(Data([0x00, 0xFE, 0x31, 0x82]))
        XCTAssertEqual(InstallWarning.expiry(inProfile: profile)?.iso, "2026-12-01T10:15:00.000Z")
        XCTAssertNil(InstallWarning.expiry(inProfile: Data("<key>CreationDate</key><date>2026-11-24T10:15:00Z</date>".utf8)))
        XCTAssertNil(InstallWarning.expiry(inProfile: Data("<key>ExpirationDate</key><date>soon</date>".utf8)))
        XCTAssertNil(InstallWarning.expiry(inProfile: Data()))
    }
    func testReadinessWarnings() {
        let low = ReadinessWarning.check(freeBytes: 1_200_000_000, batteryLevel: 0.15, isCharging: false)
        XCTAssertEqual(low, [.lowStorage(freeBytes: 1_200_000_000), .lowBattery(percent: 15)])
        XCTAssertEqual(low.map(\.text), ["Only 1.2 GB of storage is free. A long session with video may not fit.",
                                         "The battery is at 15 % and the phone is not charging."])
        XCTAssertEqual(ReadinessWarning.lowStorage(freeBytes: 85_000_000).text, "Only 85 MB of storage is free. A long session with video may not fit.")
        XCTAssertEqual(ReadinessWarning.check(freeBytes: 1_200_000_000, batteryLevel: 0.15, isCharging: true), [.lowStorage(freeBytes: 1_200_000_000)])
        XCTAssertEqual(ReadinessWarning.check(freeBytes: 2_000_000_000, batteryLevel: 0.20, isCharging: false), [])
        XCTAssertEqual(ReadinessWarning.check(freeBytes: nil, batteryLevel: nil, isCharging: false), [])
        XCTAssertEqual(ReadinessWarning.check(freeBytes: 64_000_000_000, batteryLevel: -1, isCharging: false), [])    // -1 is how the phone says "unknown"
    }
}
