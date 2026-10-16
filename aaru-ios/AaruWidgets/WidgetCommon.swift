import ImageIO
import SwiftUI
import UniformTypeIdentifiers
import WidgetKit

/// Brand colours, from the extension's own asset catalog (the app's catalog is not in this target).
enum Palette {
    static let paper = Color("Paper")
    static let ink = Color("Ink")
    static let muted = Color("Muted")
    static let surface = Color("Surface")
    static let brand = Color("Brand")
    static let gold = Color(red: 0.80, green: 0.60, blue: 0.20)
}

/// One timeline entry: the snapshot as of `date`, plus downsampled artwork keyed by library id.
struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
    var artwork: [String: Data] = [:]
}

/// Shown when the app has not written a snapshot yet (never opened, or signed out).
struct SetUpView: View {
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: "sparkles.tv")
                .font(compact ? .body : .title3)
                .foregroundStyle(Palette.brand)
            Text("Open Aaru to set up")
                .font(compact ? .caption : .subheadline.weight(.semibold))
                .foregroundStyle(Palette.ink)
            if !compact {
                Text("Your shows appear here after you sign in.")
                    .font(.caption)
                    .foregroundStyle(Palette.muted)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

/// Artwork for widget rows: fetched while building the timeline (widgets cannot load images while
/// rendering) and downsampled so a large widget stays inside the extension's memory budget.
enum WidgetArtwork {
    static func fetch(_ urls: [String: URL], maxPixel: Int = 360) async -> [String: Data] {
        await withTaskGroup(of: (String, Data?).self) { group in
            for (id, url) in urls {
                group.addTask {
                    var request = URLRequest(url: url)
                    request.timeoutInterval = 6
                    guard let (data, _) = try? await URLSession.shared.data(for: request) else { return (id, nil) }
                    return (id, downsample(data, maxPixel: maxPixel))
                }
            }
            var result: [String: Data] = [:]
            for await (id, data) in group {
                result[id] = data
            }
            return result
        }
    }

    private static func downsample(_ data: Data, maxPixel: Int) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceThumbnailMaxPixelSize: maxPixel,
                  kCGImageSourceCreateThumbnailWithTransform: true,
              ] as CFDictionary)
        else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(
            destination,
            image,
            [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary
        )
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }
}

/// Fetched artwork, or a brand wash when there is none.
struct ArtworkView: View {
    let data: Data?

    var body: some View {
        if let data, let source = CGImageSourceCreateWithData(data as CFData, nil),
           let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        {
            Image(decorative: image, scale: 1)
                .resizable()
                .scaledToFill()
        } else {
            LinearGradient(
                colors: [Palette.brand.opacity(0.35), Palette.gold.opacity(0.35)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        }
    }
}

extension View {
    /// The brand paper behind every widget.
    func aaruWidgetBackground() -> some View {
        containerBackground(for: .widget) { Palette.paper }
    }
}

/// "57m", "1h", "8h 40m".
func widgetDuration(minutes: Int) -> String {
    let hours = minutes / 60
    let rest = minutes % 60
    switch (hours, rest) {
    case (0, _): return "\(rest)m"
    case (_, 0): return "\(hours)h"
    default: return "\(hours)h \(rest)m"
    }
}
