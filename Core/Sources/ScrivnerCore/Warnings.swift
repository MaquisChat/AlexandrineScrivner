import Foundation

/// How long the app's install has left. With a free developer account an install stops working
/// seven days after it was made, so the home screen says how long is left.
public enum InstallWarning: Equatable, Sendable {
    case daysLeft(Int)
    case endsToday
    case expired
    case unknown

    public static func state(expires: Instant?, now: Instant) -> InstallWarning {
        guard let expires else { return .unknown }
        let remaining = expires.millisecondsSince1970 - now.millisecondsSince1970
        if remaining <= 0 { return .expired }
        let day: Int64 = 86_400_000
        return remaining < day ? .endsToday : .daysLeft(Int(remaining / day))
    }

    /// Two days or fewer: shown prominently.
    public var isUrgent: Bool {
        switch self {
        case .daysLeft(let days): return days <= 2
        case .endsToday, .expired: return true
        case .unknown: return false
        }
    }

    public var text: String {
        switch self {
        case .daysLeft(1): return "This install stops working tomorrow"
        case .daysLeft(let days): return "This install stops working in \(days) days"
        case .endsToday: return "This install stops working today"
        case .expired: return "This install has stopped working. Reinstall it from the Mac."
        case .unknown: return ""
        }
    }

    /// Finds the expiry date inside the app's install profile (`embedded.mobileprovision`). The file
    /// is a signed wrapper around a property list; the date is found by its key, without unwrapping.
    public static func expiry(inProfile data: Data) -> Instant? {
        let bytes = [UInt8](data)
        func find(_ text: String, from start: Int) -> Int? {
            let needle = Array(text.utf8)
            guard !needle.isEmpty, bytes.count >= needle.count, start <= bytes.count - needle.count else { return nil }
            var index = start
            while index <= bytes.count - needle.count {
                if bytes[index] == needle[0], Array(bytes[index..<(index + needle.count)]) == needle {
                    return index
                }
                index += 1
            }
            return nil
        }
        guard let key = find("<key>ExpirationDate</key>", from: 0),
              let open = find("<date>", from: key),
              let close = find("</date>", from: open),
              // Nothing but blank space between the key and its date.
              bytes[(key + "<key>ExpirationDate</key>".utf8.count)..<open].allSatisfy({ $0 == 9 || $0 == 10 || $0 == 13 || $0 == 32 })
        else { return nil }
        let text = String(decoding: bytes[(open + 6)..<close], as: UTF8.self)
        // Property lists write dates as 2026-12-01T10:15:00Z, without a fraction.
        guard text.utf8.count == 20, text.hasSuffix("Z") else { return nil }
        return Instant(iso: String(text.dropLast()) + ".000Z")
    }
}

/// Something worth saying before a session starts.
public enum ReadinessWarning: Equatable, Sendable {
    case lowStorage(freeBytes: Int64)
    case lowBattery(percent: Int)

    static let storageFloorBytes: Int64 = 2_000_000_000
    static let batteryFloor = 0.20

    /// Under 2 GB free; under 20 % battery and not charging. A reading that is nil, or a battery
    /// level below zero (how the phone says it does not know), raises nothing.
    public static func check(freeBytes: Int64?, batteryLevel: Double?, isCharging: Bool) -> [ReadinessWarning] {
        var warnings: [ReadinessWarning] = []
        if let freeBytes, freeBytes >= 0, freeBytes < storageFloorBytes {
            warnings.append(.lowStorage(freeBytes: freeBytes))
        }
        if let batteryLevel, batteryLevel >= 0, batteryLevel < batteryFloor, !isCharging {
            warnings.append(.lowBattery(percent: Int((batteryLevel * 100).rounded())))
        }
        return warnings
    }

    public var text: String {
        switch self {
        case .lowStorage(let freeBytes):
            let amount: String
            if freeBytes >= 1_000_000_000 {
                let tenths = Int((Double(freeBytes) / 100_000_000).rounded())
                amount = "\(tenths / 10).\(tenths % 10) GB"
            } else {
                amount = "\(Int((Double(freeBytes) / 1_000_000).rounded())) MB"
            }
            return "Only \(amount) of storage is free. A long session with video may not fit."
        case .lowBattery(let percent):
            return "The battery is at \(percent) % and the phone is not charging."
        }
    }
}
