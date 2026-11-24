import ImageIO
import ScrivnerCore
import SwiftUI
import UIKit

/// One row of the page in the margin layout: its clock time in the margin, then what it is.
struct MarginRow: View {
    let row: PageRow
    @ObservedObject var session: SessionModel

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(row.time)
                .font(Theme.ui(12))
                .monospacedDigit()
                .foregroundStyle(Theme.secondary)
                .frame(width: MarginRow.marginWidth(for: session.style), alignment: .trailing)
                .padding(.top, timeInset)
                .accessibilityLabel("At \(row.time)")
            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The margin is a little wider when times carry "am" or "pm".
    static func marginWidth(for style: ClockStyle) -> CGFloat {
        // Grows with the text size, up to a point: at the very largest sizes the times wrap instead.
        min(Theme.scaled(style == .twelveHour ? 66 : 58), 110)
    }

    /// Sets the small time level with the first line of what is beside it.
    private var timeInset: CGFloat {
        switch row.content {
        case .text: return 5
        case .photo: return 2
        case .marker, .video, .ink: return 0
        }
    }

    @ViewBuilder
    private var content: some View {
        switch row.content {
        case .marker(let text):
            MarkerLine(text: text)
        case .text(let text, let edited):
            VStack(alignment: .leading, spacing: 2) {
                Text(text)
                    .font(Theme.note(18))
                    .lineSpacing(4)
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("note")
                if edited {
                    Text("edited")
                        .font(Theme.ui(11))
                        .foregroundStyle(Theme.secondary)
                }
            }
        case .photo(let file):
            PhotoThumbnail(url: session.url(for: file), side: 132)
                .accessibilityElement(children: .ignore)
                .accessibilityAddTraits(.isImage)
                .accessibilityLabel("Photo taken at \(row.time)")
                .accessibilityIdentifier("photo-row")
        case .video(_, let length, let note):
            Label([length, note].compactMap { $0 }.joined(separator: ", "), systemImage: "video")
                .font(Theme.ui(13))
                .foregroundStyle(Theme.secondary)
        case .ink:
            Label("Handwriting", systemImage: "pencil.tip")
                .font(Theme.ui(13))
                .foregroundStyle(Theme.secondary)
        }
    }
}

/// A line the recorder wrote itself: "Recording started · local time, UTC+5:45".
struct MarkerLine: View {
    let text: String

    private var isAboutRecording: Bool {
        !text.hasPrefix("Location")
    }

    var body: some View {
        HStack(spacing: 8) {
            if isAboutRecording {
                Circle()
                    .fill(Theme.recording)
                    .frame(width: 7, height: 7)
                    .accessibilityHidden(true)
            }
            Text(text)
                .font(Theme.ui(12, .semibold))
                .foregroundStyle(isAboutRecording ? Theme.recording : Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("marker")
            Rectangle()
                .fill(Theme.rule)
                .frame(height: 1)
                .accessibilityHidden(true)
        }
    }
}

/// A photo from the session folder, shown small. Decoded once, at the size it is shown.
struct PhotoThumbnail: View {
    let url: URL
    let side: CGFloat
    var square = false

    var body: some View {
        Group {
            if let image = ThumbnailCache.image(for: url, side: side) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Theme.thumbnail
                    .overlay(Image(systemName: "photo").foregroundStyle(Theme.secondary))
            }
        }
        .frame(width: side, height: square ? side : side * 0.75)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.rule))
    }
}

/// Small versions of photos, kept in memory while the page is open.
enum ThumbnailCache {
    private static let cache = NSCache<NSString, UIImage>()

    static func image(for url: URL, side: CGFloat) -> UIImage? {
        let key = "\(url.path)#\(Int(side))" as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(side * 3),
        ]
        guard let pixels = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let image = UIImage(cgImage: pixels)
        cache.setObject(image, forKey: key)
        return image
    }
}
