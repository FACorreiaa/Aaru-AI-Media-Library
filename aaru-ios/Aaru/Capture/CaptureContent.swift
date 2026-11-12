import AaruAPI
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// AG-006: what one capture sends. A link alone goes as a link (the server reads it by id and
/// never opens it); anything else typed is text; pictures go as JPEGs, up to five (BOOK-001).
enum CaptureContent: Equatable {
    case text(String)
    case link(String)
    case images([Data])

    init?(typed: String) {
        let text = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.contains(where: \.isWhitespace), let url = URL(string: text),
           let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https", url.host != nil
        {
            self = .link(text)
        } else {
            self = .text(text)
        }
    }
}

/// A picture is read at most 1568 px on its long edge (what the model looks at anyway), so the
/// app shrinks it, turns it upright and sends a JPEG.
enum CaptureImage {
    static let longEdge = 1568
    /// What one capture sends at most; the server holds the same limit.
    static let maxPictures = 5

    /// What one picked picture becomes.
    enum Pieces {
        case jpegs([Data])
        case tooLong
        case unreadable
    }

    static func jpeg(_ data: Data) -> Data? {
        thumbnail(data, maxPixels: longEdge).flatMap(encode)
    }

    /// The JPEGs one picture sends. A tall scrolling screenshot is cut into overlapping pieces:
    /// shrunk whole to `longEdge` it would be about 250 px wide and unreadable (BOOK-002).
    static func pieces(_ data: Data) -> Pieces {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int
        else { return .unreadable }
        // A photo stays one picture, and is never decoded at full size. EXIF may swap the sides.
        guard slices(width: min(width, height), height: max(width, height)).count > 1,
              let upright = thumbnail(data, maxPixels: max(width, height))
        else { return jpeg(data).map { .jpegs([$0]) } ?? .unreadable }
        let rects = slices(width: upright.width, height: upright.height)
        guard rects.count <= maxPictures else { return .tooLong }
        let jpegs = rects.compactMap { upright.cropping(to: $0).flatMap(shrunk).flatMap(encode) }
        return jpegs.count == rects.count ? .jpegs(jpegs) : .unreadable
    }

    /// Where to cut a picture of this size: whole up to 12:5, else pieces of 11:5 with a tenth of a
    /// piece shared, so a line cut at one edge is whole in the next.
    static func slices(width: Int, height: Int) -> [CGRect] {
        guard width > 0, height * 5 > width * 12 else {
            return [CGRect(x: 0, y: 0, width: width, height: height)]
        }
        let piece = width * 11 / 5
        let step = piece - piece / 10
        return stride(from: 0, to: height - piece / 10, by: step).map { top in
            CGRect(x: 0, y: top, width: width, height: min(piece, height - top))
        }
    }

    /// At most `longEdge` on its long edge.
    private static func shrunk(_ image: CGImage) -> CGImage? {
        let long = max(image.width, image.height)
        guard long > longEdge else { return image }
        let width = image.width * longEdge / long
        let height = image.height * longEdge / long
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
              )
        else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    /// A JPEG at quality 0.85.
    static func encode(_ image: CGImage) -> Data? {
        let out = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(
            destination, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary
        )
        return CGImageDestinationFinalize(destination) ? out as Data : nil
    }

    static func thumbnail(_ data: Data, maxPixels: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}

extension ImportJob {
    var isCapture: Bool {
        source == .capture
    }

    /// The plan card's line: "Add 7 · 2 need a pick". Nil while it is still being read.
    var captureHeadline: String? {
        guard state == .planned else { return nil }
        let adds = stats.created + stats.updated
        let parts = [
            adds > 0 ? String(localized: "Add \(String(adds))") : nil,
            stats.unmatched == 1 ? String(localized: "1 needs a pick") : nil,
            stats.unmatched > 1 ? String(localized: "\(String(stats.unmatched)) need a pick") : nil,
        ].compactMap(\.self)
        guard parts.isEmpty else { return parts.joined(separator: " · ") }
        return stats.skipped > 0 ? String(localized: "Already in your library") : String(localized: "Nothing chosen")
    }

    /// Being read, or a plan to approve: it waits on Home.
    var isWaitingCapture: Bool {
        isCapture && (isWorking || state == .planned)
    }
}

/// SOC-001b: the photo the server keeps, a 512 px square JPEG cut from the middle and turned
/// upright. The original never leaves the device.
enum AvatarImage {
    static let side = 512

    static func jpeg(_ data: Data) -> Data? {
        guard let image = CaptureImage.thumbnail(data, maxPixels: side * 2) else { return nil }
        let crop = min(image.width, image.height)
        let square = CGRect(x: (image.width - crop) / 2, y: (image.height - crop) / 2, width: crop, height: crop)
        let out = min(side, crop)
        guard let cropped = image.cropping(to: square),
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil, width: out, height: out, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
              )
        else { return nil }
        context.interpolationQuality = .high
        context.draw(cropped, in: CGRect(x: 0, y: 0, width: out, height: out))
        return context.makeImage().flatMap(CaptureImage.encode)
    }
}
