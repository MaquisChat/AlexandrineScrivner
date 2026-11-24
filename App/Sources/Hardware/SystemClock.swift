import Foundation
import ScrivnerCore

/// The device's clocks, for the session controller.
final class SystemClock: SessionClock {
    func now() -> Moment {
        let date = Date()
        let zone = TimeZone.current
        return Moment(host: ProcessInfo.processInfo.systemUptime, wall: Instant(date: date),
                      utcOffset: UTCOffset(seconds: zone.secondsFromGMT(for: date)), timeZone: zone.identifier)
    }
}

/// What the device is, as it is written into a session.
enum ThisDevice {
    static var info: DeviceInfo {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let os = "iOS \(version.majorVersion).\(version.minorVersion)" + (version.patchVersion == 0 ? "" : ".\(version.patchVersion)")
        return DeviceInfo(model: model, os: os, app: appVersion)
    }

    /// The hardware model, such as "iPhone18,1". In the simulator, the model being simulated.
    static var model: String {
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
            return simulated
        }
        var system = utsname()
        uname(&system)
        return withUnsafeBytes(of: &system.machine) { bytes in
            String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
        }
    }

    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }
}
