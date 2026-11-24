import Foundation

/// How clock times are shown, following the device's own setting.
public enum ClockStyle: Sendable {
    case twentyFourHour, twelveHour
}

/// The words and number forms the app shows, in one place so the page, `notes.md` and the
/// screens all say the same thing.
public enum Wording {
    private static func two(_ value: Int) -> String {
        value < 10 ? "0\(value)" : "\(value)"
    }

    /// The clock time at that offset: `10:43` or `10:43 am`. Seconds are not shown.
    public static func clock(_ instant: Instant, offset: UTCOffset, style: ClockStyle) -> String {
        let local = LocalClock(instant, offset: offset)
        switch style {
        case .twentyFourHour:
            return "\(two(local.hour)):\(two(local.minute))"
        case .twelveHour:
            let hour = local.hour % 12 == 0 ? 12 : local.hour % 12
            return "\(hour):\(two(local.minute)) \(local.hour < 12 ? "am" : "pm")"
        }
    }

    /// `UTC+5:45`, `UTC-9:30`, `UTC+0`, `UTC+1`.
    public static func zone(_ offset: UTCOffset) -> String {
        let magnitude = abs(offset.seconds)
        let hours = magnitude / 3600
        let minutes = (magnitude % 3600) / 60
        return "UTC\(offset.seconds < 0 ? "-" : "+")\(hours)" + (minutes == 0 ? "" : ":\(two(minutes))")
    }

    /// What a marker says on the page.
    public static func marker(_ type: MarkerType, detail: String?) -> String {
        switch type {
        case .recordingStarted: return "Recording started"
        case .paused: return "Paused"
        case .resumed: return "Resumed"
        case .stopped: return "Stopped"
        case .interrupted:
            guard let detail else { return "Interrupted" }
            return detail == "crash-recovered" ? "Interrupted (the app was closed unexpectedly)" : "Interrupted (\(detail))"
        case .locationOff: return "Location off"
        case .locationOn: return "Location on"
        }
    }

    /// A length to the nearest second: `0:48`, `12:07`, `1:02:03`.
    public static func length(milliseconds: Int) -> String {
        let seconds = max(0, Int((Double(milliseconds) / 1000).rounded()))
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        if hours > 0 {
            return "\(hours):\(two(minutes)):\(two(seconds % 60))"
        }
        return "\(minutes):\(two(seconds % 60))"
    }
}
