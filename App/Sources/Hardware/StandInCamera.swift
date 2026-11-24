import ImageIO
import ScrivnerCore
import UIKit
import UniformTypeIdentifiers

/// A camera for where there is none to use yet. It draws a picture that says what it is and when,
/// and writes it with the same time, time zone, device and place inside the file that a real
/// photo will carry. Stage 1c replaces it with the camera.
enum StandInCamera {
    struct CouldNotWrite: Error {}

    /// HEIC where the system can write it; JPEG otherwise (some simulators cannot write HEIC).
    static let fileExtension: String = {
        let types = CGImageDestinationCopyTypeIdentifiers() as? [String] ?? []
        return types.contains(UTType.heic.identifier) ? "heic" : "jpg"
    }()

    static func capture(_ request: PhotoRequest, style: ClockStyle) throws {
        let size = CGSize(width: 1200, height: 900)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor(red: 0.77, green: 0.54, blue: 0.29, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            let title = "Stand-in photo" as NSString
            title.draw(at: CGPoint(x: 80, y: 340), withAttributes: [
                .font: UIFont.systemFont(ofSize: 96, weight: .semibold), .foregroundColor: UIColor.white,
            ])
            let time = Wording.clock(request.moment.wall, offset: request.moment.utcOffset, style: style) as NSString
            time.draw(at: CGPoint(x: 80, y: 470), withAttributes: [
                .font: UIFont.systemFont(ofSize: 72, weight: .regular), .foregroundColor: UIColor.white,
            ])
        }
        guard let pixels = image.cgImage else { throw CouldNotWrite() }

        let type = request.file.hasSuffix(".heic") ? UTType.heic : UTType.jpeg
        guard let destination = CGImageDestinationCreateWithURL(request.url as CFURL, type.identifier as CFString, 1, nil) else {
            throw CouldNotWrite()
        }
        CGImageDestinationAddImage(destination, pixels, properties(for: request) as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw CouldNotWrite() }
    }

    /// What is written inside the file: the same tags an iPhone's own camera writes (design spec 6.3).
    static func properties(for request: PhotoRequest) -> [CFString: Any] {
        let local = LocalClock(request.moment.wall, offset: request.moment.utcOffset)
        func two(_ value: Int) -> String { value < 10 ? "0\(value)" : "\(value)" }
        let stamp = "\(local.year):\(two(local.month)):\(two(local.day)) \(two(local.hour)):\(two(local.minute)):\(two(local.second))"
        let milliseconds = Int(((request.moment.wall.millisecondsSince1970 % 1000) + 1000) % 1000)
        let subSeconds = String(repeating: "0", count: 3 - String(milliseconds).count) + String(milliseconds)
        let offset = request.moment.utcOffset.string

        var result: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: 0.7,
            kCGImagePropertyExifDictionary: [
                kCGImagePropertyExifDateTimeOriginal: stamp,
                kCGImagePropertyExifSubsecTimeOriginal: subSeconds,
                kCGImagePropertyExifOffsetTimeOriginal: offset,
                kCGImagePropertyExifDateTimeDigitized: stamp,
                kCGImagePropertyExifSubsecTimeDigitized: subSeconds,
                kCGImagePropertyExifOffsetTimeDigitized: offset,
                kCGImagePropertyExifLensModel: "Stand-in camera",
            ] as [CFString: Any],
            kCGImagePropertyTIFFDictionary: [
                kCGImagePropertyTIFFMake: "Apple",
                kCGImagePropertyTIFFModel: ThisDevice.model,
            ] as [CFString: Any],
        ]
        if let place = request.place {
            var gps: [CFString: Any] = [
                kCGImagePropertyGPSLatitude: abs(place.lat),
                kCGImagePropertyGPSLatitudeRef: place.lat < 0 ? "S" : "N",
                kCGImagePropertyGPSLongitude: abs(place.lon),
                kCGImagePropertyGPSLongitudeRef: place.lon < 0 ? "W" : "E",
            ]
            if let altitude = place.alt {
                gps[kCGImagePropertyGPSAltitude] = abs(altitude)
                gps[kCGImagePropertyGPSAltitudeRef] = altitude < 0 ? 1 : 0
            }
            result[kCGImagePropertyGPSDictionary] = gps
        }
        return result
    }
}

/// A location for where there is no location chip to use yet: off unless a test asks for it.
final class StandInLocation: LocationProviding {
    private let isOn: Bool

    init(isOn: Bool) {
        self.isOn = isOn
    }

    var latest: LocationFix? {
        guard isOn else { return nil }
        return LocationFix(lat: 27.7046, lon: 85.3076, alt: 1300, horizontalAccuracyM: 5, verticalAccuracyM: 3,
                           at: Instant(date: Date()))
    }
}
