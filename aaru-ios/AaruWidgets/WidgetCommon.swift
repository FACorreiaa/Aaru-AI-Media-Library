import ImageIO
import SwiftUI
import UniformTypeIdentifiers
import WidgetKit

// Colours are the generated asset symbols of the extension's own catalog (`WidgetAssets.xcassets`,
// written by scripts/generate-tokens.mjs from each token's `widget` list): `Color(.paper)`,
// `Color(.accent)`, `Color(.onAccent)`, and so on. Tints are `AaruAlpha` steps, corners `AaruRadius`.

extension Font {
    /// A widget's one heading, as in the app (`Font.aaruDisplay`): the system sans at the
    /// headline's size, scaled with Dynamic Type.
    static var widgetDisplay: Font {
        .system(.headline, design: .default, weight: .medium)
    }
}

/// One timeline entry: the snapshot as of `date`, plus downsampled artwork keyed by library id.
struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
    var artwork: [String: Data] = [:]
}

/// Shown when the app has not written a snapshot yet (never opened, or signed out). On the Lock
/// Screen (vibrant mode) it draws in the hierarchical styles, since a token fill turns to its
/// luminance there and ink can vanish.
struct SetUpView: View {
    var compact = false
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        VStack(alignment: .leading, spacing: AaruSpace.xsmall) {
            Image(systemName: "sparkles.tv")
                .font(compact ? .body : .title3)
                .foregroundStyle(vibrant ? AnyShapeStyle(.primary) : AnyShapeStyle(Color(.accent)))
                .widgetAccentable()
            Text("Open Aaru to set up")
                .font(compact ? .caption : .subheadline.weight(.semibold))
                .foregroundStyle(vibrant ? AnyShapeStyle(.primary) : AnyShapeStyle(Color(.ink)))
            if !compact {
                Text("Your shows appear here after you sign in.")
                    .font(.caption)
                    .foregroundStyle(vibrant ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color(.muted)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var vibrant: Bool {
        renderingMode == .vibrant
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

/// Fetched artwork, or a flat surface with a hairline when there is none (surfaces are flat; a
/// gradient is only a glow or a scrim). Clipped here, to a continuous `radius`, so the hairline
/// follows the corner.
struct ArtworkView: View {
    let data: Data?
    var radius: CGFloat = AaruRadius.thumb

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        Group {
            if let data, let source = CGImageSourceCreateWithData(data as CFData, nil),
               let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
            {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFill()
            } else {
                Color(.surface)
                    .overlay { shape.strokeBorder(Color(.line), lineWidth: 1) }
            }
        }
        .clipShape(shape)
    }
}

extension View {
    /// The brand paper behind every widget.
    func aaruWidgetBackground() -> some View {
        containerBackground(for: .widget) { Color(.paper) }
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
