import AaruAPI
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// AG-006: what one capture sends. A link alone goes as a link (the server reads it by id and
/// never opens it); anything else typed is text; a picture goes as a JPEG.
enum CaptureContent: Equatable {
    case text(String)
    case link(String)
    case image(Data)

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

    static func jpeg(_ data: Data) -> Data? {
        guard let image = thumbnail(data, maxPixels: longEdge) else { return nil }
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
            adds > 0 ? "Add \(adds)" : nil,
            stats.unmatched == 1 ? "1 needs a pick" : nil,
            stats.unmatched > 1 ? "\(stats.unmatched) need a pick" : nil,
        ].compactMap(\.self)
        return parts.isEmpty ? "Already in your library" : parts.joined(separator: " · ")
    }

    /// Being read, or a plan to approve: it waits on Home.
    var isWaitingCapture: Bool {
        isCapture && (isWorking || state == .planned)
    }
}
